#!/usr/bin/env python3
"""
ECMWF AIFS Meteogram Generator
Generates SHMÚ-styled EPSGRAM meteograms using free ECMWF AI-model (AIFS) ensemble data.

Usage examples:
    python3 meteogram.py --location "Bratislava"
    python3 meteogram.py --location "Košice" --days 10 --output kosice.png
    python3 meteogram.py --location "48.15,17.11" --lang en
"""

import argparse
import os
import sys
from datetime import datetime
from typing import Optional

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(BASE_DIR, ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from aifs_client import AIFSClient
from renderer import MeteogramRenderer


def generate_meteogram(
    location: str = "Bratislava-Koliba",
    days: int = 15,
    output: Optional[str] = None,
    lang: str = "en",
    tz: str = "local",
    dpi: int = 200,
    model: str = "aifs",
) -> str:
    """End-to-end pipeline: geocode, fetch ensemble, fetch sun times, render."""
    client = AIFSClient()
    renderer = MeteogramRenderer(lang=lang)

    print(f"[*] Geocoding location: '{location}'...")
    loc_info = client.geocode(location)
    lat = loc_info["latitude"]
    lon = loc_info["longitude"]
    elev = loc_info.get("elevation", 0)
    loc_name = loc_info.get("name", location)
    country = loc_info.get("country", "")

    print(f"[✓] Found: {loc_name} ({country}) at {lat:.4f}°N, {lon:.4f}°E (alt: {elev:.0f}m)")

    img_dir = os.path.join(REPO_ROOT, ".img")
    os.makedirs(img_dir, exist_ok=True)

    print(f"[*] Fetching {model.upper()} ensemble data ({days} days)...")
    stats = client.fetch_ensemble(lat, lon, days=days, model=model)
    timesteps = len(stats["times"])
    print(f"[✓] Retrieved {timesteps} time steps across ensemble members.")

    actual_model = stats.get("model", model)
    if stats.get("model_fallback"):
        print(f"[!] NOTICE: 2-day model '{model.upper()}' is not available for '{loc_name}' (outside domain).")
        print(f"[✓] Automatically switched to closest available model: '{actual_model.upper()}'.")

    if not output:
        clean_name = "".join(c if c.isalnum() else "_" for c in loc_name.lower())
        output = os.path.join(img_dir, f"{clean_name}_{actual_model}_meteogram.png")
    elif not os.path.isabs(output) and not os.path.dirname(output):
        # Bare filename (e.g. -o output.png) placed inside .img folder
        output = os.path.join(img_dir, output)

    print(f"[*] Fetching sunrise & sunset times for {loc_name}...")
    sun_times = client.fetch_sun_times(lat, lon, days=days)

    print(f"[*] Rendering SHMÚ-style meteogram (Temperature on top, in {lang.upper()}, Time: {tz.upper()})...")
    out_file = renderer.render(
        location_info=loc_info,
        stats=stats,
        sun_times=sun_times,
        output_path=output,
        dpi=dpi,
        tz_mode=tz,
    )
    print(f"[SUCCESS] Meteogram generated and saved to: {os.path.abspath(out_file)}")
    return out_file


def main():
    parser = argparse.ArgumentParser(
        description="Generate an SHMÚ-styled meteogram from ECMWF AI-model (AIFS) or DWD ICON ensemble data."
    )
    parser.add_argument(
        "-l",
        "--location",
        type=str,
        default="Bratislava-Koliba",
        help="City or preset name (e.g. 'Bratislava-Koliba', 'Liptovsky Mikulas', 'Jasna', 'Plavecke Podhradie') or 'lat,lon' coordinates. Default: Bratislava-Koliba.",
    )
    parser.add_argument(
        "-m",
        "--model",
        type=str,
        default="aifs",
        choices=["aifs", "icon_d2", "icon_eu"],
        help="Ensemble model: 'aifs' (ECMWF 0.25° AI), 'icon_d2' (DWD 2.2 km, 48h), 'icon_eu' (DWD 7.0 km, 5-day). Default: aifs.",
    )
    parser.add_argument(
        "-d",
        "--days",
        type=int,
        default=15,
        choices=range(1, 17),
        help="Forecast duration in days (1 to 16). Default: 15.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default=None,
        help="Output file path (e.g. 'bratislava.png'). Defaults to auto-named inside '.img/' directory.",
    )
    parser.add_argument(
        "--lang",
        type=str,
        default="en",
        choices=["en", "sk"],
        help="Language for labels ('en' for English, 'sk' for Slovak). Default: en.",
    )
    parser.add_argument(
        "--tz",
        type=str,
        default="local",
        choices=["local", "utc"],
        help="Timezone on X-axis: 'local' (default, current local time [summer/winter] at render time) or 'utc'.",
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=200,
        help="DPI resolution for rendered image. Default: 200.",
    )

    args = parser.parse_args()

    try:
        generate_meteogram(
            location=args.location,
            days=args.days,
            output=args.output,
            lang=args.lang,
            tz=args.tz,
            dpi=args.dpi,
            model=args.model,
        )
    except Exception as e:
        print(f"[ERROR] Failed to generate meteogram: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
