#!/usr/bin/env python3
"""
Lightweight Web Server for ECMWF AIFS Meteogram.
Serves interactive web UI and dynamic meteogram generation API.
No external web framework dependencies needed (uses standard library http.server).
"""

import hashlib
import io
import json
import os
import sys
import urllib.parse
from http.server import HTTPServer, SimpleHTTPRequestHandler, ThreadingHTTPServer

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(BASE_DIR, ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from aifs_client import AIFSClient
from renderer import MeteogramRenderer

CACHE_DIR = os.path.join(REPO_ROOT, ".cache")
os.makedirs(CACHE_DIR, exist_ok=True)

client = AIFSClient()
renderers = {
    "sk": MeteogramRenderer(lang="sk"),
    "en": MeteogramRenderer(lang="en"),
}


class MeteogramHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        # Clean request logging
        sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        # Route / -> web/index.html
        if path == "/" or path == "/index.html":
            index_file = os.path.join(REPO_ROOT, "web", "index.html")
            if not os.path.exists(index_file):
                index_file = os.path.join(BASE_DIR, "web", "index.html")
            try:
                with open(index_file, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return
            except (BrokenPipeError, ConnectionResetError):
                return
            except Exception as e:
                try:
                    self.send_error(500, f"Failed to read index.html: {e}")
                except Exception:
                    pass
                return

        # API: /api/check_location
        if path == "/api/check_location":
            loc_param = query.get("location", [""])[0].strip()
            if not loc_param:
                self.send_error(400, "Missing location parameter")
                return
            try:
                import importlib
                import aifs_client
                importlib.reload(aifs_client)
                client_inst = aifs_client.AIFSClient()
                loc_info = client_inst.geocode(loc_param)
                lat = loc_info["latitude"]
                lon = loc_info["longitude"]
                icon_d2_ok = client_inst.is_icon_d2_available(lat, lon)
                
                resp_payload = {
                    "name": loc_info.get("name", loc_param),
                    "country": loc_info.get("country", ""),
                    "latitude": lat,
                    "longitude": lon,
                    "elevation": loc_info.get("elevation", 0),
                    "icon_d2_available": icon_d2_ok,
                    "closest_model_for_2day": "icon_d2" if icon_d2_ok else "icon_eu",
                }
                body = json.dumps(resp_payload).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "public, max-age=3600")
                self.end_headers()
                self.wfile.write(body)
                return
            except Exception as e:
                try:
                    self.send_error(400, f"Error checking location: {e}")
                except Exception:
                    pass
                return

        # API: /api/image
        if path == "/api/image":
            loc_param = query.get("location", ["Bratislava-Koliba"])[0].strip()
            days_param = int(query.get("days", ["15"])[0])
            lang_param = query.get("lang", ["en"])[0]
            tz_param = query.get("tz", ["local"])[0].lower()
            if tz_param not in ["local", "utc"]:
                tz_param = "local"
            if lang_param not in renderers:
                lang_param = "en"

            model_param = query.get("model", ["aifs"])[0].lower()
            if model_param not in ["aifs", "icon_d2", "icon_eu"]:
                model_param = "aifs"

            # Cache key (includes model and renderer.py mtime to automatically invalidate on style updates)
            renderer_file = os.path.join(BASE_DIR, "renderer.py")
            renderer_mtime = int(os.path.getmtime(renderer_file)) if os.path.exists(renderer_file) else 0
            cache_key = hashlib.md5(f"{loc_param}_{days_param}_{lang_param}_{tz_param}_{model_param}_{renderer_mtime}".encode()).hexdigest()
            cache_file = os.path.join(CACHE_DIR, f"{cache_key}.png")
            meta_file = os.path.join(CACHE_DIR, f"{cache_key}.json")

            # Check if cached recently (under 1 hour)
            use_cache = False
            actual_model = model_param
            fallback_used = False
            fallback_from = ""

            if os.path.exists(cache_file) and os.path.exists(meta_file):
                mtime = os.path.getmtime(cache_file)
                import time
                if time.time() - mtime < 3600:
                    try:
                        with open(meta_file, "r", encoding="utf-8") as f:
                            meta = json.load(f)
                            actual_model = meta.get("actual_model", model_param)
                            fallback_used = meta.get("fallback_used", False)
                            fallback_from = meta.get("fallback_from", "")
                            use_cache = True
                    except Exception:
                        use_cache = False

            if not use_cache:
                try:
                    import importlib
                    import aifs_client
                    import renderer as renderer_mod
                    importlib.reload(aifs_client)
                    importlib.reload(renderer_mod)

                    client_inst = aifs_client.AIFSClient()
                    loc_info = client_inst.geocode(loc_param)
                    lat = loc_info["latitude"]
                    lon = loc_info["longitude"]
                    stats = client_inst.fetch_ensemble(lat, lon, days=days_param, model=model_param)
                    sun_times = client_inst.fetch_sun_times(lat, lon, days=days_param)

                    renderer = renderer_mod.MeteogramRenderer(lang=lang_param)
                    renderer.render(
                        location_info=loc_info,
                        stats=stats,
                        sun_times=sun_times,
                        output_path=cache_file,
                        dpi=170,
                        tz_mode=tz_param,
                    )

                    actual_model = stats.get("model", model_param)
                    fallback_used = stats.get("model_fallback", False)
                    fallback_from = stats.get("fallback_from", "")

                    # Save sidecar metadata for cache hits
                    try:
                        with open(meta_file, "w", encoding="utf-8") as f:
                            json.dump({
                                "actual_model": actual_model,
                                "fallback_used": fallback_used,
                                "fallback_from": fallback_from,
                                "location_name": loc_info.get("name", loc_param),
                            }, f)
                    except Exception:
                        pass
                except Exception as e:
                    try:
                        self.send_error(400, f"Error generating meteogram: {e}")
                    except Exception:
                        pass
                    return

            try:
                with open(cache_file, "rb") as f:
                    img_data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(img_data)))
                self.send_header("Cache-Control", "public, max-age=1800")
                self.send_header("X-Actual-Model", actual_model)
                self.send_header("X-Model-Fallback", "true" if fallback_used else "false")
                if fallback_from:
                    self.send_header("X-Fallback-From", fallback_from)
                self.send_header("Access-Control-Expose-Headers", "X-Actual-Model, X-Model-Fallback, X-Fallback-From")
                self.end_headers()
                self.wfile.write(img_data)
                return
            except (BrokenPipeError, ConnectionResetError):
                return
            except Exception as e:
                try:
                    self.send_error(500, f"Failed to deliver image: {e}")
                except Exception:
                    pass
                return

        # Default static file serving
        super().do_GET()

    def do_HEAD(self):
        self.do_GET()


def run_server(port=8080):
    server_address = ("", port)
    httpd = ThreadingHTTPServer(server_address, MeteogramHandler)
    print(f"[*] Meteogram Web Server running on http://localhost:{port}")
    print(f"[*] Open http://localhost:{port} in your browser to explore!")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down server.")
        httpd.server_close()


if __name__ == "__main__":
    port = 8080
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            pass
    run_server(port)
