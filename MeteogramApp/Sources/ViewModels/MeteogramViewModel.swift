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
        self.horizon = target
        fetchMeteogram()
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

    public func fetchMeteogram() {
        currentTask?.cancel()

        checkLocationDomainAndWarn()

        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !loc.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        loadingStatusText = "Fetching \(horizon.shortName) forecast for \(loc)..."

        currentTask = Task {
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
                self.isLoading = false

                if forecastResult.fallbackUsed {
                    if forecastResult.actualModel == "icon_eu" {
                        self.horizon = .iconEu5
                    } else if forecastResult.actualModel == "aifs" {
                        self.horizon = .aifs15
                    }
                    self.triggerFallbackAlert(from: forecastResult.fallbackFrom, to: forecastResult.actualModel)
                } else if !MeteogramConfig.isOutsideIconD2Domain(loc) {
                    self.showFallbackAlert = false
                }
            } catch {
                if Task.isCancelled { return }
                print("Forecast JSON fetch error: \(error), falling back to raster image")
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
                // Only set error if we don't have timeSeries either
                if self.timeSeries.isEmpty {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
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
