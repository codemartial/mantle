// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

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
    case location

    func equals(_ a: ImageRecord, _ b: ImageRecord) -> Bool {
        switch self {
        case .headline:    return Self.trimEquals(a.headline, b.headline)
        case .caption:     return Self.trimEquals(a.caption, b.caption)
        case .keywords:    return Self.keywordsEqual(a.keywords, b.keywords)
        case .captureDate: return Self.dateEqualToSecond(a.captureDate, b.captureDate)
        case .timezone:    return Self.timezoneEqual(a.timezone, b.timezone)
        case .location:    return Self.coordsEqual(a.latitude, a.longitude,
                                                   b.latitude, b.longitude)
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

    // Tolerance ~ 1e-7 degrees (~1cm) absorbs round-trip drift through
    // ExifTool's 7-decimal formatting on save -> reload.
    private static func coordsEqual(_ ax: Double?, _ ay: Double?,
                                    _ bx: Double?, _ by: Double?) -> Bool {
        coordEqual(ax, bx) && coordEqual(ay, by)
    }

    private static func coordEqual(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < 1e-7
        default: return false
        }
    }

    // TZRule.fixed carries a cosmetic `label` (a place name or IANA zone id)
    // that the UI may regenerate differently from what the sidecar produced
    // on load. Compare offsets, ignore labels.
    private static func timezoneEqual(_ x: TZRule, _ y: TZRule) -> Bool {
        switch (x, y) {
        case (.unknown, .unknown), (.auto, .auto): return true
        case let (.fixed(mx, _), .fixed(my, _)):   return mx == my
        default: return false
        }
    }
}
