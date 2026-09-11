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
import zoneinfo
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple
import matplotlib
matplotlib.use("Agg")  # Non-interactive backend for server/CLI
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import matplotlib.transforms as mtransforms
import numpy as np


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
    },
}


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

        # Convert times to matplotlib numerical dates for smooth plotting
        num_times = mdates.date2num(times)

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
                "bottom": 0.060,
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
        ax_temp.fill_between(
            num_times,
            temp["min"],
            temp["max"],
            color="#ffccd5",
            alpha=0.6,
            label=self.t["spread"],
        )
        ax_temp.fill_between(
            num_times,
            temp["q25"],
            temp["q75"],
            color="#ff4d6d",
            alpha=0.45,
            label=self.t["iqr"],
        )
        ax_temp.plot(
            num_times,
            temp["median"],
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

        ax_temp.set_ylabel(self.t["temp_title"], fontsize=10.5, fontweight="bold", color="#800f2f")
        ax_temp.grid(True, linestyle=":", alpha=0.45, color="#94a3b8", zorder=1)

        # Include Night shading in legend
        from matplotlib.patches import Patch
        handles, labels = ax_temp.get_legend_handles_labels()
        night_patch = Patch(facecolor="#c8d1d9", edgecolor="none", alpha=0.75, label=self.t["night"])
        handles.append(night_patch)
        labels.append(self.t["night"])
        ax_temp.legend(handles=handles, labels=labels, loc="upper right", framealpha=0.92, fontsize=8.5, ncol=4)

        # -------------------------------------------------------------
        # PANEL 2: PRECIPITATION & SNOWFALL (Hourly for high-res / 6h for long range)
        # -------------------------------------------------------------
        precip_raw = stats["precipitation"]
        snow_raw = stats["snowfall"]
        active_model = stats.get("model", "aifs")
        is_hourly = (active_model in ["icon_d2", "icon_eu"]) or (forecast_days <= 5.5)

        if is_hourly:
            # Hourly precipitation bars: directly plot each individual hour
            bar_num_times = num_times
            bar_width = (1.0 / 24.0) * 0.78  # ~47 minutes wide in days
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
        # PANEL 3: CLOUD COVER (Yellow palette as requested)
        # -------------------------------------------------------------
        cloud = stats["cloud_cover"]
        # Shaded min-max spread in light warm yellow
        ax_cloud.fill_between(
            num_times,
            cloud["min"],
            cloud["max"],
            color="#fff3b0",
            alpha=0.75,
            label=self.t["spread"],
            zorder=2,
        )
        # 25-75% interquartile range in vibrant sunny yellow
        ax_cloud.fill_between(
            num_times,
            cloud["q25"],
            cloud["q75"],
            color="#ffd166",
            alpha=0.85,
            label=self.t["iqr"],
            zorder=3,
        )
        # Area fill under median in warm sunny yellow
        ax_cloud.fill_between(
            num_times,
            0,
            cloud["median"],
            color="#ffe066",
            alpha=0.35,
            zorder=2,
        )
        # Solid median line in deep golden amber yellow
        ax_cloud.plot(
            num_times,
            cloud["median"],
            color="#d48b00",
            linewidth=2.4,
            label=self.t["median"],
            zorder=4,
        )

        ax_cloud.set_ylabel(self.t["cloud_title"], fontsize=10, fontweight="bold", color="#b57600")
        ax_cloud.set_ylim(-2, 104)
        ax_cloud.set_yticks([0, 25, 50, 75, 100])
        ax_cloud.grid(True, linestyle=":", alpha=0.55, color="#6c757d", zorder=1)
        ax_cloud.legend(loc="upper right", framealpha=0.9, fontsize=8.5, ncol=3)

        # -------------------------------------------------------------
        # PANEL 4: WIND SPEED & DIRECTION
        # -------------------------------------------------------------
        wind_spd = stats["wind_speed_10m"]
        wind_dir = stats["wind_direction_10m"]

        ax_wind.fill_between(
            num_times,
            wind_spd["min"],
            wind_spd["max"],
            color="#d8b4a0",
            alpha=0.55,
            label=self.t["spread"],
        )
        ax_wind.fill_between(
            num_times,
            wind_spd["q25"],
            wind_spd["q75"],
            color="#bc6c25",
            alpha=0.45,
            label=self.t["iqr"],
        )
        ax_wind.plot(
            num_times,
            wind_spd["median"],
            color="#603808",
            linewidth=2.2,
            label=self.t["median"],
            zorder=4,
        )

        y_max_wind = max(35.0, float(np.nanmax(wind_spd["max"])) * 1.3)
        ax_wind.set_ylim(0, y_max_wind)
        arrow_y = y_max_wind * 0.88

        # Draw clean meteorological wind arrows along the top of wind plot
        if forecast_days <= 2.5:
            step = 1  # hourly arrows for short horizon (ICON-D2)
        elif forecast_days <= 5.5:
            step = 2  # every 2h for ICON-EU
        else:
            step = max(1, len(num_times) // 28)
        for i in range(0, len(num_times), step):
            t_val = num_times[i]
            deg = wind_dir["median"][i]
            # Meteorological convention: arrow points in direction wind blows to
            blow_to_rad = np.deg2rad(270 - deg)
            arrow_len = 0.014 * (num_times[-1] - num_times[0])
            u = arrow_len * np.cos(blow_to_rad)
            v = arrow_len * np.sin(blow_to_rad) * (y_max_wind / 5.5)

            ax_wind.annotate(
                "",
                xy=(t_val + u, arrow_y + v),
                xytext=(t_val - u, arrow_y - v),
                arrowprops=dict(
                    arrowstyle="->",
                    color="#2b1810",
                    lw=1.4,
                    shrinkA=0,
                    shrinkB=0,
                ),
                zorder=5,
            )

        ax_wind.set_ylabel(self.t["wind_title"], fontsize=10, fontweight="bold", color="#7f4f24")
        ax_wind.grid(True, linestyle=":", alpha=0.55, color="#6c757d")
        ax_wind.legend(loc="upper right", framealpha=0.9, fontsize=8.5, ncol=3)

        # -------------------------------------------------------------
        # PANEL 5: MEAN SEA LEVEL PRESSURE (MSLP)
        # -------------------------------------------------------------
        press = stats["pressure_msl"]
        ax_press.fill_between(
            num_times,
            press["min"],
            press["max"],
            color="#d8f3dc",
            alpha=0.6,
            label=self.t["spread"],
        )
        ax_press.fill_between(
            num_times,
            press["q25"],
            press["q75"],
            color="#74c69d",
            alpha=0.5,
            label=self.t["iqr"],
        )
        ax_press.plot(
            num_times,
            press["median"],
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
        ax_press.legend(loc="upper right", framealpha=0.9, fontsize=8.5, ncol=3)

        # -------------------------------------------------------------
        # TIMELINE CONFIGURATION & LABELS ACROSS ALL PANES
        # -------------------------------------------------------------
        self._format_axes_timeline(
            fig, axes, start_time, end_time, active_tz, tz_badge, sun_times_tz
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

    def _format_axes_timeline(
        self,
        fig: plt.Figure,
        axes: List[plt.Axes],
        start_time: datetime,
        end_time: datetime,
        active_tz: Any,
        tz_badge: str,
        sun_times_tz: Optional[List[Tuple[datetime, datetime]]] = None,
    ):
        """Format X-axes on all panes: ticks and day badges both between graph panes and at the bottom with sunrise/sunset."""
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
            badge_y_offset = -23 if is_bottom else -18
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
                            sun_str = f"\n☀ {r.strftime('%H:%M')}   ☽ {s.strftime('%H:%M')}"
                        badge_text = f"{day_name} {date_str}{sun_str}"
                        fontsize = 7.8 if forecast_days > 10 else 8.5
                        pad = 0.26
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

        for day_str, indices in days_map.items():
            if len(indices) < 2:
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
