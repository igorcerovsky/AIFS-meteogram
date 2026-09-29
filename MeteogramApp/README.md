# MeteogramApp (iOS & macOS)

A native multiplatform Apple application built with **SwiftUI** for visualizing **ECMWF AIFS** (50-member AI ensemble) and **DWD ICON-EU / ICON-D2** meteograms, inspired by [SHMÚ's EPSGRAM](https://www.shmu.sk/sk/?page=1&id=meteo_epsgramy) layouts.

Runs seamlessly on:
- **macOS** (macOS 14.0 Sonoma or newer, Apple Silicon & Intel)
- **iOS & iPadOS** (iOS 17.0 or newer, iPhone & iPad)

---

## ✨ Features

- **Full Model Parity with Web Interface**:
  - **ECMWF AIFS**: 15 days, 10 days, 7 days (50 ensemble members).
  - **DWD ICON-EU**: 5 days (7 km, 40 ensemble members).
  - **DWD ICON-D2**: 2 days / 48h (2.2 km high resolution, 20 ensemble members).
- **Smart Domain Fallback**:
  - Automatic coverage check for locations outside Central Europe (ICON-D2).
  - Seamless fallback to ICON-EU or AIFS with an in-app notice banner.
- **Location Search & Presets**:
  - Quick chips: *Bratislava-Koliba, Jasná, Liptovský Mikuláš, Repiská, Plavecké Podhradie, Lengerich (DE), Rajka (HU), Košice, Poprad/Tatry, Vienna, Prague*.
  - Search by city name or `lat, lon` coordinates.
  - One-tap **GPS Location** (`CoreLocation`).
  - Star / Favorites system.
- **Interactive Native Chart & Image Viewer**:
  - Native **Swift Charts** engine with real-time gesture selection, 90th percentile (P90) semi-transparent precipitation bars alongside solid median rain/snow, transparent side-by-side Solar & Lunar Analemma cards, and continuous wind curve loops.
  - Interactive HUD inspection pane with dynamic rotating wind direction arrow colored by speed tier.
  - Locked time domain scaling during horizontal model swipes (`15d ↔ 2d ↔ 5d ↔ 10d ↔ 7d`) for absolute gesture stability without zoom shifts.
  - Fluid pinch-to-zoom (up to 400%), smooth panning, and double-tap zoom reset.
  - Floating zoom controls overlay (+, -, reset).
  - High-DPI crisp rendering.
- **Language & Time Zone**:
  - Languages: English (`en`) and Slovenčina (`sk`).
  - Time Zones: Local Time (`local`) and UTC (`utc`).
- **Native Apple Integrations**:
  - System Share Sheet (AirDrop, Messages, Mail).
  - Copy Image to Clipboard (`⌘C` on Mac).
  - Keyboard Shortcuts (`⌘R` to refresh).
- **Flexible Server Connection**:
  - Easily switch between `http://localhost:8080` (when running on Mac) and `http://Igors-MacBook-Air.local:8080` (or LAN IP/cloud URL on iPhone).
  - In-app **Test Connection** button measuring real-time latency.

---

## 🚀 How to Run

### 1. Start the Meteogram Python Server
The app connects to the lightweight backend in the `server/` directory:
```bash
python3 server/server.py 8080
```
This runs the API on port `8080`.

### 2. Open the Project in Xcode
1. Open `MeteogramApp/MeteogramApp.xcodeproj` in Xcode:
   ```bash
   open MeteogramApp/MeteogramApp.xcodeproj
   ```
2. Select your run destination in the top toolbar:
   - **My Mac** (to run natively on macOS)
   - **iPhone 17 Pro / any iOS Simulator** (to run on iOS)
   - **Your connected physical iPhone/iPad**
3. Press **Run (`⌘R`)**.

---

## 📱 Connecting from an iPhone or iPad

When running on an iPhone:
1. Ensure your iPhone is connected to the same Wi-Fi network as your Mac.
2. Tap the **Settings (gear)** icon in the top right.
3. Tap **Mac Bonjour** (`http://Igors-MacBook-Air.local:8080`) or enter your Mac's local IP (`http://192.168.1.X:8080`).
4. Tap **Test Connection** to confirm connectivity.
5. Tap **Save**. Your iPhone will now fetch and display meteograms directly from your Mac!

---

## 📲 Permanent Installation on iPhone

To run the app on your physical iPhone without having it expire:

| Method | Validity | Cost | Renewal Effort | Best For |
| :--- | :--- | :--- | :--- | :--- |
| **PWA Web App** | Unlimited | Free | None (Automatic) | Instant access anywhere without Xcode |
| **Apple Developer Account** | 365 Days | $99/year | Once a year | Best native experience & TestFlight distribution |
| **AltStore / SideStore** | Permanent (auto-refresh) | Free | Automatic in background over Wi-Fi | Free native sideloading without weekly Mac connection |
| **Xcode Free Team** | 7 Days | Free | Re-run `⌘R` in Xcode weekly | Local testing and debugging |

### 1. PWA Web App (Zero Setup, No Expiry)
Open the live meteogram web app in Safari on your iPhone:
`https://igorcerovsky.github.io/AIFS-meteogram/`
Tap the **Share** button in Safari $\rightarrow$ tap **Add to Home Screen** $\rightarrow$ tap **Add**.
- Launches full-screen like a standalone app with its own app icon.
- Queries Open-Meteo directly with zero backend required.
- Never expires and requires no certificates or profiles.

### 2. Apple Developer Account (365 Days or TestFlight)
With an active Apple Developer Program account:
1. In Xcode, set **Signing & Capabilities** to your paid Apple Developer Team.
2. Direct install on your device remains valid for a full **365 days**.
3. Or distribute via **TestFlight** (internal testing: up to 100 devices, builds valid 90 days with seamless automatic updates over the air).

### 3. AltStore / SideStore (Permanent Free Sideloading)
1. Install [SideStore](https://sidestore.io/) or [AltStore](https://altstore.io/) on your iPhone.
2. In Xcode, select **Product $\rightarrow$ Archive**, export the `.ipa` package.
3. Open the `.ipa` in SideStore/AltStore on your iPhone.
4. SideStore automatically refreshes the 7-day provisioning certificate in the background over local Wi-Fi via a local WireGuard loopback, keeping the native app permanently active.

---

## 📁 Architecture & File Structure

```
MeteogramApp/
├── MeteogramApp.xcodeproj/     # Multiplatform Xcode Project
├── Sources/
│   ├── MeteogramApp.swift      # App lifecycle & macOS menu commands
│   ├── Models/
│   │   ├── ForecastModel.swift # Horizons, models, languages, timezones
│   │   ├── ForecastData.swift  # Time-series ephemeris & lunar/solar analemma math
│   │   └── MeteogramConfig.swift # Presets and domain validation
│   ├── Services/
│   │   ├── MeteogramService.swift # URLSession client & header parser
│   │   └── LocationManager.swift  # CoreLocation GPS coordinates
│   ├── ViewModels/
│   │   └── MeteogramViewModel.swift # State manager & caching
│   ├── Views/
│   │   ├── ContentView.swift      # Adaptive root container
│   │   ├── NativeMeteogramChartView.swift # Native Swift Charts meteogram & analemmas
│   │   ├── ControlPanelView.swift # Controls & parameters form
│   │   ├── ModelPillsBar.swift    # Compact model switch pills
│   │   ├── MeteogramImageViewer.swift # Gesture-enabled image viewer
│   │   ├── FallbackAlertBanner.swift  # Model fallback warning banner
│   │   ├── PresetsRowView.swift   # Quick preset chips
│   │   └── SettingsView.swift     # Server config & latency test
│   └── Resources/
│       ├── Assets.xcassets/       # AppIcon and AccentColor
│       └── Info.plist             # Permissions and ATS settings
└── README.md
```
