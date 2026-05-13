import SwiftUI

// SF Pro for MVP. Geist swap is deferred to a follow-up:
// register Geist-Regular.otf, Geist-Medium.otf, Geist-Semibold.otf,
// GeistMono-Regular.otf, GeistMono-Medium.otf via
// CTFontManagerRegisterFontsForURL at launch and update the helpers below.

enum Typo {
    static let body      = Font.system(size: 12, weight: .regular)
    static let bodyMid   = Font.system(size: 12, weight: .medium)
    static let title     = Font.system(size: 12, weight: .semibold)
    static let small     = Font.system(size: 11, weight: .regular)
    static let label     = Font.system(size: 10, weight: .medium).smallCaps()
    static let mono      = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let monoMid   = Font.system(size: 11, weight: .medium, design: .monospaced)
}
