import Foundation

// Two-way switch for the Location section's MKMapView. `.hybrid` shows
// satellite imagery with road and place labels overlaid -- the common
// "satellite view" expectation. Pure `.satellite` (no labels) was tested
// and felt disorienting at low zoom, so we don't expose it.
enum MapStyleChoice: String, CaseIterable, Sendable {
    case standard
    case hybrid

    var label: String {
        switch self {
        case .standard: return "Map"
        case .hybrid:   return "Satellite"
        }
    }

    private static let key = "mapStyle.v1"

    static func load() -> MapStyleChoice {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let value = MapStyleChoice(rawValue: raw) else {
            return .standard
        }
        return value
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}
