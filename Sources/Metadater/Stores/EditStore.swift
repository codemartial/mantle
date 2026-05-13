import Foundation
import Observation

@MainActor
@Observable
final class EditStore {
    private(set) var images: [String: ImageRecord] = [:]
    private(set) var lastSaved: [String: ImageRecord] = [:]

    func ingest(_ record: ImageRecord) {
        images[record.id] = record
        lastSaved[record.id] = record
    }

    func record(_ id: String) -> ImageRecord? {
        images[id]
    }

    func reset() {
        images.removeAll(keepingCapacity: false)
        lastSaved.removeAll(keepingCapacity: false)
    }
}
