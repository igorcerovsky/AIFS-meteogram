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
