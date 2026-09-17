"""
Meteogram Renderer for ECMWF AIFS (AI Model) Ensemble Data.
Generates high-resolution EPSGRAM-styled charts similar to SHMÚ (Slovak Hydrometeorological Institute).
Panels:
1. Temperature 2m [°C] (TOP PANEL)
2. Total Precipitation & Snow [mm]
3. Cloud Cover [%]
4. Wind Speed & Direction [km/h]
5. Mean Sea Level Pressure [hPa]
"""

import os
import math
import zoneinfo
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple
import matplotlib
matplotlib.use("Agg")  # Non-interactive backend for server/CLI
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import matplotlib.transforms as mtransforms
from matplotlib.lines import Line2D
from matplotlib.patches import Circle, Patch, Polygon
from matplotlib.offsetbox import AnnotationBbox, DrawingArea
import matplotlib.colors as mcolors
import numpy as np
from scipy.interpolate import PchipInterpolator

# Continuous dark colormap for wind speed in m/s (high contrast on daylight and night backgrounds)
WIND_PALETTE_HEX = [
    "#2b2d42",  # 0-2 m/s: calm / charcoal
    "#1d3557",  # 2-5 m/s: light / dark navy
    "#006466",  # 5-8 m/s: gentle / deep petrol
    "#2d6a4f",  # 8-12 m/s: moderate / forest green
    "#b45309",  # 12-16 m/s: fresh / dark amber
    "#9a3412",  # 16-20 m/s: strong / rust
    "#780000",  # 20-25 m/s: gale / deep crimson
    "#4c061d",  # >25 m/s: storm / deep wine
]
WIND_CMAP = mcolors.LinearSegmentedColormap.from_list("dark_wind", WIND_PALETTE_HEX)
WIND_NORM = mcolors.Normalize(vmin=0.0, vmax=24.0)


LANG_TEXTS = {
    "sk": {
        "title_model": "Model: ECMWF AIFS 0.25° Ensemble (50 AI členov)",
        "model_prefix": "Model",
        "models": {
            "aifs": "ECMWF AIFS 0.25° Ensemble (50 AI členov)",
            "icon_d2": "DWD ICON-D2 2.2 km Ensemble (20 členov)",
            "icon_eu": "DWD ICON-EU 7.0 km Ensemble (40 členov)",
        },
        "fallback_notice": "(zmena z ICON-D2: poloha mimo domény)",
        "alt": "Nadm. výška",
        "coord": "Súradnice",
        "run_prefix": "Beh",
        "time_prefix": "Čas",
        "hour_label": "Hodina",
        "temp_title": "Teplota 2 m [°C]",
        "precip_title": "Zrážky [mm / 6h]",
        "precip_title_hourly": "Zrážky [mm / 1h]",
        "precip_title_6h": "Zrážky [mm / 6h]",
        "cloud_title": "Oblačnosť [%]",
        "cloud_total": "Celková",
        "cloud_low": "Nízka",
        "cloud_mid": "Stredná",
        "cloud_high": "Vysoká",
        "wind_title": "Vietor 10 m [km/h]",
        "pressure_title": "Tlak vzduchu (MSLP) [hPa]",
        "days": ["Po", "Ut", "St", "Št", "Pi", "So", "Ne"],
        "min": "Min",
        "max": "Max",
        "sum": "Suma",
        "median": "Medián",
        "iqr": "25-75% percentil",
        "spread": "Rozptyl (Min-Max)",
        "rain": "Dážď",
        "snow": "Sneh",
        "max_precip": "Max úhrn ansámbla",
        "max_precip_hourly": "Max úhrn ansámbla / 1h",
        "max_precip_6h": "Max úhrn ansámbla / 6h",
        "night": "Noc (západ až východ slnka)",
        "sun_alt": "Výška slnka [°]",
        "moon_alt": "Výška mesiaca [°]",
    },
    "en": {
        "title_model": "Model: ECMWF AIFS 0.25° Ensemble (50 AI members)",
        "model_prefix": "Model",
        "models": {
            "aifs": "ECMWF AIFS 0.25° Ensemble (50 AI members)",
            "icon_d2": "DWD ICON-D2 2.2 km Ensemble (20 members)",
            "icon_eu": "DWD ICON-EU 7.0 km Ensemble (40 members)",
        },
        "fallback_notice": "(fallback from ICON-D2: location outside domain)",
        "alt": "Elevation",
        "coord": "Coordinates",
        "run_prefix": "Run",
        "time_prefix": "Time",
        "hour_label": "Hour",
        "temp_title": "2m Temperature [°C]",
        "precip_title": "Precipitation [mm / 6h]",
        "precip_title_hourly": "Precipitation [mm / 1h]",
        "precip_title_6h": "Precipitation [mm / 6h]",
        "cloud_title": "Cloud Cover [%]",
        "cloud_total": "Total",
        "cloud_low": "Low",
        "cloud_mid": "Medium",
        "cloud_high": "High",
        "wind_title": "10m Wind [km/h]",
        "pressure_title": "MSLP Pressure [hPa]",
        "days": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        "min": "Min",
        "max": "Max",
        "sum": "Sum",
        "median": "Median",
        "iqr": "25-75% percentile",
        "spread": "Spread (Min-Max)",
        "rain": "Rain",
        "snow": "Snow",
        "max_precip": "Max ensemble precip",
        "max_precip_hourly": "Max ensemble precip / 1h",
        "max_precip_6h": "Max ensemble precip / 6h",
        "night": "Night (sunset to sunrise)",
        "sun_alt": "Sun altitude [°]",
        "moon_alt": "Moon altitude [°]",
    },
}


def get_solar_altitude(dt_utc: datetime, lat: float, lon: float) -> float:
    """Calculate solar altitude in degrees above horizon (-90 to +90)."""
    t_epoch = dt_utc.timestamp()
    d = (t_epoch - 946728000.0) / 86400.0

    g = (357.529 + 0.98560028 * d) % 360.0
    g_rad = math.radians(g)
    q = (280.459 + 0.98564736 * d) % 360.0
    l_ecl = (q + 1.915 * math.sin(g_rad) + 0.020 * math.sin(2 * g_rad)) % 360.0
    l_rad = math.radians(l_ecl)

    e = 23.439 - 0.00000036 * d
    e_rad = math.radians(e)

    sin_dec = math.sin(e_rad) * math.sin(l_rad)
    dec_rad = math.asin(sin_dec)

    y = math.cos(e_rad) * math.sin(l_rad)
    x = math.cos(l_rad)
    ra_rad = math.atan2(y, x)

    gmst = (280.46061837 + 360.98564736629 * d) % 360.0
    lst_rad = math.radians((gmst + lon) % 360.0)
    ha_rad = lst_rad - ra_rad

    lat_rad = math.radians(lat)
    sin_alt = math.sin(lat_rad) * math.sin(dec_rad) + math.cos(lat_rad) * math.cos(dec_rad) * math.cos(ha_rad)
    return math.degrees(math.asin(max(-1.0, min(1.0, sin_alt))))


def get_lunar_altitude(dt_utc: datetime, lat: float, lon: float) -> float:
    """Calculate lunar altitude in degrees above horizon (-90 to +90)."""
    t_epoch = dt_utc.timestamp()
    d = (t_epoch - 946728000.0) / 86400.0

    l_moon = (218.316 + 13.176396 * d) % 360.0
    m_moon = (134.963 + 13.064993 * d) % 360.0
    f_moon = (93.272 + 13.229350 * d) % 360.0

    m_rad = math.radians(m_moon)
    f_rad = math.radians(f_moon)

    lon_moon = l_moon + 6.289 * math.sin(m_rad)
    lat_moon = 5.128 * math.sin(f_rad)

    lon_rad = math.radians(lon_moon)
    lat_rad_moon = math.radians(lat_moon)

    e = 23.439 - 0.00000036 * d
    e_rad = math.radians(e)

    sin_dec = (math.sin(lat_rad_moon) * math.cos(e_rad) +
               math.cos(lat_rad_moon) * math.sin(e_rad) * math.sin(lon_rad))
    dec_rad = math.asin(max(-1.0, min(1.0, sin_dec)))

    y = (math.sin(lon_rad) * math.cos(e_rad) -
         math.tan(lat_rad_moon) * math.sin(e_rad))
    x = math.cos(lon_rad)
    ra_rad = math.atan2(y, x)

    gmst = (280.46061837 + 360.98564736629 * d) % 360.0
    lst_rad = math.radians((gmst + lon) % 360.0)
    ha_rad = lst_rad - ra_rad

    lat_rad = math.radians(lat)
    sin_alt = (math.sin(lat_rad) * math.sin(dec_rad) +
               math.cos(lat_rad) * math.cos(dec_rad) * math.cos(ha_rad))
    return math.degrees(math.asin(max(-1.0, min(1.0, sin_alt))))


def get_moon_phase_name(phase: float, lang: str = "en") -> str:
    """Return localized moon phase name for a given phase in [0, 1)."""
    p = phase % 1.0
    if p < 0.03 or p >= 0.97:
        return "Nov" if lang == "sk" else "New Moon"
    elif p < 0.22:
        return "Dorastajúci kosák" if lang == "sk" else "Waxing Crescent"
    elif p < 0.28:
        return "Prvá štvrť" if lang == "sk" else "First Quarter"
    elif p < 0.47:
        return "Dorastajúci mesiac" if lang == "sk" else "Waxing Gibbous"
    elif p < 0.53:
        return "Spln" if lang == "sk" else "Full Moon"
    elif p < 0.72:
        return "Cúvajúci mesiac" if lang == "sk" else "Waning Gibbous"
    elif p < 0.78:
        return "Posledná štvrť" if lang == "sk" else "Last Quarter"
    else:
        return "Ubúdajúci kosák" if lang == "sk" else "Waning Crescent"


def create_moon_icon_box(phase: float, size_pt: float = 14.0) -> DrawingArea:
    """
    Creates an OffsetImage/DrawingArea containing a crisp vector-drawn Moon phase disk.
    Zero emoji/font glyph dependencies, renders cleanly at all DPIs.
    Lit side uses a luminous moonish pearl silver-white; unlit side is almost transparent.
    """
    da = DrawingArea(size_pt, size_pt, 0, 0)
    cx = size_pt / 2.0
    cy = size_pt / 2.0
    r = size_pt / 2.0 - 0.5

    theta = np.linspace(0, 2 * np.pi, 80)
    # Dark unlit side circle: almost transparent with subtle delicate perimeter
    dark_circle = Polygon(
        np.column_stack([cx + r * np.cos(theta), cy + r * np.sin(theta)]),
        closed=True,
        facecolor=(0.12, 0.16, 0.24, 0.08),
        edgecolor=(0.35, 0.45, 0.55, 0.40),
        linewidth=0.6,
    )
    da.add_artist(dark_circle)

    # Moonish luminous silvery-pearl tone
    moonish_lit_color = "#f1f5f9"
    moonish_edge_color = (0.35, 0.45, 0.55, 0.45)

    p = phase % 1.0
    if 0.48 <= p <= 0.52:
        # Full Moon: fully lit disc
        full_circle = Circle(
            (cx, cy), r, facecolor=moonish_lit_color, edgecolor=moonish_edge_color, linewidth=0.6
        )
        da.add_artist(full_circle)
    elif 0.02 < p < 0.98:
        phi = np.linspace(-np.pi / 2, np.pi / 2, 40)
        k = math.cos(2 * math.pi * p)
        if p < 0.5:
            # Waxing: lit on right side
            x_limb = cx + r * np.cos(phi)
            y_limb = cy + r * np.sin(phi)
            x_term = cx + r * k * np.cos(phi[::-1])
            y_term = cy + r * np.sin(phi[::-1])
        else:
            # Waning: lit on left side
            x_limb = cx - r * np.cos(phi)
            y_limb = cy + r * np.sin(phi)
            x_term = cx - r * k * np.cos(phi[::-1])
            y_term = cy + r * np.sin(phi[::-1])

        poly_x = np.concatenate([x_limb, x_term])
        poly_y = np.concatenate([y_limb, y_term])
        lit_patch = Polygon(
            np.column_stack([poly_x, poly_y]),
            closed=True,
            facecolor=moonish_lit_color,
            edgecolor=moonish_edge_color,
            linewidth=0.5,
        )
        da.add_artist(lit_patch)

    return da


class MeteogramRenderer:
    def __init__(self, lang: str = "en"):
        self.lang = lang if lang in LANG_TEXTS else "en"
        self.t = LANG_TEXTS[self.lang]

    def render(
        self,
        location_info: Dict[str, Any],
        stats: Dict[str, Any],
        sun_times: List[Tuple[datetime, datetime]],
        output_path: str,
        dpi: int = 200,
        tz_mode: str = "local",
        astro_data: Optional[Dict[str, Any]] = None,
    ) -> str:
        """Render the complete meteogram to output_path (PNG, SVG, or PDF)."""
        raw_times = stats["times"]
        if not raw_times:
            raise ValueError("No forecast time data available.")

        # Resolve Timezone for location
        iana_tz_name = location_info.get("timezone") or stats.get("timezone") or "Europe/Bratislava"
        if iana_tz_name == "auto":
            iana_tz_name = stats.get("timezone") or "Europe/Bratislava"

        try:
            tz_obj = zoneinfo.ZoneInfo(iana_tz_name)
        except Exception:
            tz_obj = zoneinfo.ZoneInfo("Europe/Bratislava")

        raw_start = raw_times[0]

        # Determine target active timezone and descriptive labels based on tz_mode ("local" or "utc")
        if tz_mode == "utc":
            active_tz = timezone.utc
            tz_badge = "UTC"
            tz_label = "UTC"
        else:
            # "local" (default): current local time (summer or winter at the time of rendering)
            now_local = datetime.now(tz=tz_obj)
            now_offset = now_local.utcoffset() or timedelta(0)
            now_name = now_local.tzname() or ""
            active_tz = timezone(now_offset, name=now_name) if now_name else timezone(now_offset)
            hrs = int(now_offset.total_seconds() // 3600)
            sign = "+" if hrs >= 0 else ""
            tz_badge = now_name if now_name else f"UTC{sign}{hrs}"
            if self.lang == "en":
                tz_label = f"Local Time ({tz_badge}, UTC{sign}{hrs})"
            else:
                tz_label = f"Miestny čas ({tz_badge}, UTC{sign}{hrs})"

        # Convert forecast times to active timezone
        times = [t.astimezone(active_tz) for t in raw_times]
        start_time = times[0]
        end_time = times[-1]
        forecast_days = (end_time - start_time).total_seconds() / 86400.0

        # Convert sun times to active timezone
        sun_times_tz = [
            (rise.astimezone(active_tz), sset.astimezone(active_tz))
            for rise, sset in sun_times
        ]

        # Precompute celestial ephemeris (sun & moon altitude trajectories and peaks)
        celestial_data = self._compute_celestial_data(start_time, end_time, location_info, astro_data)

        # Convert times to matplotlib numerical dates for smooth plotting
        num_times = mdates.date2num(times)
        # Dense grid for silky-smooth continuous curve interpolation (PCHIP monotonic cubic splines)
        num_dense_points = max(len(num_times) * 6, 600)
        num_times_dense = np.linspace(num_times[0], num_times[-1], num_dense_points)

        # Scale width dynamically based on duration (from 14 inches up to 24 inches for 15 days)
        fig_width = max(14.0, min(24.0, 10.0 + forecast_days * 0.9))
        fig_height = 18.0

        # Create Figure with 5 subplots (Temperature on top!)
        fig, axes = plt.subplots(
            nrows=5,
            ncols=1,
            figsize=(fig_width, fig_height),
            sharex=True,
            gridspec_kw={
                "height_ratios": [2.5, 1.8, 1.5, 1.9, 1.6],
                "hspace": 0.22,
                "top": 0.938,
                "bottom": 0.068,
                "left": 0.075,
                "right": 0.965,
            },
        )

        ax_temp, ax_precip, ax_cloud, ax_wind, ax_press = axes

        # Apply night background shading across all axes
        self._draw_night_shading(axes, sun_times_tz, start_time, end_time)

        # -------------------------------------------------------------
        # PANEL 1: TEMPERATURE 2M (TOP PANEL - As requested)
        # -------------------------------------------------------------
        temp = stats["temperature_2m"]
        temp_smooth = self._smooth_envelope(num_times, temp, num_times_dense)
        ax_temp.fill_between(
            num_times_dense,
            temp_smooth["min"],
            temp_smooth["max"],
            color="#ffccd5",
            alpha=0.6,
            label=self.t["spread"],
        )
        ax_temp.fill_between(
            num_times_dense,
            temp_smooth["q25"],
            temp_smooth["q75"],
            color="#ff4d6d",
            alpha=0.45,
            label=self.t["iqr"],
        )
        ax_temp.plot(
            num_times_dense,
            temp_smooth["median"],
            color="#a4161a",
            linewidth=2.4,
            label=self.t["median"],
            zorder=4,
        )

        # Thicker lines to -10, 0, 10, 20, 30 degrees with distinctive light colors:
        # -10: light blue, 0: blue, 10: yellow, 20: orange, 30: red
        temp_levels = [
            (-10, "#38bdf8", " -10°C"),  # light blue
            (0,   "#0284c7", "   0°C"),  # blue
            (10,  "#eab308", "  10°C"),  # yellow
            (20,  "#f97316", "  20°C"),  # orange
            (30,  "#ef4444", "  30°C"),  # red
        ]

        t_min_data = float(np.nanmin(temp["min"]))
        t_max_data = float(np.nanmax(temp["max"]))
        y_min = min(-2.0, t_min_data - 2.0)
        y_max = max(32.0, t_max_data + 3.0)
        if t_min_data < -8.0:
            y_min = min(-12.0, t_min_data - 2.0)
        ax_temp.set_ylim(y_min, y_max)

        for deg, color, lbl in temp_levels:
            if y_min <= deg <= y_max:
                ax_temp.axhline(deg, color=color, linestyle="--", linewidth=1.5, alpha=0.85, zorder=3)
                ax_temp.text(
                    num_times[-1],
                    deg,
                    lbl,
                    verticalalignment="center",
                    ha="left",
                    fontsize=8.5,
                    fontweight="bold",
                    color=color,
                    zorder=5,
                )

        # Annotate daily min / max temperatures for the median curve
        self._annotate_daily_temp(ax_temp, times, num_times, temp["median"])

        # -------------------------------------------------------------
        # CELESTIAL ALTITUDE TRAJECTORIES (Sun & Moon) on Background Twin Axis
        # -------------------------------------------------------------
        self._draw_celestial_trajectories(ax_temp, forecast_days, celestial_data)

        ax_temp.set_ylabel(self.t["temp_title"], fontsize=10.5, fontweight="bold", color="#800f2f")
        ax_temp.grid(True, linestyle=":", alpha=0.45, color="#94a3b8", zorder=1)

        # Include Night shading, Sun & Moon altitude in legend
        handles, labels = ax_temp.get_legend_handles_labels()
        night_patch = Patch(facecolor="#c8d1d9", edgecolor="none", alpha=0.75, label=self.t["night"])
        handles.append(night_patch)
        labels.append(self.t["night"])
        sun_line = Line2D([], [], color="#f4a261", linestyle="--", linewidth=1.2, alpha=0.85, label=self.t["sun_alt"])
        moon_line = Line2D([], [], color="#00b4d8", linestyle=":", linewidth=1.3, alpha=0.85, label=self.t["moon_alt"])
        handles.extend([sun_line, moon_line])
        labels.extend([self.t["sun_alt"], self.t["moon_alt"]])
        ax_temp.legend(handles=handles, labels=labels, loc="upper right", framealpha=0.92, fontsize=8.0, ncol=6)

        # -------------------------------------------------------------
        # PANEL 2: PRECIPITATION & SNOWFALL (Hourly for high-res / 6h for long range)
        # -------------------------------------------------------------
        precip_raw = stats["precipitation"]
        snow_raw = stats["snowfall"]
        active_model = stats.get("model", "aifs")
        is_hourly = (active_model in ["icon_d2", "icon_eu"]) or (forecast_days <= 5.5)

        step_hours = (times[1] - times[0]).total_seconds() / 3600.0 if len(times) > 1 else 1.0

        if is_hourly:
            if step_hours < 0.9:
                # 15-minute (or sub-hourly) data: aggregate precipitation and snowfall into 1-hour blocks
                # so the bars strictly represent standard mm / 1h
                blocks: Dict[datetime, List[int]] = {}
                for i, t in enumerate(times):
                    block_dt = t.replace(minute=0, second=0, microsecond=0)
                    blocks.setdefault(block_dt, []).append(i)

                block_dts = sorted(blocks.keys())
                bar_num_times = [mdates.date2num(b + timedelta(minutes=30)) for b in block_dts]
                bar_width = (1.0 / 24.0) * 0.78

                rain_1h = []
                snow_1h = []
                max_precip_1h = []
                for b_dt in block_dts:
                    idxs = blocks[b_dt]
                    p_med_sum = float(np.sum(precip_raw["median"][idxs]))
                    s_med_sum = float(np.sum(snow_raw["median"][idxs]))
                    r_med_sum = max(0.0, p_med_sum - s_med_sum)
                    rain_1h.append(r_med_sum)
                    snow_1h.append(s_med_sum)
                    max_precip_1h.append(float(np.sum(precip_raw["max"][idxs])))

                rain_vals = np.array(rain_1h)
                snow_vals = np.array(snow_1h)
                max_precip_vals = np.array(max_precip_1h)
            else:
                bar_num_times = num_times
                bar_width = (1.0 / 24.0) * 0.78
                p_med = np.nan_to_num(precip_raw["median"], nan=0.0)
                s_med = np.nan_to_num(snow_raw["median"], nan=0.0)
                rain_vals = np.maximum(0.0, p_med - s_med)
                snow_vals = s_med
                max_precip_vals = np.nan_to_num(precip_raw["max"], nan=0.0)

            p_title = self.t.get("precip_title_hourly", self.t["precip_title"])
            max_precip_label = self.t.get("max_precip_hourly", self.t["max_precip"])
            edge_lw = 0.5
            marker_size = 5.5
        else:
            # Aggregate hourly data into 6-hour blocks for medium/long range (AIFS 10-15 days)
            blocks: Dict[datetime, List[int]] = {}
            for i, t in enumerate(times):
                block_start_hour = (t.hour // 6) * 6
                block_dt = t.replace(hour=block_start_hour, minute=0, second=0, microsecond=0)
                blocks.setdefault(block_dt, []).append(i)

            block_dts = sorted(blocks.keys())
            bar_num_times = [mdates.date2num(b + timedelta(hours=3)) for b in block_dts]
            bar_width = (6.0 / 24.0) * 0.82  # ~5 hours wide in days

            rain_6h = []
            snow_6h = []
            max_precip_6h = []

            for b_dt in block_dts:
                idxs = blocks[b_dt]
                p_med_sum = float(np.sum(precip_raw["median"][idxs]))
                s_med_sum = float(np.sum(snow_raw["median"][idxs]))
                r_med_sum = max(0.0, p_med_sum - s_med_sum)
                rain_6h.append(r_med_sum)
                snow_6h.append(s_med_sum)
                max_precip_6h.append(float(np.sum(precip_raw["max"][idxs])))

            rain_vals = np.array(rain_6h)
            snow_vals = np.array(snow_6h)
            max_precip_vals = np.array(max_precip_6h)
            p_title = self.t.get("precip_title_6h", self.t["precip_title"])
            max_precip_label = self.t.get("max_precip_6h", self.t["max_precip"])
            edge_lw = 0.8
            marker_size = 9.0

        # Plot stacked bars with clean edges
        ax_precip.bar(
            bar_num_times,
            rain_vals,
            width=bar_width,
            color="#1d70b8",
            edgecolor="#0f4c81",
            linewidth=edge_lw,
            alpha=0.85,
            label=self.t["rain"],
            zorder=3,
        )
        ax_precip.bar(
            bar_num_times,
            snow_vals,
            bottom=rain_vals,
            width=bar_width,
            color="#00b4d8",
            edgecolor="#0077b6",
            linewidth=edge_lw,
            alpha=0.9,
            label=self.t["snow"],
            zorder=3,
        )

        # Error ticks for ensemble max spread
        ax_precip.plot(
            bar_num_times,
            max_precip_vals,
            color="#03045e",
            linestyle="",
            marker="_",
            markersize=marker_size,
            markeredgewidth=1.8,
            alpha=0.85,
            label=max_precip_label,
            zorder=4,
        )

        # Better scaling for precipitation: Square-root scale allows small amounts (0.1 - 2mm)
        # to be clearly visible while still cleanly accommodating heavy rain without squashing!
        max_p_val = max(2.5, float(np.nanmax(max_precip_vals)) * 1.25)
        ax_precip.set_yscale("function", functions=(lambda v: np.sqrt(np.maximum(0, v)), lambda v: v**2))
        ax_precip.set_ylim(0, max_p_val)

        possible_ticks = [0, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 20.0, 30.0, 50.0]
        precip_ticks = [t for t in possible_ticks if t <= max_p_val]
        if len(precip_ticks) < 4:
            precip_ticks = [0, 0.5, 1.0, 2.0, max_p_val]
        ax_precip.set_yticks(precip_ticks)
        ax_precip.set_yticklabels([f"{t:g}" for t in precip_ticks], fontsize=8.5)

        # Annotate daily precipitation sum
        self._annotate_daily_precip(ax_precip, times, num_times, precip_raw["median"])

        ax_precip.set_ylabel(p_title, fontsize=10, fontweight="bold", color="#0077b6")
        ax_precip.grid(True, linestyle=":", alpha=0.55, color="#6c757d", zorder=1)
        ax_precip.legend(loc="upper right", framealpha=0.9, fontsize=8.5, ncol=3)

        # -------------------------------------------------------------
        # PANEL 3: CLOUD COVER (Multi-layer differentiated by colors)
        # -------------------------------------------------------------
        cloud_total = stats["cloud_cover"]
        cloud_low = stats.get("cloud_cover_low")
        cloud_mid = stats.get("cloud_cover_mid")
        cloud_high = stats.get("cloud_cover_high")

        cloud_total_smooth = self._smooth_envelope(
            num_times, cloud_total, num_times_dense, clip_min=0.0, clip_max=100.0
        )

        # Soft background spread of total cloud cover (transparent dark blue variants)
        ax_cloud.fill_between(
            num_times_dense,
            cloud_total_smooth["min"],
            cloud_total_smooth["max"],
            color="#1e3a8a",
            alpha=0.10,
            zorder=2,
        )
        ax_cloud.fill_between(
            num_times_dense,
            cloud_total_smooth["q25"],
            cloud_total_smooth["q75"],
            color="#1e3a8a",
            alpha=0.22,
            zorder=2,
        )

        # Plot 4 distinct curves with thicker lines
        # 1. Total Cloud Cover: Deep Dark Blue (#1e3a8a), thick line (lw=2.8)
        ax_cloud.plot(
            num_times_dense,
            cloud_total_smooth["median"],
            color="#1e3a8a",
            linewidth=2.8,
            label=f"{self.t['cloud_total']}",
            zorder=6,
        )

        # 2. High Clouds: Vivid Cyan / Sky Blue (#0096c7), thick line (lw=2.4)
        if cloud_high is not None and "median" in cloud_high:
            c_high_smooth = self._smooth_curve(
                num_times, cloud_high["median"], num_times_dense, clip_min=0.0, clip_max=100.0
            )
            ax_cloud.plot(
                num_times_dense,
                c_high_smooth,
                color="#0096c7",
                linewidth=2.4,
                label=f"{self.t['cloud_high']}",
                zorder=5,
            )

        # 3. Medium Clouds: Emerald Teal / Jade Green (#2a9d8f), thick line (lw=2.4)
        if cloud_mid is not None and "median" in cloud_mid:
            c_mid_smooth = self._smooth_curve(
                num_times, cloud_mid["median"], num_times_dense, clip_min=0.0, clip_max=100.0
            )
            ax_cloud.plot(
                num_times_dense,
                c_mid_smooth,
                color="#2a9d8f",
                linewidth=2.4,
                label=f"{self.t['cloud_mid']}",
                zorder=4,
            )

        # 4. Low Clouds: Deep Crimson / Burgundy (#c1121f), thick line (lw=2.4)
        if cloud_low is not None and "median" in cloud_low:
            c_low_smooth = self._smooth_curve(
                num_times, cloud_low["median"], num_times_dense, clip_min=0.0, clip_max=100.0
            )
            ax_cloud.plot(
                num_times_dense,
                c_low_smooth,
                color="#c1121f",
                linewidth=2.4,
                label=f"{self.t['cloud_low']}",
                zorder=3,
            )

        ax_cloud.set_ylabel(self.t["cloud_title"], fontsize=10, fontweight="bold", color="#1e3a8a")
        ax_cloud.set_ylim(-2, 104)
        ax_cloud.set_yticks([0, 25, 50, 75, 100])
        ax_cloud.grid(True, linestyle=":", alpha=0.55, color="#6c757d", zorder=1)
        ax_cloud.legend(loc="upper right", framealpha=0.92, fontsize=8.5, ncol=4)

        # -------------------------------------------------------------
        # PANEL 4: WIND SPEED & DIRECTION
        # -------------------------------------------------------------
        wind_spd = stats["wind_speed_10m"]
        wind_dir = stats["wind_direction_10m"]
        wind_spd_smooth = self._smooth_envelope(
            num_times, wind_spd, num_times_dense, clip_min=0.0
        )

        ax_wind.fill_between(
            num_times_dense,
            wind_spd_smooth["min"],
            wind_spd_smooth["max"],
            color="#d8b4a0",
            alpha=0.55,
            label=self.t["spread"],
        )
        ax_wind.fill_between(
            num_times_dense,
            wind_spd_smooth["q25"],
            wind_spd_smooth["q75"],
            color="#bc6c25",
            alpha=0.45,
            label=self.t["iqr"],
        )
        ax_wind.plot(
            num_times_dense,
            wind_spd_smooth["median"],
            color="#603808",
            linewidth=2.2,
            label=self.t["median"],
            zorder=4,
        )

        y_max_wind = max(35.0, float(np.nanmax(wind_spd["max"])) * 1.3)
        ax_wind.set_ylim(0, y_max_wind)
        # Draw clean, thin meteorological wind arrows distributed vertically by azimuth
        # Start of vector: North (0°) at top, South (180°) at bottom
        # Arrow length scaled by wind speed in m/s (reference: 10 m/s)
        ref_spd_ms = 10.0
        ref_len_x = 0.016 * (num_times[-1] - num_times[0])
        ref_len_y = y_max_wind * 0.10
        max_scale = 1.9

        # Margins ensure the vector in any orientation stays comfortably within the pane bounds
        margin_y = ref_len_y * max_scale * 1.08
        y_top = y_max_wind - margin_y
        y_bottom = margin_y
        y_mid = (y_top + y_bottom) / 2.0
        y_span = (y_top - y_bottom) / 2.0

        dt_hours = (times[1] - times[0]).total_seconds() / 3600.0 if len(times) > 1 else 1.0
        if forecast_days <= 2.5:
            target_arrow_interval_hours = 2.0  # clean sparse 2h steps for 48h
        elif forecast_days <= 5.5:
            target_arrow_interval_hours = 3.5  # clean sparse steps for 5d
        else:
            target_arrow_interval_hours = max(6.0, (forecast_days * 24.0) / 24.0)
        step = max(1, int(round(target_arrow_interval_hours / dt_hours)))

        for i in range(0, len(num_times), step):
            t_val = num_times[i]
            deg = wind_dir["median"][i]
            spd_kmh = wind_spd["median"][i]
            spd_ms = spd_kmh / 3.6

            # Scale arrow length proportional to speed in m/s
            scale = max(0.25, min(max_scale, spd_ms / ref_spd_ms))
            u_len = ref_len_x * scale
            v_len = ref_len_y * scale

            # Vector start anchored by azimuth: North (0 deg) -> top, South (180 deg) -> bottom
            y_start = y_mid + y_span * np.cos(np.deg2rad(deg))

            # Meteorological convention: arrow points in direction wind blows to
            blow_to_rad = np.deg2rad(270 - deg)
            u = u_len * np.cos(blow_to_rad)
            v = v_len * np.sin(blow_to_rad)

            arrow_color = WIND_CMAP(WIND_NORM(spd_ms))

            ax_wind.annotate(
                "",
                xy=(t_val + u, y_start + v),
                xytext=(t_val, y_start),
                arrowprops=dict(
                    arrowstyle="->,head_width=0.22,head_length=0.32",
                    color=arrow_color,
                    lw=0.9,
                    shrinkA=0,
                    shrinkB=0,
                ),
                zorder=5,
            )

        # Wind speed reference arrow length legend in m/s at top-left of pane
        ref_ax_len = 0.016  # exactly matches ref_len_x in axis fraction
        color_10 = WIND_CMAP(WIND_NORM(10.0))

        ax_wind.text(
            0.014, 0.91,
            " " * 20,
            transform=ax_wind.transAxes,
            fontsize=8.5,
            va="center",
            bbox=dict(boxstyle="round,pad=0.28", fc="#ffffff", ec="#ced4da", lw=0.7, alpha=0.92),
            zorder=6,
        )
        ax_wind.annotate(
            "",
            xy=(0.019 + ref_ax_len, 0.91),
            xytext=(0.019, 0.91),
            xycoords="axes fraction",
            arrowprops=dict(
                arrowstyle="->,head_width=0.22,head_length=0.32",
                color=color_10,
                lw=1.0,
            ),
            zorder=7,
        )
        ax_wind.text(
            0.019 + ref_ax_len + 0.005, 0.91,
            "10 m/s",
            transform=ax_wind.transAxes,
            fontsize=7.8,
            fontweight="bold",
            color="#343a40",
            va="center",
            zorder=7,
        )

        ax_wind.set_ylabel(self.t["wind_title"], fontsize=10, fontweight="bold", color="#7f4f24")
        ax_wind.grid(True, linestyle=":", alpha=0.55, color="#6c757d")
        ax_wind.legend(loc="upper right", framealpha=0.9, fontsize=8.5, ncol=3)

        # -------------------------------------------------------------
        # PANEL 5: MEAN SEA LEVEL PRESSURE (MSLP)
        # -------------------------------------------------------------
        press = stats["pressure_msl"]
        press_smooth = self._smooth_envelope(num_times, press, num_times_dense)
        ax_press.fill_between(
            num_times_dense,
            press_smooth["min"],
            press_smooth["max"],
            color="#d8f3dc",
            alpha=0.6,
            label=self.t["spread"],
        )
        ax_press.fill_between(
            num_times_dense,
            press_smooth["q25"],
            press_smooth["q75"],
            color="#74c69d",
            alpha=0.5,
            label=self.t["iqr"],
        )
        ax_press.plot(
            num_times_dense,
            press_smooth["median"],
            color="#1b4332",
            linewidth=2.2,
            label=self.t["median"],
            zorder=4,
        )

        p_min = np.nanmin(press["min"])
        p_max = np.nanmax(press["max"])
        margin = max(4.0, (p_max - p_min) * 0.18)
        ax_press.set_ylim(p_min - margin, p_max + margin)

        ax_press.set_ylabel(self.t["pressure_title"], fontsize=9.5, fontweight="bold", color="#2d6a4f")
        ax_press.grid(True, linestyle=":", alpha=0.55, color="#6c757d")

        # Celestial altitude trajectories on twin axis in pressure panel
        self._draw_celestial_trajectories(ax_press, forecast_days, celestial_data)

        handles, labels = ax_press.get_legend_handles_labels()
        sun_line = Line2D([], [], color="#f4a261", linestyle="--", linewidth=1.2, alpha=0.85, label=self.t["sun_alt"])
        moon_line = Line2D([], [], color="#00b4d8", linestyle=":", linewidth=1.3, alpha=0.85, label=self.t["moon_alt"])
        handles.extend([sun_line, moon_line])
        labels.extend([self.t["sun_alt"], self.t["moon_alt"]])
        ax_press.legend(handles=handles, labels=labels, loc="upper right", framealpha=0.92, fontsize=8.0, ncol=5)

        # -------------------------------------------------------------
        # TIMELINE CONFIGURATION & LABELS ACROSS ALL PANES
        # -------------------------------------------------------------
        self._format_axes_timeline(
            fig, axes, start_time, end_time, active_tz, tz_badge, sun_times_tz, astro_data=astro_data
        )

        # Super Title / Header banner
        loc_name = location_info.get("name", "Unknown")
        country = location_info.get("country", "")
        loc_str = f"{loc_name}, {country}" if country else loc_name
        lat = location_info.get("latitude", 0.0)
        lon = location_info.get("longitude", 0.0)
        elev = location_info.get("elevation", stats.get("elevation", 0))

        run_time_str = raw_start.astimezone(active_tz).strftime("%Y-%m-%d %H:%M")

        header_title = f"{loc_str} ({lat:.2f}°N, {lon:.2f}°E, {self.t['alt']}: {elev:.0f} m)"
        
        active_model = stats.get("model", "aifs")
        model_desc = self.t.get("models", {}).get(active_model, self.t["title_model"])
        if stats.get("model_fallback"):
            model_desc += f" {self.t.get('fallback_notice', '')}"
        model_header = f"{self.t['model_prefix']}: {model_desc}"

        header_sub = (
            f"{model_header}  |  "
            f"{self.t['run_prefix']}: {run_time_str} ({tz_badge})  |  "
            f"{self.t['time_prefix']}: {tz_label}"
        )

        fig.text(
            0.075,
            0.972,
            header_title,
            fontsize=15,
            fontweight="bold",
            color="#14213d",
            ha="left",
        )
        fig.text(
            0.075,
            0.948,
            header_sub,
            fontsize=10.5,
            color="#4a4e69",
            ha="left",
        )

        # Save to file
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        plt.savefig(output_path, dpi=dpi, facecolor="white", edgecolor="none")
        plt.close(fig)
        return output_path

    def _draw_night_shading(
        self,
        axes: List[plt.Axes],
        sun_times: List[Tuple[datetime, datetime]],
        start_time: datetime,
        end_time: datetime,
    ):
        """Draw night bands (grey rectangle between sunset and sunrise) across all panels."""
        if not sun_times:
            return

        night_intervals = []
        for i in range(len(sun_times)):
            rise, sset = sun_times[i]
            if i == 0 and start_time < rise:
                night_intervals.append((start_time, rise))
            if i < len(sun_times) - 1:
                next_rise = sun_times[i + 1][0]
                night_intervals.append((sset, next_rise))
            else:
                night_intervals.append((sset, end_time))

        for ax in axes:
            for n_start, n_end in night_intervals:
                clamped_start = max(start_time, n_start)
                clamped_end = min(end_time, n_end)
                if clamped_start < clamped_end:
                    x0 = mdates.date2num(clamped_start)
                    x1 = mdates.date2num(clamped_end)
                    ax.axvspan(x0, x1, color="#c8d1d9", alpha=0.75, zorder=0)

            # Mark midnight (00:00 local time) with solid dark vertical line across all panels
            current_day = start_time.replace(hour=0, minute=0, second=0, microsecond=0)
            while current_day <= end_time + timedelta(days=1):
                if current_day >= start_time and current_day <= end_time:
                    ax.axvline(
                        mdates.date2num(current_day),
                        color="#495057",
                        linestyle="-",
                        linewidth=1.1,
                        alpha=0.45,
                        zorder=2,
                    )
                current_day += timedelta(days=1)

        # Draw subtle warm yellowish daytime background across all panels
        if axes is not None:
            for ax in axes:
                for rise, sset in sun_times:
                    clamped_rise = max(start_time, rise)
                    clamped_sset = min(end_time, sset)
                    if clamped_rise < clamped_sset:
                        x0 = mdates.date2num(clamped_rise)
                        x1 = mdates.date2num(clamped_sset)
                        ax.axvspan(x0, x1, color="#fef9c3", alpha=0.65, zorder=0)

    def _format_axes_timeline(
        self,
        fig: plt.Figure,
        axes: List[plt.Axes],
        start_time: datetime,
        end_time: datetime,
        active_tz: Any,
        tz_badge: str,
        sun_times_tz: Optional[List[Tuple[datetime, datetime]]] = None,
        astro_data: Optional[Dict[str, Any]] = None,
    ):
        """Format X-axes on all panes: ticks and day badges both between graph panes and at the bottom with sunrise/sunset and moon phase."""
        x_min = mdates.date2num(start_time)
        x_max = mdates.date2num(end_time)

        forecast_days = (end_time - start_time).total_seconds() / 86400.0

        def get_sun_pair(target_day: datetime) -> Optional[Tuple[datetime, datetime]]:
            if not sun_times_tz:
                return None
            midday = target_day + timedelta(hours=12)
            best_pair = None
            min_diff = None
            for r, s in sun_times_tz:
                solar_noon = r + (s - r) / 2
                diff = abs((solar_noon - midday).total_seconds())
                if min_diff is None or diff < min_diff:
                    min_diff = diff
                    best_pair = (r, s)
            if min_diff is not None and min_diff < 18 * 3600:
                return best_pair
            return None

        for p_idx, ax in enumerate(axes):
            ax.set_xlim(x_min, x_max)
            is_bottom = (p_idx == len(axes) - 1)

            if forecast_days <= 2.5:
                # 48-hour high-res model (ICON-D2):
                # Major ticks every 3 hours with labels (00, 03, 06, 09, 12, 15, 18, 21)
                hours_locator = mdates.HourLocator(byhour=[0, 3, 6, 9, 12, 15, 18, 21], tz=active_tz)
                minor_locator = mdates.HourLocator(interval=1, tz=active_tz)
                ax.xaxis.set_minor_locator(minor_locator)
                ax.grid(True, which="minor", axis="x", linestyle=":", alpha=0.35, color="#cbd5e1", zorder=1)
                ax.tick_params(axis="x", which="minor", length=2, color="#94a3b8")
            elif forecast_days <= 5.5:
                # 5-day model (ICON-EU):
                # Major ticks every 6 hours, minor ticks every 3 hours with subtle grid
                hours_locator = mdates.HourLocator(byhour=[0, 6, 12, 18], tz=active_tz)
                minor_locator = mdates.HourLocator(byhour=[0, 3, 6, 9, 12, 15, 18, 21], tz=active_tz)
                ax.xaxis.set_minor_locator(minor_locator)
                ax.grid(True, which="minor", axis="x", linestyle=":", alpha=0.30, color="#cbd5e1", zorder=1)
                ax.tick_params(axis="x", which="minor", length=2, color="#94a3b8")
            else:
                # Medium/long range (AIFS):
                hours_locator = mdates.HourLocator(byhour=[0, 6, 12, 18], tz=active_tz)

            ax.xaxis.set_major_locator(hours_locator)
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%H", tz=active_tz))
            ax.tick_params(axis="x", which="major", labelbottom=True, labelsize=8, length=3, pad=2)

            # Use point offset so badges are placed at identical physical distances regardless of subplot height
            badge_y_offset = -28 if is_bottom else -18
            trans_badge = mtransforms.offset_copy(ax.get_xaxis_transform(), fig=fig, y=badge_y_offset, units="points")

            curr = start_time.replace(hour=0, minute=0, second=0, microsecond=0)
            while curr <= end_time:
                midday = curr + timedelta(hours=12)
                num_mid = mdates.date2num(midday)
                if num_mid >= x_min and num_mid <= x_max:
                    day_name = self.t["days"][curr.weekday()]
                    date_str = curr.strftime("%d.%m.")
                    if is_bottom:
                        sun_str = ""
                        pair = get_sun_pair(curr)
                        if pair:
                            r, s = pair
                            sun_str = f"\n☀ {r.strftime('%H:%M')} – {s.strftime('%H:%M')}"

                        moon_str = ""
                        if astro_data and "daily" in astro_data:
                            curr_d_str = curr.strftime("%Y-%m-%d")
                            if curr_d_str in astro_data["daily"]:
                                d_info = astro_data["daily"][curr_d_str]
                                m_ph = d_info.get("moon_phase", 0.0)
                                m_illum = d_info.get("illum_pct", 0)
                                m_ph_name = get_moon_phase_name(m_ph, self.lang)

                                mrise = d_info.get("moonrise")
                                mset = d_info.get("moonset")
                                mr_str = mrise.astimezone(active_tz).strftime('%H:%M') if mrise else "--:--"
                                ms_str = mset.astimezone(active_tz).strftime('%H:%M') if mset else "--:--"

                                if forecast_days > 8.0:
                                    moon_str = f"\n☾ {mr_str} – {ms_str} ({m_illum}%)"
                                else:
                                    moon_str = f"\n☾ {mr_str} – {ms_str}\n{m_ph_name} ({m_illum}%)"

                        badge_text = f"{day_name} {date_str}{sun_str}{moon_str}"
                        fontsize = 7.0 if forecast_days > 10 else 7.8
                        pad = 0.28
                    else:
                        badge_text = f"{day_name} {date_str}"
                        fontsize = 8.0
                        pad = 0.18

                    ax.text(
                        num_mid,
                        0,
                        badge_text,
                        ha="center",
                        va="top",
                        fontsize=fontsize,
                        fontweight="bold",
                        color="#1e293b",
                        transform=trans_badge,
                        bbox=dict(boxstyle=f"square,pad={pad}", fc="#f8fafc", ec="#cbd5e1", lw=0.75, alpha=0.94),
                        zorder=10,
                    )
                curr += timedelta(days=1)

    @staticmethod
    def _smooth_curve(
        x: np.ndarray,
        y: np.ndarray,
        x_dense: np.ndarray,
        clip_min: Optional[float] = None,
        clip_max: Optional[float] = None,
    ) -> np.ndarray:
        """Interpolate curve using shape-preserving monotonic cubic spline (PCHIP) to eliminate angular spikiness."""
        if len(x) < 3:
            return np.interp(x_dense, x, y)
        valid = ~np.isnan(y)
        if np.sum(valid) < 3:
            return np.interp(x_dense, x, y)
        pchip = PchipInterpolator(x[valid], y[valid], extrapolate=True)
        res = pchip(x_dense)
        if clip_min is not None:
            res = np.maximum(clip_min, res)
        if clip_max is not None:
            res = np.minimum(clip_max, res)
        return res

    @classmethod
    def _smooth_envelope(
        cls,
        x: np.ndarray,
        stats_dict: Dict[str, np.ndarray],
        x_dense: np.ndarray,
        clip_min: Optional[float] = None,
        clip_max: Optional[float] = None,
    ) -> Dict[str, np.ndarray]:
        """Interpolate full statistical envelope (min, q25, median, q75, max) while strictly preserving ordering."""
        med = cls._smooth_curve(x, stats_dict["median"], x_dense, clip_min, clip_max)
        q25 = cls._smooth_curve(x, stats_dict["q25"], x_dense, clip_min, clip_max)
        q75 = cls._smooth_curve(x, stats_dict["q75"], x_dense, clip_min, clip_max)
        mn = cls._smooth_curve(x, stats_dict["min"], x_dense, clip_min, clip_max)
        mx = cls._smooth_curve(x, stats_dict["max"], x_dense, clip_min, clip_max)

        # Enforce strict envelope ordering: min <= q25 <= med <= q75 <= max
        q25 = np.minimum(q25, med)
        q75 = np.maximum(q75, med)
        mn = np.minimum(mn, q25)
        mx = np.maximum(mx, q75)
        return {"median": med, "q25": q25, "q75": q75, "min": mn, "max": mx}

    def _annotate_daily_temp(
        self,
        ax: plt.Axes,
        times: List[datetime],
        num_times: np.ndarray,
        median_temp: np.ndarray,
    ):
        """Annotate daily minimum and maximum temperature values on the top graph."""
        days_map: Dict[str, List[int]] = {}
        for idx, t in enumerate(times):
            day_str = t.strftime("%Y-%m-%d")
            days_map.setdefault(day_str, []).append(idx)

        dt_hours = (times[1] - times[0]).total_seconds() / 3600.0 if len(times) > 1 else 1.0
        min_indices_required = max(3, int(6.0 / dt_hours))

        for day_str, indices in days_map.items():
            if len(indices) < min_indices_required:
                continue
            day_temps = [median_temp[i] for i in indices]
            min_val = min(day_temps)
            max_val = max(day_temps)

            min_idx = indices[day_temps.index(min_val)]
            max_idx = indices[day_temps.index(max_val)]

            ax.annotate(
                f"{max_val:.1f}°",
                xy=(num_times[max_idx], max_val),
                xytext=(0, 6),
                textcoords="offset points",
                ha="center",
                fontsize=8.5,
                fontweight="bold",
                color="#b7094c",
                bbox=dict(boxstyle="round,pad=0.15", fc="#ffeef2", ec="none", alpha=0.85),
            )
            ax.annotate(
                f"{min_val:.1f}°",
                xy=(num_times[min_idx], min_val),
                xytext=(0, -14),
                textcoords="offset points",
                ha="center",
                fontsize=8.5,
                fontweight="bold",
                color="#00509d",
                bbox=dict(boxstyle="round,pad=0.15", fc="#eef4f8", ec="none", alpha=0.85),
            )

    def _annotate_daily_precip(
        self,
        ax: plt.Axes,
        times: List[datetime],
        num_times: np.ndarray,
        precip_vals: np.ndarray,
    ):
        """Annotate 24-hour total precipitation sums on the precipitation panel."""
        days_map: Dict[str, List[int]] = {}
        for idx, t in enumerate(times):
            day_str = t.strftime("%Y-%m-%d")
            days_map.setdefault(day_str, []).append(idx)

        for day_str, indices in days_map.items():
            if not indices:
                continue
            daily_sum = sum(precip_vals[i] for i in indices)
            mid_idx = indices[len(indices) // 2]
            mid_time = num_times[mid_idx]

            ax.text(
                mid_time,
                0.78,
                f"Σ {daily_sum:.1f} mm",
                transform=ax.get_xaxis_transform(),
                ha="center",
                va="top",
                fontsize=8.5,
                fontweight="bold",
                color="#0077b6" if daily_sum > 0 else "#6c757d",
                bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="#90e0ef", lw=0.8, alpha=0.9),
            )

    def _compute_celestial_data(
        self,
        start_time: datetime,
        end_time: datetime,
        location_info: Dict[str, Any],
        astro_data: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Compute high-resolution solar & lunar altitude trajectories and peak passages."""
        # Sample with 5-minute steps, extending slightly before/after to capture natural horizon crossings
        pad_hours = 18
        ext_start = start_time - timedelta(hours=pad_hours)
        ext_end = end_time + timedelta(hours=pad_hours)
        total_seconds = (ext_end - ext_start).total_seconds()
        step_sec = 300.0  # 5 minutes
        n_steps = max(2, int(round(total_seconds / step_sec)))
        dense_dts = [ext_start + timedelta(seconds=i * step_sec) for i in range(n_steps + 1)]
        dense_nums = np.array([mdates.date2num(t) for t in dense_dts])
        dense_utcs = [t.astimezone(timezone.utc) for t in dense_dts]

        lat_val = location_info.get("latitude", 0.0)
        lon_val = location_info.get("longitude", 0.0)

        sun_alts = np.array([get_solar_altitude(t_utc, lat_val, lon_val) for t_utc in dense_utcs])
        moon_alts = np.array([get_lunar_altitude(t_utc, lat_val, lon_val) for t_utc in dense_utcs])

        def extract_passages(alts: np.ndarray, nums: np.ndarray, dts: List[datetime], is_moon: bool = False):
            passages = []
            in_pass = False
            p_start = 0
            for i in range(len(alts)):
                if alts[i] >= 0.0 and not in_pass:
                    in_pass = True
                    p_start = i
                elif alts[i] < 0.0 and in_pass:
                    in_pass = False
                    passages.append((p_start, i))
            if in_pass:
                passages.append((p_start, len(alts)))

            curves = []
            peaks = []
            for p_s, p_e in passages:
                seg_nums = list(nums[p_s:p_e])
                seg_alts = list(alts[p_s:p_e])

                # Interpolate exact zero-crossing before p_s (rising at horizon = 0.0)
                if p_s > 0 and alts[p_s - 1] < 0.0:
                    frac = (0.0 - alts[p_s - 1]) / (alts[p_s] - alts[p_s - 1])
                    num_zero = nums[p_s - 1] + frac * (nums[p_s] - nums[p_s - 1])
                    seg_nums.insert(0, num_zero)
                    seg_alts.insert(0, 0.0)

                # Interpolate exact zero-crossing after p_e - 1 (setting at horizon = 0.0)
                if p_e < len(alts) and alts[p_e] < 0.0:
                    frac = (0.0 - alts[p_e - 1]) / (alts[p_e] - alts[p_e - 1])
                    num_zero = nums[p_e - 1] + frac * (nums[p_e] - nums[p_e - 1])
                    seg_nums.append(num_zero)
                    seg_alts.append(0.0)

                curves.append((np.array(seg_nums), np.array(seg_alts)))

                peak_idx = p_s + int(np.argmax(alts[p_s:p_e]))
                p_alt = alts[peak_idx]
                peak_dt = dts[peak_idx]
                if p_alt >= 5.0 and start_time <= peak_dt <= end_time:
                    t_str = peak_dt.strftime("%H:%M")
                    if is_moon:
                        dt_peak = dense_utcs[peak_idx]
                        d_key = dt_peak.strftime("%Y-%m-%d")
                        m_phase = 0.0
                        if astro_data and "daily" in astro_data and d_key in astro_data["daily"]:
                            m_phase = astro_data["daily"][d_key].get("moon_phase", 0.0)
                        peaks.append((nums[peak_idx], p_alt, t_str, m_phase))
                    else:
                        peaks.append((nums[peak_idx], p_alt, t_str))

            return curves, peaks

        sun_curves, sun_peaks = extract_passages(sun_alts, dense_nums, dense_dts, is_moon=False)
        moon_curves, moon_peaks = extract_passages(moon_alts, dense_nums, dense_dts, is_moon=True)

        return {
            "sun_curves": sun_curves,
            "moon_curves": moon_curves,
            "sun_peaks": sun_peaks,
            "moon_peaks": moon_peaks,
        }

    def _draw_celestial_trajectories(
        self,
        ax_parent: plt.Axes,
        forecast_days: float,
        celestial_data: Dict[str, Any],
    ):
        """Draw sun and moon altitude arcs, solar peaks (time & deg), and lunar peaks (icon, time & deg) on a twin axis."""
        ax_cel = ax_parent.twinx()
        ax_cel.set_xlim(ax_parent.get_xlim())
        # Y-limits start strictly at 0.0 so altitude=0 (horizon/rise/set) is EXACTLY at the pane bottom
        ax_cel.set_ylim(0.0, 92.0)
        ax_cel.axis("off")

        # Plot sun passages anchored at the bottom
        for s_nums, s_alts in celestial_data["sun_curves"]:
            ax_cel.plot(
                s_nums,
                s_alts,
                color="#f4a261",
                linestyle="--",
                linewidth=1.2,
                alpha=0.48,
                zorder=2,
            )

        # Plot moon passages anchored at the bottom
        for m_nums, m_alts in celestial_data["moon_curves"]:
            ax_cel.plot(
                m_nums,
                m_alts,
                color="#00b4d8",
                linestyle=":",
                linewidth=1.3,
                alpha=0.55,
                zorder=2,
            )

        # Solar peaks: time + altitude
        for x_pos, p_alt, t_str in celestial_data["sun_peaks"]:
            label_text = f"☀ {t_str} ({p_alt:.0f}°)" if forecast_days <= 10 else f"☀ {p_alt:.0f}°"
            fs = 6.6 if forecast_days > 8 else 7.2
            ax_cel.text(
                x_pos,
                p_alt + 2.0,
                label_text,
                ha="center",
                va="bottom",
                fontsize=fs,
                color="#b45309",
                fontweight="bold",
                bbox=dict(boxstyle="round,pad=0.15", fc="#fffbeb", ec="#fde68a", lw=0.6, alpha=0.9),
                zorder=4,
            )

        # Lunar peaks: moon phase vector icon + time + altitude
        for x_pos, p_alt, t_str, m_phase in celestial_data["moon_peaks"]:
            da = create_moon_icon_box(phase=m_phase, size_pt=13.0)
            ab = AnnotationBbox(da, (x_pos, p_alt), frameon=False, pad=0.0, zorder=5)
            ax_cel.add_artist(ab)

            label_text = f"{t_str} ({p_alt:.0f}°)" if forecast_days <= 10 else f"{p_alt:.0f}°"
            fs = 6.3 if forecast_days > 8 else 6.8
            ax_cel.text(
                x_pos,
                p_alt - 5.5,
                label_text,
                ha="center",
                va="top",
                fontsize=fs,
                color="#0284c7",
                fontweight="bold",
                bbox=dict(boxstyle="round,pad=0.12", fc="#f0f9ff", ec="#bae6fd", lw=0.5, alpha=0.88),
                zorder=4,
            )
