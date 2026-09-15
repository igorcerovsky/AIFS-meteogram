import Foundation

/// Available numerical weather prediction / AI forecast models
public enum ForecastHorizon: String, CaseIterable, Identifiable {
    case aifs15 = "15"
    case iconD22 = "icon_d2_2"
    case iconEu5 = "icon_eu_5"
    case aifs10 = "10"
    case aifs7 = "7"

    public var id: String { rawValue }

    /// Exact sequence requested by user: 15 days, 2 days, 5 days, 10 days, 7 days
    public static let displayOrder: [ForecastHorizon] = [
        .aifs15,
        .iconD22,
        .iconEu5,
        .aifs10,
        .aifs7
    ]

    public var pillTitle: String {
        switch self {
        case .aifs15: return "15d"
        case .iconD22: return "2d"
        case .iconEu5: return "5d"
        case .aifs10: return "10d"
        case .aifs7: return "7d"
        }
    }

    public var subtitle: String {
        switch self {
        case .aifs15: return "ECMWF AIFS"
        case .iconD22: return "DWD ICON-D2"
        case .iconEu5: return "DWD ICON-EU"
        case .aifs10: return "ECMWF AIFS"
        case .aifs7: return "ECMWF AIFS"
        }
    }

    public var displayName: String {
        switch self {
        case .aifs15: return "15 days (ECMWF AIFS Global 50-member)"
        case .iconD22: return "2 days / 48h (DWD ICON-D2 2.2 km, 20-member)"
        case .iconEu5: return "5 days (DWD ICON-EU 7 km, 40-member)"
        case .aifs10: return "10 days (ECMWF AIFS Global)"
        case .aifs7: return "7 days (ECMWF AIFS 1 week)"
        }
    }

    public var shortName: String {
        switch self {
        case .aifs15: return "AIFS 15d"
        case .iconD22: return "ICON-D2 2d"
        case .iconEu5: return "ICON-EU 5d"
        case .aifs10: return "AIFS 10d"
        case .aifs7: return "AIFS 7d"
        }
    }

    public var modelParam: String {
        switch self {
        case .aifs15, .aifs10, .aifs7: return "aifs"
        case .iconEu5: return "icon_eu"
        case .iconD22: return "icon_d2"
        }
    }

    public var daysParam: Int {
        switch self {
        case .aifs15: return 15
        case .iconD22: return 2
        case .iconEu5: return 5
        case .aifs10: return 10
        case .aifs7: return 7
        }
    }

    public var group: String {
        switch self {
        case .aifs15, .aifs10, .aifs7:
            return "ECMWF AIFS (Global AI Ensemble)"
        case .iconEu5, .iconD22:
            return "Regional High-Resolution (ALADIN style)"
        }
    }

    public static func availableHorizons(for location: String) -> [ForecastHorizon] {
        if MeteogramConfig.isOutsideIconD2Domain(location) {
            return [.aifs15, .iconEu5, .aifs10, .aifs7]
        }
        return displayOrder
    }

    public func nextInOrder(for location: String) -> ForecastHorizon {
        let order = ForecastHorizon.availableHorizons(for: location)
        guard let idx = order.firstIndex(of: self) else { return order.first ?? .aifs15 }
        let nextIdx = (idx + 1) % order.count
        return order[nextIdx]
    }

    public func previousInOrder(for location: String) -> ForecastHorizon {
        let order = ForecastHorizon.availableHorizons(for: location)
        guard let idx = order.firstIndex(of: self) else { return order.last ?? .aifs15 }
        let prevIdx = (idx - 1 + order.count) % order.count
        return order[prevIdx]
    }
}

public enum ForecastLanguage: String, CaseIterable, Identifiable {
    case en = "en"
    case sk = "sk"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .en: return "English (Default)"
        case .sk: return "Slovenčina (SHMÚ)"
        }
    }
}

public enum ForecastTimeZone: String, CaseIterable, Identifiable {
    case local = "local"
    case utc = "utc"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .local: return "Local Time (Default)"
        case .utc: return "UTC"
        }
    }
}
