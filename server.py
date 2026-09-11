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

from aifs_client import AIFSClient
from renderer import MeteogramRenderer

CACHE_DIR = os.path.join(os.path.dirname(__file__), ".cache")
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
            index_file = os.path.join(os.path.dirname(__file__), "web", "index.html")
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

            # Cache key (includes renderer.py mtime to automatically invalidate on style updates)
            renderer_file = os.path.join(os.path.dirname(__file__), "renderer.py")
            renderer_mtime = int(os.path.getmtime(renderer_file)) if os.path.exists(renderer_file) else 0
            cache_key = hashlib.md5(f"{loc_param}_{days_param}_{lang_param}_{tz_param}_{renderer_mtime}".encode()).hexdigest()
            cache_file = os.path.join(CACHE_DIR, f"{cache_key}.png")

            # Check if cached recently (under 1 hour)
            use_cache = False
            if os.path.exists(cache_file):
                mtime = os.path.getmtime(cache_file)
                import time
                if time.time() - mtime < 3600:
                    use_cache = True

            if not use_cache:
                try:
                    loc_info = client.geocode(loc_param)
                    lat = loc_info["latitude"]
                    lon = loc_info["longitude"]
                    stats = client.fetch_aifs_ensemble(lat, lon, days=days_param)
                    sun_times = client.fetch_sun_times(lat, lon, days=days_param)

                    renderer = renderers[lang_param]
                    renderer.render(
                        location_info=loc_info,
                        stats=stats,
                        sun_times=sun_times,
                        output_path=cache_file,
                        dpi=170,
                        tz_mode=tz_param,
                    )
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
