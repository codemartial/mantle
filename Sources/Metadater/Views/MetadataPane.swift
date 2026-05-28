import SwiftUI

// Right pane. Read-only metadata sections, in order: CAMERA, CAPTURED,
// FILE, LOCATION, KEYWORDS. Caption / headline live in the centre pane.

struct MetadataPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            if state.selectedEntry == nil {
                emptyPlaceholder
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {

                        ExifReadOnlyList(title: "Camera", items: cameraItems)
                        sectionDivider()

                        capturedSection
                        sectionDivider()

                        ExifReadOnlyList(title: "File", items: fileItems)
                        sectionDivider()

                        locationSection
                        sectionDivider()

                        KeywordChips()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyPlaceholder: some View {
        VStack {
            Spacer()
            Text("Select an image to inspect its metadata.")
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section data

    private var record: ImageRecord? { state.selectedRecord }

    private var cameraItems: [(String, String)] {
        let body = record?.camera ?? ""
        let lens = record?.lens ?? ""
        let exposure: String = {
            guard let r = record else { return "" }
            // Mathematical italic small f (U+1D453) -- the conventional
            // glyph for f-number in photographic notation, e.g. "f/2.8".
            let aperture = r.aperture.isEmpty ? "" : "\u{1D453}/\(r.aperture)"
            let parts = [r.shutter, aperture].filter { !$0.isEmpty }
            return parts.joined(separator: " ")
        }()
        let iso = record?.iso ?? 0
        let focal = record?.focal ?? ""
        return [
            ("Camera",       body),
            ("Lens",         lens),
            ("Exposure",     exposure),
            ("ISO",          iso == 0 ? "" : String(iso)),
            ("Focal length", focal),
        ]
    }

    private var capturedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Captured")
            DateEditor(
                date: Binding(
                    get: { state.selectedRecord?.captureDate },
                    set: { newDate in
                        guard let id = state.selectedID, let newDate else { return }
                        state.updateField(id: id, field: .captureDate) { $0.captureDate = newDate }
                    }
                ),
                timezone: Binding(
                    get: { state.selectedRecord?.timezone ?? .unknown },
                    set: { newTz in
                        guard let id = state.selectedID else { return }
                        state.updateField(id: id, field: .timezone) { $0.timezone = newTz }
                    }
                )
            )
        }
    }

    private var fileItems: [(String, String)] {
        [
            ("Format",     record?.fmt ?? ""),
            ("Dimensions", dimensions(record?.dim ?? .zero)),
            ("Size",       ByteSize.format(record?.size ?? 0)),
            ("Color",      record?.colorProfile ?? ""),
        ]
    }

    // MARK: - Location

    // Map aspect = original 228w x 110h design dimensions. Holding this
    // ratio constant means the map widens with the pane and grows
    // Square map: width fills the pane, height follows by aspect ratio --
    // same sizing mechanism as the original placeholder, just retuned from
    // 228:110 to 1:1 so the cone and pin have enough headroom.
    private let mapAspectRatio: CGFloat = 1.0

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Location") {
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
                    get: { state.selectedRecord?.latitude },
                    set: { newLat in
                        guard let id = state.selectedID else { return }
                        state.updateLocation(id: id, lat: newLat, lon: state.selectedRecord?.longitude)
                    }
                ),
                lon: Binding(
                    get: { state.selectedRecord?.longitude },
                    set: { newLon in
                        guard let id = state.selectedID else { return }
                        state.updateLocation(id: id, lat: state.selectedRecord?.latitude, lon: newLon)
                    }
                )
            )

            HStack(spacing: 6) {
                Button("Reset") {
                    if let id = state.selectedID {
                        state.resetLocationFromEmbedded(id: id)
                    }
                }
                .controlSize(.small)
                .disabled(state.selectedID == nil)
                .help("Re-read GPS from the image's embedded EXIF")

                Spacer()

                altitudeBadge(record?.altitude)
            }
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

    @ViewBuilder
    private func altitudeBadge(_ altitude: Double?) -> some View {
        if let alt = altitude {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 9 * 1.15, weight: .medium))
                    .foregroundStyle(Theme.fgFaint)
                Text(String(format: "%.0f m", alt))
                    .font(.system(size: 10 * 1.15, design: .monospaced))
                    .foregroundStyle(Theme.fgDim)
            }
        }
    }

    // MARK: - Helpers

    private func sectionDivider() -> some View {
        Rectangle()
            .fill(Theme.line1.opacity(0.4))
            .frame(height: 1)
    }

    private func dimensions(_ dim: CGSize) -> String {
        guard dim.width > 0, dim.height > 0 else { return "" }
        return "\(Int(dim.width)) x \(Int(dim.height))"
    }

}
