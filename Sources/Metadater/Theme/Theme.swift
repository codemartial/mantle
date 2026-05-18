import SwiftUI

// Design tokens ported from the prototype's styles.css.
// Values are stated in OKLCH (lightness, chroma, hue) and converted to sRGB
// at runtime so the source of truth stays the OKLCH tuple, not a hex literal.
// Only the dark token set ships in the MVP; the light set is deferred.

enum Theme {

    // Surfaces
    static let bgDesktop    = oklch(0.14,  0.005, 250)
    static let bgWindow     = oklch(0.20,  0.005, 250)
    static let bgToolbar    = oklch(0.235, 0.005, 250)
    static let bgPanel      = oklch(0.225, 0.005, 250)
    static let bgElev       = oklch(0.27,  0.005, 250)
    static let bgElevHi     = oklch(0.32,  0.005, 250)
    static let bgInput      = oklch(0.17,  0.005, 250)
    // Matches bgPanel so square thumbnail tiles dissolve into the
    // browser pane background -- letterbox bands on tall / wide shots
    // read as part of the pane, not as a visible tile boundary.
    static let bgThumb      = oklch(0.225, 0.005, 250)
    static let bgStripeA    = oklch(0.16,  0.005, 250)
    static let bgStripeB    = oklch(0.18,  0.005, 250)

    // Text
    static let fg          = oklch(0.96, 0.005, 250)
    static let fgMute      = oklch(0.74, 0.005, 250)
    static let fgDim       = oklch(0.58, 0.005, 250)
    static let fgFaint     = oklch(0.46, 0.005, 250)

    // Lines
    static let line1       = oklch(0.30, 0.005, 250)
    static let line2       = oklch(0.34, 0.005, 250)
    static let lineSoft    = oklch(0.27, 0.005, 250, alpha: 0.70)

    // Accent + signal
    static let accent      = oklch(0.72, 0.13, 235)
    static let accentSoft  = oklch(0.72, 0.13, 235, alpha: 0.22)
    static let accentEdge  = oklch(0.72, 0.13, 235, alpha: 0.55)
    static let accentFg    = oklch(0.15, 0.02, 235)
    static let ok          = oklch(0.70, 0.13, 142)
    static let warn        = oklch(0.78, 0.14,  60)
    static let no          = oklch(0.65, 0.16,  28)

    // Chips
    static let chipBg      = oklch(0.30, 0.005, 250)
    static let chipBgSome  = oklch(0.30, 0.005, 250, alpha: 0.42)
    static let chipBorder  = oklch(0.34, 0.005, 250)

    // Traffic-light dots (kept for empty-state polish)
    static let tlR         = oklch(0.68, 0.18,  28)
    static let tlY         = oklch(0.82, 0.17,  88)
    static let tlG         = oklch(0.74, 0.18, 142)
}

// OKLCH -> sRGB. Standard conversion per Bjorn Ottosson's reference matrices.
// Clamps each sRGB component to [0, 1] after the gamma encode so out-of-gamut
// OKLCH points become the closest in-gamut sRGB approximation.
private func oklch(_ L: Double, _ C: Double, _ H: Double, alpha: Double = 1.0) -> Color {
    let h = H * .pi / 180.0
    let a = C * cos(h)
    let b = C * sin(h)

    let lPrime = L + 0.3963377774 * a + 0.2158037573 * b
    let mPrime = L - 0.1055613458 * a - 0.0638541728 * b
    let sPrime = L - 0.0894841775 * a - 1.2914855480 * b

    let lLin = lPrime * lPrime * lPrime
    let mLin = mPrime * mPrime * mPrime
    let sLin = sPrime * sPrime * sPrime

    let rLin =  4.0767416621 * lLin - 3.3077115913 * mLin + 0.2309699292 * sLin
    let gLin = -1.2684380046 * lLin + 2.6097574011 * mLin - 0.3413193965 * sLin
    let bLin = -0.0041960863 * lLin - 0.7034186147 * mLin + 1.7076147010 * sLin

    return Color(
        .sRGB,
        red:     gammaEncode(rLin),
        green:   gammaEncode(gLin),
        blue:    gammaEncode(bLin),
        opacity: alpha
    )
}

private func gammaEncode(_ x: Double) -> Double {
    let clamped = max(0.0, min(1.0, x))
    if clamped <= 0.0031308 {
        return 12.92 * clamped
    }
    return 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
}
