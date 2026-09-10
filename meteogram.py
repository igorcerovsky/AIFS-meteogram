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

from aifs_client import AIFSClient
from renderer import MeteogramRenderer


def generate_meteogram(
    location: str,
    days: int = 15,
    output: str = None,
    lang: str = "en",
    dpi: int = 200,
) -> str:
    """End-to-end pipeline: geocode -> fetch AIFS ensemble -> render image."""
    client = AIFSClient()
    renderer = MeteogramRenderer(lang=lang)

    print(f"[*] Geocoding location: '{location}'...")
    loc_info = client.geocode(location)
    loc_name = loc_info["name"]
    country = loc_info["country"]
    lat = loc_info["latitude"]
    lon = loc_info["longitude"]
    elev = loc_info["elevation"]

    print(f"[✓] Found: {loc_name} ({country}) at {lat:.4f}°N, {lon:.4f}°E (alt: {elev:.0f}m)")

    if not output:
        clean_name = "".join(c if c.isalnum() else "_" for c in loc_name.lower())
        output = f"{clean_name}_aifs_meteogram.png"

    print(f"[*] Fetching ECMWF AIFS 0.25° 50-member ensemble ({days} days - full AI horizon)...")
    stats = client.fetch_aifs_ensemble(lat, lon, days=days)
    timesteps = len(stats["times"])
    print(f"[✓] Retrieved {timesteps} time steps across 50 AI ensemble members.")

    print(f"[*] Fetching sunrise & sunset times for {loc_name}...")
    sun_times = client.fetch_sun_times(lat, lon, days=days)

    print(f"[*] Rendering SHMÚ-style meteogram (Temperature on top, in {lang.upper()})...")
    out_file = renderer.render(
        location_info=loc_info,
        stats=stats,
        sun_times=sun_times,
        output_path=output,
        dpi=dpi,
    )
    print(f"[SUCCESS] Meteogram generated and saved to: {os.path.abspath(out_file)}")
    return out_file


def main():
    parser = argparse.ArgumentParser(
        description="Generate an SHMÚ-styled meteogram from ECMWF AI-model (AIFS) ensemble data."
    )
    parser.add_argument(
        "-l",
        "--location",
        type=str,
        default="Bratislava-Koliba",
        help="City or preset name (e.g. 'Bratislava-Koliba', 'Liptovsky Mikulas', 'Jasna', 'Plavecke Podhradie') or 'lat,lon' coordinates. Default: Bratislava-Koliba.",
    )
    parser.add_argument(
        "-d",
        "--days",
        type=int,
        default=15,
        choices=range(1, 17),
        help="Forecast duration in days (1 to 16, full AI model horizon). Default: 15.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default=None,
        help="Output file path (e.g. 'bratislava.png' or 'bratislava.svg'). Default: auto-named.",
    )
    parser.add_argument(
        "--lang",
        type=str,
        default="en",
        choices=["en", "sk"],
        help="Language for labels ('en' for English, 'sk' for Slovak). Default: en.",
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
            dpi=args.dpi,
        )
    except Exception as e:
        print(f"[ERROR] Failed to generate meteogram: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
