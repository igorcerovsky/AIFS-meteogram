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
                VStack(spacing: 0) {
                    // Fixed Interactive Data HUD (Pinned, App Style)
                    interactiveHUDPane
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

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

            ZStack(alignment: .topTrailing) {
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

                let tempDomain = adaptiveTempDomain(points: points)

                // Foreground: Temperature Ensemble & Grid
                Chart {
                    temperatureSpreadMarks(points: points)
                    temperatureMedianMark(points: points)
                    temperatureThresholdMarks(bottomMajor: tempDomain.bottomMajor, topMajor: tempDomain.topMajor)

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
                .chartYScale(domain: tempDomain.yMin...tempDomain.yMax)
                .chartXSelection(value: $selectedDate)
                .chartYAxis {
                    AxisMarks(position: .leading, values: Array(stride(from: tempDomain.bottomMajor, through: tempDomain.topMajor, by: 5.0)))
                }
                .chartXAxis {
                    xAxisMarks(points: points)
                }

                // Analemma Widget reflecting location latitude & active solar culmination
                let lat = viewModel.forecastData?.location.latitude ?? 48.15
                let activeDate = selectedDate ?? points.first?.date ?? Date()
                AnalemmaWidgetView(date: activeDate, latitude: lat)
                    .padding(.top, 4)
                    .padding(.trailing, 26)
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

        // Centered Sun apex icons with transparent background at local culminations
        ForEach(sunPeakPoints(points: points)) { p in
            if let alt = p.sunAltitude {
                PointMark(
                    x: .value("Time", p.date),
                    y: .value("Sun Peak", alt)
                )
                .symbol {
                    Text("☀")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 180/255, green: 83/255, blue: 9/255))
                }
            }
        }

        // Centered Moon phase icons with transparent background at local culminations
        ForEach(moonPeakPoints(points: points)) { p in
            if let alt = p.moonAltitude {
                PointMark(
                    x: .value("Time", p.date),
                    y: .value("Moon Peak", alt)
                )
                .symbol {
                    Text(moonIconForDate(p.date))
                        .font(.system(size: 10))
                }
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

    private func adaptiveTempDomain(points: [TimeSeriesPoint]) -> (bottomMajor: Double, topMajor: Double, yMin: Double, yMax: Double) {
        let mins = points.compactMap { $0.tempMin }
        let maxs = points.compactMap { $0.tempMax }
        let medians = points.map { $0.tempMedian }
        let minVal = mins.min() ?? (medians.min() ?? 5.0)
        let maxVal = maxs.max() ?? (medians.max() ?? 25.0)

        var bottomMajor = floor(minVal / 10.0) * 10.0
        var topMajor = ceil(maxVal / 10.0) * 10.0
        if topMajor <= bottomMajor {
            topMajor = bottomMajor + 10.0
        }
        let span = topMajor - bottomMajor
        let margin = max(1.8, min(3.5, span * 0.12))
        return (bottomMajor, topMajor, bottomMajor - margin, topMajor + margin)
    }

    @ChartContentBuilder
    private func temperatureThresholdMarks(bottomMajor: Double, topMajor: Double) -> some ChartContent {
        if bottomMajor <= -20.0 && -20.0 <= topMajor {
            RuleMark(y: .value("Threshold", -20.0))
                .foregroundStyle(Color.cyan.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        if bottomMajor <= -10.0 && -10.0 <= topMajor {
            RuleMark(y: .value("Threshold", -10.0))
                .foregroundStyle(Color.cyan.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        if bottomMajor <= 0.0 && 0.0 <= topMajor {
            RuleMark(y: .value("Freezing", 0.0))
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 3]))
        }
        if bottomMajor <= 10.0 && 10.0 <= topMajor {
            RuleMark(y: .value("Threshold", 10.0))
                .foregroundStyle(Color.yellow.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        if bottomMajor <= 20.0 && 20.0 <= topMajor {
            RuleMark(y: .value("Threshold", 20.0))
                .foregroundStyle(Color.orange.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        if bottomMajor <= 30.0 && 30.0 <= topMajor {
            RuleMark(y: .value("Threshold", 30.0))
                .foregroundStyle(Color.red.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        if bottomMajor <= 40.0 && 40.0 <= topMajor {
            RuleMark(y: .value("Threshold", 40.0))
                .foregroundStyle(Color.red.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
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

// MARK: - Wind Direction Azimuth Y Mapping
private func calcWindDirY(dirDeg: Double, yMaxWind: Double) -> Double {
    let d = dirDeg.truncatingRemainder(dividingBy: 360.0)
    let normD = d < 0 ? d + 360.0 : d
    let yTop = yMaxWind * 0.90
    let yBottom = yMaxWind * 0.20
    let ySpan = yTop - yBottom
    // 360° -> yTop (N), 270° -> W, 180° -> S, 90° -> E, 0° -> yBottom (N)
    return yTop - ((360.0 - normD) / 360.0) * ySpan
}

    // MARK: - Panel 4: Wind Speed & Direction [km/h]
    private func windPanelView(points: [TimeSeriesPoint]) -> some View {
        let maxSpd = points.compactMap { $0.windSpeedMax }.max() ?? 10.0
        let yMaxWind = max(40.0, ceil((maxSpd * 3.6 + 5.0) / 10.0) * 10.0)

        // 5 Wind Direction Levels from Top to Bottom: N, W, S, E, N (360° loop)
        let yTop = yMaxWind * 0.90
        let yBottom = yMaxWind * 0.20
        let ySpan = yTop - yBottom
        let yN_top = yTop
        let yW = yTop - ySpan * 0.25
        let yS = yTop - ySpan * 0.50
        let yE = yTop - ySpan * 0.75
        let yN_bot = yBottom

        let sampleStep = max(1, points.count / 14)
        let arrowPoints = points.enumerated().filter { $0.offset % sampleStep == 0 }.map(\.element)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label("10m Wind Speed [km/h] & Direction", systemImage: "wind")
                    .font(.caption.bold())
                    .foregroundColor(.brown)

                Spacer()

                windCurveThicknessLegend

                windSpeedScaleBar

                HStack(spacing: 6) {
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

                RuleMark(y: .value("DirLevel", yN_top))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 0.85, dash: [3, 3]))

                RuleMark(y: .value("DirLevel", yW))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 0.85, dash: [3, 3]))

                RuleMark(y: .value("DirLevel", yS))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 0.85, dash: [3, 3]))

                RuleMark(y: .value("DirLevel", yE))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 0.85, dash: [3, 3]))

                RuleMark(y: .value("DirLevel", yN_bot))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 0.85, dash: [3, 3]))

                // Wind direction trajectory curve colored continuously by wind direction, thickness scaled by wind speed (PoC)
                ForEach(0..<max(0, points.count - 1), id: \.self) { idx in
                    let p1 = points[idx]
                    let p2 = points[idx + 1]
                    if let rawDir1 = p1.windDirection, let rawDir2 = p2.windDirection {
                        let d1 = rawDir1.truncatingRemainder(dividingBy: 360.0)
                        let dir1 = d1 < 0 ? d1 + 360.0 : d1
                        let d2 = rawDir2.truncatingRemainder(dividingBy: 360.0)
                        let dir2 = d2 < 0 ? d2 + 360.0 : d2
                        let spd1 = p1.windSpeedMedian
                        let spd2 = p2.windSpeedMedian
                        let avgSpd = (spd1 + spd2) / 2.0
                        let segWidth = max(1.2, min(5.5, 1.2 + (avgSpd / 15.0) * 3.8))

                        if dir1 - dir2 > 180 {
                            // Crossing N clockwise (e.g. 350° -> 10°)
                            let frac = (360.0 - dir1) / ((360.0 - dir1) + dir2)
                            let timeDiff = p2.date.timeIntervalSince(p1.date)
                            let midDate = p1.date.addingTimeInterval(timeDiff * frac)
                            let spdMid = spd1 + (spd2 - spd1) * frac

                            // Sub-segment 1: (p1.date, y1) to (midDate, yN_top)
                            LineMark(
                                x: .value("Time", p1.date),
                                y: .value("WindWave", calcWindDirY(dirDeg: dir1, yMaxWind: yMaxWind)),
                                series: .value("WindWaveSeg", "\(idx)_a")
                            )
                            .foregroundStyle(windColor(speedMs: spd1))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))

                            LineMark(
                                x: .value("Time", midDate),
                                y: .value("WindWave", yN_top),
                                series: .value("WindWaveSeg", "\(idx)_a")
                            )
                            .foregroundStyle(windColor(speedMs: spdMid))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))

                            // Sub-segment 2: (midDate, yN_bot) to (p2.date, y2)
                            LineMark(
                                x: .value("Time", midDate),
                                y: .value("WindWave", yN_bot),
                                series: .value("WindWaveSeg", "\(idx)_b")
                            )
                            .foregroundStyle(windColor(speedMs: spdMid))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))

                            LineMark(
                                x: .value("Time", p2.date),
                                y: .value("WindWave", calcWindDirY(dirDeg: dir2, yMaxWind: yMaxWind)),
                                series: .value("WindWaveSeg", "\(idx)_b")
                            )
                            .foregroundStyle(windColor(speedMs: spd2))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))
                        } else if dir2 - dir1 > 180 {
                            // Crossing N counter-clockwise (e.g. 10° -> 350°)
                            let frac = dir1 / (dir1 + (360.0 - dir2))
                            let timeDiff = p2.date.timeIntervalSince(p1.date)
                            let midDate = p1.date.addingTimeInterval(timeDiff * frac)
                            let spdMid = spd1 + (spd2 - spd1) * frac

                            // Sub-segment 1: (p1.date, y1) to (midDate, yN_bot)
                            LineMark(
                                x: .value("Time", p1.date),
                                y: .value("WindWave", calcWindDirY(dirDeg: dir1, yMaxWind: yMaxWind)),
                                series: .value("WindWaveSeg", "\(idx)_a")
                            )
                            .foregroundStyle(windColor(speedMs: spd1))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))

                            LineMark(
                                x: .value("Time", midDate),
                                y: .value("WindWave", yN_bot),
                                series: .value("WindWaveSeg", "\(idx)_a")
                            )
                            .foregroundStyle(windColor(speedMs: spdMid))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))

                            // Sub-segment 2: (midDate, yN_top) to (p2.date, y2)
                            LineMark(
                                x: .value("Time", midDate),
                                y: .value("WindWave", yN_top),
                                series: .value("WindWaveSeg", "\(idx)_b")
                            )
                            .foregroundStyle(windColor(speedMs: spdMid))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))

                            LineMark(
                                x: .value("Time", p2.date),
                                y: .value("WindWave", calcWindDirY(dirDeg: dir2, yMaxWind: yMaxWind)),
                                series: .value("WindWaveSeg", "\(idx)_b")
                            )
                            .foregroundStyle(windColor(speedMs: spd2))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))
                        } else {
                            let y1 = calcWindDirY(dirDeg: dir1, yMaxWind: yMaxWind)
                            let y2 = calcWindDirY(dirDeg: dir2, yMaxWind: yMaxWind)
                            LineMark(
                                x: .value("Time", p1.date),
                                y: .value("WindWave", y1),
                                series: .value("WindWaveSeg", "\(idx)")
                            )
                            .foregroundStyle(windColor(speedMs: spd1))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))

                            LineMark(
                                x: .value("Time", p2.date),
                                y: .value("WindWave", y2),
                                series: .value("WindWaveSeg", "\(idx)")
                            )
                            .foregroundStyle(windColor(speedMs: spd2))
                            .lineStyle(StrokeStyle(lineWidth: segWidth, lineCap: .round))
                        }
                    }
                }

                // Sampled Wind Arrows distributed by 5-direction azimuth (N, W, S, E, N)
                ForEach(arrowPoints) { p in
                    if let dir = p.windDirection {
                        let arrowY = calcWindDirY(dirDeg: dir, yMaxWind: yMaxWind)
                        PointMark(
                            x: .value("Time", p.date),
                            y: .value("ArrowY", arrowY)
                        )
                        .symbol {
                            WindArrowShape(dirDeg: dir, speedMs: p.windSpeedMedian)
                        }
                    }
                }

                if let selDate = selectedDate {
                    RuleMark(x: .value("Selected", selDate))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: 0...yMaxWind)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 10)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))")
                                .font(.system(size: 8.5))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                AxisMarks(position: .trailing, values: [yN_bot, yE, yS, yW, yN_top]) { val in
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            let label: String = {
                                if abs(v - yN_top) < 1.0 || abs(v - yN_bot) < 1.0 { return "N" }
                                if abs(v - yW) < 1.0 { return "W" }
                                if abs(v - yS) < 1.0 { return "S" }
                                if abs(v - yE) < 1.0 { return "E" }
                                return ""
                            }()
                            if !label.isEmpty {
                                Text(label)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                }
            }
            .frame(height: 115)
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

                HStack(spacing: 8) {
                    legendItem(title: "Median", color: .purple, isLine: true)
                    legendItem(title: "Spread", color: .purple.opacity(0.25))
                    if showStdLine {
                        legendItem(title: "1013 hPa", color: .gray, isLine: true)
                    }
                    legendItem(title: "☀ Sun", color: Color(red: 244/255, green: 162/255, blue: 97/255), isLine: true)
                    legendItem(title: "🌙 Moon", color: Color(red: 0/255, green: 180/255, blue: 216/255), isLine: true)
                }
                .font(.caption2)
            }

            ZStack(alignment: .topTrailing) {
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

                // Foreground: Pressure & Grid
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

                        if let selPoint = selectedPoint {
                            PointMark(
                                x: .value("Selected", selPoint.date),
                                y: .value("Pressure", selPoint.pressureMedian)
                            )
                            .foregroundStyle(Color.purple)
                            .symbolSize(40)
                        }
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
            }
            .frame(height: 110)
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

    // MARK: - Interactive Data HUD (Fixed Pinned App Style)
    private var interactiveHUDPane: some View {
        Group {
            if let selPoint = selectedPoint {
                floatingHUDView(point: selPoint)
            } else if let firstPoint = viewModel.timeSeries.first {
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                    Text("Scrub chart to view ensemble spread & solar altitude")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Latest: \(String(format: "%.1f°C", firstPoint.tempMedian)) • \(String(format: "%.0f km/h", firstPoint.windSpeedKmH))")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.ultraThickMaterial)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Floating HUD View
    private func floatingHUDView(point: TimeSeriesPoint) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f km/h", point.windSpeedKmH))
                            .font(.subheadline.bold())
                            .foregroundColor(.brown)
                        Text(String(format: "(%.1f m/s)", point.windSpeedMedian))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        if let dir = point.windDirection {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(windColor(speedMs: point.windSpeedMedian))
                                .rotationEffect(.degrees(dir))
                        }
                        Text(point.windCompassDirection)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
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
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThickMaterial)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Wind Speed Color Scale & Arrows
    private var windSpeedScaleBar: some View {
        HStack(spacing: 2) {
            scaleBadge(label: "<2", color: Color(red: 148/255, green: 163/255, blue: 184/255))
            scaleBadge(label: "2–5", color: Color(red: 16/255, green: 185/255, blue: 129/255))
            scaleBadge(label: "5–10", color: Color(red: 37/255, green: 99/255, blue: 235/255))
            scaleBadge(label: "10–15", color: Color(red: 245/255, green: 158/255, blue: 11/255))
            scaleBadge(label: ">15 m/s", color: Color(red: 239/255, green: 68/255, blue: 68/255))
        }
    }

    private var windCurveThicknessLegend: some View {
        HStack(spacing: 3) {
            Text("<2")
                .font(.system(size: 7))
                .foregroundColor(.secondary)

            TaperedWedgeShape()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 148/255, green: 163/255, blue: 184/255),
                                 Color(red: 16/255, green: 185/255, blue: 129/255),
                                 Color(red: 37/255, green: 99/255, blue: 235/255),
                                 Color(red: 245/255, green: 158/255, blue: 11/255),
                                 Color(red: 239/255, green: 68/255, blue: 68/255)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 26, height: 7)

            Text("≥15")
                .font(.system(size: 7))
                .foregroundColor(.secondary)
        }
    }

    private func scaleBadge(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(2)
    }

// MARK: - Tapered Wedge Shape
public struct TaperedWedgeShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let r1: CGFloat = 0.8
        let r2: CGFloat = rect.height / 2.0
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY - r1))
        path.addLine(to: CGPoint(x: rect.maxX - r2, y: midY - r2))
        path.addArc(center: CGPoint(x: rect.maxX - r2, y: midY), radius: r2, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: midY + r1))
        path.addArc(center: CGPoint(x: rect.minX, y: midY), radius: r1, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
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

    private func sunPeakPoints(points: [TimeSeriesPoint]) -> [TimeSeriesPoint] {
        guard points.count >= 3 else { return [] }
        var peaks: [TimeSeriesPoint] = []
        for i in 1..<(points.count - 1) {
            let prev = points[i - 1].sunAltitude ?? -90
            let cur = points[i].sunAltitude ?? -90
            let next = points[i + 1].sunAltitude ?? -90
            if cur > 5.0 && cur >= prev && cur >= next {
                let pPrev2 = i >= 2 ? (points[i - 2].sunAltitude ?? -90) : -90
                let pNext2 = i + 2 < points.count ? (points[i + 2].sunAltitude ?? -90) : -90
                if cur >= pPrev2 && cur >= pNext2 {
                    peaks.append(points[i])
                }
            }
        }
        return peaks
    }

    private func moonPeakPoints(points: [TimeSeriesPoint]) -> [TimeSeriesPoint] {
        guard points.count >= 3 else { return [] }
        var peaks: [TimeSeriesPoint] = []
        for i in 1..<(points.count - 1) {
            let prev = points[i - 1].moonAltitude ?? -90
            let cur = points[i].moonAltitude ?? -90
            let next = points[i + 1].moonAltitude ?? -90
            if cur > 5.0 && cur >= prev && cur >= next {
                let pPrev2 = i >= 2 ? (points[i - 2].moonAltitude ?? -90) : -90
                let pNext2 = i + 2 < points.count ? (points[i + 2].moonAltitude ?? -90) : -90
                if cur >= pPrev2 && cur >= pNext2 {
                    peaks.append(points[i])
                }
            }
        }
        return peaks
    }

    private func moonIconForDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dayKey = formatter.string(from: date)
        if let item = viewModel.forecastData?.astro?.daily?[dayKey], let phase = item.moonPhase {
            return moonIcon(for: phase)
        }
        let daysSinceRef = date.timeIntervalSince1970 / 86400.0 - 19733.0
        let phase = (daysSinceRef / 29.53058867).truncatingRemainder(dividingBy: 1.0)
        let normPhase = phase < 0 ? phase + 1.0 : phase
        return moonIcon(for: normPhase)
    }
}

// MARK: - Wind Speed Color
private func windColor(speedMs: Double) -> Color {
    let stops: [(s: Double, r: Double, g: Double, b: Double)] = [
        (0.0, 148.0, 163.0, 184.0), // 0 m/s: Slate
        (2.0, 148.0, 163.0, 184.0), // 2 m/s: Slate
        (4.0, 16.0, 185.0, 129.0),  // 4 m/s: Emerald
        (7.5, 37.0, 99.0, 235.0),   // 7.5 m/s: Royal Blue
        (12.0, 245.0, 158.0, 11.0), // 12 m/s: Amber
        (16.0, 239.0, 68.0, 68.0),  // 16+ m/s: Coral Red
        (25.0, 220.0, 38.0, 38.0)   // 25+ m/s: Crimson
    ]
    if speedMs <= stops[0].s {
        return Color(red: stops[0].r / 255.0, green: stops[0].g / 255.0, blue: stops[0].b / 255.0)
    }
    var i = 0
    while i < stops.count - 1 && speedMs > stops[i + 1].s {
        i += 1
    }
    if i >= stops.count - 1 {
        let last = stops[stops.count - 1]
        return Color(red: last.r / 255.0, green: last.g / 255.0, blue: last.b / 255.0)
    }
    let s1 = stops[i]
    let s2 = stops[i + 1]
    let t = (speedMs - s1.s) / (s2.s - s1.s)
    let r = (s1.r + (s2.r - s1.r) * t) / 255.0
    let g = (s1.g + (s2.g - s1.g) * t) / 255.0
    let b = (s1.b + (s2.b - s1.b) * t) / 255.0
    return Color(red: r, green: g, blue: b)
}

// MARK: - Wind Direction Color
private func windDirectionColor(dirDeg: Double) -> Color {
    let d = dirDeg.truncatingRemainder(dividingBy: 360.0)
    let normD = d < 0 ? d + 360.0 : d
    let stops: [(deg: Double, r: Double, g: Double, b: Double)] = [
        (0.0, 37.0, 99.0, 235.0),    // N: Royal Blue
        (45.0, 6.0, 182.0, 212.0),   // NE: Cyan
        (90.0, 16.0, 185.0, 129.0),  // E: Emerald
        (135.0, 245.0, 158.0, 11.0), // SE: Amber
        (180.0, 239.0, 68.0, 68.0),  // S: Coral Red
        (225.0, 217.0, 70.0, 239.0), // SW: Fuchsia
        (270.0, 139.0, 92.0, 246.0), // W: Purple
        (315.0, 99.0, 102.0, 241.0), // NW: Indigo
        (360.0, 37.0, 99.0, 235.0)   // N: Royal Blue
    ]
    var i = 0
    while i < stops.count - 1 && normD > stops[i + 1].deg {
        i += 1
    }
    let s1 = stops[i]
    let s2 = stops[i + 1]
    let t = (normD - s1.deg) / (s2.deg - s1.deg)
    let r = (s1.r + (s2.r - s1.r) * t) / 255.0
    let g = (s1.g + (s2.g - s1.g) * t) / 255.0
    let b = (s1.b + (s2.b - s1.b) * t) / 255.0
    return Color(red: r, green: g, blue: b)
}

// MARK: - Triangle Shape
public struct Triangle: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Wind Arrow Shape
public struct WindArrowShape: View {
    public let dirDeg: Double
    public let speedMs: Double

    public init(dirDeg: Double, speedMs: Double) {
        self.dirDeg = dirDeg
        self.speedMs = speedMs
    }

    public var body: some View {
        let col = windColor(speedMs: speedMs)
        let arrowLen = max(8, min(24, 7 + CGFloat(speedMs) * 1.2))
        let headSize = max(3, min(6, arrowLen * 0.25))
        let shaftW: CGFloat = speedMs >= 15 ? 2.0 : (speedMs >= 10 ? 1.6 : 1.2)

        ZStack {
            // White halo outline so arrow stands out cleanly over the colored curve
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: shaftW + 2.2, height: arrowLen - headSize)

                Triangle()
                    .fill(Color.white)
                    .frame(width: headSize * 2.2, height: headSize + 1.2)
            }
            .rotationEffect(.degrees(dirDeg))

            // Arrow foreground
            VStack(spacing: 0) {
                // Shaft
                Rectangle()
                    .fill(col)
                    .frame(width: shaftW, height: arrowLen - headSize)

                // Arrow head pointing towards bottom (positive Y)
                Triangle()
                    .fill(col)
                    .frame(width: headSize * 1.8, height: headSize)
            }
            .rotationEffect(.degrees(dirDeg))
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Location-Reflecting Analemma Widget View
public struct AnalemmaWidgetView: View {
    public let date: Date
    public let latitude: Double

    public init(date: Date, latitude: Double = 48.15) {
        self.date = date
        self.latitude = latitude
    }

    private var annualCurve: [AnalemmaPoint] {
        getAnnualAnalemmaCurve(year: Calendar.current.component(.year, from: date))
    }

    private func calcNoonAlt(decDeg: Double) -> Double {
        if latitude >= 0 {
            return 90.0 - latitude + decDeg
        } else {
            return 90.0 + latitude - decDeg
        }
    }

    public var body: some View {
        let activeSun = calculateSolarDeclinationAndEoT(date: date)
        let activeAlt = calcNoonAlt(decDeg: activeSun.dec)

        let eqAlt = 90.0 - abs(latitude)
        let maxSolstice = max(calcNoonAlt(decDeg: 23.44), calcNoonAlt(decDeg: -23.44))
        let minSolstice = min(calcNoonAlt(decDeg: 23.44), calcNoonAlt(decDeg: -23.44))

        let altMin = max(0.0, minSolstice - 4.0)
        let altMax = min(90.0, maxSolstice + 4.0)

        let isNorth = latitude >= 0
        let topLabel = isNorth ? "Jun \(Int(round(calcNoonAlt(decDeg: 23.44))))°" : "Dec \(Int(round(calcNoonAlt(decDeg: -23.44))))°"
        let btmLabel = isNorth ? "Dec \(Int(round(calcNoonAlt(decDeg: -23.44))))°" : "Jun \(Int(round(calcNoonAlt(decDeg: 23.44))))°"

        let latTitle = String(format: "Analemma (%.1f°%@)", abs(latitude), latitude >= 0 ? "N" : "S")

        VStack(spacing: 2) {
            Text(latTitle)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(Color.orange.opacity(0.95))

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                let toX: (Double) -> CGFloat = { eot in
                    let norm = (eot + 18.0) / 36.0
                    return CGFloat(norm) * w
                }

                let toY: (Double) -> CGFloat = { alt in
                    let norm = (alt - altMin) / max(1.0, altMax - altMin)
                    return CGFloat(1.0 - norm) * h
                }

                ZStack {
                    // Equinox reference line
                    let eqY = toY(eqAlt)
                    Path { p in
                        p.move(to: CGPoint(x: 2, y: eqY))
                        p.addLine(to: CGPoint(x: w - 2, y: eqY))
                    }
                    .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))

                    // Solstice tick labels
                    Text(topLabel)
                        .font(.system(size: 6, weight: .semibold))
                        .foregroundColor(.secondary)
                        .position(x: 16, y: 5)

                    Text(btmLabel)
                        .font(.system(size: 6, weight: .semibold))
                        .foregroundColor(.secondary)
                        .position(x: 16, y: h - 5)

                    // Equinox label
                    Text("Eq \(Int(round(eqAlt)))°")
                        .font(.system(size: 5.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.85))
                        .position(x: w - 12, y: eqY - 4)

                    // Analemma Figure-8 Path
                    Path { path in
                        let curve = annualCurve
                        guard let first = curve.first else { return }
                        let startAlt = calcNoonAlt(decDeg: first.dec)
                        path.move(to: CGPoint(x: toX(first.eot), y: toY(startAlt)))
                        for pt in curve.dropFirst() {
                            let alt = calcNoonAlt(decDeg: pt.dec)
                            path.addLine(to: CGPoint(x: toX(pt.eot), y: toY(alt)))
                        }
                        path.closeSubpath()
                    }
                    .stroke(
                        Color(red: 245/255, green: 158/255, blue: 11/255),
                        style: StrokeStyle(lineWidth: 1.4, lineJoin: .round)
                    )

                    // Current Sun Position on Analemma
                    let sunX = toX(activeSun.eot)
                    let sunY = toY(activeAlt)

                    Circle()
                        .fill(Color(red: 239/255, green: 68/255, blue: 68/255))
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .position(x: sunX, y: sunY)
                }
            }
            .frame(height: 62)

            // Current Noon Alt & EoT info
            let signStr = activeSun.eot >= 0 ? "+" : ""
            Text(String(format: "Alt: %.1f° (%@%dm)", activeAlt, signStr, Int(round(activeSun.eot))))
                .font(.system(size: 6.5, weight: .semibold))
                .foregroundColor(Color(red: 245/255, green: 158/255, blue: 11/255))
        }
        .padding(4)
        .frame(width: 88, height: 92)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.3), lineWidth: 0.8))
    }
}
