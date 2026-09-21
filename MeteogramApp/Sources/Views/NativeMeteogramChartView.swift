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

    // MARK: - Panel 1: Temperature [°C] & Celestial Curves
    private func temperaturePanelView(points: [TimeSeriesPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("2m Air Temperature [°C] & Celestial Altitude", systemImage: "thermometer.medium")
                    .font(.caption.bold())
                    .foregroundColor(.red)

                Spacer()

                HStack(spacing: 10) {
                    legendItem(title: "Median", color: .red, isLine: true)
                    legendItem(title: "Spread", color: .red.opacity(0.25))
                    legendItem(title: "☀ Sun Alt", color: Color(red: 244/255, green: 162/255, blue: 97/255), isLine: true)
                    legendItem(title: "🌙 Moon Alt", color: Color(red: 0/255, green: 180/255, blue: 216/255), isLine: true)
                }
                .font(.caption2)
            }

            ZStack {
                // Background: Celestial Altitude (0° .. 92°, anchored at horizon = 0°)
                Chart {
                    celestialMarks(points: points)
                }
                .chartYScale(domain: 0...92)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [30, 60]) { val in
                        AxisGridLine()
                            .foregroundStyle(Color.orange.opacity(0.12))
                        AxisValueLabel {
                            if let v = val.as(Int.self) {
                                Text("\(v)°")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(Color(red: 244/255, green: 162/255, blue: 97/255))
                            }
                        }
                    }
                }

                // Foreground: Temperature Ensemble & Grid
                Chart {
                    temperatureSpreadMarks(points: points)
                    temperatureMedianMark(points: points)
                    temperatureThresholdMarks()

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
                    xAxisMarks(points: points)
                }
            }
            .frame(height: 155)
            .background(Color(white: 0.98).opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }

    @ChartContentBuilder
    private func celestialMarks(points: [TimeSeriesPoint]) -> some ChartContent {
        ForEach(points) { p in
            if let sAlt = p.sunAltitude, sAlt >= 0 {
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Sun Alt", sAlt),
                    series: .value("Celestial", "Sun")
                )
                .foregroundStyle(Color(red: 244/255, green: 162/255, blue: 97/255))
                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
            }
        }

        ForEach(points) { p in
            if let mAlt = p.moonAltitude, mAlt >= 0 {
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Moon Alt", mAlt),
                    series: .value("Celestial", "Moon")
                )
                .foregroundStyle(Color(red: 0/255, green: 180/255, blue: 216/255))
                .lineStyle(StrokeStyle(lineWidth: 1.3, dash: [2, 3]))
            }
        }
    }

    @ChartContentBuilder
    private func temperatureSpreadMarks(points: [TimeSeriesPoint]) -> some ChartContent {
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
    }

    @ChartContentBuilder
    private func temperatureMedianMark(points: [TimeSeriesPoint]) -> some ChartContent {
        ForEach(points) { p in
            LineMark(
                x: .value("Time", p.date),
                y: .value("Temperature", p.tempMedian),
                series: .value("Temp", "Median")
            )
            .foregroundStyle(Color.red)
            .lineStyle(StrokeStyle(lineWidth: 2.2))
        }
    }

    @ChartContentBuilder
    private func temperatureThresholdMarks() -> some ChartContent {
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
    }

    @AxisContentBuilder
    private func xAxisMarks(points: [TimeSeriesPoint]) -> some AxisContent {
        let isShort = (points.count <= 72)
        if isShort {
            AxisMarks(values: .automatic(desiredCount: 8)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.weekday(.short).hour())
            }
        } else {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.weekday().day())
            }
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
                    .foregroundColor(Color(red: 202/255, green: 138/255, blue: 4/255))

                Spacer()

                HStack(spacing: 12) {
                    legendItem(title: "Total (Bars)", color: Color(red: 250/255, green: 204/255, blue: 21/255))
                    legendItem(title: "High (cirrus)", color: Color(red: 6/255, green: 182/255, blue: 212/255), isLine: true)
                    legendItem(title: "Medium (alto)", color: Color(red: 16/255, green: 185/255, blue: 129/255), isLine: true)
                    legendItem(title: "Low (stratus)", color: Color(red: 225/255, green: 29/255, blue: 72/255), isLine: true)
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
        // Full ensemble min-max spread
        ForEach(points) { p in
            if let cMin = p.cloudTotalMin, let cMax = p.cloudTotalMax, (cMax > 0 || cMin > 0) {
                BarMark(
                    x: .value("Time", p.date),
                    yStart: .value("Min", cMin),
                    yEnd: .value("Max", cMax)
                )
                .foregroundStyle(Color(red: 254/255, green: 240/255, blue: 138/255).opacity(0.55))
            } else if p.cloudTotalMin == nil && p.cloudTotalMedian > 0 {
                // Deterministic / single-member fallback
                BarMark(
                    x: .value("Time", p.date),
                    y: .value("Total", p.cloudTotalMedian)
                )
                .foregroundStyle(Color(red: 250/255, green: 204/255, blue: 21/255).opacity(0.82))
            }
        }

        // 50% interquartile spread (Q25-Q75)
        ForEach(points) { p in
            if let cQ25 = p.cloudTotalQ25, let cQ75 = p.cloudTotalQ75, cQ75 > 0 {
                BarMark(
                    x: .value("Time", p.date),
                    yStart: .value("Q25", cQ25),
                    yEnd: .value("Q75", cQ75)
                )
                .foregroundStyle(Color(red: 250/255, green: 204/255, blue: 21/255).opacity(0.85))
            }
        }
    }

    @ChartContentBuilder
    private func cloudLayerLines(points: [TimeSeriesPoint]) -> some ChartContent {
        // 1. Total Cloud Median line (Golden amber)
        ForEach(points) { p in
            LineMark(
                x: .value("Time", p.date),
                y: .value("Total Median", p.cloudTotalMedian),
                series: .value("Layer", "Total")
            )
            .foregroundStyle(Color(red: 202/255, green: 138/255, blue: 4/255))
            .lineStyle(StrokeStyle(lineWidth: 1.8))
        }

        // 2. High Clouds: Blue / Cyan (#06b6d4)
        ForEach(points) { p in
            if let cHigh = p.cloudHigh {
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("High", cHigh),
                    series: .value("Layer", "High")
                )
                .foregroundStyle(Color(red: 6/255, green: 182/255, blue: 212/255))
                .lineStyle(StrokeStyle(lineWidth: 1.8))
            }
        }

        // 3. Medium Clouds: Green / Emerald (#10b981)
        ForEach(points) { p in
            if let cMid = p.cloudMid {
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Mid", cMid),
                    series: .value("Layer", "Mid")
                )
                .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
                .lineStyle(StrokeStyle(lineWidth: 1.8))
            }
        }

        // 4. Low Clouds: Red / Crimson (#e11d48)
        ForEach(points) { p in
            if let cLow = p.cloudLow {
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Low", cLow),
                    series: .value("Layer", "Low")
                )
                .foregroundStyle(Color(red: 225/255, green: 29/255, blue: 72/255))
                .lineStyle(StrokeStyle(lineWidth: 1.8))
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
        let validMinList = points.compactMap { $0.pressureMin }
        let validMaxList = points.compactMap { $0.pressureMax }
        let validMedList = points.map(\.pressureMedian).filter { $0 > 800 }

        let minP = validMinList.min() ?? (validMedList.min() ?? 1010.0)
        let maxP = validMaxList.max() ?? (validMedList.max() ?? 1025.0)

        let rawMin = floor((minP - 2.0) / 5.0) * 5.0
        let rawMax = ceil((maxP + 2.0) / 5.0) * 5.0
        let yDomain: ClosedRange<Double> = {
            if rawMax - rawMin < 10 {
                return (rawMin - 5)...(rawMax + 5)
            }
            return rawMin...rawMax
        }()

        let showStdLine = yDomain.contains(1013.25)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Mean Sea Level Pressure [hPa]", systemImage: "gauge.with.needle")
                    .font(.caption.bold())
                    .foregroundColor(.purple)

                Spacer()

                HStack(spacing: 12) {
                    legendItem(title: "Median", color: .purple, isLine: true)
                    if showStdLine {
                        legendItem(title: "1013 hPa Std", color: .gray, isLine: true)
                    }
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

                if showStdLine {
                    RuleMark(y: .value("Std", 1013.25))
                        .foregroundStyle(Color.gray.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                if let selDate = selectedDate {
                    RuleMark(x: .value("Selected", selDate))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 5)) { val in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))")
                        }
                    }
                }
            }
            .chartXAxis {
                xAxisMarks(points: points)
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
                HStack(spacing: 4) {
                    if let sunAlt = point.sunAltitude, sunAlt > 0 {
                        Text(String(format: "☀ %.0f°", sunAlt))
                            .foregroundColor(Color(red: 244/255, green: 162/255, blue: 97/255))
                    }
                    if let moonAlt = point.moonAltitude, moonAlt > 0 {
                        Text(String(format: "🌙 %.0f°", moonAlt))
                            .foregroundColor(Color(red: 0/255, green: 180/255, blue: 216/255))
                    }
                }
                .font(.system(size: 9, weight: .semibold))
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
                    .foregroundColor(Color(red: 202/255, green: 138/255, blue: 4/255))
                HStack(spacing: 4) {
                    Text(String(format: "H:%.0f", point.cloudHigh ?? 0))
                        .foregroundColor(Color(red: 6/255, green: 182/255, blue: 212/255))
                    Text(String(format: "M:%.0f", point.cloudMid ?? 0))
                        .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
                    Text(String(format: "L:%.0f", point.cloudLow ?? 0))
                        .foregroundColor(Color(red: 225/255, green: 29/255, blue: 72/255))
                }
                .font(.system(size: 9, weight: .bold))
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
