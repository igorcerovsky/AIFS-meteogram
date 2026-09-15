import Foundation
import CoreLocation
import Combine

public class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()

    private let manager = CLLocationManager()
    @Published public var lastKnownLocation: CLLocation?
    @Published public var authorizationStatus: CLAuthorizationStatus
    @Published public var isLocating = false
    @Published public var locationError: String?

    public var onLocationReceived: ((String) -> Void)?

    override public init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    private var isAuthorized: Bool {
        #if os(iOS)
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #elseif os(macOS)
        return authorizationStatus == .authorizedAlways
        #else
        return false
        #endif
    }

    public func requestCurrentLocation(completion: @escaping (String) -> Void) {
        self.onLocationReceived = completion
        self.isLocating = true
        self.locationError = nil

        let status = manager.authorizationStatus
        if status == .notDetermined {
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #elseif os(macOS)
            manager.requestAlwaysAuthorization()
            #endif
        } else if isAuthorized {
            manager.requestLocation()
        } else {
            self.isLocating = false
            self.locationError = "Location permission was denied. Please enable in Settings."
        }
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        if isAuthorized && isLocating {
            manager.requestLocation()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.lastKnownLocation = location
        self.isLocating = false

        // Format coordinates as lat, lon
        let formatted = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
        DispatchQueue.main.async {
            self.onLocationReceived?(formatted)
            self.onLocationReceived = nil
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.isLocating = false
        self.locationError = error.localizedDescription
    }
}
