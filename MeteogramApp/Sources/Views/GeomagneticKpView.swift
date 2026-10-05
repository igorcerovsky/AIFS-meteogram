import SwiftUI
import Charts

public struct GeomagneticKpView: View {
    public let aurora: AuroraData
    public let language: ForecastLanguage

    @State private var selectedItem: KpForecastItem? = nil

    public init(aurora: AuroraData, language: ForecastLanguage = .en) {
        self.aurora = aurora
        self.language = language
    }

    private var isSlovak: Bool {
        language == .sk
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            headerView

            // Active Storm / Aurora Visibility Alert Banner (if applicable)
            if aurora.isStormActiveOrPredicted || !aurora.activeAlerts.isEmpty {
                alertBannerView
            }

            // Summary Metrics Row (4 Cards)
            metricsRowView

            // 3-Day Planetary Kp Timeline Chart
            chartSectionView

            // Kp Scale Legend
            scaleLegendView
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.98).opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    aurora.isAuroraLikelyVisible
                        ? Color.purple.opacity(0.4)
                        : (aurora.isStormActiveOrPredicted ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.15)),
                    lineWidth: aurora.isAuroraLikelyVisible ? 1.5 : 1
                )
        )
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(auroraColor(for: aurora.currentKp).opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(auroraColor(for: aurora.currentKp))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(isSlovak ? "Planetárny Kp index & Polárna žiara" : "Planetary Kp Index & Aurora Forecast")
                    .font(.caption.bold())
                    .foregroundColor(.primary)

                Text(isSlovak ? "NOAA Vesmírne počasie (SWPC 3-dňová predpoveď)" : "NOAA Space Weather Prediction Center (3-Day)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Current Kp Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(auroraColor(for: aurora.currentKp))
                    .frame(width: 7, height: 7)
                Text(String(format: "Kp %.1f", aurora.currentKp))
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                if let storm = kpStormScale(aurora.currentKp) {
                    Text(storm)
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(auroraColor(for: aurora.currentKp))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(auroraColor(for: aurora.currentKp).opacity(0.15))
            .cornerRadius(8)
        }
    }

    // MARK: - Alert Banner
    private var alertBannerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: aurora.isAuroraLikelyVisible ? "sparkles.rectangle.stack" : "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundColor(aurora.isAuroraLikelyVisible ? .purple : .orange)

                Text(alertBannerTitle)
                    .font(.caption.bold())
                    .foregroundColor(.primary)

                Spacer()

                if let storm = aurora.activeStorm {
                    Text(storm)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }

            if let firstAlert = aurora.activeAlerts.first?.summary, !firstAlert.isEmpty {
                Text(firstAlert)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if aurora.isAuroraLikelyVisible {
                Text(isSlovak
                     ? "Predpovedaná hodnota Kp prekračuje prah pre túto lokalitu! Polárna žiara môže byť viditeľná nízko nad severným obzorom."
                     : "Forecasted Kp reaches visibility threshold for this location! Aurora may be visible low on the northern horizon.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            (aurora.isAuroraLikelyVisible ? Color.purple : Color.orange).opacity(0.12)
        )
        .cornerRadius(8)
    }

    private var alertBannerTitle: String {
        if aurora.isAuroraLikelyVisible {
            return isSlovak ? "Priaznivé podmienky pre polárnu žiaru" : "Aurora Visibility Possible"
        }
        if let storm = aurora.activeStorm {
            return isSlovak ? "Geomagnetická búrka \(storm) v predpovedi" : "Geomagnetic Storm \(storm) in Forecast"
        }
        return isSlovak ? "Zvýšená geomagnetická aktivita" : "Elevated Geomagnetic Activity"
    }

    // MARK: - Metrics Row
    private var metricsRowView: some View {
        HStack(spacing: 6) {
            metricCard(
                title: isSlovak ? "Aktuálny Kp" : "Current Kp",
                value: String(format: "%.1f", aurora.currentKp),
                subtitle: kpDescription(aurora.currentKp),
                color: auroraColor(for: aurora.currentKp)
            )

            metricCard(
                title: isSlovak ? "3-dňové maximum" : "3-Day Peak",
                value: String(format: "%.1f", aurora.maxKp3d),
                subtitle: kpStormScale(aurora.maxKp3d) ?? (isSlovak ? "Pod prahom búrky" : "Below storm"),
                color: auroraColor(for: aurora.maxKp3d)
            )

            metricCard(
                title: isSlovak ? "Prah pre obzor" : "Horizon Min Kp",
                value: String(format: "≥ %.1f", aurora.minKpNeeded),
                subtitle: isSlovak ? "Severný obzor" : "North horizon",
                color: aurora.isAuroraLikelyVisible ? .purple : .secondary
            )

            if let gLat = aurora.geomagLat {
                metricCard(
                    title: isSlovak ? "Geomag. šírka" : "Geomag Lat",
                    value: String(format: "%.1f°", gLat),
                    subtitle: isSlovak ? "Magnetický dipól" : "Centered dipole",
                    color: .blue
                )
            }
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)

            Text(subtitle)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
    }

    // MARK: - 3-Day Planetary Kp Timeline Chart
    private var chartSectionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let selected = selectedItem {
                selectedInspectionView(selected)
            }

            if !aurora.kpForecast.isEmpty {
                Chart {
                    // Min Kp Needed Threshold Rule
                    RuleMark(y: .value("Threshold", aurora.minKpNeeded))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .foregroundStyle(Color.purple.opacity(0.75))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(format: "%@: Kp %.1f", isSlovak ? "Prah lokality" : "Location threshold", aurora.minKpNeeded))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15))
                                .cornerRadius(3)
                        }

                    // Kp Bars for each 3-hour interval
                    ForEach(aurora.kpForecast) { item in
                        BarMark(
                            x: .value("Time", item.time),
                            y: .value("Kp", item.kp),
                            width: .fixed(7)
                        )
                        .foregroundStyle(barColor(for: item))
                        .cornerRadius(2)
                        .opacity(item.isForecast ? 1.0 : 0.6)
                    }

                    // Selection Indicator
                    if let selected = selectedItem {
                        RuleMark(x: .value("Selected", selected.time))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                }
                .chartYScale(domain: 0...9)
                .chartYAxis {
                    AxisMarks(values: [0, 3, 5, 7, 9]) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let intVal = val.as(Int.self) {
                                Text("\(intVal)")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let t = val.as(String.self) {
                                Text(formatXAxisTime(t))
                                    .font(.system(size: 7))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 120)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let currentX = value.location.x
                                        if let timeTag: String = proxy.value(atX: currentX) {
                                            selectedItem = aurora.kpForecast.min(by: { abs($0.time.compare(timeTag).rawValue) < abs($1.time.compare(timeTag).rawValue) })
                                                ?? aurora.kpForecast.first
                                        }
                                    }
                                    .onEnded { _ in
                                        // Keep selected or clear after delay if desired
                                    }
                            )
                    }
                }
            } else {
                Text(isSlovak ? "Dáta Kp indexu sa načítavajú..." : "Loading Kp index data...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Selected Item Tooltip HUD
    private func selectedInspectionView(_ item: KpForecastItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(formatDetailTime(item.time))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Text(item.isForecast ? (isSlovak ? "Predpoveď" : "Forecast") : (isSlovak ? "Pozorované" : "Observed"))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    if let scale = kpStormScale(item.kp) {
                        Text(scale)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(auroraColor(for: item.kp))
                            .foregroundColor(.white)
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "Kp %.2f", item.kp))
                    .font(.caption.bold())
                    .foregroundColor(auroraColor(for: item.kp))

                Text("• \(kpDescription(item.kp))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Button {
                selectedItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Scale Legend
    private var scaleLegendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                legendItem(title: isSlovak ? "0-2 Pokoj" : "0-2 Quiet", color: Color(hex: "#64748b"))
                legendItem(title: isSlovak ? "3 Mierne" : "3 Unsettled", color: Color(hex: "#84cc16"))
                legendItem(title: isSlovak ? "4 Aktívne" : "4 Active", color: Color(hex: "#eab308"))
                legendItem(title: "5 G1", color: Color(hex: "#f97316"))
                legendItem(title: "6 G2", color: Color(hex: "#ef4444"))
                legendItem(title: "7 G3", color: Color(hex: "#a855f7"))
                legendItem(title: "8 G4", color: Color(hex: "#c026d3"))
                legendItem(title: "9 G5", color: Color(hex: "#7e22ce"))
            }
            .padding(.vertical, 2)
        }
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(4)
    }

    // MARK: - Helpers & Color Logic
    private func barColor(for item: KpForecastItem) -> Color {
        if let hex = item.color, !hex.isEmpty {
            return Color(hex: hex)
        }
        return auroraColor(for: item.kp)
    }

    private func auroraColor(for kp: Double) -> Color {
        if kp >= 9.0 { return Color(hex: "#7e22ce") } // G5 Deep Violet
        if kp >= 8.0 { return Color(hex: "#c026d3") } // G4 Fuchsia
        if kp >= 7.0 { return Color(hex: "#a855f7") } // G3 Purple
        if kp >= 6.0 { return Color(hex: "#ef4444") } // G2 Red
        if kp >= 5.0 { return Color(hex: "#f97316") } // G1 Orange
        if kp >= 4.0 { return Color(hex: "#eab308") } // Active Amber
        if kp >= 3.0 { return Color(hex: "#84cc16") } // Unsettled Lime
        return Color(hex: "#64748b")                  // Quiet Slate
    }

    private func kpStormScale(_ kp: Double) -> String? {
        if kp >= 9.0 { return "G5" }
        if kp >= 8.0 { return "G4" }
        if kp >= 7.0 { return "G3" }
        if kp >= 6.0 { return "G2" }
        if kp >= 5.0 { return "G1" }
        return nil
    }

    private func kpDescription(_ kp: Double) -> String {
        if kp >= 9.0 { return isSlovak ? "G5 Extrémna búrka" : "G5 Extreme Storm" }
        if kp >= 8.0 { return isSlovak ? "G4 Veľmi silná búrka" : "G4 Severe Storm" }
        if kp >= 7.0 { return isSlovak ? "G3 Silná búrka" : "G3 Strong Storm" }
        if kp >= 6.0 { return isSlovak ? "G2 Mierna búrka" : "G2 Moderate Storm" }
        if kp >= 5.0 { return isSlovak ? "G1 Malá búrka" : "G1 Minor Storm" }
        if kp >= 4.0 { return isSlovak ? "Aktívne" : "Active" }
        if kp >= 3.0 { return isSlovak ? "Mierne nepokojné" : "Unsettled" }
        return isSlovak ? "Pokojné" : "Quiet"
    }

    private func formatXAxisTime(_ timeStr: String) -> String {
        let clean = timeStr.replacingOccurrences(of: "Z", with: "")
        let parts = clean.split(separator: "T").isEmpty ? clean.split(separator: " ") : clean.split(separator: "T")
        if parts.count >= 2 {
            let dayPart = parts[0].split(separator: "-").suffix(2).joined(separator: "/")
            let hourPart = parts[1].prefix(5)
            return "\(dayPart) \(hourPart)"
        }
        return timeStr
    }

    private func formatDetailTime(_ timeStr: String) -> String {
        let clean = timeStr.replacingOccurrences(of: "Z", with: "")
        return clean.replacingOccurrences(of: "T", with: " ")
    }
}

// MARK: - Color Hex Initializer
private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch clean.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
