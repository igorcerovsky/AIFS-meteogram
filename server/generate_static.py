#!/usr/bin/env python3
"""
Static Meteogram Pre-Renderer for GitHub Pages.
Generates meteogram images for preset locations and outputs them to web/images/
along with a manifest.json file containing metadata and update timestamps.
"""

import os
import sys
import json
import time
from datetime import datetime, timezone

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(BASE_DIR, ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from aifs_client import AIFSClient
from renderer import MeteogramRenderer

OUTPUT_DIR = os.path.join(REPO_ROOT, "web", "images")
os.makedirs(OUTPUT_DIR, exist_ok=True)

LOCATIONS = [
    {"name": "Bratislava-Koliba", "slug": "bratislava-koliba"},
    {"name": "Liptovsky Mikulas", "slug": "liptovsky-mikulas"},
    {"name": "Jasna", "slug": "jasna"},
    {"name": "Plavecke Podhradie", "slug": "plavecke-podhradie"},
    {"name": "Košice", "slug": "kosice"},
    {"name": "Poprad", "slug": "poprad"},
    {"name": "Vienna", "slug": "vienna"},
    {"name": "Prague", "slug": "prague"},
]

MODELS = [
    {"id": "aifs", "days": 15, "label": "ECMWF AIFS (15-day)"},
    {"id": "icon_d2", "days": 2, "label": "DWD ICON-D2 (2-day, 2.2 km)"},
    {"id": "icon_eu", "days": 5, "label": "DWD ICON-EU (5-day, 7.0 km)"},
]

LANGUAGES = ["sk", "en"]


def main():
    print(f"[*] Starting static meteogram generation to {OUTPUT_DIR}")
    start_time = time.time()
    client = AIFSClient()
    renderers = {
        "sk": MeteogramRenderer(lang="sk"),
        "en": MeteogramRenderer(lang="en"),
    }

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generated_at_human": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "images": {},
    }

    total = len(LOCATIONS) * len(MODELS) * len(LANGUAGES)
    count = 0

    for loc in LOCATIONS:
        loc_name = loc["name"]
        loc_slug = loc["slug"]
        print(f"\n[+] Geocoding {loc_name}...")
        try:
            loc_info = client.geocode(loc_name)
        except Exception as e:
            print(f"[-] Geocode failed for {loc_name}: {e}")
            continue

        lat = loc_info["latitude"]
        lon = loc_info["longitude"]
        location_cache = {}

        for model_cfg in MODELS:
            model_id = model_cfg["id"]
            days = model_cfg["days"]

            # If requesting icon_d2 but location is outside coverage, fallback or skip
            is_d2_ok = client.is_icon_d2_available(lat, lon)
            target_model = model_id
            if model_id == "icon_d2" and not is_d2_ok:
                target_model = "icon_eu"
                days = 5

            cache_key = (target_model, days)
            if cache_key in location_cache:
                print(f"  -> Reusing cached {target_model} data for {loc_name} ({days} days)...")
                stats, astro_data, sun_times = location_cache[cache_key]
            else:
                time.sleep(2.0)  # Pacing to avoid hitting Open-Meteo rate limits
                print(f"  -> Fetching {target_model} data for {loc_name} ({days} days)...")
                try:
                    stats = client.fetch_ensemble(lat, lon, days=days, model=target_model)
                    astro_data = client.fetch_astronomy_data(lat, lon, days=days)
                    sun_times = astro_data["sun_pairs"]
                    location_cache[cache_key] = (stats, astro_data, sun_times)
                except Exception as e:
                    print(f"[-] Fetch error for {loc_name} {target_model}: {e}")
                    continue

            # Verify cloud layers on regional models
            if target_model in ["icon_eu", "icon_d2"]:
                c_low = stats.get("cloud_cover_low")
                if c_low is None or ("median" in c_low and hasattr(c_low["median"], "__len__") and len(c_low["median"]) > 0 and (c_low["median"] == 0).all()):
                    print(f"    [!] WARNING: Cloud cover layers missing or flat for {loc_name} ({target_model})")

            actual_model = stats.get("model", target_model)

            for lang in LANGUAGES:
                count += 1
                out_filename = f"{loc_slug}_{model_id}_{lang}.png"
                out_path = os.path.join(OUTPUT_DIR, out_filename)
                print(f"    [{count}/{total}] Rendering {out_filename}...")

                try:
                    renderers[lang].render(
                        location_info=loc_info,
                        stats=stats,
                        sun_times=sun_times,
                        output_path=out_path,
                        dpi=160,
                        tz_mode="local",
                        astro_data=astro_data,
                    )

                    key = f"{loc_slug}_{model_id}_{lang}"
                    manifest["images"][key] = {
                        "file": out_filename,
                        "location": loc_name,
                        "slug": loc_slug,
                        "model": actual_model,
                        "requested_model": model_id,
                        "lang": lang,
                    }
                except Exception as e:
                    print(f"[-] Render error {out_filename}: {e}")

    # Write manifest
    manifest_path = os.path.join(OUTPUT_DIR, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    elapsed = time.time() - start_time
    print(f"\n[✓] Completed! Generated {len(manifest['images'])} meteograms in {elapsed:.1f}s.")
    print(f"[✓] Manifest saved to {manifest_path}")


if __name__ == "__main__":
    main()
