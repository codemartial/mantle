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

    // Batch editing state. Non-empty iff in batch mode. batchOrder[0] is the
    // master -- its values prefill nothing in the draft (blank = do not
    // modify), but its date / tz / location ARE editable directly through
    // the right pane in batch mode (writes flow through normal updateField).
    var batchOrder: [String] = []
    var batchDraft: BatchDraft = BatchDraft() {
        // Draft mutations land outside EditStore (synthesis happens on exit)
        // but the status pill needs to reflect the pending count so the user
        // sees their typing reflected immediately. saver is set up in init();
        // the implicit-unwrap-optional pattern keeps this safe even if Swift
        // someday fires didSet during init.
        didSet { saver?.dirtyChanged() }
    }

    // Last single-clicked ID. Pivot for Shift+Click range selection. Stays
    // around through batch entry / exit so subsequent shift-clicks anchor
    // off the right thing.
    var selectionAnchor: String?

    var mapStyle: MapStyleChoice = MapStyleChoice.load() {
        didSet { mapStyle.save() }
    }

    let thumbs = ThumbnailCache()
    let edits = EditStore()
    let debugLog = DebugLog()
    // Force-unwrapped because saver needs `self` -- assigned in init below.
    // SaveCoordinator stores AppState weakly, so the cycle is broken.
    private(set) var saver: SaveCoordinator!

    // One-shot auto-select intent. openFolder takes these as parameters so
    // the bootstrap restore path and explicit-UI-open path can both work
    // through the same async flow without racing against the reset that
    // happens inside performOpenFolder.
    private var autoSelectOnScan: Bool = false
    private var preferredSelectionID: String?

    init() {
        self.saver = SaveCoordinator(state: self)
    }

    func bootstrap() {
        if let url = FolderBookmark.load() {
            openFolder(url, autoSelect: true, preferredID: SelectionBookmark.load())
        }
    }

    func openFolder(_ url: URL, autoSelect: Bool = false, preferredID: String? = nil) {
        // Flush any pending saves from the previous folder before resetting
        // the edit store. The UI doesn't visibly change until performOpen
        // -- the user just sees a brief "Saving..." pill if needed. If a
        // batch is in flight, synthesize it first so its edits get included
        // in the flush.
        Task { [weak self] in
            guard let self else { return }
            self.exitBatch(selecting: nil)
            await self.saver.flushAll()
            self.performOpenFolder(url, autoSelect: autoSelect, preferredID: preferredID)
        }
    }

    private func performOpenFolder(_ url: URL, autoSelect: Bool, preferredID: String?) {
        folderURL = url
        FolderBookmark.save(url)
        selectedID = nil
        selectionAnchor = nil
        batchOrder = []
        batchDraft = BatchDraft()
        status = .idle
        library = []
        thumbs.reset()
        edits.reset()
        autoSelectOnScan = autoSelect
        preferredSelectionID = preferredID
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
        // Plain click while in batch mode collapses the batch (synthesize +
        // save all dirty) and lands on the clicked image. The batch-exit
        // path falls through to a fresh select on this id.
        if !batchOrder.isEmpty {
            exitBatch(selecting: id)
            return
        }
        guard selectedID != id else {
            // Even a no-op tap re-anchors for the next Shift+Click.
            selectionAnchor = id
            return
        }
        // Fire-and-forget save for the outgoing image. UI changes
        // immediately; the save runs in parallel and updates the pill.
        if let outgoing = selectedID {
            saver.requestSave(id: outgoing)
        }
        selectedID = id
        selectionAnchor = id
        SelectionBookmark.save(id)
        ingestIfNeeded(id)
    }

    // MARK: - Batch selection

    var batchMode: Bool { batchOrder.count >= 2 }
    var masterID: String? { batchOrder.first }
    var masterRecord: ImageRecord? { masterID.flatMap { edits.record($0) } }

    // Cmd+Click. If no batch yet, seed with [currentSelection, id]. If id
    // is already in the batch, remove it (collapsing to single if only one
    // remains). Otherwise append. selectedID always tracks the master so
    // PreviewPane / LocationMap stay anchored to batchOrder[0].
    func toggleBatch(_ id: String) {
        if let idx = batchOrder.firstIndex(of: id) {
            batchOrder.remove(at: idx)
            if batchOrder.count < 2 {
                let remaining = batchOrder.first ?? selectedID
                exitBatch(selecting: remaining)
            } else {
                selectedID = batchOrder[0]
            }
            return
        }
        if batchOrder.isEmpty {
            guard let sel = selectedID, sel != id else {
                // No prior selection -- just select the clicked image.
                select(id)
                return
            }
            batchOrder = [sel, id]
        } else {
            batchOrder.append(id)
        }
        selectedID = batchOrder[0]
        ingestIfNeeded(id)
    }

    // Shift+Click. Range = library-order slice from anchor to clicked id,
    // inclusive. Anchor (first in batchOrder, becomes master) is whichever
    // end was the previous single-click anchor. If no anchor, treat as a
    // plain click.
    func selectRange(to id: String) {
        let anchor = selectionAnchor ?? selectedID
        guard let anchor, anchor != id else {
            select(id)
            return
        }
        let ids = library.map { $0.id }
        guard let aIdx = ids.firstIndex(of: anchor),
              let bIdx = ids.firstIndex(of: id) else {
            select(id)
            return
        }
        let lo = min(aIdx, bIdx)
        let hi = max(aIdx, bIdx)
        let slice = Array(ids[lo...hi])
        // Master = anchor. Put it first, then the rest in library order.
        var ordered: [String] = [anchor]
        for entry in slice where entry != anchor {
            ordered.append(entry)
        }
        if ordered.count < 2 {
            select(id)
            return
        }
        batchOrder = ordered
        selectedID = batchOrder[0]
        for entry in batchOrder { ingestIfNeeded(entry) }
    }

    // Synthesize the current draft into per-id field updates, clear batch
    // state, fire saves for every dirty id, and optionally land on a new
    // selection. Safe to call when not in batch -- it's a no-op then.
    func exitBatch(selecting newID: String?) {
        guard !batchOrder.isEmpty else {
            if let newID, newID != selectedID { select(newID) }
            return
        }
        let ids = batchOrder
        synthesizeBatch()
        batchOrder = []
        batchDraft = BatchDraft()
        // Fire-and-forget saves for every id touched by synthesis. The
        // SaveCoordinator dedupes per-id so this is fine even if some ids
        // weren't actually dirtied.
        for id in ids {
            saver.requestSave(id: id)
        }
        if let newID {
            // Land on the chosen image. Skip the batch branch in select()
            // since batchOrder is already empty.
            if newID != selectedID {
                selectedID = newID
                selectionAnchor = newID
                SelectionBookmark.save(newID)
                ingestIfNeeded(newID)
            } else {
                selectionAnchor = newID
            }
        }
    }

    // Apply batchDraft to every id in batchOrder via the normal updateField
    // path. Blank-value semantics per the multi-edit feedback memory:
    // empty headline / empty captionReplace / empty captionAppend means
    // "do not modify". Date shift of (0, 0) is a no-op.
    func synthesizeBatch() {
        let draft = batchDraft
        let ids = batchOrder
        guard !ids.isEmpty else { return }

        let trimmedHeadline = draft.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplace = draft.captionReplace.trimmingCharacters(in: .whitespacesAndNewlines)

        var skipped: [String] = []
        for id in ids {
            guard let current = edits.record(id) else {
                skipped.append(id)
                continue
            }

            if !trimmedHeadline.isEmpty,
               current.headline.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedHeadline {
                updateField(id: id, field: .headline) { rec in
                    rec.headline = draft.headline
                }
            }

            switch draft.captionMode {
            case .replace:
                if !trimmedReplace.isEmpty,
                   current.caption.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedReplace {
                    updateField(id: id, field: .caption) { rec in
                        rec.caption = draft.captionReplace
                    }
                }
            case .append:
                if !draft.captionAppend.isEmpty {
                    updateField(id: id, field: .caption) { rec in
                        rec.caption = current.caption + draft.captionAppend
                    }
                }
            }

            if draft.hasDateShift, let cd = current.captureDate {
                let shifted = cd.addingTimeInterval(draft.dateShiftInterval)
                updateField(id: id, field: .captureDate) { rec in
                    rec.captureDate = shifted
                }
            }
        }
        if !skipped.isEmpty {
            debugLog.append("[batch] synthesis skipped \(skipped.count) un-ingested image\(skipped.count == 1 ? "" : "s")")
        }
    }

    // MARK: - Batch keyword broadcasts (immediate, deferred save)

    // Add `kw` to every batch image that doesn't already have it (case-
    // insensitive). Saves are deferred to batch exit (saver.requestSave is
    // not called here).
    func addKeywordToAll(_ kw: String) {
        let trimmed = kw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lower = trimmed.lowercased()
        var skipped = 0
        for id in batchOrder {
            guard let rec = edits.record(id) else {
                skipped += 1
                continue
            }
            let existingLower = Set(rec.keywords.map { $0.lowercased() })
            if existingLower.contains(lower) { continue }
            updateField(id: id, field: .keywords) { record in
                record.keywords.append(trimmed)
            }
        }
        if skipped > 0 {
            debugLog.append("[batch] add '\(trimmed)' skipped \(skipped) un-ingested image\(skipped == 1 ? "" : "s")")
        }
    }

    // Remove every case-insensitive match of `kw` from every batch image.
    func removeKeywordFromAll(_ kw: String) {
        let lower = kw.lowercased()
        var skipped = 0
        for id in batchOrder {
            guard edits.record(id) != nil else {
                skipped += 1
                continue
            }
            updateField(id: id, field: .keywords) { record in
                record.keywords.removeAll { $0.lowercased() == lower }
            }
        }
        if skipped > 0 {
            debugLog.append("[batch] remove '\(kw)' skipped \(skipped) un-ingested image\(skipped == 1 ? "" : "s")")
        }
    }

    // Promote a "some" keyword to "all" -- add it to every image that
    // doesn't have it. Same shape as addKeywordToAll; named separately so
    // the UI's intent is explicit in the call site.
    func promoteKeywordToAll(_ kw: String) {
        addKeywordToAll(kw)
    }

    // Common / some sets over the current batch. Common = present in every
    // image; some = present in at least one but not all. Both case-sensitive
    // for display (matching the single-mode case-sensitive on-disk shape).
    // Returns empty arrays when not in batch mode.
    var commonKeywords: [String] {
        guard batchMode else { return [] }
        return splitKeywords().common
    }

    var someKeywords: [String] {
        guard batchMode else { return [] }
        return splitKeywords().some
    }

    // How many per-image field changes would synthesizeBatch produce right
    // now. Mirrors the synthesis loop's conditions exactly so the status
    // pill's count matches what will actually hit the EditStore on exit.
    // Returns 0 when not in batch.
    var pendingBatchEditCount: Int {
        guard batchMode else { return 0 }
        let draft = batchDraft
        let trimmedHeadline = draft.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplace = draft.captionReplace.trimmingCharacters(in: .whitespacesAndNewlines)

        var count = 0
        for id in batchOrder {
            guard let current = edits.record(id) else { continue }

            if !trimmedHeadline.isEmpty,
               current.headline.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedHeadline {
                count += 1
            }

            switch draft.captionMode {
            case .replace:
                if !trimmedReplace.isEmpty,
                   current.caption.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedReplace {
                    count += 1
                }
            case .append:
                if !draft.captionAppend.isEmpty {
                    count += 1
                }
            }

            if draft.hasDateShift, current.captureDate != nil {
                count += 1
            }
        }
        return count
    }

    private func splitKeywords() -> (common: [String], some: [String]) {
        // Build a case-insensitive presence map: lowercased keyword ->
        // (firstSeenForm, count across batch). Then partition by whether
        // count == batchOrder.count. Display the first-seen casing.
        var firstForm: [String: String] = [:]
        var count: [String: Int] = [:]
        for id in batchOrder {
            guard let rec = edits.record(id) else { continue }
            var seenInThisImage: Set<String> = []
            for raw in rec.keywords {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                let lower = trimmed.lowercased()
                if seenInThisImage.contains(lower) { continue }
                seenInThisImage.insert(lower)
                if firstForm[lower] == nil { firstForm[lower] = trimmed }
                count[lower, default: 0] += 1
            }
        }
        let total = batchOrder.count
        var common: [String] = []
        var some: [String] = []
        for (lower, n) in count {
            let display = firstForm[lower] ?? lower
            if n == total { common.append(display) }
            else { some.append(display) }
        }
        common.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        some.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return (common, some)
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
            // Commit the ingest if the id is still relevant -- either it is
            // the single selection, OR it is a member of the current batch.
            // The batch case is the one that bit us: in batch mode selectedID
            // pins to master, so without the batchOrder check every other
            // batch member's ingest would be dropped on the floor.
            guard selectedID == id || batchOrder.contains(id) else { return }
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

    // Map pin drag and GeoCells text commit both end here. Lat or lon nil
    // (e.g. user clears one cell) is a valid state; the writer will emit
    // empty XMP-exif tags to scrub the sidecar back to no-coord.
    func updateLocation(id: String, lat: Double?, lon: Double?) {
        updateField(id: id, field: .location) {
            $0.latitude = lat
            $0.longitude = lon
        }
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
