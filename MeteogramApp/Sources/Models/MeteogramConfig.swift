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
    public static let githubPagesBaseUrl = "https://igorcerovsky.github.io/AIFS-meteogram"

    public static let defaultPresets: [PresetLocation] = [
        PresetLocation(name: "Bratislava-Koliba", displayName: "📍 Bratislava-Koliba", isMajor: true),
        PresetLocation(name: "Liptovsky Mikulas", displayName: "📍 Liptovský Mikuláš", isMajor: true),
        PresetLocation(name: "Jasna", displayName: "📍 Jasná", isMajor: true),
        PresetLocation(name: "Plavecke Podhradie", displayName: "📍 Plavecké Podhradie", isMajor: true),
        PresetLocation(name: "Repiska", displayName: "📍 Repiská", isMajor: true),
        PresetLocation(name: "Poprad", displayName: "Poprad / Tatry"),
        PresetLocation(name: "Vienna", displayName: "Vienna"),
        PresetLocation(name: "Prague", displayName: "Prague")
    ]

    /// Resolves location string to a pre-rendered static image slug for GitHub Pages fallback
    public static func staticSlug(for locationName: String) -> String? {
        let norm = locationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if norm.contains("koliba") || norm.contains("bratislava") { return "bratislava-koliba" }
        if norm.contains("liptov") || norm.contains("mikulas") || norm.contains("mikuláš") { return "liptovsky-mikulas" }
        if norm.contains("jasna") || norm.contains("jasná") { return "jasna" }
        if norm.contains("plaveck") { return "plavecke-podhradie" }
        if norm.contains("repisk") || norm.contains("demanov") || norm.contains("demänov") { return "repiska" }
        if norm.contains("kosic") || norm.contains("košic") { return "kosice" }
        if norm.contains("poprad") || norm.contains("tatr") { return "poprad" }
        if norm.contains("vienna") || norm.contains("vieden") || norm.contains("viedeň") { return "vienna" }
        if norm.contains("prag") || norm.contains("praha") { return "prague" }
        return nil
    }

    /// Locations that are known to be outside DWD ICON-D2 domain (Germany / Western Central Europe)
    public static func isOutsideIconD2Domain(_ locationName: String) -> Bool {
        let norm = locationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let outsideKeywords = [
            "repiska", "repiská", "demanovska", "demänovská",
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
