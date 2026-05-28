import Foundation
import CoreGraphics

// One photo, with read-only EXIF + the mutable fields the user edits via
// the metadata pane / caption block. Editable bindings are wired up in the
// step that follows the design pass.
struct ImageRecord: Identifiable, Hashable, Sendable {

    let id: String
    let file: URL
    let sidecarURL: URL?

    let fmt: String
    let dim: CGSize
    let size: Int64
    let colorProfile: String

    let camera: String
    let lens: String
    let shutter: String
    let aperture: String
    let iso: Int
    let focal: String
    let originalCaptureDate: Date?

    var latitude: Double?
    var longitude: Double?
    let altitude: Double?
    let direction: Double?

    var headline: String
    var caption: String
    var keywords: [String]
    var captureDate: Date?
    var timezone: TZRule

    static func == (lhs: ImageRecord, rhs: ImageRecord) -> Bool {
        lhs.id == rhs.id &&
        lhs.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            == rhs.headline.trimmingCharacters(in: .whitespacesAndNewlines) &&
        lhs.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            == rhs.caption.trimmingCharacters(in: .whitespacesAndNewlines) &&
        lhs.keywords == rhs.keywords &&
        lhs.captureDate == rhs.captureDate &&
        lhs.timezone == rhs.timezone
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
