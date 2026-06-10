// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation
import Observation

// Pure undo/redo history. Recording, coalescing, and grouping live here;
// actually restoring values into EditStore stays in AppState (it owns the
// stores, the selection, and the save coordinator).
//
// Snapshots are whole ImageRecords -- the record is a small value type, so
// copying it twice per change is cheaper than inventing a typed per-field
// value enum. Restore reads only `field` out of the snapshot.

struct FieldChange {
    let id: String
    let field: EditableField
    let before: ImageRecord
    var after: ImageRecord
}

// A batch-draft typing step (batch mode only). Drafts are AppState-level
// transient state, not per-image records, so they snapshot whole.
struct DraftChange {
    let before: BatchDraft
    var after: BatchDraft
}

struct UndoEntry {
    var label: String              // "Edit Title", "Add Keyword 'sunset' (5 photos)"
    var changes: [FieldChange]
    var draftChange: DraftChange? = nil
    // Streaming runs (enrich, reset-location) stamp their entries with one
    // key so adjacent entries from the same run fold into a single step. A
    // user edit in between pushes a keyless entry on top, which splits the
    // run -- history stays strictly linear.
    let mergeKey: UUID?
    // The batch session this entry was recorded in (nil outside batch).
    // Lets undo detect when the chain crosses out of the live batch, so
    // AppState can drop back to single-image browsing first.
    var batchSession: UUID? = nil

    var imageCount: Int { Set(changes.map(\.id)).count }
}

@MainActor
@Observable
final class UndoStack {
    private(set) var undoEntries: [UndoEntry] = []
    private(set) var redoEntries: [UndoEntry] = []
    private let capacity = 100

    // While set, the top undo entry is "open" for this (id, field) pair and
    // further updates to the same pair replace its `after` instead of
    // pushing -- that's what collapses a typing burst into one step. Anything
    // that changes editing context (selection, a different field, a group,
    // undo/redo) closes it.
    private enum CoalescingKey: Equatable {
        case field(id: String, field: EditableField)
        case draft(String)
    }
    private var openCoalescingKey: CoalescingKey?

    // Identity of the live batch session, set by AppState while batchOrder
    // holds 2+ images. New entries are stamped with it.
    var currentSession: UUID?

    // While a group is open, record() accumulates into pendingGroup instead
    // of pushing. Depth counter tolerates nesting; the outermost label wins.
    private var groupDepth = 0
    private var pendingGroup: UndoEntry?

    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }
    var undoMenuTitle: String { undoEntries.last.map { "Undo \($0.label)" } ?? "Undo" }
    var redoMenuTitle: String { redoEntries.last.map { "Redo \($0.label)" } ?? "Redo" }

    // MARK: - Recording

    func record(id: String, field: EditableField,
                before: ImageRecord, after: ImageRecord, label: String) {
        let change = FieldChange(id: id, field: field, before: before, after: after)
        if groupDepth > 0 {
            pendingGroup?.changes.append(change)
            return
        }
        let key = CoalescingKey.field(id: id, field: field)
        if openCoalescingKey == key,
           var top = undoEntries.popLast(),
           let idx = top.changes.firstIndex(where: { $0.id == id && $0.field == field }) {
            top.changes[idx].after = after        // keep the original before
            undoEntries.append(top)
            return
        }
        push(UndoEntry(label: label, changes: [change],
                       mergeKey: nil, batchSession: currentSession))
        openCoalescingKey = key
    }

    // Batch-draft typing. Same coalescing shape as record(), keyed on the
    // draft's logical field instead of an (image, field) pair. Never grouped.
    func recordDraft(before: BatchDraft, after: BatchDraft,
                     fieldKey: String, label: String) {
        let key = CoalescingKey.draft(fieldKey)
        if openCoalescingKey == key,
           var top = undoEntries.popLast(), top.draftChange != nil {
            top.draftChange?.after = after        // keep the original before
            undoEntries.append(top)
            return
        }
        push(UndoEntry(label: label, changes: [],
                       draftChange: DraftChange(before: before, after: after),
                       mergeKey: nil, batchSession: currentSession))
        openCoalescingKey = key
    }

    // Draft entries only make sense while their batch is alive. Called when
    // the batch ends (synthesis replaces the draft with a "Batch Edit" entry,
    // or an undo walked out of the batch) so stale draft steps never linger
    // in either stack.
    func purgeDraftEntries() {
        undoEntries.removeAll { $0.draftChange != nil }
        redoEntries.removeAll { $0.draftChange != nil }
        if case .draft = openCoalescingKey { openCoalescingKey = nil }
    }

    func beginGroup(label: String, mergeKey: UUID? = nil) {
        groupDepth += 1
        guard groupDepth == 1 else { return }
        pendingGroup = UndoEntry(label: label, changes: [],
                                 mergeKey: mergeKey, batchSession: currentSession)
    }

    // labelFor lets the caller finalize the label with the actual affected
    // image count ("Batch Edit (12 photos)") once the changes are known.
    // Empty groups (every member was a no-op) are discarded.
    func endGroup(labelFor: ((Int) -> String)? = nil) {
        groupDepth -= 1
        guard groupDepth == 0 else { return }
        defer { pendingGroup = nil }
        guard var entry = pendingGroup, !entry.changes.isEmpty else { return }
        if let labelFor { entry.label = labelFor(entry.imageCount) }
        if let key = entry.mergeKey,
           let top = undoEntries.last, top.mergeKey == key {
            var merged = undoEntries.removeLast()
            merged.changes.append(contentsOf: entry.changes)
            if let labelFor { merged.label = labelFor(merged.imageCount) }
            undoEntries.append(merged)
            return
        }
        push(entry)
    }

    func breakCoalescing() {
        openCoalescingKey = nil
    }

    // MARK: - Stack ops (AppState drives the actual restore)

    func popForUndo() -> UndoEntry? {
        breakCoalescing()
        return undoEntries.popLast()
    }

    func popForRedo() -> UndoEntry? {
        breakCoalescing()
        return redoEntries.popLast()
    }

    func pushUndone(_ entry: UndoEntry) {
        redoEntries.append(entry)
    }

    // Deliberately does NOT clear redoEntries -- redoing is not a new edit.
    func pushRedone(_ entry: UndoEntry) {
        undoEntries.append(entry)
    }

    func reset() {
        undoEntries.removeAll()
        redoEntries.removeAll()
        openCoalescingKey = nil
        pendingGroup = nil
        groupDepth = 0
        currentSession = nil
    }

    private func push(_ entry: UndoEntry) {
        undoEntries.append(entry)
        redoEntries.removeAll()                   // a new edit invalidates redo
        if undoEntries.count > capacity { undoEntries.removeFirst() }
        openCoalescingKey = nil
    }
}
