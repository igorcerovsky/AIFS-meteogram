import Foundation

public struct PresetLocation: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let isMajor: Bool

    public init(name: String, displayName: String? = nil, isMajor: Bool = false) {
        self.name = name
        self.displayName = displayName ?? name
        self.isMajor = isMajor
    }
}

public struct MeteogramConfig {
    public static let defaultServerUrl = "http://localhost:8080"
    public static let defaultBonjourUrl = "http://Igors-MacBook-Air.local:8080"

    public static let defaultPresets: [PresetLocation] = [
        PresetLocation(name: "Bratislava-Koliba", displayName: "📍 Bratislava-Koliba", isMajor: true),
        PresetLocation(name: "Liptovsky Mikulas", displayName: "📍 Liptovský Mikuláš", isMajor: true),
        PresetLocation(name: "Jasna", displayName: "📍 Jasná", isMajor: true),
        PresetLocation(name: "Plavecke Podhradie", displayName: "📍 Plavecké Podhradie", isMajor: true),
        PresetLocation(name: "Košice", displayName: "Košice"),
        PresetLocation(name: "Poprad", displayName: "Poprad / Tatry"),
        PresetLocation(name: "Vienna", displayName: "Vienna"),
        PresetLocation(name: "Prague", displayName: "Prague")
    ]

    /// Locations that are known to be outside DWD ICON-D2 domain (Germany / Western Central Europe)
    public static func isOutsideIconD2Domain(_ locationName: String) -> Bool {
        let norm = locationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let outsideKeywords = [
            "jasna", "jasná",
            "liptovsky mikulas", "liptovský mikuláš", "mikulas", "mikuláš",
            "poprad", "tatry", "tatras", "vysoke tatry", "nizke tatry",
            "kosice", "košice", "presov", "prešov",
            "banska bystrica", "banská bystrica", "zvolen", "brezno",
            "strbske pleso", "štrbské pleso", "tatranska lomnica", "tatranská lomnica",
            "bardejov", "humenne", "michalovce", "trebisov", "roznava", "spisska nova ves"
        ]
        return outsideKeywords.contains { norm.contains($0) }
    }
}
