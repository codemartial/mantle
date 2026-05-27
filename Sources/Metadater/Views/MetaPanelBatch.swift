import SwiftUI

// Right pane in batch mode. Sections, top to bottom:
//   Selection (count, master, date span, distinct locations, total size)
//   Captured (master)  -- master's own DateEditor + a relative DateShift
//                          that applies to all on synthesis
//   Location (master)  -- LocationMap + GeoCells writing to master directly
//   Keywords           -- common + some chips
//
// "Captured (master)" and "Location (master)" edit the master image's
// stored record directly (same path as single-mode). The DateShift control
// goes through batchDraft and is applied to every image at exitBatch().

struct MetaPanelBatch: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            debugStrip

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    selectionSection
                    sectionDivider()

                    capturedSection
                    sectionDivider()

                    locationSection
                    sectionDivider()

                    BatchKeywordChips()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Debug strip (shared with MetadataPane)

    private var debugStrip: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if state.debugLog.lines.isEmpty {
                        Text("(debug log -- exiftool save commands appear here)")
                            .foregroundStyle(Theme.fgFaint)
                    }
                    ForEach(Array(state.debugLog.lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .id(idx)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.fgDim)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 200)
            .background(Theme.bgInput)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.line1)
                    .frame(height: 1)
            }
            .onChange(of: state.debugLog.lines.count) { _, _ in
                if let last = state.debugLog.lines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Selection summary

    private var selectionSection: some View {
        ExifReadOnlyList(title: "Selection",
                         items: selectionItems,
                         trailing: { selectionBadge })
    }

    private var selectionBadge: some View {
        Text(String(state.batchOrder.count))
            .font(.system(size: 10 * 1.15, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Theme.accent)
    }

    private var selectionItems: [(String, String)] {
        let masterName = state.library.first { $0.id == state.masterID }?.basename ?? ""
        return [
            ("Master",    masterName),
            ("Date span", dateSpanText),
            ("Locations", locationsText),
            ("Total size", totalSizeText),
        ]
    }

    private var dateSpanText: String {
        let dates: [String] = state.batchOrder.compactMap { id in
            guard let rec = state.edits.record(id), let d = rec.captureDate else { return nil }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            return f.string(from: d)
        }
        let distinct = Set(dates).count
        if distinct == 0 { return "no dates" }
        if distinct == 1 { return "same day" }
        return "\(distinct) dates"
    }

    private var locationsText: String {
        let locs: [String] = state.batchOrder.compactMap { id in
            guard let rec = state.edits.record(id),
                  let lat = rec.latitude, let lon = rec.longitude else { return nil }
            return String(format: "%.2f,%.2f", lat, lon)
        }
        let distinct = Set(locs).count
        if distinct == 0 { return "none" }
        return "\(distinct) distinct"
    }

    private var totalSizeText: String {
        let total = state.batchOrder.reduce(Int64(0)) { acc, id in
            acc + (state.edits.record(id)?.size ?? 0)
        }
        return ByteSize.format(total)
    }

    // MARK: - Captured (master) + DateShift

    private var capturedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Captured (master)")
            DateEditor(
                date: Binding(
                    get: { state.masterRecord?.captureDate },
                    set: { newDate in
                        guard let id = state.masterID, let newDate else { return }
                        state.updateField(id: id, field: .captureDate) { $0.captureDate = newDate }
                    }
                ),
                timezone: Binding(
                    get: { state.masterRecord?.timezone ?? .unknown },
                    set: { newTz in
                        guard let id = state.masterID else { return }
                        state.updateField(id: id, field: .timezone) { $0.timezone = newTz }
                    }
                )
            )

            dateShiftRow
        }
    }

    @ViewBuilder
    private var dateShiftRow: some View {
        @Bindable var state = state

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Shift all by")
                .font(.system(size: 10 * 1.15, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.fgDim)

            shiftStepper(value: $state.batchDraft.dateShiftHours,
                         range: -240...240,
                         suffix: "h")

            shiftStepper(value: $state.batchDraft.dateShiftMinutes,
                         range: -59...59,
                         suffix: "m")

            Spacer()
        }
    }

    private func shiftStepper(value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack(spacing: 2) {
            TextField("0", value: value, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .font(.system(size: 11 * 1.15, design: .monospaced))
                .foregroundStyle(Theme.fg)
                .frame(width: 36, height: 20)
                .padding(.horizontal, 4)
                .background(Theme.bgInput)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.line1, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(suffix)
                .font(.system(size: 10 * 1.15, design: .monospaced))
                .foregroundStyle(Theme.fgDim)
        }
    }

    // MARK: - Location (master)

    private let mapAspectRatio: CGFloat = 1.0

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Location (master)") {
                mapStyleToggle
            }

            LocationMap()
                .aspectRatio(mapAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.line1, lineWidth: 0.5)
                )

            GeoCells(
                lat: Binding(
                    get: { state.masterRecord?.latitude },
                    set: { newLat in
                        guard let id = state.masterID else { return }
                        state.updateLocation(id: id, lat: newLat, lon: state.masterRecord?.longitude)
                    }
                ),
                lon: Binding(
                    get: { state.masterRecord?.longitude },
                    set: { newLon in
                        guard let id = state.masterID else { return }
                        state.updateLocation(id: id, lat: state.masterRecord?.latitude, lon: newLon)
                    }
                )
            )

            locationsSummaryLine
        }
    }

    @ViewBuilder
    private var mapStyleToggle: some View {
        @Bindable var state = state
        Picker("", selection: $state.mapStyle) {
            ForEach(MapStyleChoice.allCases, id: \.self) { choice in
                Text(choice.label).tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .fixedSize()
    }

    private var locationsSummaryLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "mappin.circle")
                .font(.system(size: 10 * 1.15))
                .foregroundStyle(Theme.fgFaint)
            Text(distinctLocationsLabel)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgMute)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
    }

    private var distinctLocationsLabel: String {
        let locs: [String] = state.batchOrder.compactMap { id in
            guard let rec = state.edits.record(id),
                  let lat = rec.latitude, let lon = rec.longitude else { return nil }
            return String(format: "%.2f,%.2f", lat, lon)
        }
        let distinct = Set(locs).count
        if distinct <= 1 {
            return state.masterRecord?.place.isEmpty == false
                ? (state.masterRecord?.place ?? "")
                : "Master location only"
        }
        let other = distinct - 1
        return "\(other) other location\(other == 1 ? "" : "s") in selection"
    }

    // MARK: - Helpers

    private func sectionDivider() -> some View {
        Rectangle()
            .fill(Theme.line1.opacity(0.4))
            .frame(height: 1)
    }
}
