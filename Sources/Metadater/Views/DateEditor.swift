import SwiftUI

// Segmented Y / MM / DD  HH : mm : ss editor with a trailing timezone picker.
// Design pass: local @State seeded from EditStore on selection change. No
// write-back yet -- the dirty / save wiring happens in the editing-phase pass.

struct DateEditor: View {
    @Environment(AppState.self) private var state

    @State private var year: String = ""
    @State private var month: String = ""
    @State private var day: String = ""
    @State private var hour: String = ""
    @State private var minute: String = ""
    @State private var second: String = ""
    @State private var tzLabel: String = TZOptions.auto

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                segment($year, width: 36)
                separator("/")
                segment($month, width: 22)
                separator("/")
                segment($day, width: 22)

                Color.clear.frame(width: 8, height: 1)

                segment($hour, width: 22)
                separator(":")
                segment($minute, width: 22)
                separator(":")
                segment($second, width: 22)

                Spacer(minLength: 0)
            }
            .font(.system(size: 12 * 1.15, design: .monospaced))

            tzPicker
        }
        .onAppear { seedFromRecord() }
        .onChange(of: state.selectedRecord?.id ?? "") { _, _ in seedFromRecord() }
    }

    // MARK: - Segment + separator

    private func segment(_ text: Binding<String>, width: CGFloat) -> some View {
        DateSegment(text: text, width: width)
    }

    private func separator(_ glyph: String) -> some View {
        Text(glyph)
            .foregroundStyle(Theme.fgFaint)
    }

    // MARK: - TZ picker

    private var tzPicker: some View {
        Menu {
            ForEach(TZOptions.all, id: \.self) { label in
                Button(label) { tzLabel = label }
            }
        } label: {
            HStack(spacing: 4) {
                Text(tzLabel.isEmpty ? TZOptions.auto : tzLabel)
                    .font(.system(size: 11 * 1.15, design: .monospaced))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8 * 1.15, weight: .semibold))
                    .foregroundStyle(Theme.fgDim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(Theme.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.line1, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    // MARK: - Seeding

    private func seedFromRecord() {
        guard let record = state.selectedRecord else {
            year = ""; month = ""; day = ""
            hour = ""; minute = ""; second = ""
            tzLabel = TZOptions.auto
            return
        }
        let zone = displayTimeZone(record.timezone)
        let parts = decompose(record.captureDate, in: zone)
        year   = parts.year.map { String(format: "%04d", $0) } ?? ""
        month  = parts.month.map { String(format: "%02d", $0) } ?? ""
        day    = parts.day.map { String(format: "%02d", $0) } ?? ""
        hour   = parts.hour.map { String(format: "%02d", $0) } ?? ""
        minute = parts.minute.map { String(format: "%02d", $0) } ?? ""
        second = parts.second.map { String(format: "%02d", $0) } ?? ""
        tzLabel = TZOptions.label(for: record.timezone)
    }

    private func displayTimeZone(_ rule: TZRule) -> TimeZone {
        if case .fixed(let mins, _) = rule {
            return TimeZone(secondsFromGMT: mins * 60) ?? TimeZone(identifier: "UTC")!
        }
        return TimeZone(identifier: "UTC")!
    }

    private func decompose(_ date: Date?, in zone: TimeZone) -> (year: Int?, month: Int?, day: Int?, hour: Int?, minute: Int?, second: Int?) {
        guard let date else { return (nil, nil, nil, nil, nil, nil) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return (c.year, c.month, c.day, c.hour, c.minute, c.second)
    }
}

// Single date segment. Strips non-digits as the user types and keeps the
// display width fixed so adjacent separators don't shimmy when the value
// shortens. Tabular nums via the parent font keeps the glyphs centered.
private struct DateSegment: View {
    @Binding var text: String
    let width: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .foregroundStyle(Theme.fg)
            .frame(width: width, height: 20)
            .background(focused ? Theme.bgInput : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(focused ? Theme.accentEdge : .clear, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .onChange(of: text) { _, newValue in
                let digitsOnly = newValue.filter { $0.isNumber }
                if digitsOnly != newValue { text = digitsOnly }
            }
    }
}

// Catalogue of the TZ options shown in the dropdown. Mirrors the
// TZ_OPTIONS list in app.jsx so the design stays in lockstep with the
// prototype while the data model in TZRule is being filled out elsewhere.
// Labels follow the SidecarIO format `UTC+HH:MM - <suffix>` so a value
// pulled from a real TZRule.fixed can sit alongside the curated entries
// without reformatting.
enum TZOptions {
    static let auto = "UTC+00:00 - Auto"

    static let all: [String] = [
        "UTC+00:00 - Auto",
        "UTC+00:00 - Iceland",
        "UTC+00:00 - UK",
        "UTC+01:00 - CET",
        "UTC-05:00 - EST",
        "UTC-08:00 - PST",
        "UTC+05:30 - IST",
        "UTC+09:00 - JST",
    ]

    static func label(for rule: TZRule) -> String {
        switch rule {
        case .unknown:               return auto
        case .auto:                  return auto
        case .fixed(_, let label):   return label
        }
    }
}
