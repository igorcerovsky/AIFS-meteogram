# ECMWF AIFS Meteogram Generator (SHMÚ EPSGRAM Style)

An advanced meteorological visualization system inspired by [SHMÚ's ECMWF EPSGRAM](https://www.shmu.sk/sk/?page=1&id=meteo_epsgramy&nwp_mesto=34031#ecmwf), powered by open forecast data from ECMWF's **AIFS** (*Artificial Intelligence Forecasting System* 0.25° Ensemble — 50 AI members) and DWD's regional high-resolution ensembles (**ICON-EU** and **ICON-D2**).

![DWD ICON-EU 5-Day High-Resolution Meteogram Preview](assets/meteogram_preview.png)

---

## 🏛️ Project Architecture

The repository is structured into three clean, dedicated components:

```
meteogram/
├── server/           # ⚡ Python backend server, CLI generator & rendering engine
│   ├── server.py     # HTTP server & API (/api/image, /api/check_location)
│   ├── renderer.py   # High-resolution matplotlib EPSGRAM rendering engine
│   ├── aifs_client.py# Open-Meteo ensemble API client & geocoder
│   ├── meteogram.py  # Standalone CLI generation tool
│   └── requirements.txt
├── web/              # 🌐 Web dashboard frontend (HTML5, CSS3, Vanilla JS)
│   └── index.html    # Interactive client with search, presets & model alert banner
└── MeteogramApp/     # 📱 Native Apple Multiplatform App (iOS, iPadOS & macOS)
    ├── MeteogramApp.xcodeproj
    ├── Sources/      # SwiftUI views, models, services & viewmodels
    └── README.md     # Detailed iOS & macOS setup guide
```

---

## 🚀 Quick Start

### 1. Install Dependencies

Clone the repository and install the Python requirements:

```bash
git clone https://github.com/igorcerovsky/AIFS-meteogram.git
cd AIFS-meteogram
pip install -r server/requirements.txt
```

### 2. Launch the Backend Server

Start the lightweight Python server (serves both the Web UI and the Apple App API):

```bash
python3 server/server.py 8080
```

---

## 🌐 1. Web Dashboard (`web/`)

Open [http://localhost:8080](http://localhost:8080) in your browser once the server is running.

### Key Features
- **Search & Quick Presets**: Type any city name or GPS coordinates (`lat, lon`), or tap preset chips (*Bratislava-Koliba, Jasná, Liptovský Mikuláš, Plavecké Podhradie, Košice, Poprad/Tatry, Vienna, Prague*).
- **Model Selection**:
  - **ECMWF AIFS Global Ensemble**: 15 days, 10 days, 7 days (50 AI members).
  - **DWD ICON-EU Regional Ensemble**: 5 days (7.0 km resolution, 40 members).
  - **DWD ICON-D2 High-Resolution Ensemble**: 2 days / 48h (2.2 km resolution, 20 members).
- **Intelligent Fallback Alert**: Automatic detection when a location is outside the Central Europe ICON-D2 domain, seamlessly transitioning to ICON-EU with an informative notification banner.
- **Language & Time Zone**: Full support for English (`en`) and Slovak (`sk`), and Local Time or UTC.
- **Instant Export**: Download high-resolution PNGs or open full-size graphs in a new tab.

---

## 📱 2. Native Apple App for iOS & macOS (`MeteogramApp/`)

A native SwiftUI multiplatform application running seamlessly on **macOS 14.0+** (Apple Silicon & Intel) and **iOS / iPadOS 17.0+** (iPhone & iPad).

### Key Features
- **Swipe Between Models**: Swipe left or right directly on the chart to cycle models in the natural order:
  $$\mathbf{15\text{ days}} \longleftrightarrow \mathbf{2\text{ days}} \longleftrightarrow \mathbf{5\text{ days}} \longleftrightarrow \mathbf{10\text{ days}} \longleftrightarrow \mathbf{7\text{ days}}$$
  *(Automatically bypasses 2-day ICON-D2 when a location is outside coverage).*
- **Sleek Model Pill Bar**: Compact `[ 15d | 2d | 5d | 10d | 7d ]` selector with real-time status and active indicator.
- **Interactive Gesture Zoom**: Fluid pinch-to-zoom (up to 400%), smooth panning, double-tap zoom reset, and floating zoom controls.
- **Off-Screen Pan Boundary Constraints**: Clamped viewport mathematics ensure the graph cannot be accidentally dragged outside the visible screen.
- **Layered UI**: Location search bar and model pills are pinned cleanly on top (`zIndex`), never overlapped by the chart.
- **One-Tap GPS**: Automatically fetches your device's current location via `CoreLocation`.
- **Bonjour Server Discovery**: Connects via `localhost:8080` on Mac, or one-tap `Igors-MacBook-Air.local:8080` (or Wi-Fi IP) on iPhone/iPad with live latency diagnostics.
- **Native Integrations**: System Share Sheet, Copy Image to Clipboard (`⌘C`), and Refresh (`⌘R`).

### How to Run
```bash
open MeteogramApp/MeteogramApp.xcodeproj
```
Select **My Mac** or your **iPhone Simulator** / physical device in Xcode and press **Run (`⌘R`)**. For more details, see [MeteogramApp/README.md](MeteogramApp/README.md).

---

## ⚡ 3. Python Server & CLI (`server/`)

### CLI Usage (`server/meteogram.py`)

Generate a publication-quality meteogram directly from the command line:

```bash
# Default location (Bratislava-Koliba, 15 days, English)
python3 server/meteogram.py

# High-resolution regional 5-day ICON-EU forecast
python3 server/meteogram.py --location "Bratislava-Koliba" --model icon_eu --days 5 --lang en

# High-resolution regional 2-day ICON-D2 forecast in Slovak
python3 server/meteogram.py --location "Bratislava-Koliba" --model icon_d2 --days 2 --lang sk

# Specify custom location, duration, and output file
python3 server/meteogram.py --location "Liptovsky Mikulas" --days 10 --output liptov.png

# Exact GPS coordinates (lat, lon)
python3 server/meteogram.py --location "48.148,17.107" --output custom_coords.png
```

#### CLI Options

| Argument | Default | Description |
| --- | --- | --- |
| `-l`, `--location` | `Bratislava-Koliba` | City name or `lat,lon` coordinates |
| `-m`, `--model` | `aifs` | Model: `aifs` (ECMWF AI, 7–15d), `icon_eu` (7.0 km, 5d), `icon_d2` (2.2 km, 48h) |
| `-d`, `--days` | `15` | Forecast duration in days |
| `-o`, `--output` | `.img/<loc>_meteogram.png` | Output file path (`.png`, `.svg`, `.pdf`) |
| `--lang` | `en` | Label language: `en` (English) or `sk` (Slovak) |
| `--tz` | `local` | Timezone: `local` (summer/winter auto-detected) or `utc` |
| `--dpi` | `200` | Resolution for rendered raster image |

### HTTP API (`server/server.py`)

- **`GET /api/image`**: Generates and serves dynamic PNG meteograms.
  - Parameters: `location`, `days`, `model`, `lang`, `tz`.
  - Response Headers: `X-Actual-Model`, `X-Model-Fallback`, `X-Fallback-From`.
  - Caching: Automated caching in `.cache/` with 1-hour expiry and auto-invalidation on renderer updates.
- **`GET /api/check_location`**: Geocodes locations, determines altitude, and checks DWD ICON-D2 domain boundaries.

---

## 📊 Weather Parameters Visualized

1. **2m Air Temperature & Celestial Trajectories**:
   - Monotonic PCHIP-smoothed median curve (solid dark red), IQR 25–75% band (soft salmon), full ensemble min-max spread (light pink), 0°C freezing line, and daily minimum and maximum labeled values.
   - **Sun Altitude Trajectory**: Orange dashed curve tracking solar elevation above the horizon with peak culmination time and angle (`☀ HH:MM (XX°)`).
   - **Moon Altitude Trajectory & Phase**: Cyan dotted curve tracking lunar elevation with peak culmination time and angle (`HH:MM (XX°)`) and rendered custom moon phase disc reflecting actual lunar illumination and waxing/waning direction.
2. **Precipitation & Snowfall**:
   - Multi-member accumulation bars for rain and snow, ensemble maximum accumulation ticks, and daily cumulative totals (`Σ X.X mm`).
3. **Cloud Layers & Total Cloud Cover**:
   - Four distinct curves: **Total Cloud Cover** (Deep Dark Blue `#1e3a8a`, thick curve) with transparent dark blue percentile ribbons (`alpha=0.10` min-max, `alpha=0.22` IQR), **High Cirrus** (Cyan `#0096c7`), **Medium Altocumulus** (Emerald Teal `#2a9d8f`), and **Low Stratus** (Crimson `#c1121f`).
4. **10m Wind Speed & Direction**:
   - Smoothed wind speed curve with IQR and spread envelopes, overlaid with meteorological wind direction arrows pointing where the wind is blowing.
5. **Mean Sea Level Pressure (MSLP) & Celestial Trajectories**:
   - Atmospheric pressure curve (hPa) and ensemble spread envelope, complemented by background Sun and Moon altitude trajectories and peak culmination annotations mirroring the top panel.
6. **Daytime & Night Shading Across All Panels**:
   - Warm light yellow background (`#fef9c3`) across all 5 panels for daytime hours, contrasted with twilight/night shading (`#343a40`) calculated from astronomical ephemeris for the target coordinates.
7. **Bottom Timeline Badges**:
   - Distinct daily badges displaying weekday, calendar date, astronomical sunrise and sunset (`☀ HH:MM – HH:MM`), moonrise and moonset (`☾ HH:MM – HH:MM`), and localized moon phase name with percentage illumination.

---

## 📄 License & Attribution

- **Data Sources**:
  - ECMWF AIFS Open Data &copy; European Centre for Medium-Range Weather Forecasts ([CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/))
  - DWD Open Data &copy; Deutscher Wetterdienst
  - Geocoding & API distribution via [Open-Meteo](https://open-meteo.com)
- **Visual Style**: Inspired by Slovak Hydrometeorological Institute ([SHMÚ](https://www.shmu.sk)) EPSGRAM layouts.
- **License**: GNU General Public License v3 (see [LICENSE](LICENSE)).
