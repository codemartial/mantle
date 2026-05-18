import SwiftUI

// Segmented Y / MM / DD  HH : mm : ss editor with a trailing timezone picker.
// Each segment holds local text state for typing-in-progress; on focus
// loss, the segments are reassembled into a Date in the current timezone
// and pushed to the store via AppState.updateField. The timezone picker
// writes immediately on selection.

private enum DateField: Hashable {
    case year, month, day, hour, minute, second
}

struct DateEditor: View {
    @Environment(AppState.self) private var state

    @State private var year: String = ""
    @State private var month: String = ""
    @State private var day: String = ""
    @State private var hour: String = ""
    @State private var minute: String = ""
    @State private var second: String = ""
    @FocusState private var focusedField: DateField?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                segment($year,   width: 36, field: .year)
                separator("/")
                segment($month,  width: 22, field: .month)
                separator("/")
                segment($day,    width: 22, field: .day)

                Color.clear.frame(width: 8, height: 1)

                segment($hour,   width: 22, field: .hour)
                separator(":")
                segment($minute, width: 22, field: .minute)
                separator(":")
                segment($second, width: 22, field: .second)

                Spacer(minLength: 0)
            }
            .font(.system(size: 12 * 1.15, design: .monospaced))

            tzPicker
        }
        .onAppear { seedFromRecord() }
        .onChange(of: state.selectedRecord?.id ?? "") { _, _ in seedFromRecord() }
        .onChange(of: focusedField) { oldValue, _ in
            // Commit whenever a segment loses focus. Multiple commits as
            // the user tabs through is fine -- the dirty tracker's
            // semantic compare elides redundant writes.
            if oldValue != nil {
                commitDate()
            }
        }
    }

    // MARK: - Segment + separator

    private func segment(_ text: Binding<String>, width: CGFloat, field: DateField) -> some View {
        DateSegment(text: text, width: width, field: field, focus: $focusedField)
    }

    private func separator(_ glyph: String) -> some View {
        Text(glyph)
            .foregroundStyle(Theme.fgFaint)
    }

    // MARK: - TZ picker

    private var tzPicker: some View {
        Menu {
            ForEach(TZOptions.all, id: \.self) { label in
                Button(label) { selectTimezone(label: label) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentTZLabel)
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

    private var currentTZLabel: String {
        guard let rule = state.selectedRecord?.timezone else { return TZOptions.auto }
        return TZOptions.label(for: rule)
    }

    // MARK: - Mutations

    // Build a Date from the current six segments interpreted in the
    // record's TZ. No-op if any segment fails to parse or the combination
    // is invalid (Feb 30, etc.) -- the local @State stays as the user
    // typed it; the record's captureDate is unchanged.
    private func commitDate() {
        guard let id = state.selectedID,
              let record = state.selectedRecord else { return }

        guard let y = Int(year), let m = Int(month), let d = Int(day),
              let hh = Int(hour), let mm = Int(minute), let ss = Int(second) else {
            return
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = displayTimeZone(record.timezone)
        let comps = DateComponents(year: y, month: m, day: d,
                                   hour: hh, minute: mm, second: ss)
        guard let date = cal.date(from: comps) else { return }

        state.updateField(id: id, field: .captureDate) { rec in
            rec.captureDate = date
        }
    }

    private func selectTimezone(label: String) {
        guard let id = state.selectedID,
              let record = state.selectedRecord else { return }
        let newRule = TZOptions.rule(for: label)
        guard newRule != record.timezone else { return }

        state.updateField(id: id, field: .timezone) { rec in
            rec.timezone = newRule
        }
        // Re-seed the segment text -- if the wall-clock interpretation
        // shifted, the segments should reflect the new view.
        seedFromRecord()
    }

    // MARK: - Seeding

    private func seedFromRecord() {
        guard let record = state.selectedRecord else {
            year = ""; month = ""; day = ""
            hour = ""; minute = ""; second = ""
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
    let field: DateField
    var focus: FocusState<DateField?>.Binding

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused(focus, equals: field)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .foregroundStyle(Theme.fg)
            .frame(width: width, height: 20)
            .background(focus.wrappedValue == field ? Theme.bgInput : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(focus.wrappedValue == field ? Theme.accentEdge : .clear, lineWidth: 0.5)
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

    // Inverse of `label(for:)`. Parses a curated label string back into
    // a TZRule. "UTC+00:00 - Auto" round-trips to .auto so picking it
    // from the menu doesn't lock in a fixed-zero rule.
    static func rule(for label: String) -> TZRule {
        if label == auto { return .auto }
        // Pattern: "UTC<sign><HH>:<MM> - <suffix>"
        let trimmed = label.replacingOccurrences(of: "UTC", with: "")
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let offsetStr = parts.first.map(String.init) ?? ""
        let sign = offsetStr.first == "-" ? -1 : 1
        let nums = offsetStr.dropFirst().split(separator: ":").compactMap { Int($0) }
        guard nums.count == 2 else { return .unknown }
        let mins = sign * (nums[0] * 60 + nums[1])
        return .fixed(offsetMinutes: mins, label: label)
    }
}
