import SwiftUI

// Editable lat / lon cells with derived hemisphere labels. Pasting a string
// that contains a recognisable coordinate pair (decimal or DMS) fills both
// cells in one shot. Hemisphere chars are read-only labels driven by the
// sign of the underlying value; to flip them, the user types a leading "-".
//
// Binding-based: lat / lon bindings are the source of truth. Internal
// @State keeps display text and a local Double copy so typing doesn't get
// round-tripped through formatCoord. External mutations (pin drag, image
// switch) propagate via .onChange(of: lat / lon).

struct GeoCells: View {
    @Binding var lat: Double?
    @Binding var lon: Double?

    @State private var latitude: Double? = nil
    @State private var longitude: Double? = nil
    @State private var latText: String = ""
    @State private var lonText: String = ""

    var body: some View {
        HStack(spacing: 6) {
            geoCell(text: $latText,
                    value: $latitude,
                    other: $longitude,
                    isLat: true)
            geoCell(text: $lonText,
                    value: $longitude,
                    other: $latitude,
                    isLat: false)
        }
        .onAppear { seedFromBinding() }
        // External mutations land here. Skip if the bound value matches our
        // local copy (i.e. the change came from our own pushToBinding), so
        // typing in one cell doesn't get its neighbour overwritten while
        // focused.
        .onChange(of: lat) { _, new in
            if !Self.coordsClose(latitude, new) {
                latitude = new
                latText = Self.formatCoord(new)
            }
        }
        .onChange(of: lon) { _, new in
            if !Self.coordsClose(longitude, new) {
                longitude = new
                lonText = Self.formatCoord(new)
            }
        }
    }

    // MARK: - Cell

    private func geoCell(text: Binding<String>,
                         value: Binding<Double?>,
                         other: Binding<Double?>,
                         isLat: Bool) -> some View {
        GeoCell(text: text,
                value: value,
                other: other,
                isLat: isLat,
                onCommit: { commitDisplay(for: isLat) })
    }

    // MARK: - Seed / format

    private func seedFromBinding() {
        latitude = lat
        longitude = lon
        latText = Self.formatCoord(latitude)
        lonText = Self.formatCoord(longitude)
    }

    private func commitDisplay(for isLat: Bool) {
        if isLat {
            latText = Self.formatCoord(latitude)
        } else {
            lonText = Self.formatCoord(longitude)
        }
        pushToBinding()
    }

    // Single entry point for write-back. Both a cell commit and a paste
    // (which can fill both cells at once) end up here.
    private func pushToBinding() {
        lat = latitude
        lon = longitude
    }

    static func formatCoord(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.4f", abs(value)) + "\u{00B0}"
    }

    static func coordsClose(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < 1e-7
        default: return false
        }
    }
}

// One coordinate cell -- TextField on the left, hemisphere label on the
// right. The hemisphere label is a passive readout: it reflects the sign of
// the bound numeric value and updates as the user edits the text.
private struct GeoCell: View {
    @Binding var text: String
    @Binding var value: Double?
    @Binding var other: Double?
    let isLat: Bool
    let onCommit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(.system(size: 11 * 1.15, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.fg)
                .padding(.leading, 7)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onPasteCommand(of: [.plainText]) { providers in
                    handlePaste(providers: providers)
                }

            Text(hemisphereLabel)
                .font(.system(size: 11 * 1.15, design: .monospaced))
                .foregroundStyle(Theme.fgDim)
                .frame(width: 22)
                .frame(maxHeight: .infinity)
                .background(Theme.bgStripeA)
                .overlay(
                    Rectangle()
                        .fill(Theme.line1)
                        .frame(width: 0.5),
                    alignment: .leading
                )
        }
        .frame(height: 24)
        .background(Theme.bgInput)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(focused ? Theme.accentEdge : Theme.line1,
                              lineWidth: focused ? 1 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Hemisphere label

    private var hemisphereLabel: String {
        guard let v = value else { return isLat ? "N" : "E" }
        if isLat { return v >= 0 ? "N" : "S" }
        return v >= 0 ? "E" : "W"
    }

    // MARK: - Commit / paste

    private func commit() {
        guard let parsed = CoordParser.parseSingle(text) else {
            onCommit()
            return
        }
        let preservingSign = (value ?? 0) < 0 ? -abs(parsed) : abs(parsed)
        value = preservingSign
        onCommit()
    }

    private func handlePaste(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = (object as? String) else { return }
            DispatchQueue.main.async { applyPaste(string) }
        }
    }

    private func applyPaste(_ raw: String) {
        guard let parsed = CoordParser.parse(raw) else { return }
        if let pair = parsed.pair {
            value = isLat ? pair.lat : pair.lon
            other = isLat ? pair.lon : pair.lat
            text = GeoCells.formatCoord(value)
        } else if let single = parsed.single {
            value = single
            text = GeoCells.formatCoord(single)
        }
        onCommit()
    }
}

// MARK: - Coordinate parser

// Translates parseLatLonPair / tokenizeCoords from app.jsx. Recognises
// decimal pairs ("37.77, -122.42"), space-separated decimals, and DMS
// triples ("37 deg 46' 26.0\" N").
enum CoordParser {
    struct Token { let value: Double; let hemisphere: Character? }
    struct Pair  { let lat: Double; let lon: Double }
    struct Result { let pair: Pair?; let single: Double? }

    static func parseSingle(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let cleaned = trimmed
            .replacingOccurrences(of: "\u{00B0}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    static func parse(_ raw: String) -> Result? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let dmsMarkers = CharacterSet(charactersIn: "\u{00B0}'\"\u{2032}\u{2033}NnSsEeWw")
        let hasDms = trimmed.rangeOfCharacter(from: dmsMarkers) != nil
        let tokens: [Token] = hasDms ? tokenizeDMS(trimmed) : tokenizeDecimal(trimmed)
        guard let first = tokens.first else { return nil }
        if tokens.count == 1 { return Result(pair: nil, single: first.value) }

        let a = tokens[0]
        let b = tokens[1]
        var lat: Double
        var lon: Double
        if isLatHem(a.hemisphere) && isLonHem(b.hemisphere) {
            lat = a.value; lon = b.value
        } else if isLatHem(b.hemisphere) && isLonHem(a.hemisphere) {
            lat = b.value; lon = a.value
        } else if isLatHem(a.hemisphere) {
            lat = a.value; lon = b.value
        } else if isLonHem(a.hemisphere) {
            lon = a.value; lat = b.value
        } else {
            lat = a.value; lon = b.value
        }
        if abs(lat) > 90, abs(lon) <= 90 {
            let swap = lat; lat = lon; lon = swap
        }
        return Result(pair: Pair(lat: lat, lon: lon), single: nil)
    }

    // MARK: - Tokenizers

    private static func tokenizeDecimal(_ s: String) -> [Token] {
        let separators = CharacterSet(charactersIn: ",;").union(.whitespaces)
        return s.components(separatedBy: separators)
            .compactMap { piece -> Token? in
                let trimmed = piece.replacingOccurrences(of: "\u{00B0}", with: "")
                guard let value = Double(trimmed) else { return nil }
                return Token(value: value, hemisphere: nil)
            }
    }

    private static func tokenizeDMS(_ s: String) -> [Token] {
        let pattern = "([+-]?\\d+(?:\\.\\d+)?)\\s*(?:\u{00B0}|d|deg)\\s*"
                    + "(?:(\\d+(?:\\.\\d+)?)\\s*(?:'|\u{2032}|m\\b))?\\s*"
                    + "(?:(\\d+(?:\\.\\d+)?)\\s*(?:\"|\u{2033}|s\\b))?\\s*"
                    + "([NSEWnsew])?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = s as NSString
        let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match -> Token? in
            let degStr = group(match, at: 1, in: ns)
            guard let deg = Double(degStr) else { return nil }
            let min = Double(group(match, at: 2, in: ns)) ?? 0
            let sec = Double(group(match, at: 3, in: ns)) ?? 0
            let hem = group(match, at: 4, in: ns).first
            let magnitude = abs(deg) + min / 60.0 + sec / 3600.0
            var signed = deg < 0 ? -magnitude : magnitude
            if let h = hem.map(Character.init(extendedGraphemeClusterLiteral:)) {
                let upper = Character(h.uppercased())
                if upper == "S" || upper == "W" { signed = -abs(magnitude) }
                else if upper == "N" || upper == "E" { signed = abs(magnitude) }
            }
            return Token(value: signed, hemisphere: hem.map { Character($0.uppercased()) })
        }
    }

    private static func group(_ match: NSTextCheckingResult, at i: Int, in ns: NSString) -> String {
        guard i < match.numberOfRanges else { return "" }
        let r = match.range(at: i)
        if r.location == NSNotFound { return "" }
        return ns.substring(with: r)
    }

    private static func isLatHem(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c == "N" || c == "S"
    }

    private static func isLonHem(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c == "E" || c == "W"
    }
}
