import Foundation

#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#endif

public struct MeteogramFetchResult {
    public let imageData: Data
    public let actualModel: String
    public let fallbackUsed: Bool
    public let fallbackFrom: String
    public let latencyMs: Double
    public let isStaticFallback: Bool

    public init(
        imageData: Data,
        actualModel: String,
        fallbackUsed: Bool,
        fallbackFrom: String,
        latencyMs: Double,
        isStaticFallback: Bool = false
    ) {
        self.imageData = imageData
        self.actualModel = actualModel
        self.fallbackUsed = fallbackUsed
        self.fallbackFrom = fallbackFrom
        self.latencyMs = latencyMs
        self.isStaticFallback = isStaticFallback
    }
}

public struct ForecastFetchResult {
    public let forecast: ForecastResponse
    public let timeSeries: [TimeSeriesPoint]
    public let actualModel: String
    public let fallbackUsed: Bool
    public let fallbackFrom: String
    public let latencyMs: Double

    public init(
        forecast: ForecastResponse,
        timeSeries: [TimeSeriesPoint],
        actualModel: String,
        fallbackUsed: Bool,
        fallbackFrom: String,
        latencyMs: Double
    ) {
        self.forecast = forecast
        self.timeSeries = timeSeries
        self.actualModel = actualModel
        self.fallbackUsed = fallbackUsed
        self.fallbackFrom = fallbackFrom
        self.latencyMs = latencyMs
    }
}

public enum MeteogramServiceError: LocalizedError {
    case invalidUrl
    case serverError(statusCode: Int, message: String)
    case decodingError
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUrl:
            return "Invalid server URL or request parameters."
        case .serverError(let code, let msg):
            return "Server returned HTTP \(code): \(msg)"
        case .decodingError:
            return "Failed to decode the received image."
        case .networkError(let msg):
            return "Network connection failed: \(msg)"
        }
    }
}

public class MeteogramService {
    public static let shared = MeteogramService()
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches the meteogram image from the primary server, with automatic GitHub Pages fallback
    public func fetchMeteogram(
        serverBaseUrl: String,
        location: String,
        horizon: ForecastHorizon,
        language: ForecastLanguage,
        timeZone: ForecastTimeZone
    ) async throws -> MeteogramFetchResult {
        // 1. Try configured server (e.g. localhost or custom cloud URL)
        do {
            return try await fetchFromServer(
                serverBaseUrl: serverBaseUrl,
                location: location,
                horizon: horizon,
                language: language,
                timeZone: timeZone
            )
        } catch {
            // 2. If primary server is unavailable, attempt GitHub Pages CDN fallback for preset locations
            if let slug = MeteogramConfig.staticSlug(for: location) {
                var effectiveModel = horizon.modelParam
                var fallbackUsed = false
                var fallbackFrom = ""
                if horizon == .iconD22 && MeteogramConfig.isOutsideIconD2Domain(location) {
                    effectiveModel = "icon_eu"
                    fallbackUsed = true
                    fallbackFrom = "icon_d2"
                }

                let staticUrlString = "\(MeteogramConfig.githubPagesBaseUrl)/images/\(slug)_\(effectiveModel)_\(language.rawValue).png"
                if let staticUrl = URL(string: staticUrlString) {
                    var request = URLRequest(url: staticUrl)
                    request.timeoutInterval = 15.0
                    let startTime = CFAbsoluteTimeGetCurrent()
                    if let (data, response) = try? await session.data(for: request),
                       let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode == 200 {
                        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                        return MeteogramFetchResult(
                            imageData: data,
                            actualModel: effectiveModel,
                            fallbackUsed: fallbackUsed,
                            fallbackFrom: fallbackFrom,
                            latencyMs: elapsedMs,
                            isStaticFallback: true
                        )
                    }
                }
            }

            // Fallback unavailable or failed; re-throw primary error
            throw error
        }
    }

    private func fetchFromServer(
        serverBaseUrl: String,
        location: String,
        horizon: ForecastHorizon,
        language: ForecastLanguage,
        timeZone: ForecastTimeZone
    ) async throws -> MeteogramFetchResult {
        var base = serverBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "http://" + base
        }
        if base.hasSuffix("/") {
            base.removeLast()
        }

        guard var components = URLComponents(string: "\(base)/api/image") else {
            throw MeteogramServiceError.invalidUrl
        }

        components.queryItems = [
            URLQueryItem(name: "location", value: location),
            URLQueryItem(name: "days", value: String(horizon.daysParam)),
            URLQueryItem(name: "model", value: horizon.modelParam),
            URLQueryItem(name: "lang", value: language.rawValue),
            URLQueryItem(name: "tz", value: timeZone.rawValue),
            URLQueryItem(name: "_t", value: String(Int64(Date().timeIntervalSince1970 * 1000)))
        ]

        guard let url = components.url else {
            throw MeteogramServiceError.invalidUrl
        }

        var request = URLRequest(url: url)
        // If connecting to localhost / local network, fail fast to allow smooth fallback
        request.timeoutInterval = (base.contains("localhost") || base.contains("127.0.0.1") || base.contains(".local")) ? 6.0 : 35.0

        let startTime = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await session.data(for: request)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeteogramServiceError.decodingError
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw MeteogramServiceError.serverError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        let actualModel = httpResponse.value(forHTTPHeaderField: "X-Actual-Model") ?? horizon.modelParam
        let fallbackUsed = httpResponse.value(forHTTPHeaderField: "X-Model-Fallback")?.lowercased() == "true"
        let fallbackFrom = httpResponse.value(forHTTPHeaderField: "X-Fallback-From") ?? "icon_d2"

        ForecastCacheManager.shared.saveImage(
            data: data,
            actualModel: actualModel,
            fallbackUsed: fallbackUsed,
            fallbackFrom: fallbackFrom,
            location: location,
            horizon: horizon.rawValue,
            lang: language.rawValue
        )

        return MeteogramFetchResult(
            imageData: data,
            actualModel: actualModel,
            fallbackUsed: fallbackUsed,
            fallbackFrom: fallbackFrom,
            latencyMs: elapsedMs,
            isStaticFallback: false
        )
    }

    /// Fetches structured forecast JSON data (/api/forecast) for native Swift Charts
    public func fetchForecastData(
        serverBaseUrl: String,
        location: String,
        horizon: ForecastHorizon,
        language: ForecastLanguage,
        timeZone: ForecastTimeZone
    ) async throws -> ForecastFetchResult {
        var base = serverBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "http://" + base
        }
        if base.hasSuffix("/") {
            base.removeLast()
        }

        guard var components = URLComponents(string: "\(base)/api/forecast") else {
            throw MeteogramServiceError.invalidUrl
        }

        components.queryItems = [
            URLQueryItem(name: "location", value: location),
            URLQueryItem(name: "days", value: String(horizon.daysParam)),
            URLQueryItem(name: "model", value: horizon.modelParam),
            URLQueryItem(name: "lang", value: language.rawValue),
            URLQueryItem(name: "tz", value: timeZone.rawValue),
            URLQueryItem(name: "_t", value: String(Int64(Date().timeIntervalSince1970 * 1000)))
        ]

        guard let url = components.url else {
            throw MeteogramServiceError.invalidUrl
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = (base.contains("localhost") || base.contains("127.0.0.1") || base.contains(".local")) ? 8.0 : 35.0

        let startTime = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await session.data(for: request)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeteogramServiceError.decodingError
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw MeteogramServiceError.serverError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        let decoder = JSONDecoder()
        let forecast = try decoder.decode(ForecastResponse.self, from: data)
        let timeSeries = forecast.toTimeSeriesPoints()

        let actualModel = forecast.model
        let fallbackUsed = forecast.modelFallback ?? false
        let fallbackFrom = forecast.fallbackFrom ?? "icon_d2"

        // Cache structured forecast response for offline resilience
        ForecastCacheManager.shared.saveForecast(
            forecast,
            location: location,
            horizon: horizon.rawValue,
            lang: language.rawValue
        )

        return ForecastFetchResult(
            forecast: forecast,
            timeSeries: timeSeries,
            actualModel: actualModel,
            fallbackUsed: fallbackUsed,
            fallbackFrom: fallbackFrom,
            latencyMs: elapsedMs
        )
    }

    /// Tests connectivity to the server and measures latency
    public func testConnection(serverBaseUrl: String) async -> (isReachable: Bool, latencyMs: Double, message: String) {
        var base = serverBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "http://" + base
        }
        if base.hasSuffix("/") {
            base.removeLast()
        }

        guard let url = URL(string: "\(base)/api/check_location?location=Bratislava-Koliba") else {
            return (false, 0, "Invalid URL format")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await session.data(for: request)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return (true, elapsedMs, "Connected successfully (\(Int(elapsedMs)) ms)")
            } else {
                let text = String(data: data, encoding: .utf8) ?? ""
                return (false, elapsedMs, "Server returned error: \(text.prefix(60))")
            }
        } catch {
            return (false, 0, error.localizedDescription)
        }
    }
}

// MARK: - Offline Forecast Cache Manager

public struct CachedForecastRecord: Codable, Sendable {
    public let forecast: ForecastResponse
    public let cachedAt: Date
    public let locationKey: String
    public let horizonKey: String
    public let languageKey: String
}

public final class ForecastCacheManager: @unchecked Sendable {
    public static let shared = ForecastCacheManager()

    private let fileManager = FileManager.default
    private let cacheDir: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // In-memory hot cache
    private var memoryForecasts: [String: (forecast: ForecastResponse, date: Date)] = [:]
    private var memoryImages: [String: (data: Data, actualModel: String, fallbackUsed: Bool, fallbackFrom: String, date: Date)] = [:]
    private let lock = NSLock()

    public init() {
        let baseDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.cacheDir = baseDir.appendingPathComponent("MeteogramForecastCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    public func cacheKey(location: String, horizon: String, lang: String = "en") -> String {
        let cleanLoc = location.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "\(cleanLoc)_\(horizon)_\(lang)"
    }

    // MARK: - Forecast JSON Caching

    public func saveForecast(_ forecast: ForecastResponse, location: String, horizon: String, lang: String = "en") {
        let key = cacheKey(location: location, horizon: horizon, lang: lang)
        let now = Date()

        lock.lock()
        memoryForecasts[key] = (forecast, now)
        lock.unlock()

        let record = CachedForecastRecord(
            forecast: forecast,
            cachedAt: now,
            locationKey: location,
            horizonKey: horizon,
            languageKey: lang
        )
        let fileURL = cacheDir.appendingPathComponent("fc_\(key).json")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if let data = try? self.encoder.encode(record) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    public func loadForecast(location: String, horizon: String, lang: String = "en") -> (forecast: ForecastResponse, cachedAt: Date)? {
        let key = cacheKey(location: location, horizon: horizon, lang: lang)

        lock.lock()
        if let mem = memoryForecasts[key] {
            lock.unlock()
            return (mem.forecast, mem.date)
        }
        lock.unlock()

        let fileURL = cacheDir.appendingPathComponent("fc_\(key).json")
        guard let data = try? Data(contentsOf: fileURL),
              let record = try? decoder.decode(CachedForecastRecord.self, from: data) else {
            return nil
        }

        lock.lock()
        memoryForecasts[key] = (record.forecast, record.cachedAt)
        lock.unlock()

        return (record.forecast, record.cachedAt)
    }

    public func hasCachedForecast(location: String, horizon: String, lang: String = "en") -> Bool {
        let key = cacheKey(location: location, horizon: horizon, lang: lang)
        lock.lock()
        if memoryForecasts[key] != nil {
            lock.unlock()
            return true
        }
        lock.unlock()
        let fileURL = cacheDir.appendingPathComponent("fc_\(key).json")
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Searches for ANY cached forecast for a given location across all known horizons
    public func findAnyCachedForecast(for location: String, preferredOrder: [ForecastHorizon] = ForecastHorizon.displayOrder) -> (horizon: ForecastHorizon, forecast: ForecastResponse, cachedAt: Date)? {
        for h in preferredOrder {
            if let cached = loadForecast(location: location, horizon: h.rawValue) {
                return (h, cached.forecast, cached.cachedAt)
            }
        }
        return nil
    }

    // MARK: - Raster Image Caching

    public func saveImage(data: Data, actualModel: String, fallbackUsed: Bool, fallbackFrom: String, location: String, horizon: String, lang: String = "en") {
        let key = cacheKey(location: location, horizon: horizon, lang: lang)
        let now = Date()

        lock.lock()
        memoryImages[key] = (data, actualModel, fallbackUsed, fallbackFrom, now)
        lock.unlock()

        let imgURL = cacheDir.appendingPathComponent("img_\(key).png")
        let metaURL = cacheDir.appendingPathComponent("meta_\(key).json")

        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: imgURL, options: .atomic)
            let meta: [String: Any] = [
                "time": now.timeIntervalSince1970,
                "model": actualModel,
                "fallbackUsed": fallbackUsed,
                "fallbackFrom": fallbackFrom
            ]
            if let metaData = try? JSONSerialization.data(withJSONObject: meta) {
                try? metaData.write(to: metaURL, options: .atomic)
            }
        }
    }

    public func loadImage(location: String, horizon: String, lang: String = "en") -> (data: Data, actualModel: String, fallbackUsed: Bool, fallbackFrom: String, cachedAt: Date)? {
        let key = cacheKey(location: location, horizon: horizon, lang: lang)

        lock.lock()
        if let mem = memoryImages[key] {
            lock.unlock()
            return (mem.data, mem.actualModel, mem.fallbackUsed, mem.fallbackFrom, mem.date)
        }
        lock.unlock()

        let imgURL = cacheDir.appendingPathComponent("img_\(key).png")
        let metaURL = cacheDir.appendingPathComponent("meta_\(key).json")

        guard let data = try? Data(contentsOf: imgURL) else { return nil }
        var date = Date()
        var actualModel = horizon
        var fallbackUsed = false
        var fallbackFrom = ""

        if let metaData = try? Data(contentsOf: metaURL),
           let obj = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] {
            if let t = obj["time"] as? Double { date = Date(timeIntervalSince1970: t) }
            if let m = obj["model"] as? String { actualModel = m }
            if let fb = obj["fallbackUsed"] as? Bool { fallbackUsed = fb }
            if let ff = obj["fallbackFrom"] as? String { fallbackFrom = ff }
        }

        lock.lock()
        memoryImages[key] = (data, actualModel, fallbackUsed, fallbackFrom, date)
        lock.unlock()

        return (data, actualModel, fallbackUsed, fallbackFrom, date)
    }
}
