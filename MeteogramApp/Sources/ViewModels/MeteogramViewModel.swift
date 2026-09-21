import Foundation
import SwiftUI
import Combine

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
public class MeteogramViewModel: ObservableObject {
    @Published public var location: String {
        didSet {
            UserDefaults.standard.set(location, forKey: "lastLocation")
            checkLocationDomainAndWarn()
        }
    }

    @Published public var horizon: ForecastHorizon {
        didSet {
            UserDefaults.standard.set(horizon.rawValue, forKey: "lastHorizon")
            checkLocationDomainAndWarn()
        }
    }

    @Published public var language: ForecastLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "lastLanguage")
        }
    }

    @Published public var timeZone: ForecastTimeZone {
        didSet {
            UserDefaults.standard.set(timeZone.rawValue, forKey: "lastTimeZone")
        }
    }

    @Published public var serverUrl: String {
        didSet {
            UserDefaults.standard.set(serverUrl, forKey: "serverUrl")
        }
    }

    // Native Swift Charts State
    @Published public var forecastData: ForecastResponse?
    @Published public var timeSeries: [TimeSeriesPoint] = []
    @Published public var selectedDate: Date?
    @Published public var displayMode: MeteogramDisplayMode = .nativeCharts

    // State
    @Published public var currentImage: PlatformImage?
    @Published public var rawImageData: Data?
    @Published public var isLoading: Bool = false
    @Published public var loadingStatusText: String = ""
    @Published public var errorMessage: String?
    @Published public var latencyMs: Double = 0
    @Published public var lastUpdated: Date?
    @Published public var isUsingStaticFallback: Bool = false

    // Fallback alert banner
    @Published public var showFallbackAlert: Bool = false
    @Published public var fallbackFromModel: String = ""
    @Published public var fallbackToModel: String = ""

    // Cache & Offline State
    @Published public var isOfflineCached: Bool = false
    @Published public var offlineCacheNotice: String?

    // User favorites
    @Published public var favoriteLocations: [String] {
        didSet {
            UserDefaults.standard.set(favoriteLocations, forKey: "favoriteLocations")
        }
    }

    private let service: MeteogramService
    private var currentTask: Task<Void, Never>?

    public init(service: MeteogramService = .shared) {
        self.service = service

        // Restore saved settings or defaults
        self.location = UserDefaults.standard.string(forKey: "lastLocation") ?? "Bratislava-Koliba"
        let savedHorizon = UserDefaults.standard.string(forKey: "lastHorizon") ?? ForecastHorizon.aifs15.rawValue
        self.horizon = ForecastHorizon(rawValue: savedHorizon) ?? .aifs15
        let savedLang = UserDefaults.standard.string(forKey: "lastLanguage") ?? ForecastLanguage.en.rawValue
        self.language = ForecastLanguage(rawValue: savedLang) ?? .en
        let savedTz = UserDefaults.standard.string(forKey: "lastTimeZone") ?? ForecastTimeZone.local.rawValue
        self.timeZone = ForecastTimeZone(rawValue: savedTz) ?? .local

        #if os(macOS)
        let defaultUrl = MeteogramConfig.defaultServerUrl
        #else
        // On iOS device/simulator default to local Mac address or localhost
        let defaultUrl = MeteogramConfig.defaultBonjourUrl
        #endif
        self.serverUrl = UserDefaults.standard.string(forKey: "serverUrl") ?? defaultUrl

        self.favoriteLocations = UserDefaults.standard.stringArray(forKey: "favoriteLocations") ?? [
            "Bratislava-Koliba", "Jasna", "Liptovsky Mikulas", "Poprad"
        ]

        // Instantly restore cached forecast on launch so the app is NEVER blank!
        if let cached = ForecastCacheManager.shared.loadForecast(location: self.location, horizon: self.horizon.rawValue, lang: self.language.rawValue) {
            self.forecastData = cached.forecast
            self.timeSeries = cached.forecast.toTimeSeriesPoints()
            self.lastUpdated = cached.cachedAt
            self.isOfflineCached = true
            self.offlineCacheNotice = "Showing cached forecast (\(self.formatRelativeTime(cached.cachedAt)))"
        } else if let anyCached = ForecastCacheManager.shared.findAnyCachedForecast(for: self.location) {
            self.horizon = anyCached.horizon
            self.forecastData = anyCached.forecast
            self.timeSeries = anyCached.forecast.toTimeSeriesPoints()
            self.lastUpdated = anyCached.cachedAt
            self.isOfflineCached = true
            self.offlineCacheNotice = "Offline: Showing cached \(anyCached.horizon.shortName) (\(self.formatRelativeTime(anyCached.cachedAt)))"
        }

        if let cachedImg = ForecastCacheManager.shared.loadImage(location: self.location, horizon: self.horizon.rawValue, lang: self.language.rawValue) {
            #if canImport(AppKit)
            self.currentImage = NSImage(data: cachedImg.data)
            #elseif canImport(UIKit)
            self.currentImage = UIImage(data: cachedImg.data)
            #endif
            self.rawImageData = cachedImg.data
        }
    }

    public var formattedTitle: String {
        "Meteogram: \(location) (\(horizon.shortName))"
    }

    public func setLocation(_ newLoc: String) {
        self.location = newLoc
        fetchMeteogram()
    }

    public func toggleFavorite(_ loc: String) {
        if favoriteLocations.contains(loc) {
            favoriteLocations.removeAll { $0 == loc }
        } else {
            favoriteLocations.append(loc)
        }
    }

    public func isFavorite(_ loc: String) -> Bool {
        favoriteLocations.contains(loc)
    }

    public func checkLocationDomainAndWarn() {
        if horizon == .iconD22 && MeteogramConfig.isOutsideIconD2Domain(location) {
            horizon = .iconEu5
            triggerFallbackAlert(from: "icon_d2", to: "icon_eu")
        } else if horizon != .iconD22 {
            dismissFallbackAlert()
        }
    }

    public func triggerFallbackAlert(from: String, to: String) {
        self.fallbackFromModel = from
        self.fallbackToModel = to
        self.showFallbackAlert = true
    }

    public func dismissFallbackAlert() {
        self.showFallbackAlert = false
    }

    public func switchToNextModel() {
        let next = horizon.nextInOrder(for: location)
        switchToModel(next)
    }

    public func switchToPreviousModel() {
        let prev = horizon.previousInOrder(for: location)
        switchToModel(prev)
    }

    public func switchToModel(_ target: ForecastHorizon) {
        guard target != horizon else { return }
        let previousHorizon = self.horizon
        let previousForecast = self.forecastData
        let previousTimeSeries = self.timeSeries
        let previousImage = self.currentImage
        let previousRawData = self.rawImageData

        self.selectedDate = nil
        self.horizon = target

        // If target model is in cache, load it immediately for seamless instant switching
        if let cached = ForecastCacheManager.shared.loadForecast(location: self.location, horizon: target.rawValue, lang: self.language.rawValue) {
            self.forecastData = cached.forecast
            self.timeSeries = cached.forecast.toTimeSeriesPoints()
            self.lastUpdated = cached.cachedAt
            self.isOfflineCached = true
            self.offlineCacheNotice = "Loaded from offline cache (\(self.formatRelativeTime(cached.cachedAt)))"
        }
        if let cachedImg = ForecastCacheManager.shared.loadImage(location: self.location, horizon: target.rawValue, lang: self.language.rawValue) {
            #if canImport(AppKit)
            self.currentImage = NSImage(data: cachedImg.data)
            #elseif canImport(UIKit)
            self.currentImage = UIImage(data: cachedImg.data)
            #endif
            self.rawImageData = cachedImg.data
        }

        fetchMeteogram(fallbackToPreviousOnFailure: (
            horizon: previousHorizon,
            forecast: previousForecast,
            timeSeries: previousTimeSeries,
            image: previousImage,
            rawData: previousRawData
        ))
    }

    public enum MeteogramDisplayMode: String, CaseIterable, Identifiable {
        case nativeCharts = "charts"
        case rasterImage = "image"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .nativeCharts: return "Native Swift Charts"
            case .rasterImage: return "Server Image"
            }
        }
    }

    public var selectedPoint: TimeSeriesPoint? {
        guard let selDate = selectedDate, !timeSeries.isEmpty else { return nil }
        return timeSeries.min(by: { abs($0.date.timeIntervalSince(selDate)) < abs($1.date.timeIntervalSince(selDate)) })
    }

    public func fetchMeteogram(fallbackToPreviousOnFailure: (horizon: ForecastHorizon, forecast: ForecastResponse?, timeSeries: [TimeSeriesPoint], image: PlatformImage?, rawData: Data?)? = nil) {
        currentTask?.cancel()
        self.selectedDate = nil

        checkLocationDomainAndWarn()

        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !loc.isEmpty else { return }

        // If not populated yet, check if cache has this model
        if self.forecastData == nil || self.timeSeries.isEmpty {
            if let cached = ForecastCacheManager.shared.loadForecast(location: loc, horizon: horizon.rawValue, lang: language.rawValue) {
                self.forecastData = cached.forecast
                self.timeSeries = cached.forecast.toTimeSeriesPoints()
                self.lastUpdated = cached.cachedAt
                self.isOfflineCached = true
                self.offlineCacheNotice = "Showing cached forecast (\(self.formatRelativeTime(cached.cachedAt)))"
            }
            if let cachedImg = ForecastCacheManager.shared.loadImage(location: loc, horizon: horizon.rawValue, lang: language.rawValue) {
                #if canImport(AppKit)
                self.currentImage = NSImage(data: cachedImg.data)
                #elseif canImport(UIKit)
                self.currentImage = UIImage(data: cachedImg.data)
                #endif
                self.rawImageData = cachedImg.data
            }
        }

        isLoading = true
        errorMessage = nil
        loadingStatusText = "Updating \(horizon.shortName) forecast..."

        currentTask = Task {
            var forecastFetchSucceeded = false

            // 1. Fetch structured forecast data for Native Swift Charts
            do {
                let forecastResult = try await service.fetchForecastData(
                    serverBaseUrl: serverUrl,
                    location: loc,
                    horizon: horizon,
                    language: language,
                    timeZone: timeZone
                )

                if Task.isCancelled { return }

                self.forecastData = forecastResult.forecast
                self.timeSeries = forecastResult.timeSeries
                self.latencyMs = forecastResult.latencyMs
                self.lastUpdated = Date()
                self.isOfflineCached = false
                self.offlineCacheNotice = nil
                self.isLoading = false
                self.errorMessage = nil
                forecastFetchSucceeded = true

                if forecastResult.fallbackUsed {
                    if forecastResult.actualModel == "icon_eu" {
                        self.horizon = .iconEu5
                    } else if forecastResult.actualModel == "aifs" {
                        self.horizon = .aifs15
                    }
                    self.triggerFallbackAlert(from: forecastResult.fallbackFrom, to: forecastResult.actualModel)
                } else {
                    self.showFallbackAlert = false
                }
            } catch {
                if Task.isCancelled { return }
                print("Forecast JSON fetch error: \(error)")
            }

            // 2. Concurrently fetch raster image (for fallback, copy/share, and raster mode)
            do {
                let imageResult = try await service.fetchMeteogram(
                    serverBaseUrl: serverUrl,
                    location: loc,
                    horizon: horizon,
                    language: language,
                    timeZone: timeZone
                )

                if Task.isCancelled { return }

                #if canImport(AppKit)
                guard let image = NSImage(data: imageResult.imageData) else {
                    throw MeteogramServiceError.decodingError
                }
                #elseif canImport(UIKit)
                guard let image = UIImage(data: imageResult.imageData) else {
                    throw MeteogramServiceError.decodingError
                }
                #endif

                self.currentImage = image
                self.rawImageData = imageResult.imageData
                self.isUsingStaticFallback = imageResult.isStaticFallback
                self.isLoading = false
            } catch {
                if Task.isCancelled { return }
                print("Raster fetch error: \(error)")
            }

            // 3. Offline / Cellular Unavailable Fallback Protection:
            // Ensure the app NEVER goes blank if network or cellular data fails!
            if !forecastFetchSucceeded {
                self.isLoading = false

                // Case A: We already have a valid loaded forecast or cached data for the target horizon
                if self.forecastData != nil && !self.timeSeries.isEmpty {
                    self.isOfflineCached = true
                    let ageText = self.lastUpdated.map { self.formatRelativeTime($0) } ?? "previously saved"
                    self.offlineCacheNotice = "Offline: Showing cached \(self.horizon.shortName) (\(ageText))"
                    self.errorMessage = nil
                    return
                }

                // Case B: No cache for target horizon, but we have a previous working model/view
                if let fallback = fallbackToPreviousOnFailure, let prevForecast = fallback.forecast, !fallback.timeSeries.isEmpty {
                    self.horizon = fallback.horizon
                    self.forecastData = prevForecast
                    self.timeSeries = fallback.timeSeries
                    self.currentImage = fallback.image
                    self.rawImageData = fallback.rawData
                    self.isOfflineCached = true
                    self.offlineCacheNotice = "Offline: No cache for \(self.horizon.shortName). Retaining \(fallback.horizon.shortName)."
                    self.errorMessage = nil
                    return
                }

                // Case C: Search for ANY cached model for this location
                if let anyCached = ForecastCacheManager.shared.findAnyCachedForecast(for: loc) {
                    self.horizon = anyCached.horizon
                    self.forecastData = anyCached.forecast
                    self.timeSeries = anyCached.forecast.toTimeSeriesPoints()
                    self.lastUpdated = anyCached.cachedAt
                    self.isOfflineCached = true
                    self.offlineCacheNotice = "Offline: Switched to cached \(anyCached.horizon.shortName) (\(self.formatRelativeTime(anyCached.cachedAt)))"
                    self.errorMessage = nil
                    return
                }

                // Case D: First launch and absolutely no network or cache available
                self.errorMessage = "No network connection. Please check your cellular/Wi-Fi connection and retry."
            }
        }
    }

    public func formatRelativeTime(_ date: Date) -> String {
        let elapsed = -date.timeIntervalSinceNow
        if elapsed < 60 {
            return "just now"
        } else if elapsed < 3600 {
            let mins = Int(elapsed / 60)
            return "\(mins)m ago"
        } else if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(elapsed / 86400)
            return "\(days)d ago"
        }
    }

    public func copyImageToClipboard() {
        #if canImport(AppKit)
        if let image = currentImage {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
        #elseif canImport(UIKit)
        if let image = currentImage {
            UIPasteboard.general.image = image
        }
        #endif
    }
}
