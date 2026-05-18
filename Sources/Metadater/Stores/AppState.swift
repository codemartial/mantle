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
    let debugLog = DebugLog()
    // Force-unwrapped because saver needs `self` -- assigned in init below.
    // SaveCoordinator stores AppState weakly, so the cycle is broken.
    private(set) var saver: SaveCoordinator!

    // One-shot auto-select intent. Bootstrap sets these AFTER calling
    // openFolder (which clears them) so the post-scan completion can
    // restore the previously-open file. Explicit UI folder opens leave
    // both nil so selection stays under the user's control.
    private var autoSelectOnScan: Bool = false
    private var preferredSelectionID: String?

    init() {
        self.saver = SaveCoordinator(state: self)
    }

    func bootstrap() {
        if let url = FolderBookmark.load() {
            openFolder(url)
            autoSelectOnScan = true
            preferredSelectionID = SelectionBookmark.load()
        }
    }

    func openFolder(_ url: URL) {
        // Flush any pending saves from the previous folder before resetting
        // the edit store. The UI doesn't visibly change until performOpen
        // -- the user just sees a brief "Saving..." pill if needed.
        Task { [weak self] in
            guard let self else { return }
            await self.saver.flushAll()
            self.performOpenFolder(url)
        }
    }

    private func performOpenFolder(_ url: URL) {
        folderURL = url
        FolderBookmark.save(url)
        selectedID = nil
        status = .idle
        library = []
        thumbs.reset()
        edits.reset()
        autoSelectOnScan = false
        preferredSelectionID = nil
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
            if autoSelectOnScan {
                autoSelectOnScan = false
                applyInitialSelection()
            }
        }
    }

    // Bootstrap restoration. Prefer the file we left open last quit; if
    // it's not in the current library (moved / deleted / renamed), pick
    // the first entry so the app always lands on something useful.
    private func applyInitialSelection() {
        let preferred = preferredSelectionID
        preferredSelectionID = nil

        if let preferred, library.contains(where: { $0.id == preferred }) {
            select(preferred)
            return
        }
        if let first = library.first {
            select(first.id)
        }
    }

    func select(_ id: String) {
        guard selectedID != id else { return }
        // Fire-and-forget save for the outgoing image. UI changes
        // immediately; the save runs in parallel and updates the pill.
        if let outgoing = selectedID {
            saver.requestSave(id: outgoing)
        }
        selectedID = id
        SelectionBookmark.save(id)
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

    // MARK: - Edit propagation

    // Single entry point for view-driven edits. Routes through EditStore
    // (which recomputes the field's dirty bit) and then asks the saver
    // to refresh the status pill -- but does NOT trigger a save. That
    // only happens at image-session boundaries.
    func updateField(id: String,
                     field: EditableField,
                     _ transform: (inout ImageRecord) -> Void) {
        edits.update(id, field: field, transform)
        saver.dirtyChanged()
    }

    // Called by SaveCoordinator after a successful write. If a fresh
    // sidecar was created, patch the matching LibraryEntry so the status
    // bar's ".xmp sidecar (new)" pill drops the "(new)".
    func adoptSidecar(id: String, url: URL) {
        guard let idx = library.firstIndex(where: { $0.id == id }) else { return }
        let old = library[idx]
        guard old.sidecarURL == nil else { return }
        library[idx] = LibraryEntry(
            id: old.id,
            basename: old.basename,
            displayURL: old.displayURL,
            siblingURLs: old.siblingURLs,
            sidecarURL: url,
            format: old.format,
            displaySize: old.displaySize
        )
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
