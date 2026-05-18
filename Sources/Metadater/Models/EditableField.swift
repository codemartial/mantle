import Foundation

// The five user-mutable fields on ImageRecord. Each case defines its own
// semantic-equality test so the dirty-tracker in EditStore can decide
// whether a field is "really" different from the last-saved baseline,
// independent of cosmetic differences that fall out of load -> normalise
// -> compare round trips. The whole point: typing "Foo" then deleting
// back to the original should land on clean, and a sidecar containing
// duplicate keywords should not appear dirty the moment we load it.

enum EditableField: CaseIterable, Sendable, Hashable {
    case headline
    case caption
    case keywords
    case captureDate
    case timezone

    func equals(_ a: ImageRecord, _ b: ImageRecord) -> Bool {
        switch self {
        case .headline:    return Self.trimEquals(a.headline, b.headline)
        case .caption:     return Self.trimEquals(a.caption, b.caption)
        case .keywords:    return Self.keywordsEqual(a.keywords, b.keywords)
        case .captureDate: return Self.dateEqualToSecond(a.captureDate, b.captureDate)
        case .timezone:    return Self.timezoneEqual(a.timezone, b.timezone)
        }
    }

    // MARK: - Per-field comparators

    private static func trimEquals(_ x: String, _ y: String) -> Bool {
        x.trimmingCharacters(in: .whitespacesAndNewlines) ==
        y.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Trim + drop empties + dedupe, then set-compare. Case-sensitive
    // ("Beach" != "beach"), order-insensitive (reorder is not a change).
    // Matches XMP dc:Subject's RDF-bag semantics: an unordered collection
    // of unique strings.
    private static func keywordsEqual(_ x: [String], _ y: [String]) -> Bool {
        Self.keywordSet(x) == Self.keywordSet(y)
    }

    static func keywordSet(_ raw: [String]) -> Set<String> {
        var s: Set<String> = []
        for raw in raw {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { s.insert(t) }
        }
        return s
    }

    // ExifTool dates are second-resolution; sub-second drift from
    // round-tripping a Date through a string formatter is structural,
    // not user-visible.
    private static func dateEqualToSecond(_ x: Date?, _ y: Date?) -> Bool {
        switch (x, y) {
        case (nil, nil): return true
        case let (a?, b?):
            return Int(a.timeIntervalSinceReferenceDate.rounded()) ==
                   Int(b.timeIntervalSinceReferenceDate.rounded())
        default: return false
        }
    }

    // TZRule.fixed carries a `label` cosmetic suffix ("UTC-08:00 - PST")
    // that the UI may regenerate slightly differently from what the
    // sidecar produced on load. Compare offsets, ignore labels.
    private static func timezoneEqual(_ x: TZRule, _ y: TZRule) -> Bool {
        switch (x, y) {
        case (.unknown, .unknown), (.auto, .auto): return true
        case let (.fixed(mx, _), .fixed(my, _)):   return mx == my
        default: return false
        }
    }
}
