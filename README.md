# ECMWF AIFS Meteogram Generator (SHMÚ EPSGRAM Style)

An advanced meteorological visualization system inspired by [SHMÚ's ECMWF EPSGRAM](https://www.shmu.sk/sk/?page=1&id=meteo_epsgramy&nwp_mesto=34031#ecmwf), powered by open forecast data from ECMWF's **AIFS** (*Artificial Intelligence Forecasting System* 0.25° Ensemble — 50 AI members) and DWD's regional high-resolution ensembles (**ICON-EU** and **ICON-D2**).

🌐 **Live Meteogram Web Page**: [https://igorcerovsky.github.io/AIFS-meteogram/](https://igorcerovsky.github.io/AIFS-meteogram/)

![ECMWF AIFS Interactive Meteogram Dashboard](assets/web_dashboard_preview.png)

---

## 🏛️ Project Architecture

The repository is structured into three dedicated components:

```
meteogram/
├── web/              # 🌐 Modern interactive Web Dashboard (HTML5 Canvas, CSS3, Vanilla JS)
│   ├── index.html    # Interactive client with search, presets, model switching & theme adaptation
│   └── meteogram-chart.js # Dynamic Retina canvas engine with HUD crosshair, analemmas & direct API
├── MeteogramApp/     # 📱 Native Apple Multiplatform App (iOS, iPadOS & macOS)
│   ├── MeteogramApp.xcodeproj
│   ├── Sources/      # SwiftUI views, models, services & viewmodels
│   └── README.md     # Detailed iOS & macOS setup guide
└── server/           # ⚡ Lightweight Python backend server & API
    ├── server.py     # HTTP server & API (/api/forecast, /api/check_location)
    ├── aifs_client.py# Open-Meteo ensemble API client & geocoder
    └── requirements.txt
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

Start the lightweight Python server (serves the Web UI, JSON forecast API, and Apple App API):

```bash
python3 server/server.py 8080
```

---

## 🌐 1. Interactive Web Dashboard (`web/`)
- 🚀 **Live GitHub Pages Web App**: [https://igorcerovsky.github.io/AIFS-meteogram/](https://igorcerovsky.github.io/AIFS-meteogram/)
- 💻 **Local Development**: Open [http://localhost:8080](http://localhost:8080) in your browser once the server is running.

### Key Features
- **Dynamic HTML5 Canvas Engine (`web/meteogram-chart.js`)**:
  - Automatically scales with `devicePixelRatio` for razor-sharp rendering on Retina and 4K/HiDPI displays.
  - Interactive crosshair tracking across all 5 synchronized panels with real-time value indicators.
  - **Floating Glassmorphism HUD Tooltip**: Real-time inspection pane displaying exact temperature, precipitation, cloud volume, pressure, and celestial altitudes at the hovered timestamp.
  - **Dynamic Wind Direction Arrow in HUD**: Displays an SVG meteorological directional arrow that rotates smoothly to indicate wind flow, dynamically color-coded by the active wind speed category (calm slate, teal, emerald green, warm orange, storm crimson).
  - **Precipitation 90th Percentile (P90) Envelope**: Semi-transparent light-blue bars render the 90th percentile ensemble upper bound behind solid median precipitation bars, highlighting probabilistic extreme rain risks.
  - **Luminous Golden Yellow Cloud Cover**: Total cloud volume rendered as a luminous golden-yellow spline curve (`#eab308`) and subtle histogram bins, paired with isolated High Cirrus (royal blue `#2563eb`), Medium Alto (emerald `#10b981`), and Low Stratus (crimson `#e11d48`) layers.
  - **Location-Aware Celestial Analemmas**: Side-by-side Solar & Lunar figure-8 analemma cards embedded directly in the precipitation pane with transparent backgrounds.
  - **Logarithmic Precipitation Scaling**: Pseudo-logarithmic scaling ($v_0 = 0.2\text{ mm}$) that expands low-intensity precipitation ($0.1 - 2.0\text{ mm}$) for clear visibility of light rain, drizzle, and snow.
  - **Continuous Loop Wind Direction & Dual Velocity Encoding**: Continuous `N-W-S-E-N` looping trajectory with speed-proportional stroke thickness and multi-threshold color coding.
- **Always-Fresh Data & One-Tap Refresh**:
  - **`[ ↻ Refresh ]` Button**: Instantly forces a fresh network fetch from Open-Meteo, bypassing browser and server caches (`refresh=1`, `Cache-Control: no-cache`) to immediately pick up new model runs (00z, 06z, 12z, 18z).
  - **Fresh Model Switching**: Toggling model pills (`15d`, `2d`, `5d`, `10d`, `7d`) automatically fetches up-to-date ensemble data.
- **Search & Quick Presets**: Type any city name or GPS coordinates (`lat, lon`), or tap preset chips (*Bratislava-Koliba, Jasná, Liptovský Mikuláš, Repiská, Plavecké Podhradie, Lengerich (DE), Rajka (HU), Košice, Poprad/Tatry, Vienna, Prague*).
- **Model Selection**:
  - **ECMWF AIFS Global Ensemble**: 15 days, 10 days, 7 days (50 AI members).
  - **DWD ICON-EU Regional Ensemble**: 5 days (7.0 km resolution, 40 members).
  - **DWD ICON-D2 High-Resolution Ensemble**: 2 days / 48h (2.2 km resolution, 20 members).
- **Automatic Browser Theme Matching**: Seamlessly adapts backgrounds, borders, chips, and typography to system dark or light mode preferences (`prefers-color-scheme`).
- **Zero-Backend GitHub Pages Fallback**: Includes a client-side direct fetch engine that queries Open-Meteo's CORS-enabled API directly, allowing the interactive meteogram to run statically on GitHub Pages for any global coordinate without requiring a backend server.
- **Language & Timezone Switching**: Instant client-side re-rendering when toggling between English (`en`) and Slovak (`sk`), or Local Time and UTC.
- **Intelligent Fallback Alert**: Automatic notification when coordinates lie outside the ICON-D2 Central Europe boundary, seamlessly switching to ICON-EU.

---

## 📱 2. Native Apple App for iOS & macOS (`MeteogramApp/`)

A native SwiftUI multiplatform application running seamlessly on **macOS 14.0+** (Apple Silicon & Intel) and **iOS / iPadOS 17.0+** (iPhone & iPad).

### Key Features
- **One-Tap Refresh & Cache Invalidation**: Dedicated `arrow.clockwise` button in the header bar and macOS toolbar (`⌘R`) to bypass caches and instantly download the latest forecast runs.
- **Seamless Swipe Between Models**: Swipe horizontally directly on the chart to cycle models in the natural order:
  $$\mathbf{15\text{ days}} \longleftrightarrow \mathbf{2\text{ days}} \longleftrightarrow \mathbf{5\text{ days}} \longleftrightarrow \mathbf{10\text{ days}} \longleftrightarrow \mathbf{7\text{ days}}$$
  *(Automatically bypasses 2-day ICON-D2 when a location is outside coverage).*
- **Gesture Stability & Locked Time Domains**: Mathematically clamped time scales ensure precipitation bars and curves maintain rigid alignment without zoom jumps or lateral shifting during swipe transitions.
- **Native Swift Charts Engine**: Complete visual parity with the web dashboard, featuring:
  - 90th percentile (P90) semi-transparent precipitation bars alongside solid median rain and snowfall.
  - Luminous golden-yellow total cloud volume curve with isolated cirrus, alto, and stratus layers.
  - Continuous `N-W-S-E-N` wind trajectory curves with velocity color weighting.
  - Interactive HUD inspection with dynamic rotating wind direction arrow colored by speed threshold.
  - Transparent side-by-side Solar & Lunar Analemma cards.
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

## ⚡ 3. Python Backend Server & API (`server/`)

The backend is a lightweight Python server (standard library `http.server`) providing forecast data fetching, automatic caching, geocoding validation, and CORS proxying for local web and native Apple app clients:

```bash
# Start server on port 8080
python3 server/server.py 8080
```

### HTTP Endpoints

- **`GET /api/forecast`**: Serves structured forecast JSON data, ensemble statistics (median, P90, IQR, min/max spreads), and astronomical ephemeris for the dynamic web canvas and native SwiftUI app.
  - Parameters: `location`, `days`, `model`, `lang`, `tz`, `refresh` (`1` to bypass disk cache).
  - Caching: Automatic server-side disk cache with 1-hour validity ($< 1\text{ ms}$ response), instantly bypassable via `refresh=1` or `Cache-Control: no-cache`.
- **`GET /api/check_location`**: Geocodes locations, resolves elevation, and validates DWD ICON-D2 domain boundaries.

---

## 📊 Weather Parameters Visualized

1. **2m Air Temperature (°C)**:
   - Median trajectory curve, interquartile 25–75% band, and full ensemble min-max spread.
   - **Colored Threshold Grid Lines**: Distinctive reference levels at $-10^\circ\text{C}$ (light blue), $0^\circ\text{C}$ (freezing level blue), $+10^\circ\text{C}$ (yellow), $+20^\circ\text{C}$ (orange), and $+30^\circ\text{C}$ (red).
   - **Sun & Moon Celestial Trajectories**: Continuous elevation arcs rising from and landing strictly at the bottom horizon line, annotated with culmination peak badges (`☀ HH:MM (XX°)`, `☾ HH:MM (XX°)`).
   - **Right Y-Axis Celestial Degree Scale**: Dedicated $0^\circ$, $45^\circ$, $90^\circ$ `[Alt]` reference ticks.
2. **Precipitation & Snowfall (mm)**:
   - **90th Percentile (P90) Probability Bars**: Light semi-transparent blue bars render the 90th percentile ensemble volume behind solid median precipitation bars, highlighting high-probability upper rain limits without distorting baseline median expectations.
   - **Logarithmic Scaling `[log]`**: Formulated with a transition factor ($v_0 = 0.2\text{ mm}$) to expand light precipitation events ($0.1 - 2.0\text{ mm}$) that would otherwise be imperceptible on linear scales.
   - **Logarithmic Reference Grid**: Non-linear grid lines at $0.1, 0.2, 0.5, 1, 2, 5, 10, \dots\text{ mm}$.
   - Liquid rain bars, snowfall bars, max-member tick caps, and daily cumulative sum badges (`Σ X.X mm`).
   - **Side-by-Side Solar & Lunar Analemmas**: Embedded in the top-right with transparent backgrounds:
     - **Solar Analemma**: Annual figure-8 tracking solar declination against the Equation of Time ($+16\text{m}$ to $-14\text{m}$) for the active location.
     - **Lunar Analemma**: Closed monthly figure-8 loop reflecting orbital inclination to the celestial equator and Equation of Time harmonics, with an illuminated phase-accurate Moon marker locked strictly on the curve.
3. **Multi-layer Cloud Cover (%)**:
   - **Total Cloud Cover**: Luminous golden-yellow spline curve (`#eab308`) and subtle histogram bins anchored at 0% baseline representing overall cloud volume across time.
   - **Cloud Layers (Single Curves)**: High Cirrus (royal blue `#2563eb`), Medium Alto (emerald `#10b981`), and Low Stratus (crimson `#e11d48`) rendered as distinct, vibrant median lines.
4. **10m Wind Speed & Direction**:
   - **Continuous 5-Point Direction Loop**: Mapped to `N` (top), `W`, `S`, `E`, and `N` (bottom) across a unified, continuous grid to prevent discontinuous edge jumps for north-westerly and northerly winds.
   - **Dual Speed Encoding**:
     - **Curve Thickness**: Line weight scales proportionally with wind speed ($< 2\text{ m/s}$ hairline to $\ge 15\text{ m/s}$ heavy).
     - **Speed Color Categories**: Segmented into calm grey ($< 2\text{ m/s}$), teal ($2-5\text{ m/s}$), emerald ($5-10\text{ m/s}$), warm orange ($10-15\text{ m/s}$), and storm crimson ($> 15\text{ m/s}$).
   - **Interactive Rotational Wind Arrow in HUD**: Displays directional arrow matching meteorological wind angle, color-coded by the active velocity tier.
5. **Mean Sea Level Pressure (MSLP, hPa)**:
   - Atmospheric pressure curve and ensemble spread, $1013.25\text{ hPa}$ standard atmosphere reference line, and synchronized Sun/Moon celestial elevation trajectories with the right-axis `[Alt]` scale.
6. **Daytime & Night Shading Across All Panels**:
   - Daytime shading contrasted with twilight/night bands calculated from astronomical solar altitude.
7. **Astronomical Ephemeris Timeline**:
   - Daily cards displaying weekday, calendar date, sunrise and sunset (`☀ HH:MM – HH:MM`), moonrise and moonset (`☾ HH:MM – HH:MM`), and illuminated vector Moon phase discs with illumination percentages.

---

## 📄 License & Attribution

- **Data Sources**:
  - ECMWF AIFS Open Data &copy; European Centre for Medium-Range Weather Forecasts ([CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/))
  - DWD Open Data &copy; Deutscher Wetterdienst
  - Geocoding & API distribution via [Open-Meteo](https://open-meteo.com)
- **Visual Style**: Inspired by Slovak Hydrometeorological Institute ([SHMÚ](https://www.shmu.sk)) EPSGRAM layouts.
- **License**: GNU General Public License v3 (see [LICENSE](LICENSE)).
