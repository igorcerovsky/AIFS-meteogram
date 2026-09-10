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
import numpy as np


LANG_TEXTS = {
    "sk": {
        "title_model": "Model: ECMWF AIFS 0.25° Ensemble (50 AI členov)",
        "alt": "Nadm. výška",
        "coord": "Súradnice",
        "run_prefix": "Beh",
        "time_prefix": "Čas",
        "hour_label": "Hodina",
        "temp_title": "Teplota 2 m [°C]",
        "precip_title": "Zrážky [mm / 6h]",
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
        "night": "Noc (západ až východ slnka)",
    },
    "en": {
        "title_model": "Model: ECMWF AIFS 0.25° Ensemble (50 AI members)",
        "alt": "Elevation",
        "coord": "Coordinates",
        "run_prefix": "Run",
        "time_prefix": "Time",
        "hour_label": "Hour",
        "temp_title": "2m Temperature [°C]",
        "precip_title": "Precipitation [mm / 6h]",
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

        # Create Figure with 5 subplots (Temperature on top!)
        fig, axes = plt.subplots(
            nrows=5,
            ncols=1,
            figsize=(fig_width, 15.5),
            sharex=True,
            gridspec_kw={
                "height_ratios": [2.4, 1.8, 1.5, 1.9, 1.6],
                "hspace": 0.08,
                "top": 0.925,
                "bottom": 0.065,
                "left": 0.08,
                "right": 0.96,
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

        # Freezing line (0°C)
        ax_temp.axhline(0, color="#1d3557", linestyle="--", linewidth=1.2, alpha=0.85, zorder=3)
        ax_temp.text(
            num_times[-1],
            0,
            " 0°C",
            verticalalignment="center",
            fontsize=9,
            fontweight="bold",
            color="#1d3557",
        )

        # Annotate daily min / max temperatures for the median curve
        self._annotate_daily_temp(ax_temp, times, num_times, temp["median"])

        ax_temp.set_ylabel(self.t["temp_title"], fontsize=10.5, fontweight="bold", color="#800f2f")
        ax_temp.grid(True, linestyle=":", alpha=0.55, color="#6c757d", zorder=1)

        # Include Night shading in legend
        from matplotlib.patches import Patch
        handles, labels = ax_temp.get_legend_handles_labels()
        night_patch = Patch(facecolor="#c8d1d9", edgecolor="none", alpha=0.75, label=self.t["night"])
        handles.append(night_patch)
        labels.append(self.t["night"])
        ax_temp.legend(handles=handles, labels=labels, loc="upper right", framealpha=0.92, fontsize=8.5, ncol=4)

        # -------------------------------------------------------------
        # PANEL 2: PRECIPITATION & SNOWFALL
        # -------------------------------------------------------------
        precip = stats["precipitation"]
        snow = stats["snowfall"]

        # Interval width in days for bar chart
        if len(num_times) > 1:
            bar_width = (num_times[1] - num_times[0]) * 0.85
        else:
            bar_width = 0.2

        # Rain (liquid) vs Snow
        rain_vals = np.maximum(0, precip["median"] - snow["median"])
        snow_vals = snow["median"]

        ax_precip.bar(
            num_times,
            rain_vals,
            width=bar_width,
            color="#1d70b8",
            alpha=0.85,
            label=self.t["rain"],
            zorder=3,
        )
        ax_precip.bar(
            num_times,
            snow_vals,
            bottom=rain_vals,
            width=bar_width,
            color="#00b4d8",
            alpha=0.9,
            label=self.t["snow"],
            zorder=3,
        )

        # Error ticks for ensemble max spread
        ax_precip.plot(
            num_times,
            precip["max"],
            color="#03045e",
            linestyle="",
            marker="_",
            markersize=6,
            markeredgewidth=1.6,
            alpha=0.75,
            label=self.t["max_precip"],
            zorder=4,
        )

        # Make sure Y axis has enough room for daily sum labels
        max_p_val = max(3.0, float(np.nanmax(precip["max"])) * 1.35)
        ax_precip.set_ylim(0, max_p_val)

        # Annotate daily precipitation sum
        self._annotate_daily_precip(ax_precip, times, num_times, precip["median"])

        ax_precip.set_ylabel(self.t["precip_title"], fontsize=10, fontweight="bold", color="#0077b6")
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
        # TIMELINE CONFIGURATION & LABELS
        # -------------------------------------------------------------
        self._format_x_axis(ax_press, start_time, end_time, active_tz, tz_badge)

        # Super Title / Header banner
        loc_name = location_info.get("name", "Unknown")
        country = location_info.get("country", "")
        loc_str = f"{loc_name}, {country}" if country else loc_name
        lat = location_info.get("latitude", 0.0)
        lon = location_info.get("longitude", 0.0)
        elev = location_info.get("elevation", stats.get("elevation", 0))

        run_time_str = raw_start.astimezone(active_tz).strftime("%Y-%m-%d %H:%M")

        header_title = f"{loc_str} ({lat:.2f}°N, {lon:.2f}°E, {self.t['alt']}: {elev:.0f} m)"
        header_sub = (
            f"{self.t['title_model']}  |  "
            f"{self.t['run_prefix']}: {run_time_str} ({tz_badge})  |  "
            f"{self.t['time_prefix']}: {tz_label}"
        )

        fig.text(
            0.09,
            0.968,
            header_title,
            fontsize=15,
            fontweight="bold",
            color="#14213d",
            ha="left",
        )
        fig.text(
            0.09,
            0.942,
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

    def _format_x_axis(
        self,
        ax: plt.Axes,
        start_time: datetime,
        end_time: datetime,
        active_tz: Any,
        tz_badge: str,
    ):
        """Format bottom X-axis with cleanly separated hours, day names, and calendar dates in active timezone."""
        x_min = mdates.date2num(start_time)
        x_max = mdates.date2num(end_time)
        ax.set_xlim(x_min, x_max)

        # 6-hour interval ticks in the active timezone
        hours_locator = mdates.HourLocator(byhour=[0, 6, 12, 18], tz=active_tz)
        ax.xaxis.set_major_locator(hours_locator)
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%H", tz=active_tz))
        ax.tick_params(axis="x", which="major", labelsize=8.5, length=4, pad=4)

        # Place day names & dates in a neat strip right under the hours
        curr = start_time.replace(hour=0, minute=0, second=0, microsecond=0)
        while curr <= end_time:
            midday = curr + timedelta(hours=12)
            num_mid = mdates.date2num(midday)
            if num_mid >= x_min and num_mid <= x_max:
                day_name = self.t["days"][curr.weekday()]
                date_str = curr.strftime("%d.%m.")
                label_text = f"{day_name}\n{date_str}"
                ax.text(
                    num_mid,
                    -0.26,
                    label_text,
                    ha="center",
                    va="top",
                    fontsize=9,
                    fontweight="bold",
                    color="#212529",
                    transform=ax.get_xaxis_transform(),
                    bbox=dict(boxstyle="square,pad=0.25", fc="#f8f9fa", ec="#ced4da", lw=0.8, alpha=0.9),
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
