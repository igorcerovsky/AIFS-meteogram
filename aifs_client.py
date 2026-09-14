"""
ECMWF AIFS (Artificial Intelligence Forecasting System) Open Data Client.
Fetches multi-member ensemble forecast data from ECMWF AIFS via Open-Meteo ensemble API
and sunrise/sunset times for day/night shading.
"""

import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple
import numpy as np


PRESET_LOCATIONS = {
    "bratislava-koliba": {
        "name": "Bratislava - Koliba",
        "country": "Slovakia",
        "latitude": 48.1708,
        "longitude": 17.1086,
        "elevation": 287.0,
        "timezone": "Europe/Bratislava",
    },
    "bratislava koliba": {
        "name": "Bratislava - Koliba",
        "country": "Slovakia",
        "latitude": 48.1708,
        "longitude": 17.1086,
        "elevation": 287.0,
        "timezone": "Europe/Bratislava",
    },
    "koliba": {
        "name": "Bratislava - Koliba",
        "country": "Slovakia",
        "latitude": 48.1708,
        "longitude": 17.1086,
        "elevation": 287.0,
        "timezone": "Europe/Bratislava",
    },
    "liptovsky mikulas": {
        "name": "Liptovský Mikuláš",
        "country": "Slovakia",
        "latitude": 49.0806,
        "longitude": 19.6222,
        "elevation": 577.0,
        "timezone": "Europe/Bratislava",
    },
    "liptovský mikuláš": {
        "name": "Liptovský Mikuláš",
        "country": "Slovakia",
        "latitude": 49.0806,
        "longitude": 19.6222,
        "elevation": 577.0,
        "timezone": "Europe/Bratislava",
    },
    "jasna": {
        "name": "Jasná (Low Tatras)",
        "country": "Slovakia",
        "latitude": 48.9709,
        "longitude": 19.5843,
        "elevation": 1118.0,
        "timezone": "Europe/Bratislava",
    },
    "jasná": {
        "name": "Jasná (Nízke Tatry)",
        "country": "Slovakia",
        "latitude": 48.9709,
        "longitude": 19.5843,
        "elevation": 1118.0,
        "timezone": "Europe/Bratislava",
    },
    "plavecke podhradie": {
        "name": "Plavecké Podhradie",
        "country": "Slovakia",
        "latitude": 48.4860,
        "longitude": 17.2573,
        "elevation": 210.0,
        "timezone": "Europe/Bratislava",
    },
    "plavecké podhradie": {
        "name": "Plavecké Podhradie",
        "country": "Slovakia",
        "latitude": 48.4860,
        "longitude": 17.2573,
        "elevation": 210.0,
        "timezone": "Europe/Bratislava",
    },
}


class AIFSClient:
    GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
    ENSEMBLE_URL = "https://ensemble-api.open-meteo.com/v1/ensemble"
    ASTRONOMY_URL = "https://api.open-meteo.com/v1/forecast"

    def __init__(self):
        self.headers = {"User-Agent": "Meteogram-AIFS/1.0 (ECMWF-AI-Meteogram)"}

    def geocode(self, query: str) -> Dict[str, Any]:
        """Geocode a city or location name to lat, lon, elevation, name, country."""
        normalized = query.strip().lower()
        if normalized in PRESET_LOCATIONS:
            return dict(PRESET_LOCATIONS[normalized])

        # Check if query is in lat,lon format
        if "," in query:
            parts = [p.strip() for p in query.split(",")]
            try:
                lat = float(parts[0])
                lon = float(parts[1])
                return {
                    "name": f"Coord ({lat:.2f}, {lon:.2f})",
                    "country": "",
                    "latitude": lat,
                    "longitude": lon,
                    "elevation": 0.0,
                    "timezone": "auto",
                }
            except ValueError:
                pass

        params = urllib.parse.urlencode(
            {"name": query, "count": 1, "language": "en", "format": "json"}
        )
        url = f"{self.GEOCODING_URL}?{params}"
        req = urllib.request.Request(url, headers=self.headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())

        results = data.get("results", [])
        if not results:
            raise ValueError(f"Location not found for query: '{query}'")

        res = results[0]
        return {
            "name": res.get("name", query),
            "country": res.get("country", ""),
            "latitude": res["latitude"],
            "longitude": res["longitude"],
            "elevation": res.get("elevation", 0.0),
            "timezone": res.get("timezone", "auto"),
        }

    def fetch_sun_times(
        self, latitude: float, longitude: float, days: int = 15
    ) -> List[Tuple[datetime, datetime]]:
        """Fetch sunrise and sunset times for day/night background bands."""
        params = urllib.parse.urlencode(
            {
                "latitude": latitude,
                "longitude": longitude,
                "daily": "sunrise,sunset",
                "forecast_days": min(days + 2, 16),
                "timezone": "UTC",
            }
        )
        url = f"{self.ASTRONOMY_URL}?{params}"
        req = urllib.request.Request(url, headers=self.headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())

        sunrises = data.get("daily", {}).get("sunrise", [])
        sunsets = data.get("daily", {}).get("sunset", [])

        pairs = []
        for rise_str, set_str in zip(sunrises, sunsets):
            if rise_str and set_str:
                rise = datetime.fromisoformat(rise_str).replace(tzinfo=timezone.utc)
                sunset = datetime.fromisoformat(set_str).replace(tzinfo=timezone.utc)
                pairs.append((rise, sunset))
        return pairs

    MODEL_MAPPING = {
        "aifs": {
            "api_model": "ecmwf_aifs025",
            "name": "ECMWF AIFS 0.25°",
            "max_days": 16,
            "default_days": 15,
        },
        "icon_d2": {
            "api_model": "icon_d2",
            "name": "DWD ICON-D2 2.2 km",
            "max_days": 3,
            "default_days": 2,
        },
        "icon_eu": {
            "api_model": "icon_eu",
            "name": "DWD ICON-EU 7.0 km",
            "max_days": 7,
            "default_days": 5,
        },
    }

    def _fetch_open_meteo_raw(
        self, latitude: float, longitude: float, api_model: str, days: int, hourly_vars: List[str]
    ) -> Dict[str, Any]:
        import re
        params = urllib.parse.urlencode(
            {
                "latitude": latitude,
                "longitude": longitude,
                "models": api_model,
                "hourly": ",".join(hourly_vars),
                "forecast_days": days,
                "timezone": "UTC",
            }
        )
        url = f"{self.ENSEMBLE_URL}?{params}"
        req = urllib.request.Request(url, headers=self.headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                raw_content = resp.read().decode()
                # Open-Meteo returns 'nan' without quotes when coordinates are out of model domain
                cleaned = re.sub(r':\s*nan\b', ': null', raw_content)
                return json.loads(cleaned)
        except Exception:
            return {"latitude": None}

    def _is_valid_forecast(self, raw: Dict[str, Any]) -> bool:
        import math
        lat_val = raw.get("latitude")
        if lat_val is None:
            return False
        if isinstance(lat_val, float) and math.isnan(lat_val):
            return False
        time_arr = raw.get("hourly", {}).get("time")
        if not time_arr or len(time_arr) == 0:
            return False
        return True

    def is_icon_d2_available(self, latitude: float, longitude: float) -> bool:
        """Check if coordinates fall within the DWD ICON-D2 domain (Germany & Central Europe)."""
        # ICON-D2 domain: lat ~43.0 to 58.0, lon ~ -2.5 to 18.35
        # Locations in Central/Eastern Slovakia (Jasna at 19.58°E, Liptovsky Mikulas, etc.) are outside.
        if not (43.0 <= latitude <= 58.0 and -2.5 <= longitude <= 18.35):
            return False
        return True

    def fetch_ensemble(
        self, latitude: float, longitude: float, days: int = 15, model: str = "aifs"
    ) -> Dict[str, Any]:
        """
        Fetch multi-member ensemble forecast:
        - aifs: ECMWF AIFS 0.25° (50 members, up to 16 days, Global)
        - icon_d2: DWD ICON-D2 2.2 km (20 members, up to 3 days / 48-72h, Central Europe)
        - icon_eu: DWD ICON-EU 7.0 km (40 members, up to 7 days / 120h, Europe)

        If 2-day data (icon_d2) is unavailable for a given location (e.g. Jasna),
        automatically falls back to the closest available model (icon_eu, or aifs).
        """
        model_key = model.lower() if model else "aifs"
        if model_key not in self.MODEL_MAPPING:
            model_key = "aifs"

        original_model = model_key
        fallback_used = False

        cfg = self.MODEL_MAPPING[model_key]
        actual_days = min(days, cfg["max_days"])
        hourly_vars = [
            "temperature_2m",
            "precipitation",
            "snowfall",
            "cloud_cover",
            "wind_speed_10m",
            "wind_direction_10m",
            "pressure_msl",
        ]

        raw = self._fetch_open_meteo_raw(latitude, longitude, cfg["api_model"], actual_days, hourly_vars)

        if not self._is_valid_forecast(raw):
            # Model data not available for this location (e.g. icon_d2 for Jasna)
            # Automatically switch to closest available model:
            # 1. icon_d2 -> icon_eu (covers all Europe)
            # 2. icon_eu -> aifs (global coverage)
            if model_key == "icon_d2":
                fallback_used = True
                model_key = "icon_eu"
                cfg = self.MODEL_MAPPING["icon_eu"]
                actual_days = min(max(days, 5), cfg["max_days"])
                raw = self._fetch_open_meteo_raw(latitude, longitude, cfg["api_model"], actual_days, hourly_vars)

            if not self._is_valid_forecast(raw) and model_key in ["icon_d2", "icon_eu"]:
                fallback_used = True
                model_key = "aifs"
                cfg = self.MODEL_MAPPING["aifs"]
                actual_days = min(max(days, 10), cfg["max_days"])
                raw = self._fetch_open_meteo_raw(latitude, longitude, cfg["api_model"], actual_days, hourly_vars)

        stats = self._process_ensemble(raw)
        stats["model"] = model_key
        stats["model_fallback"] = fallback_used
        if fallback_used:
            stats["fallback_from"] = original_model
        return stats

    def fetch_aifs_ensemble(
        self, latitude: float, longitude: float, days: int = 15
    ) -> Dict[str, Any]:
        """Backwards-compatible wrapper for fetching ECMWF AIFS ensemble."""
        return self.fetch_ensemble(latitude, longitude, days=days, model="aifs")

    def _process_ensemble(self, raw: Dict[str, Any]) -> Dict[str, Any]:
        """Compute median, 25th, 75th, min, and max across the 50 ensemble members."""
        hourly = raw.get("hourly", {})
        time_strings = hourly.get("time", [])
        times = [
            datetime.fromisoformat(t).replace(tzinfo=timezone.utc)
            for t in time_strings
        ]

        vars_to_process = [
            "temperature_2m",
            "precipitation",
            "snowfall",
            "cloud_cover",
            "wind_speed_10m",
            "wind_direction_10m",
            "pressure_msl",
        ]

        stats = {
            "times": times,
            "elevation": raw.get("elevation", 0),
            "utc_offset_seconds": raw.get("utc_offset_seconds", 0),
        }

        num_timesteps = len(times)

        for var in vars_to_process:
            # Collect deterministic/mean and members
            members_data = []
            # Check default / member 00
            if var in hourly:
                vals = hourly[var]
                if vals and any(v is not None for v in vals):
                    members_data.append([v if v is not None else np.nan for v in vals])

            # Check members 01 through 50
            for m in range(1, 51):
                member_key = f"{var}_member{m:02d}"
                if member_key in hourly:
                    vals = hourly[member_key]
                    members_data.append([v if v is not None else np.nan for v in vals])

            if not members_data:
                arr = np.zeros((1, num_timesteps))
            else:
                arr = np.array(members_data, dtype=float)

            # Special case for circular wind direction: use vector averaging for median direction
            if var == "wind_direction_10m":
                rad = np.deg2rad(arr)
                sin_mean = np.nanmean(np.sin(rad), axis=0)
                cos_mean = np.nanmean(np.cos(rad), axis=0)
                mean_dir = (np.rad2deg(np.arctan2(sin_mean, cos_mean)) + 360) % 360
                stats[var] = {
                    "median": mean_dir,
                    "q25": np.nanpercentile(arr, 25, axis=0),
                    "q75": np.nanpercentile(arr, 75, axis=0),
                    "min": np.nanmin(arr, axis=0),
                    "max": np.nanmax(arr, axis=0),
                    "members_count": arr.shape[0],
                }
            else:
                stats[var] = {
                    "median": np.nanpercentile(arr, 50, axis=0),
                    "q25": np.nanpercentile(arr, 25, axis=0),
                    "q75": np.nanpercentile(arr, 75, axis=0),
                    "min": np.nanmin(arr, axis=0),
                    "max": np.nanmax(arr, axis=0),
                    "members_count": arr.shape[0],
                }

        return stats
