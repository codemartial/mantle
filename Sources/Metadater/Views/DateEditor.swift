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
            Button("Auto") { selectTimezone(identifier: TZOptions.auto) }
            Divider()
            ForEach(TZOptions.regions, id: \.self) { region in
                Menu(region) {
                    ForEach(TZOptions.cities(in: region), id: \.self) { ident in
                        Button(TZOptions.cityDisplay(ident)) {
                            selectTimezone(identifier: ident)
                        }
                    }
                }
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

    private func selectTimezone(identifier: String) {
        guard let id = state.selectedID,
              let record = state.selectedRecord else { return }
        let newRule = TZOptions.rule(for: identifier, at: record.captureDate)
        // Always assign -- the displayed label has to reflect the user's
        // pick even when the offset is unchanged. EditableField's tz
        // comparator ignores labels so this won't false-positive as dirty.
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

// Full IANA timezone catalogue, served hierarchically by region for the
// picker submenus. Labels stored on TZRule.fixed are the IANA identifier
// (e.g. "America/Los_Angeles"); the offset minutes are computed relative
// to the photo's captureDate at pick time so DST is honoured for the
// year in question.
//
// "Auto" is a special label the picker shows for both .auto and .unknown
// records -- picking it from the menu sets the rule back to .auto.
enum TZOptions {
    static let auto = "Auto"

    // `regionMap` is the single source of truth. `all` is preserved as a
    // flat sorted list in case callers want it. Built once at module load
    // by walking the sorted identifier list and bucketing on the first
    // path segment. Because `all` is sorted alphabetically, both the
    // regions and the cities within each region come out sorted without
    // any extra .sorted() call.
    static let all: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()

    private static let regionMap: [String: [String]] = {
        var map: [String: [String]] = [:]
        for id in all {
            let head = id.split(separator: "/").first.map(String.init) ?? id
            map[head, default: []].append(id)
        }
        return map
    }()

    static let regions: [String] = {
        var seen: Set<String> = []
        var out: [String] = []
        for id in all {
            let head = id.split(separator: "/").first.map(String.init) ?? id
            if seen.insert(head).inserted {
                out.append(head)
            }
        }
        return out
    }()

    static func cities(in region: String) -> [String] {
        regionMap[region] ?? []
    }

    // What to show as the menu item under a region. "America/Los_Angeles"
    // -> "Los Angeles". "America/Indiana/Indianapolis" -> "Indiana / Indianapolis".
    static func cityDisplay(_ identifier: String) -> String {
        let comps = identifier.split(separator: "/").dropFirst()
        let joined = comps.map { $0.replacingOccurrences(of: "_", with: " ") }
                          .joined(separator: " / ")
        return joined.isEmpty ? identifier : joined
    }

    // Label rendered in the picker's button. .auto / .unknown -> "Auto";
    // .fixed shows whatever the rule stored (typically the IANA id).
    static func label(for rule: TZRule) -> String {
        switch rule {
        case .unknown, .auto:        return auto
        case .fixed(_, let label):   return label
        }
    }

    // Convert a user pick into a TZRule. "Auto" -> .auto. Otherwise
    // resolve the IANA id and compute offset at the photo's captureDate
    // (falling back to now if the photo has no date yet). The label on
    // the .fixed case is the IANA id, so it round-trips back through the
    // picker visually.
    static func rule(for identifier: String, at date: Date?) -> TZRule {
        if identifier == auto { return .auto }
        guard let tz = TimeZone(identifier: identifier) else { return .unknown }
        let secs = tz.secondsFromGMT(for: date ?? Date())
        return .fixed(offsetMinutes: secs / 60, label: identifier)
    }
}
