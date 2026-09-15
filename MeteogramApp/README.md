# MeteogramApp (iOS & macOS)

A native multiplatform Apple application built with **SwiftUI** for visualizing **ECMWF AIFS** (50-member AI ensemble) and **DWD ICON-EU / ICON-D2** meteograms in the classic **SHMÚ EPSGRAM** style.

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
  - Quick chips: *Bratislava-Koliba, Jasná, Liptovský Mikuláš, Plavecké Podhradie, Košice, Poprad/Tatry, Vienna, Prague*.
  - Search by city name or `lat, lon` coordinates.
  - One-tap **GPS Location** (`CoreLocation`).
  - Star / Favorites system.
- **Interactive Meteogram Viewer**:
  - Pinch-to-zoom (up to 400%), smooth panning, and double-tap zoom reset.
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

## 📁 Architecture & File Structure

```
MeteogramApp/
├── MeteogramApp.xcodeproj/     # Multiplatform Xcode Project
├── Sources/
│   ├── MeteogramApp.swift      # App lifecycle & macOS menu commands
│   ├── Models/
│   │   ├── ForecastModel.swift # Horizons, models, languages, timezones
│   │   └── MeteogramConfig.swift # Presets and domain validation
│   ├── Services/
│   │   ├── MeteogramService.swift # URLSession client & header parser
│   │   └── LocationManager.swift  # CoreLocation GPS coordinates
│   ├── ViewModels/
│   │   └── MeteogramViewModel.swift # State manager & caching
│   ├── Views/
│   │   ├── ContentView.swift      # Adaptive root container
│   │   ├── ControlPanelView.swift # Controls & parameters form
│   │   ├── MeteogramImageViewer.swift # Gesture-enabled image viewer
│   │   ├── FallbackAlertBanner.swift  # Model fallback warning banner
│   │   ├── PresetsRowView.swift   # Quick preset chips
│   │   └── SettingsView.swift     # Server config & latency test
│   └── Resources/
│       ├── Assets.xcassets/       # AppIcon and AccentColor
│       └── Info.plist             # Permissions and ATS settings
└── README.md
```
