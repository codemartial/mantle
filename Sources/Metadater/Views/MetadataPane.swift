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

                        ExifReadOnlyList(title: "Captured", items: capturedItems)
                        sectionDivider()

                        ExifReadOnlyList(title: "File", items: fileItems)
                        sectionDivider()

                        locationSection
                        sectionDivider()

                        KeywordChips(keywords: record?.keywords ?? [])
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
            let parts = [r.shutter, r.aperture].filter { !$0.isEmpty }
            return parts.joined(separator: "  -  ")
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

    private var capturedItems: [(String, String)] {
        [
            ("Date", formatDate(record?.captureDate, timezone: record?.timezone)),
            ("TZ",   tzLabel(record?.timezone)),
        ]
    }

    private func tzLabel(_ rule: TZRule?) -> String {
        guard let rule else { return "" }
        switch rule {
        case .unknown:                  return ""
        case .auto:                     return "Auto - from GPS"
        case .fixed(_, let label):      return label
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

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Location") {
                Text("Edit pin")
                    .font(.system(size: 10 * 1.15, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            // Map placeholder: dark rectangle with subtle gradient and a pin
            // dot for design preview. Real MapKit comes in a polish pass.
            mapPlaceholder

            // Lat / Lon cells
            HStack(spacing: 6) {
                geoCell(label: "LAT", value: formatCoord(record?.latitude), hemiPositive: "N", hemiNegative: "S")
                geoCell(label: "LON", value: formatCoord(record?.longitude), hemiPositive: "E", hemiNegative: "W")
            }

            // Place + altitude line
            placeLine
        }
    }

    private var mapPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Theme.bgInput)

            // Soft contour ring suggestion
            Circle()
                .strokeBorder(Theme.line1.opacity(0.7), lineWidth: 0.5)
                .frame(width: 90, height: 90)
            Circle()
                .strokeBorder(Theme.line1.opacity(0.5), lineWidth: 0.5)
                .frame(width: 56, height: 56)

            if record?.latitude != nil && record?.longitude != nil {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.25))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                        )
                }
            }
        }
        .frame(height: 110)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.line1, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func geoCell(label: String, value: String, hemiPositive: String, hemiNegative: String) -> some View {
        HStack(spacing: 0) {
            Text(value.isEmpty ? "--" : value)
                .font(.system(size: 11 * 1.15, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(value.isEmpty ? Theme.fgFaint : Theme.fg)
                .padding(.leading, 7)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Text(hemisphere(for: value, positive: hemiPositive, negative: hemiNegative))
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
                .strokeBorder(Theme.line1, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var placeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "mappin.circle")
                .font(.system(size: 10 * 1.15))
                .foregroundStyle(Theme.fgFaint)
            Text(record?.place.isEmpty == false ? (record?.place ?? "") : "Location not resolved")
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(record?.place.isEmpty == false ? Theme.fgMute : Theme.fgFaint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if let alt = record?.altitude {
                HStack(spacing: 3) {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 7 * 1.15))
                        .foregroundStyle(Theme.fgFaint)
                    Text(String(format: "%.0f m", alt))
                        .font(.system(size: 10 * 1.15, design: .monospaced))
                        .foregroundStyle(Theme.fgDim)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionDivider() -> some View {
        Rectangle()
            .fill(Theme.line1.opacity(0.4))
            .frame(height: 1)
    }

    private func formatDate(_ date: Date?, timezone: TZRule?) -> String {
        guard let date else { return "" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy / MM / dd  HH:mm:ss"
        df.timeZone = displayTimeZone(timezone)
        return df.string(from: date)
    }

    private func displayTimeZone(_ rule: TZRule?) -> TimeZone {
        if let rule, case .fixed(let mins, _) = rule {
            return TimeZone(secondsFromGMT: mins * 60) ?? TimeZone(identifier: "UTC")!
        }
        return TimeZone(identifier: "UTC")!
    }

    private func dimensions(_ dim: CGSize) -> String {
        guard dim.width > 0, dim.height > 0 else { return "" }
        return "\(Int(dim.width)) x \(Int(dim.height))"
    }

    private func formatCoord(_ c: Double?) -> String {
        guard let c else { return "" }
        return String(format: "%.4f", abs(c))
    }

    private func hemisphere(for value: String, positive: String, negative: String) -> String {
        guard !value.isEmpty else { return "--" }
        return value.first == "-" ? negative : positive
    }
}
