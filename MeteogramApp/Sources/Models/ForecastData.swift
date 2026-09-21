import Foundation

// MARK: - API Response Models

public struct ForecastResponse: Codable, Sendable {
    public let location: LocationMetadata
    public let model: String
    public let modelFallback: Bool?
    public let fallbackFrom: String?
    public let stats: ForecastStats
    public let astro: AstroData?

    enum CodingKeys: String, CodingKey {
        case location
        case model
        case modelFallback = "model_fallback"
        case fallbackFrom = "fallback_from"
        case stats
        case astro
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.location = try container.decode(LocationMetadata.self, forKey: .location)
        self.model = try container.decode(String.self, forKey: .model)
        self.fallbackFrom = try container.decodeIfPresent(String.self, forKey: .fallbackFrom)
        self.stats = try container.decode(ForecastStats.self, forKey: .stats)
        self.astro = try container.decodeIfPresent(AstroData.self, forKey: .astro)

        if let boolVal = try? container.decode(Bool.self, forKey: .modelFallback) {
            self.modelFallback = boolVal
        } else if let intVal = try? container.decode(Int.self, forKey: .modelFallback) {
            self.modelFallback = intVal != 0
        } else {
            self.modelFallback = false
        }
    }
}

public struct LocationMetadata: Codable, Sendable {
    public let name: String
    public let country: String?
    public let latitude: Double
    public let longitude: Double
    public let elevation: Double?
    public let timezone: String?
}

public struct ForecastStats: Codable, Sendable {
    public let times: [String]
    public let elevation: Double?
    public let utcOffsetSeconds: Int?
    public let temperature2m: EnsembleStat?
    public let precipitation: EnsembleStat?
    public let snowfall: EnsembleStat?
    public let cloudCover: EnsembleStat?
    public let cloudCoverLow: EnsembleStat?
    public let cloudCoverMid: EnsembleStat?
    public let cloudCoverHigh: EnsembleStat?
    public let windSpeed10m: EnsembleStat?
    public let windDirection10m: EnsembleStat?
    public let pressureMsl: EnsembleStat?

    enum CodingKeys: String, CodingKey {
        case times
        case elevation
        case utcOffsetSeconds = "utc_offset_seconds"
        case temperature2m = "temperature_2m"
        case precipitation
        case snowfall
        case cloudCover = "cloud_cover"
        case cloudCoverLow = "cloud_cover_low"
        case cloudCoverMid = "cloud_cover_mid"
        case cloudCoverHigh = "cloud_cover_high"
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
        case pressureMsl = "pressure_msl"
    }
}

public struct EnsembleStat: Codable, Sendable {
    public let median: [Double]
    public let q25: [Double]?
    public let q75: [Double]?
    public let min: [Double]?
    public let max: [Double]?
    public let membersCount: Int?

    enum CodingKeys: String, CodingKey {
        case median, q25, q75, min, max
        case membersCount = "members_count"
    }
}

public struct AstroData: Codable, Sendable {
    public let sunPairs: [[String]]?
    public let daily: [String: AstroDailyItem]?

    enum CodingKeys: String, CodingKey {
        case sunPairs = "sun_pairs"
        case daily
    }
}

public struct AstroDailyItem: Codable, Sendable {
    public let sunrise: String?
    public let sunset: String?
    public let moonrise: String?
    public let moonset: String?
    public let moonPhase: Double?
    public let illumPct: Int?

    enum CodingKeys: String, CodingKey {
        case sunrise, sunset, moonrise, moonset
        case moonPhase = "moon_phase"
        case illumPct = "illum_pct"
    }
}

// MARK: - Unified TimeSeriesPoint for Swift Charts

public struct TimeSeriesPoint: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let index: Int

    // Temperature (°C)
    public let tempMedian: Double
    public let tempQ25: Double?
    public let tempQ75: Double?
    public let tempMin: Double?
    public let tempMax: Double?

    // Precipitation (mm) & Snowfall (cm)
    public let precipMedian: Double
    public let precipMax: Double?
    public let snowMedian: Double

    // Cloud Cover (%)
    public let cloudTotalMedian: Double
    public let cloudTotalQ25: Double?
    public let cloudTotalQ75: Double?
    public let cloudTotalMin: Double?
    public let cloudTotalMax: Double?
    public let cloudHigh: Double?
    public let cloudMid: Double?
    public let cloudLow: Double?

    // Wind (m/s & degrees)
    public let windSpeedMedian: Double
    public let windSpeedQ25: Double?
    public let windSpeedQ75: Double?
    public let windSpeedMin: Double?
    public let windSpeedMax: Double?
    public let windDirection: Double?

    // Pressure (hPa)
    public let pressureMedian: Double
    public let pressureQ25: Double?
    public let pressureQ75: Double?
    public let pressureMin: Double?
    public let pressureMax: Double?

    // Celestial Elevation (Degrees above horizon)
    public let sunAltitude: Double?
    public let moonAltitude: Double?

    public var windSpeedKmH: Double {
        windSpeedMedian * 3.6
    }

    public var windCompassDirection: String {
        guard let dir = windDirection else { return "N/A" }
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((dir + 11.25) / 22.5) % 16
        return directions[index]
    }
}

// MARK: - Converter Helper

extension ForecastResponse {
    public func toTimeSeriesPoints() -> [TimeSeriesPoint] {
        let count = stats.times.count
        guard count > 0 else { return [] }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        var points: [TimeSeriesPoint] = []
        points.reserveCapacity(count)

        for i in 0..<count {
            let dateStr = stats.times[i]
            let date = isoFormatter.date(from: dateStr) ?? fallbackFormatter.date(from: dateStr) ?? Date()

            let tMed = stats.temperature2m?.median[safe: i] ?? 0.0
            let tQ25 = stats.temperature2m?.q25?[safe: i]
            let tQ75 = stats.temperature2m?.q75?[safe: i]
            let tMin = stats.temperature2m?.min?[safe: i]
            let tMax = stats.temperature2m?.max?[safe: i]

            let pMed = stats.precipitation?.median[safe: i] ?? 0.0
            let pMax = stats.precipitation?.max?[safe: i]
            let sMed = stats.snowfall?.median[safe: i] ?? 0.0

            let cMed = stats.cloudCover?.median[safe: i] ?? 0.0
            let cQ25 = stats.cloudCover?.q25?[safe: i]
            let cQ75 = stats.cloudCover?.q75?[safe: i]
            let cMin = stats.cloudCover?.min?[safe: i]
            let cMax = stats.cloudCover?.max?[safe: i]
            let cHigh = stats.cloudCoverHigh?.median[safe: i]
            let cMid = stats.cloudCoverMid?.median[safe: i]
            let cLow = stats.cloudCoverLow?.median[safe: i]

            let wMed = stats.windSpeed10m?.median[safe: i] ?? 0.0
            let wQ25 = stats.windSpeed10m?.q25?[safe: i]
            let wQ75 = stats.windSpeed10m?.q75?[safe: i]
            let wMin = stats.windSpeed10m?.min?[safe: i]
            let wMax = stats.windSpeed10m?.max?[safe: i]
            let wDir = stats.windDirection10m?.median[safe: i]

            let prMed = stats.pressureMsl?.median[safe: i] ?? 1013.25
            let prQ25 = stats.pressureMsl?.q25?[safe: i]
            let prQ75 = stats.pressureMsl?.q75?[safe: i]
            let prMin = stats.pressureMsl?.min?[safe: i]
            let prMax = stats.pressureMsl?.max?[safe: i]

            let sunAlt = ForecastResponse.calculateSolarAltitude(date: date, lat: location.latitude, lon: location.longitude)
            let moonAlt = ForecastResponse.calculateLunarAltitude(date: date, lat: location.latitude, lon: location.longitude)

            points.append(TimeSeriesPoint(
                date: date,
                index: i,
                tempMedian: tMed,
                tempQ25: tQ25,
                tempQ75: tQ75,
                tempMin: tMin,
                tempMax: tMax,
                precipMedian: pMed,
                precipMax: pMax,
                snowMedian: sMed,
                cloudTotalMedian: cMed,
                cloudTotalQ25: cQ25,
                cloudTotalQ75: cQ75,
                cloudTotalMin: cMin,
                cloudTotalMax: cMax,
                cloudHigh: cHigh,
                cloudMid: cMid,
                cloudLow: cLow,
                windSpeedMedian: wMed,
                windSpeedQ25: wQ25,
                windSpeedQ75: wQ75,
                windSpeedMin: wMin,
                windSpeedMax: wMax,
                windDirection: wDir,
                pressureMedian: prMed,
                pressureQ25: prQ25,
                pressureQ75: prQ75,
                pressureMin: prMin,
                pressureMax: prMax,
                sunAltitude: sunAlt,
                moonAltitude: moonAlt
            ))
        }

        return points
    }

    /// Solar altitude calculation (in degrees above horizon)
    public static func calculateSolarAltitude(date: Date, lat: Double, lon: Double) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)

        let hour = Double(cal.component(.hour, from: date))
        let minuteVal = Double(cal.component(.minute, from: date))
        let sec = Double(cal.component(.second, from: date))
        let utcH = hour + minuteVal / 60.0 + sec / 3600.0

        // Approximate solar declination
        let declination = -23.44 * cos((360.0 / 365.0 * (dayOfYear + 10)) * .pi / 180.0)

        // Equation of time approximation
        let b = 2.0 * .pi * (dayOfYear - 81) / 365.0
        let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b) // minutes

        // Solar time in hours
        let solarTime = utcH + (lon / 15.0) + (eot / 60.0)

        // Hour angle H (-180 to +180)
        let hourAngle = (solarTime - 12.0) * 15.0

        // Altitude angle calculation
        let phi = lat * .pi / 180.0
        let delta = declination * .pi / 180.0
        let h = hourAngle * .pi / 180.0

        let sinAlt = sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(h)
        let altRad = asin(max(-1.0, min(1.0, sinAlt)))
        return altRad * 180.0 / .pi
    }

    /// Lunar altitude calculation (in degrees above horizon)
    public static func calculateLunarAltitude(date: Date, lat: Double, lon: Double) -> Double {
        let tEpoch = date.timeIntervalSince1970
        let d = (tEpoch - 946728000.0) / 86400.0

        let lMoon = ((218.316 + 13.176396 * d).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let mMoon = ((134.963 + 13.064993 * d).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let fMoon = ((93.272 + 13.229350 * d).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)

        let mRad = mMoon * .pi / 180.0
        let fRad = fMoon * .pi / 180.0

        let lonMoon = lMoon + 6.289 * sin(mRad)
        let latMoon = 5.128 * sin(fRad)

        let lonRad = lonMoon * .pi / 180.0
        let latRadMoon = latMoon * .pi / 180.0

        let e = 23.439 - 0.00000036 * d
        let eRad = e * .pi / 180.0

        let sinDec = sin(latRadMoon) * cos(eRad) + cos(latRadMoon) * sin(eRad) * sin(lonRad)
        let decRad = asin(max(-1.0, min(1.0, sinDec)))

        let y = sin(lonRad) * cos(eRad) - tan(latRadMoon) * sin(eRad)
        let x = cos(lonRad)
        let raRad = atan2(y, x)

        let gmst = ((280.46061837 + 360.98564736629 * d).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let lstRad = (((gmst + lon).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)) * .pi / 180.0
        let haRad = lstRad - raRad

        let latRad = lat * .pi / 180.0
        let sinAlt = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        return asin(max(-1.0, min(1.0, sinAlt))) * 180.0 / .pi
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
