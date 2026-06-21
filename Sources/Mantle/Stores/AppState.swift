// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class AppState {

    var folderURL: URL?
    var library: [LibraryEntry] = []
    var selectedID: String? {
        didSet {
            // Switching images closes the open typing-coalescing window --
            // returning to an image later starts a fresh undo step.
            if selectedID != oldValue {
                undo.breakCoalescing()
            }
        }
    }
    var status: SaveStatus = .idle
    var isScanning: Bool = false

    // Browser-grid filter. The grid renders `visibleLibrary` instead of
    // `library` whenever this is active.
    var filter = LibraryFilter() {
        didSet { reconcileSelectionWithFilter() }
    }

    // Browser-grid sort direction (filename only). Drives the order of
    // `visibleLibrary`, so a shift-range selection always follows what the
    // user sees. In-memory only -- defaults to ascending each launch.
    var sortOrder: LibrarySortOrder = .nameAscending

    // Title + keywords for every file, read by a background sweep on folder
    // open (MetadataIndex). A missing id means not yet swept (treated as
    // unknown -- the file stays visible until classified); an empty headline
    // or empty keywords means known-absent. Live edits in EditStore take
    // precedence over this cache.
    private(set) var sweptMeta: [String: SweptMetadata] = [:]
    // >0 while the metadata sweep is running, for the toolbar's progress hint.
    private(set) var headlineSweepRemaining: Int = 0

    // Batch editing state. Non-empty iff in batch mode. batchOrder[0] is the
    // master -- its values prefill nothing in the draft (blank = do not
    // modify), but its date / tz / location ARE editable directly through
    // the right pane in batch mode (writes flow through normal updateField).
    var batchOrder: [String] = [] {
        // Each live batch gets one session identity; undo entries recorded
        // while it is active carry it, so performUndo can tell when the
        // chain walks out of the current batch's history.
        didSet {
            if batchOrder.count >= 2 {
                if undo.currentSession == nil { undo.currentSession = UUID() }
            } else {
                undo.currentSession = nil
            }
        }
    }
    var batchDraft: BatchDraft = BatchDraft() {
        // Draft mutations land outside EditStore (synthesis happens on exit)
        // but the status pill needs to reflect the pending count so the user
        // sees their typing reflected immediately. saver is set up in init();
        // the implicit-unwrap-optional pattern keeps this safe even if Swift
        // someday fires didSet during init.
        //
        // Draft typing is also undoable: every binding write lands here with
        // its old value, so this didSet is the single capture point -- the
        // batch-mode counterpart of updateField. Programmatic resets are
        // filtered out because they happen after batchOrder is cleared
        // (batchMode false) or during history replay (isRestoringHistory).
        didSet {
            saver?.dirtyChanged()
            guard batchMode, !isRestoringHistory, oldValue != batchDraft,
                  let diff = BatchDraft.changedField(oldValue, batchDraft) else { return }
            undo.recordDraft(before: oldValue, after: batchDraft,
                             fieldKey: diff.key, label: diff.label)
        }
    }

    // Last single-clicked ID. Pivot for Shift+Click range selection. Stays
    // around through batch entry / exit so subsequent shift-clicks anchor
    // off the right thing.
    var selectionAnchor: String?

    // Bumped when a downstream binding refuses to write (e.g. nil location
    // in batch mode). Views observing this token re-seed their local
    // input state from the binding's current value -- the only way to
    // visually snap a cleared cell back to its bound value when the
    // binding's wrappedValue itself never changed.
    var geoReseedTick: Int = 0

    // Bumped to ask the LocationMap to recentre on the selected record's
    // current pin. Driven by the map's recentre button and by a coordinate
    // paste. Distinct from geoReseedTick, which re-seeds the GeoCells inputs.
    var mapRecenterTick: Int = 0

    var mapStyle: MapStyleChoice = MapStyleChoice.load() {
        didSet { mapStyle.save() }
    }

    var batchRatingNumberShortcut: BatchRatingNumberShortcutPreference =
        BatchRatingNumberShortcutPreference.load() {
        didSet { batchRatingNumberShortcut.save() }
    }

    let thumbs = ThumbnailCache()
    let edits = EditStore()
    let undo = UndoStack()
    let debugLog = DebugLog()

    // True while performUndo/performRedo replays snapshots through
    // updateField -- the replay must not record fresh history.
    private var isRestoringHistory = false

    // Transient "Undid Batch Edit (5 photos)" message for the StatusBar,
    // auto-cleared after a few seconds (same shape as the enricher summary).
    private(set) var undoToast: String?
    private var undoToastTask: Task<Void, Never>?
    // Force-unwrapped because saver needs `self` -- assigned in init below.
    // SaveCoordinator stores AppState weakly, so the cycle is broken.
    private(set) var saver: SaveCoordinator!

    // One-shot auto-select intent. openFolder takes these as parameters so
    // the bootstrap restore path and explicit-UI-open path can both work
    // through the same async flow without racing against the reset that
    // happens inside performOpenFolder.
    private var autoSelectOnScan: Bool = false
    private var preferredSelectionID: String?
    // When the preferred id isn't in the freshly scanned library, fall back to
    // selecting the first entry. True for a plain open; false for rescan, where
    // a vanished selection should land on nothing rather than jumping.
    private var fallbackToFirstOnScan: Bool = true

    init() {
        self.saver = SaveCoordinator(state: self)
    }

    func bootstrap() {
        if let url = FolderBookmark.load() {
            openFolder(url, autoSelect: true, preferredID: SelectionBookmark.load())
        }
    }

    // Re-open the current folder: full reset + rescan, keeping the current
    // selection if its file survives (otherwise no selection). Reuses
    // openFolder so the flush-then-reset pipeline persists pending edits first.
    func rescan() {
        guard let url = folderURL else { return }
        openFolder(url, autoSelect: true, preferredID: selectedID,
                   fallbackToFirst: false)
    }

    func openFolder(_ url: URL, autoSelect: Bool = false, preferredID: String? = nil,
                    fallbackToFirst: Bool = true) {
        // Flush any pending saves from the previous folder before resetting
        // the edit store. The UI doesn't visibly change until performOpen
        // -- the user just sees a brief "Saving..." pill if needed. If a
        // batch is in flight, synthesize it first so its edits get included
        // in the flush.
        Task { [weak self] in
            guard let self else { return }
            self.exitBatch(selecting: nil)
            await self.saver.flushAll()
            self.performOpenFolder(url, autoSelect: autoSelect, preferredID: preferredID,
                                   fallbackToFirst: fallbackToFirst)
        }
    }

    private func performOpenFolder(_ url: URL, autoSelect: Bool, preferredID: String?,
                                   fallbackToFirst: Bool) {
        folderURL = url
        FolderBookmark.save(url)
        selectedID = nil
        selectionAnchor = nil
        batchOrder = []
        batchDraft = BatchDraft()
        status = .idle
        library = []
        sweptMeta = [:]
        headlineSweepRemaining = 0
        thumbs.reset()
        edits.reset()
        undo.reset()
        undoToastTask?.cancel()
        undoToast = nil
        autoSelectOnScan = autoSelect
        preferredSelectionID = preferredID
        fallbackToFirstOnScan = fallbackToFirst
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
            self.sweepHeadlines(for: url, entries: entries)
        }
    }

    // One-time background metadata sweep so the headline / keyword filters
    // can classify every file, not just the lazily-ingested selection. Reads
    // all titles and keywords in a single exiftool pass off the main actor.
    // Bails if the folder changed out from under us before the read finished.
    private func sweepHeadlines(for url: URL, entries: [LibraryEntry]) {
        guard !entries.isEmpty else { return }
        headlineSweepRemaining = entries.count
        Task {
            let meta: [String: SweptMetadata] = await Task.detached(priority: .utility) {
                MetadataIndex.scan(entries: entries)
            }.value
            guard self.folderURL == url else { return }
            self.sweptMeta = meta
            self.headlineSweepRemaining = 0
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
        if fallbackToFirstOnScan, let first = library.first {
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

    var commonBatchRating: Int? {
        guard batchMode else { return nil }
        var common: Int?
        for id in batchOrder {
            guard let rating = edits.record(id)?.rating else { continue }
            if let existing = common, existing != rating { return nil }
            common = rating
        }
        return common
    }

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
        // Range spans the *visible* grid order, so a shift-range never pulls
        // in rows hidden by the active filter.
        let ids = visibleLibrary.map { $0.id }
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
        // The synthesized "Batch Edit" entry supersedes the draft-typing
        // steps; without the live draft they would replay into nothing.
        undo.purgeDraftEntries()
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
        withUndoGroup(label: "Batch Edit",
                      labelFor: { "Batch Edit (\(Self.photoCount($0)))" }) {
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
                    let trimmedAppend = draft.captionAppend.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedAppend.isEmpty {
                        let trimmedPrior = current.caption.trimmingCharacters(in: .whitespacesAndNewlines)
                        let merged = trimmedPrior.isEmpty
                            ? trimmedAppend
                            : trimmedPrior + "\n\n" + trimmedAppend
                        updateField(id: id, field: .caption) { rec in
                            rec.caption = merged
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
        withUndoGroup(label: "Add Keyword",
                      labelFor: { "Add Keyword '\(trimmed)' (\(Self.photoCount($0)))" }) {
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
        }
        if skipped > 0 {
            debugLog.append("[batch] add '\(trimmed)' skipped \(skipped) un-ingested image\(skipped == 1 ? "" : "s")")
        }
    }

    // Remove every case-insensitive match of `kw` from every batch image.
    func removeKeywordFromAll(_ kw: String) {
        let lower = kw.lowercased()
        var skipped = 0
        withUndoGroup(label: "Remove Keyword",
                      labelFor: { "Remove Keyword '\(kw)' (\(Self.photoCount($0)))" }) {
            for id in batchOrder {
                guard edits.record(id) != nil else {
                    skipped += 1
                    continue
                }
                updateField(id: id, field: .keywords) { record in
                    record.keywords.removeAll { $0.lowercased() == lower }
                }
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

    // Re-read the file's embedded GPS (image only, sidecar ignored) and
    // overwrite the in-memory location for that image. Useful for repairing
    // a sidecar whose hemisphere got flipped by a past bug -- the embedded
    // GPS in the parent file is the canonical source of truth. No-op when
    // the file has no embedded GPS coords.
    func resetLocationFromEmbedded(id: String, mergeKey: UUID? = nil) {
        guard let entry = library.first(where: { $0.id == id }) else { return }
        let entryURL = entry.displayURL
        Task { [weak self] in
            let embedded = await Task.detached(priority: .userInitiated) {
                SidecarIO.read(file: entryURL, sidecar: nil)
            }.value
            guard let self else { return }
            // Only apply if the file actually has embedded coords; otherwise
            // we'd silently wipe a user-set location.
            if embedded.latitude != nil || embedded.longitude != nil {
                // Each completion arrives in its own main-actor hop; the
                // shared mergeKey folds a batch run's completions into one
                // undo step as long as nothing else lands in between.
                self.withUndoGroup(label: "Reset Location",
                                   mergeKey: mergeKey,
                                   labelFor: { "Reset Location (\(Self.photoCount($0)))" }) {
                    self.updateLocation(id: id, lat: embedded.latitude, lon: embedded.longitude)
                }
            } else {
                self.debugLog.append("[reset] \(entry.basename): no embedded GPS")
            }
        }
    }

    // Batch variant -- re-read every batch member's own embedded GPS into
    // its own record. Skips members whose parent files have no embedded GPS.
    func resetLocationFromEmbeddedForAllBatch() {
        guard batchMode else { return }
        let runKey = UUID()
        for id in batchOrder {
            resetLocationFromEmbedded(id: id, mergeKey: runKey)
        }
    }

    // Copy the master's current lat / lon onto every other batch member.
    // No-op for master itself (already there). Saves are deferred to batch
    // exit, same shape as the keyword broadcasts.
    func applyMasterLocationToAll() {
        guard batchMode, let master = masterRecord else { return }
        let lat = master.latitude
        let lon = master.longitude
        var skipped = 0
        withUndoGroup(label: "Apply Location",
                      labelFor: { "Apply Location (\(Self.photoCount($0)))" }) {
            for id in batchOrder where id != master.id {
                guard edits.record(id) != nil else {
                    skipped += 1
                    continue
                }
                updateLocation(id: id, lat: lat, lon: lon)
            }
        }
        if skipped > 0 {
            debugLog.append("[batch] apply location skipped \(skipped) un-ingested image\(skipped == 1 ? "" : "s")")
        }
    }

    // Set the capture timezone on the master and every other batch member.
    // Unlike location (where per-image coords legitimately differ and
    // broadcast is opt-in via a button), a batch shares one capture timezone,
    // so the picker applies its value across the whole selection.
    //
    // The offset is re-resolved per image against that image's own capture
    // date, so a batch straddling a DST change (e.g. shots on either side of
    // a spring-forward) gets the right offset for each shot instead of the
    // single offset that happened to be resolved for the master. Saves are
    // deferred to batch exit.
    func applyTimezoneToAll(_ tz: TZRule) {
        guard batchMode else { return }
        var skipped = 0
        withUndoGroup(label: "Apply Time Zone",
                      labelFor: { "Apply Time Zone (\(Self.photoCount($0)))" }) {
            for id in batchOrder {
                guard let record = edits.record(id) else {
                    skipped += 1
                    continue
                }
                let resolved = timezoneResolved(tz, at: record.captureDate)
                updateField(id: id, field: .timezone) { $0.timezone = resolved }
            }
        }
        if skipped > 0 {
            debugLog.append("[batch] apply timezone skipped \(skipped) un-ingested image\(skipped == 1 ? "" : "s")")
        }
    }

    // Re-resolve a picked timezone's offset against a specific capture date so
    // DST is honoured per image. The picker stores the IANA zone id as the
    // .fixed label, which we re-resolve here. Everything else passes through
    // unchanged: .auto / .unknown carry no offset, a .fixed whose label isn't
    // a zone id (e.g. a raw offset read from disk) has no zone to re-resolve,
    // and a date-less image has nothing to resolve against.
    private func timezoneResolved(_ tz: TZRule, at date: Date?) -> TZRule {
        guard let date,
              case .fixed(_, let label) = tz,
              TimeZone(identifier: label) != nil else { return tz }
        return TZOptions.rule(for: label, at: date)
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
                if !draft.captionAppend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
    //
    // Every mutation path in the app funnels through here, so this is also
    // the single capture point for undo: snapshot before/after around the
    // transform and record the change (unless we're replaying history, or
    // the change is a semantic no-op).
    func updateField(id: String,
                     field: EditableField,
                     _ transform: (inout ImageRecord) -> Void) {
        let before = edits.record(id)        // nil -> edits.update no-ops too
        edits.update(id, field: field, transform)
        if !isRestoringHistory,
           let before, let after = edits.record(id),
           !field.equals(before, after) {
            undo.record(id: id, field: field, before: before, after: after,
                        label: "Edit \(field.displayName)")
        }
        saver.dirtyChanged()
    }

    // MARK: - Undo / redo

    // Collect every updateField inside `body` into ONE undo entry, so a
    // batch operation undoes atomically. labelFor finalizes the label with
    // the count of images actually changed (no-ops record nothing, so the
    // count never overstates). mergeKey lets async streaming runs (enrich)
    // fold adjacent groups from the same run into a single step.
    func withUndoGroup(label: String,
                       mergeKey: UUID? = nil,
                       labelFor: ((Int) -> String)? = nil,
                       _ body: () -> Void) {
        undo.beginGroup(label: label, mergeKey: mergeKey)
        body()
        undo.endGroup(labelFor: labelFor)
    }

    func performUndo() {
        // Peek before popping: leaving the batch needs confirmation, and a
        // declined confirmation must leave the entry on the stack.
        guard let next = undo.undoEntries.last else { return }
        if historyLeavesBatch(next) {
            guard confirmLeaveBatch(direction: "undo") else { return }
        }
        guard let entry = undo.popForUndo() else { return }
        if historyLeavesBatch(entry) { exitBatchForHistory() }
        apply(entry: entry, useBefore: true)
        undo.pushUndone(entry)
        surfaceHistoryResult(entry, verb: "Undid")
    }

    func performRedo() {
        guard let next = undo.redoEntries.last else { return }
        if historyLeavesBatch(next) {
            guard confirmLeaveBatch(direction: "redo") else { return }
        }
        guard let entry = undo.popForRedo() else { return }
        if historyLeavesBatch(entry) { exitBatchForHistory() }
        apply(entry: entry, useBefore: false)
        undo.pushRedone(entry)
        surfaceHistoryResult(entry, verb: "Redid")
    }

    // An entry from outside the live batch session means the user has
    // finished unwinding the batch's own history and the next step would
    // walk older, non-batch changes.
    private func historyLeavesBatch(_ entry: UndoEntry) -> Bool {
        batchMode && entry.batchSession != undo.currentSession
    }

    // Exiting the batch via undo is irreversible (redo cannot resurrect the
    // selection), so gate it on an explicit choice. The alert is modal:
    // mashed Cmd+Z presses are swallowed while it is up, and "Stay in Batch"
    // is the default button -- so holding/mashing undo unwinds every batch
    // change, lands here, and a stray Return keeps the batch. That makes
    // mash-Cmd+Z a legitimate "clear all batch changes" gesture.
    private func confirmLeaveBatch(direction: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Leave the batch selection?"
        alert.informativeText = """
            The next \(direction) step changes images outside this batch. \
            Continuing exits the batch selection, and redo cannot restore it. \
            Staying keeps the batch; steps already \(direction == "undo" ? "undone" : "redone") are unaffected.
            """
        alert.addButton(withTitle: "Stay in Batch")   // default (Return)
        alert.addButton(withTitle: "Leave Batch")
        return alert.runModal() == .alertSecondButtonReturn
    }

    // Drop back to single-image browsing so each further history step is
    // visible (surfaceHistoryResult selects the affected image).
    //
    // The stack is LIFO, so every batch-scoped entry -- including all draft
    // typing -- sits above the boundary and has already been undone; the
    // draft is therefore empty and discarding it loses nothing. Skipping
    // synthesis (vs. exitBatch) also guarantees the exit can't push a fresh
    // entry in the middle of an undo gesture. Member saves still fire,
    // persisting whatever the unwinding restored.
    private func exitBatchForHistory() {
        let ids = batchOrder
        batchOrder = []          // didSet clears undo.currentSession
        batchDraft = BatchDraft()
        undo.purgeDraftEntries()
        for id in ids { saver.requestSave(id: id) }
    }

    private func apply(entry: UndoEntry, useBefore: Bool) {
        isRestoringHistory = true
        defer { isRestoringHistory = false }
        if let draft = entry.draftChange, batchMode {
            batchDraft = useBefore ? draft.before : draft.after
        }
        // Undo replays in reverse so stacked changes to the same field
        // within one group unwind correctly; redo replays forward.
        let ordered = useBefore ? entry.changes.reversed() : Array(entry.changes)
        for change in ordered {
            let snapshot = useBefore ? change.before : change.after
            edits.update(change.id, field: change.field) { rec in
                change.field.apply(from: snapshot, into: &rec)
            }
        }
        saver.dirtyChanged()
    }

    // Make the result of an undo/redo visible. A single-image entry jumps
    // to that image (unless we're in batch mode -- select() would exit the
    // batch and synthesize the draft, far too destructive for an undo).
    // Everything else gets a transient StatusBar toast.
    private func surfaceHistoryResult(_ entry: UndoEntry, verb: String) {
        // Draft steps revert visibly in the batch form itself.
        if entry.draftChange != nil { return }
        let ids = Set(entry.changes.map(\.id))
        if ids.count == 1, let id = ids.first, !batchMode {
            if selectedID != id { select(id) }
            return
        }
        showUndoToast("\(verb) \(entry.label)")
    }

    private func showUndoToast(_ message: String) {
        undoToastTask?.cancel()
        undoToast = message
        undoToastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.undoToast = nil
        }
    }

    static func photoCount(_ n: Int) -> String {
        "\(n) photo\(n == 1 ? "" : "s")"
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

    // Star rating set from the preview overlay. Clamped to 0...5; 0 clears
    // the rating. Routes through updateField so it dirties, saves, and undoes
    // like every other field.
    func updateRating(id: String, to value: Int) {
        let clamped = max(0, min(5, value))
        updateField(id: id, field: .rating) { $0.rating = clamped }
    }

    func applyRatingToAll(_ value: Int) {
        let clamped = max(0, min(5, value))
        let ids = batchOrder
        guard !ids.isEmpty else { return }

        withUndoGroup(label: "Edit Batch Rating",
                      labelFor: { "Edit Batch Rating (\(Self.photoCount($0)))" }) {
            for id in ids {
                guard edits.record(id) != nil else { continue }
                updateField(id: id, field: .rating) { $0.rating = clamped }
            }
        }
    }

    // Ask the LocationMap to recentre on the selected record's pin. The map
    // observes mapRecenterTick and pans to the current coordinate when it
    // changes. Used by the recentre button and after a coordinate paste.
    func recenterMap() {
        mapRecenterTick &+= 1
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

    // MARK: - Filtering

    // The best-known headline for an id: a live (possibly unsaved) edit wins
    // over the sweep cache, so toggling a title in the right pane re-filters
    // immediately. Returns nil when neither source knows yet (unknown).
    func headlineValue(for id: String) -> String? {
        if let rec = edits.record(id) { return rec.headline }
        return sweptMeta[id]?.headline
    }

    // Same shape as headlineValue, for keywords. nil == not yet swept.
    func keywordsValue(for id: String) -> [String]? {
        if let rec = edits.record(id) { return rec.keywords }
        return sweptMeta[id]?.keywords
    }

    // Same shape as headlineValue, for rating. nil == not yet swept; 0 means
    // known unrated.
    func ratingValue(for id: String) -> Int? {
        if let rec = edits.record(id) { return rec.rating }
        return sweptMeta[id]?.rating
    }

    // The distinct keyword vocabulary across the whole folder, for filter
    // autocomplete. Union of the swept metadata and any live (session-edited)
    // records, deduped case-insensitively but keeping each keyword's existing
    // casing -- so a folder tagged "Beach" offers "Beach", not whatever case
    // the user types. Sorted case-insensitively. Deterministic: ids are
    // walked in sorted order, first-seen casing wins on conflict.
    var keywordVocabulary: [String] {
        var display: [String: String] = [:]   // lowercased -> canonical form
        let ids = Set(sweptMeta.keys).union(edits.images.keys).sorted()
        for id in ids {
            guard let kws = keywordsValue(for: id) else { continue }
            for kw in kws {
                let t = kw.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                let lower = t.lowercased()
                if display[lower] == nil { display[lower] = t }
            }
        }
        return display.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // Close out the current edit session before the filter dialog opens, so
    // a filter can't strand unsaved edits on files it hides -- or fragment a
    // batch whose draft edits aren't in EditStore yet. Batch: synthesize +
    // save every member, then collapse to the master. Single: save the
    // selected file if it's dirty. A no-op when there's nothing to flush.
    func flushBeforeFilter() {
        if !batchOrder.isEmpty {
            exitBatch(selecting: selectedID)
        } else if let sel = selectedID, edits.isDirty(sel) {
            saver.requestSave(id: sel)
        }
    }

    // Evaluate one attribute against one entry. Returns nil when the answer
    // is not yet known (headline sweep still in flight for this file) so the
    // caller can keep the file visible until it's classified.
    func matches(_ entry: LibraryEntry, _ attr: FilterAttribute, _ f: AttributeFilter) -> Bool? {
        switch attr {
        case .xmp:
            let has = entry.sidecarURL != nil   // always known from the scan
            switch f {
            case .present:    return has
            case .absent:     return !has
            case .ignore, .matches, .chips, .ratings: return true  // xmp is binary; no match status
            }
        case .headline:
            guard let value = headlineValue(for: entry.id) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch f {
            case .ignore:        return true
            case .present:       return !trimmed.isEmpty
            case .absent:        return trimmed.isEmpty
            case .matches(let q):
                let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
                return query.isEmpty || trimmed.localizedCaseInsensitiveContains(query)
            case .chips, .ratings:
                return true   // headline has no chip / rating mode
            }
        case .rating:
            guard let value = ratingValue(for: entry.id) else { return nil }
            let rating = max(0, min(5, value))
            switch f {
            case .ignore:        return true
            case .present:       return rating > 0
            case .absent:        return rating == 0
            case .ratings(let selected):
                let valid = Set(selected.filter { (1...5).contains($0) })
                return valid.isEmpty || valid.contains(rating)
            case .matches, .chips:
                return true   // rating has no text / chip mode
            }
        case .keywords:
            guard let kw = keywordsValue(for: entry.id) else { return nil }
            switch f {
            case .ignore:   return true
            case .present:  return !kw.isEmpty
            case .absent:   return kw.isEmpty
            case .matches:  return true        // keywords use chips, not text
            case .ratings:  return true        // keywords have no rating mode
            case .chips(let chips):
                // Exact, case-insensitive. File must carry every include chip
                // and none of the exclude chips. Blank-text chips are dropped.
                let have = Set(kw.map { $0.lowercased() })
                func key(_ c: FilterChip) -> String? {
                    let t = c.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return t.isEmpty ? nil : t
                }
                let includes = chips.filter { !$0.exclude }.compactMap(key)
                let excludes = chips.filter { $0.exclude }.compactMap(key)
                return includes.allSatisfy { have.contains($0) }
                    && excludes.allSatisfy { !have.contains($0) }
            }
        }
    }

    // The entries the browser grid renders. Applies the active filter with
    // the .all / .any combinator, then the current sort order. An undecidable
    // (nil) attribute result does NOT hide the file while the sweep is still
    // loading -- it's treated as a pass so files stay visible and re-filter
    // reactively as titles arrive.
    var visibleLibrary: [LibraryEntry] {
        let filtered: [LibraryEntry] = {
            guard filter.isActive else { return library }
            let active = filter.activeAttributes
            return library.filter { entry in
                switch filter.combine {
                case .all:
                    return active.allSatisfy { attr in
                        matches(entry, attr, filter.status(attr)) ?? true
                    }
                case .any:
                    return active.contains { attr in
                        matches(entry, attr, filter.status(attr)) == true
                    }
                }
            }
        }()
        return sorted(filtered)
    }

    // Order entries by filename per the current sort direction. LibraryIndex
    // already scans in ascending name order, but sorting here keeps the grid
    // and shift-range selection consistent regardless of scan order.
    private func sorted(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.sorted { a, b in
            let cmp = a.basename.localizedCaseInsensitiveCompare(b.basename)
            return sortOrder == .nameAscending
                ? cmp == .orderedAscending
                : cmp == .orderedDescending
        }
    }

    // When the active filter changes, the selected file may no longer be in
    // the visible set. Leaving it selected keeps it in the preview and right
    // pane, which reads as "this file matched the filter" when it didn't.
    // Drop the selection (saving any pending edit first, as a normal deselect
    // does) so the preview follows the filtered grid's empty state. Batch mode
    // is already collapsed via flushBeforeFilter before the dialog opens, so
    // only single selection needs reconciling here.
    private func reconcileSelectionWithFilter() {
        guard let id = selectedID, filter.isActive else { return }
        if !visibleLibrary.contains(where: { $0.id == id }) {
            saver.requestSave(id: id)
            selectedID = nil
        }
    }
}
