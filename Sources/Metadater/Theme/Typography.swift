import SwiftUI

// Single source of truth for font sizes. Bump `scale` to enlarge the
// whole UI uniformly. Per-display sizing is task #12.

enum Typo {

    static let scale: CGFloat = 1.15

    static func size(_ points: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: points * scale, weight: weight, design: design)
    }

    // Convenience presets matching the prototype's roles
    static var body:    Font { size(12) }
    static var bodyMid: Font { size(12, weight: .medium) }
    static var title:   Font { size(12, weight: .semibold) }
    static var small:   Font { size(11) }
    static var label:   Font { size(10, weight: .medium).smallCaps() }
    static var mono:    Font { size(11, design: .monospaced) }
    static var monoMid: Font { size(11, weight: .medium, design: .monospaced) }
}
