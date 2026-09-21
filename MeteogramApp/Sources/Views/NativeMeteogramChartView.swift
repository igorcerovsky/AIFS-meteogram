import SwiftUI
import Charts

public struct NativeMeteogramChartView: View {
    @ObservedObject var viewModel: MeteogramViewModel
    @Binding var selectedDate: Date?

    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void

    @State private var dragOffset: CGFloat = 0

    public init(
        viewModel: MeteogramViewModel,
        selectedDate: Binding<Date?>,
        onSwipeLeft: @escaping () -> Void = {},
        onSwipeRight: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self._selectedDate = selectedDate
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
    }

    public var body: some View {
        GeometryReader { proxy in
            let points = viewModel.timeSeries

            if points.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(viewModel.loadingStatusText.isEmpty ? "Loading forecast..." : viewModel.loadingStatusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .top) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 10) {
                            // Location Header
                            chartHeaderView

                            // Panel 1: Temperature & Freezing / Thresholds
                            temperaturePanelView(points: points)

                            // Panel 2: Precipitation & Snowfall
                            precipitationPanelView(points: points)

                            // Panel 3: Cloud Cover Breakdown
                            cloudCoverPanelView(points: points)

                            // Panel 4: Wind Speed & Direction
                            windPanelView(points: points)

                            // Panel 5: Mean Sea Level Pressure
                            pressurePanelView(points: points)

                            // Astronomical Ephemeris Timeline
                            ephemerisTimelineView(points: points)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .padding(.top, selectedPoint != nil ? 75 : 0) // Space for floating HUD
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 30)
                            .onChanged { value in
                                if selectedDate == nil && abs(value.translation.width) > abs(value.translation.height) {
                                    dragOffset = value.translation.width
                                }
                            }
                            .onEnded { value in
                                if selectedDate == nil {
                                    if value.translation.width < -60 {
                                        onSwipeLeft()
                                    } else if value.translation.width > 60 {
                                        onSwipeRight()
                                    }
                                    dragOffset = 0
                                }
                            }
                    )

                    // Floating HUD Tooltip when scrubbing with .chartXSelection
                    if let selPoint = selectedPoint {
                        floatingHUDView(point: selPoint)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 4)
                            .zIndex(100)
                    }
                }
            }
        }
    }

    private var selectedPoint: TimeSeriesPoint? {
        viewModel.selectedPoint
    }

    // MARK: - Header
    private var chartHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let loc = viewModel.forecastData?.location {
                    HStack(spacing: 6) {
                        Text("\(loc.name)")
                            .font(.headline)
                            .fontWeight(.bold)
                        if let elev = loc.elevation {
                            Text("(\(Int(elev)) m)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Text("Ensemble Forecast (SHMÚ EPSGRAM Style) • \(viewModel.horizon.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()

            if selectedDate != nil {
                Button("Clear Crosshair") {
                    withAnimation { selectedDate = nil }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Panel 1: Temperature [°C]
    private func temperaturePanelView(points: [TimeSeriesPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("2m Air Temperature [°C]", systemImage: "thermometer.medium")
                    .font(.caption.bold())
                    .foregroundColor(.red)

                Spacer()

                HStack(spacing: 12) {
                    legendItem(title: "Median", color: .red, isLine: true)
                    legendItem(title: "25-75%", color: .red.opacity(0.35))
                    legendItem(title: "Spread", color: .red.opacity(0.18))
                }
                .font(.caption2)
            }

            Chart {
                ForEach(points) { p in
                    if let pMin = p.tempMin, let pMax = p.tempMax {
                        AreaMark(
                            x: .value("Time", p.date),
                            yStart: .value("Min", pMin),
                            yEnd: .value("Max", pMax)
                        )
                        .foregroundStyle(Color.red.opacity(0.14))
                    }
                }

                ForEach(points) { p in
                    if let pQ25 = p.tempQ25, let pQ75 = p.tempQ75 {
                        AreaMark(
                            x: .value("Time", p.date),
                            yStart: .value("Q25", pQ25),
                            yEnd: .value("Q75", pQ75)
                        )
                        .foregroundStyle(Color.red.opacity(0.28))
                    }
                }

                ForEach(points) { p in
                    LineMark(
                        x: .value("Time", p.date),
                        y: .value("Temperature", p.tempMedian)
                    )
                    .foregroundStyle(Color.red)
                    .lineStyle(StrokeStyle(lineWidth: 2.2))
                }

                // Reference Threshold Grid Lines (-10, 0, 10, 20, 30°C)
                RuleMark(y: .value("Threshold", -10.0))
                    .foregroundStyle(Color.cyan.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                RuleMark(y: .value("Freezing", 0.0))
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 3]))

                RuleMark(y: .value("Threshold", 10.0))
                    .foregroundStyle(Color.yellow.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                RuleMark(y: .value("Threshold", 20.0))
                    .foregroundStyle(Color.orange.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                RuleMark(y: .value("Threshold", 30.0))
                    .foregroundStyle(Color.red.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                // Synchronized Selection Crosshair
                if let selDate = selectedDate {
                    RuleMark(x: .value("Selected", selDate))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                    if let selPoint = selectedPoint {
                        PointMark(
                            x: .value("Selected", selPoint.date),
                            y: .value("Temperature", selPoint.tempMedian)
                        )
                        .foregroundStyle(Color.red)
                        .symbolSize(40)
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.weekday().day())
                }
            }
            .frame(height: 150)
            .background(Color(white: 0.98).opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    // MARK: - Panel 2: Precipitation & Snowfall [mm]
    private func precipitationPanelView(points: [TimeSeriesPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Precipitation & Snowfall [mm]", systemImage: "cloud.rain.fill")
                    .font(.caption.bold())
                    .foregroundColor(.blue)

                Spacer()

                HStack(spacing: 12) {
                    legendItem(title: "Rain", color: .blue)
                    legendItem(title: "Snow", color: .cyan)
                    legendItem(title: "Max Member", color: .indigo, isLine: true)
                }
                .font(.caption2)
            }

            Chart {
                ForEach(points) { p in
                    if p.precipMedian > 0 {
                        BarMark(
                            x: .value("Time", p.date),
                            y: .value("Rain", p.precipMedian)
                        )
                        .foregroundStyle(Color.blue.opacity(0.85))
                    }
                }

                ForEach(points) { p in
                    if p.snowMedian > 0 {
                        BarMark(
                            x: .value("Time", p.date),
                            y: .value("Snow", p.snowMedian)
                        )
                        .foregroundStyle(Color.cyan.opacity(0.85))
                    }
                }

                ForEach(points) { p in
                    if let pMax = p.precipMax, pMax > 0 {
                        RuleMark(
                            xStart: .value("Time", p.date.addingTimeInterval(-1200)),
                            xEnd: .value("Time", p.date.addingTimeInterval(1200)),
                            y: .value("Max", pMax)
                        )
                        .foregroundStyle(Color.indigo)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }

                if let selDate = selectedDate {
                    RuleMark(x: .value("Selected", selDate))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                }
            }
            .frame(height: 100)
            .background(Color(white: 0.98).opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    // MARK: - Panel 3: Multi-Layer Cloud Cover [%]
    private func cloudCoverPanelView(points: [TimeSeriesPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Cloud Cover [%]", systemImage: "cloud.fill")
                    .font(.caption.bold())
                    .foregroundColor(.yellow)

                Spacer()

                HStack(spacing: 10) {
                    legendItem(title: "Total (Bars)", color: .yellow)
                    legendItem(title: "High", color: .cyan, isLine: true)
                    legendItem(title: "Mid", color: .teal, isLine: true)
                    legendItem(title: "Low", color: .pink, isLine: true)
                }
                .font(.caption2)
            }

            Chart {
                cloudBars(points: points)
                cloudLayerLines(points: points)

                if let selDate = selectedDate {
                    RuleMark(x: .value("Selected", selDate))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                }
            }
            .frame(height: 110)
            .background(Color(white: 0.98).opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    @ChartContentBuilder
    private func cloudBars(points: [TimeSeriesPoint]) -> some ChartContent {
        ForEach(points) { p in
            if let cMin = p.cloudTotalMin, let cMax = p.cloudTotalMax, cMax > 0 {
                BarMark(
                    x: .value("Time", p.date),
                    yStart: .value("Min", cMin),
                    yEnd: .value("Max", cMax)
                )
                .foregroundStyle(Color.yellow.opacity(0.35))
            }
        }

        ForEach(points) { p in
            if let cQ25 = p.cloudTotalQ25, let cQ75 = p.cloudTotalQ75, cQ75 > 0 {
                BarMark(
                    x: .value("Time", p.date),
                    yStart: .value("Q25", cQ25),
                    yEnd: .value("Q75", cQ75)
                )
                .foregroundStyle(Color.yellow.opacity(0.75))
            }
        }
    }

    @ChartContentBuilder
    private func cloudLayerLines(points: [TimeSeriesPoint]) -> some ChartContent {
        ForEach(points) { p in
            LineMark(
                x: .value("Time", p.date),
                y: .value("Total Median", p.cloudTotalMedian)
            )
            .foregroundStyle(Color.orange)
            .lineStyle(StrokeStyle(lineWidth: 1.8))
        }

        ForEach(points) { p in
            if let cHigh = p.cloudHigh {
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("High", cHigh)
                )
                .foregroundStyle(Color.cyan)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
            }
        }

        ForEach(points) { p in
            if let cMid = p.cloudMid {
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Mid", cMid)
                )
                .foregroundStyle(Color.teal)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
            }
        }

        ForEach(points) { p in
            if let cLow = p.cloudLow {
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Low", cLow)
                )
                .foregroundStyle(Color.pink)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
            }
        }
    }

    // MARK: - Panel 4: Wind Speed & Direction [km/h]
    private func windPanelView(points: [TimeSeriesPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("10m Wind Speed [km/h] & Direction", systemImage: "wind")
                    .font(.caption.bold())
                    .foregroundColor(.brown)

                Spacer()

                HStack(spacing: 12) {
                    legendItem(title: "Median", color: .brown, isLine: true)
                    legendItem(title: "Spread", color: .brown.opacity(0.2))
                }
                .font(.caption2)
            }

            Chart {
                ForEach(points) { p in
                    if let wMin = p.windSpeedMin, let wMax = p.windSpeedMax {
                        AreaMark(
                            x: .value("Time", p.date),
                            yStart: .value("Min", wMin * 3.6),
                            yEnd: .value("Max", wMax * 3.6)
                        )
                        .foregroundStyle(Color.brown.opacity(0.18))
                    }
                }

                ForEach(points) { p in
                    if let wQ25 = p.windSpeedQ25, let wQ75 = p.windSpeedQ75 {
                        AreaMark(
                            x: .value("Time", p.date),
                            yStart: .value("Q25", wQ25 * 3.6),
                            yEnd: .value("Q75", wQ75 * 3.6)
                        )
                        .foregroundStyle(Color.brown.opacity(0.32))
                    }
                }

                ForEach(points) { p in
                    LineMark(
                        x: .value("Time", p.date),
                        y: .value("Speed", p.windSpeedKmH)
                    )
                    .foregroundStyle(Color.brown)
                    .lineStyle(StrokeStyle(lineWidth: 2.0))
                }

                if let selDate = selectedDate {
                    RuleMark(x: .value("Selected", selDate))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                }
            }
            .frame(height: 105)
            .background(Color(white: 0.98).opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    // MARK: - Panel 5: Mean Sea Level Pressure [hPa]
    private func pressurePanelView(points: [TimeSeriesPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Mean Sea Level Pressure [hPa]", systemImage: "gauge.with.needle")
                    .font(.caption.bold())
                    .foregroundColor(.purple)

                Spacer()

                HStack(spacing: 12) {
                    legendItem(title: "Median", color: .purple, isLine: true)
                    legendItem(title: "1013 hPa Std", color: .gray, isLine: true)
                }
                .font(.caption2)
            }

            Chart {
                ForEach(points) { p in
                    if let prMin = p.pressureMin, let prMax = p.pressureMax {
                        AreaMark(
                            x: .value("Time", p.date),
                            yStart: .value("Min", prMin),
                            yEnd: .value("Max", prMax)
                        )
                        .foregroundStyle(Color.purple.opacity(0.15))
                    }
                }

                ForEach(points) { p in
                    LineMark(
                        x: .value("Time", p.date),
                        y: .value("Pressure", p.pressureMedian)
                    )
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2.0))
                }

                RuleMark(y: .value("Std", 1013.25))
                    .foregroundStyle(Color.gray.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                if let selDate = selectedDate {
                    RuleMark(x: .value("Selected", selDate))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                }
            }
            .frame(height: 100)
            .background(Color(white: 0.98).opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    // MARK: - Ephemeris Timeline View
    private func ephemerisTimelineView(points: [TimeSeriesPoint]) -> some View {
        let daily = viewModel.forecastData?.astro?.daily ?? [:]

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(daily.keys.sorted(), id: \.self) { dayKey in
                    if let item = daily[dayKey] {
                        VStack(alignment: .center, spacing: 3) {
                            Text(dayKey)
                                .font(.caption.bold())
                                .foregroundColor(.primary)

                            if let r = item.sunrise, let s = item.sunset {
                                Text("☀️ \(formatTime(r)) – \(formatTime(s))")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                            }

                            if let mr = item.moonrise, let ms = item.moonset {
                                Text("☾ \(formatTime(mr)) – \(formatTime(ms))")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }

                            if let phase = item.moonPhase, let illum = item.illumPct {
                                HStack(spacing: 4) {
                                    Text(moonIcon(for: phase))
                                    Text("\(illum)%")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Floating HUD View
    private func floatingHUDView(point: TimeSeriesPoint) -> some View {
        HStack(spacing: 12) {
            // Time
            VStack(alignment: .leading, spacing: 2) {
                Text(point.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                if let sunAlt = point.sunAltitude {
                    Text(String(format: "☀️ Alt: %.1f°", sunAlt))
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }

            Divider().frame(height: 30)

            // Temp
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f°C", point.tempMedian))
                    .font(.subheadline.bold())
                    .foregroundColor(.red)
                if let q25 = point.tempQ25, let q75 = point.tempQ75 {
                    Text(String(format: "%.0f–%.0f°C", q25, q75))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            Divider().frame(height: 30)

            // Precip
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f mm", point.precipMedian))
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
                if point.snowMedian > 0 {
                    Text(String(format: "❄️ %.1f cm", point.snowMedian))
                        .font(.system(size: 9))
                        .foregroundColor(.cyan)
                }
            }

            Divider().frame(height: 30)

            // Clouds
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "☁ %.0f%%", point.cloudTotalMedian))
                    .font(.subheadline.bold())
                    .foregroundColor(.yellow)
                Text(String(format: "H:%.0f M:%.0f L:%.0f", point.cloudHigh ?? 0, point.cloudMid ?? 0, point.cloudLow ?? 0))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 30)

            // Wind
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f km/h", point.windSpeedKmH))
                    .font(.subheadline.bold())
                    .foregroundColor(.brown)
                Text("\(point.windCompassDirection)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 30)

            // Pressure
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f hPa", point.pressureMedian))
                    .font(.subheadline.bold())
                    .foregroundColor(.purple)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThickMaterial)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Helpers
    private func legendItem(title: String, color: Color, isLine: Bool = false) -> some View {
        HStack(spacing: 4) {
            if isLine {
                Rectangle()
                    .fill(color)
                    .frame(width: 10, height: 2)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .foregroundColor(.secondary)
        }
    }

    private func formatTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return "--:--"
        }
        let out = DateFormatter()
        out.dateFormat = "HH:mm"
        return out.string(from: d)
    }

    private func moonIcon(for phase: Double) -> String {
        switch phase {
        case 0.0..<0.125, 0.95...1.0: return "🌑"
        case 0.125..<0.25: return "🌒"
        case 0.25..<0.375: return "🌓"
        case 0.375..<0.50: return "🌔"
        case 0.50..<0.625: return "🌕"
        case 0.625..<0.75: return "🌖"
        case 0.75..<0.875: return "🌗"
        default: return "🌘"
        }
    }
}
