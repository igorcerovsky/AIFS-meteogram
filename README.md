# ECMWF AIFS AI-Model Meteogram Generator (SHMÚ Style)

A meteogram / EPSGRAM generator inspired by [SHMÚ's ECMWF EPSGRAM](https://www.shmu.sk/sk/?page=1&id=meteo_epsgramy&nwp_mesto=34031#ecmwf) powered by open forecast data from ECMWF's **AIFS** (*Artificial Intelligence Forecasting System* 0.25° Ensemble — 50 AI members) catalogued in [ECMWF AI Models](https://charts.ecmwf.int/catalogue/packages/ai_models/).

---

## Installation

Clone the repository and install dependencies:
```bash
git clone https://github.com/igorcerovsky/AIFS-meteogram.git
cd AIFS-meteogram
pip install -r requirements.txt
```

---

## Features

- **SHMÚ EPSGRAM Layout**:
  1. **2m Air Temperature (Top Panel)**: Solid red median line, 25–75% interquartile range (darker shaded band), full 50-member min-max spread (light band), 0°C freezing level reference line, and labeled daily min/max extrema.
  2. **Precipitation & Snowfall**: 6-hour interval bars for liquid precipitation (rain) and solid precipitation (snow), ensemble maximum accumulation ticks, and daily total sum annotations (`Σ X.X mm`).
  3. **Total Cloud Cover (Yellow)**: Cloud cover percentage (0–100%) drawn in warm yellow tones (golden median line, bright yellow 25–75% IQR, soft yellow min-max spread, and subtle area fill under median).
  4. **10m Wind Speed & Direction**: Wind speed curve + meteorological wind direction arrows pointing in the direction the wind blows.
  5. **Mean Sea Level Pressure (MSLP)**: Atmospheric pressure curve (hPa) and ensemble spread envelope.
  6. **Sunset to Sunrise Night Shading**: Clear grey background bands representing the nighttime period from sunset to sunrise for each day, computed from astronomical coordinates.
  7. **Time Axis**: Clean 6-hour interval ticks and centered day badges (`Mon`, `Tue`, `Wed`, `Thu`, `Fri`, `Sat`, `Sun` with calendar dates).
- **Default Curated Locations**:
  - **Bratislava-Koliba** (SHMÚ Observatory, 287 m) — *Default*
  - **Liptovský Mikuláš** (577 m)
  - **Jasná** (Low Tatras / Chopok, 1,118 m)
  - **Plavecké Podhradie** (Záhorie / Little Carpathians, 210 m)
  - Also works with any other city in the world or GPS `lat,lon` coordinates.
- **Language**: English by default (`--lang en`), with Slovak available (`--lang sk`).
- **Two Usage Modes**:
  1. **CLI Script (`meteogram.py`)**: Directly outputs publication-quality PNG / SVG images.
  2. **Interactive Web Dashboard (`server.py`)**: Local web app at `http://localhost:8080` with city search, quick-select chips, and instant downloads.

---

## 1. CLI Usage

Generate a meteogram for the default location (**Bratislava-Koliba**, 15 days, English):
```bash
python3 meteogram.py
```

Quick generation for the default locations:
```bash
# Bratislava-Koliba (Default)
python3 meteogram.py --location "Bratislava-Koliba"

# Liptovský Mikuláš
python3 meteogram.py --location "Liptovsky Mikulas"

# Jasná (Low Tatras)
python3 meteogram.py --location "Jasna"

# Plavecké Podhradie
python3 meteogram.py --location "Plavecke Podhradie"
```

Other custom locations or coordinates:
```bash
# 15-day forecast for Vienna
python3 meteogram.py --location "Vienna" --days 15 --output vienna_meteogram.png

# High-mountain location (Poprad / High Tatras)
python3 meteogram.py --location "Poprad" --days 10 --output poprad.png

# Exact GPS coordinates (lat, lon)
python3 meteogram.py --location "48.148,17.107" --output custom_coord.png
```

### CLI Arguments
| Parameter | Default | Description |
|---|---|---|
| `-l`, `--location` | `Bratislava-Koliba` | City / preset name or `lat,lon` coordinates |
| `-d`, `--days` | `15` | Forecast horizon (1 to 16 days, full AI horizon) |
| `-o`, `--output` | `.img/<location>_aifs_meteogram.png` | Output image file path (`.png`, `.svg`, `.pdf`). Saved in `.img/` by default. |
| `--lang` | `en` | Label language: `en` (English, default) or `sk` (Slovak) |
| `--dpi` | `200` | Resolution for rendered image |

---

## 2. Interactive Web Dashboard

To launch the web interface:
```bash
python3 server.py 8080
```
Open [http://localhost:8080](http://localhost:8080) in your web browser.

Features:
- Type any city name in the search bar or click the quick presets
- Switch forecast horizon (3, 5, 7, 10, 15 days)
- Download generated image with a single click
- View full-size graph in a new tab

---

## Requirements

Python 3.9+ with standard packages:
- `matplotlib`
- `numpy`
- Standard library modules (`urllib`, `http.server`, `json`, `datetime`)
