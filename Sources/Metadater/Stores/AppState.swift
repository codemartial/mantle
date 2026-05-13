import Foundation
import Observation

@MainActor
@Observable
final class AppState {

    var folderURL: URL?
    var library: [LibraryEntry] = []
    var selectedID: String?
    var status: SaveStatus = .idle
    var isScanning: Bool = false

    let thumbs = ThumbnailCache()
    let edits = EditStore()

    func bootstrap() {
        if let url = FolderBookmark.load() {
            openFolder(url)
        }
    }

    func openFolder(_ url: URL) {
        folderURL = url
        FolderBookmark.save(url)
        selectedID = nil
        status = .idle
        library = []
        thumbs.reset()
        edits.reset()
        scan(url)
    }

    private func scan(_ url: URL) {
        isScanning = true
        Task {
            let entries: [LibraryEntry] = await Task.detached(priority: .userInitiated) {
                LibraryIndex.scan(url)
            }.value
            guard self.folderURL == url else { return }
            self.library = entries
            self.isScanning = false
        }
    }

    func select(_ id: String) {
        guard selectedID != id else { return }
        selectedID = id
        ingestIfNeeded(id)
    }

    private func ingestIfNeeded(_ id: String) {
        if edits.record(id) != nil { return }
        guard let entry = library.first(where: { $0.id == id }) else { return }

        Task {
            // SidecarIO uses ExifTool first (handles RAW + sidecar merging),
            // falling back to ImageIOReader if ExifTool resources can't be
            // resolved. Per-selection latency is ~150-300ms on cold spawn;
            // daemon mode is the next optimisation pass.
            let record: ImageRecord = await Task.detached(priority: .userInitiated) {
                SidecarIO.read(file: entry.displayURL, sidecar: entry.sidecarURL)
            }.value
            guard selectedID == id else { return }
            edits.ingest(record)
        }
    }

    var folderDisplayName: String {
        folderURL?.lastPathComponent ?? ""
    }

    var selectedEntry: LibraryEntry? {
        guard let id = selectedID else { return nil }
        return library.first { $0.id == id }
    }

    var selectedRecord: ImageRecord? {
        guard let id = selectedID else { return nil }
        return edits.record(id)
    }
}
