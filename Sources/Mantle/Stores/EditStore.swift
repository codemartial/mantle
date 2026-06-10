// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation
import Observation

@MainActor
@Observable
final class EditStore {
    private(set) var images: [String: ImageRecord] = [:]
    private(set) var lastSaved: [String: ImageRecord] = [:]
    private(set) var dirty: [String: Set<EditableField>] = [:]

    func ingest(_ record: ImageRecord) {
        images[record.id] = record
        lastSaved[record.id] = record
        dirty[record.id] = nil
    }

    func record(_ id: String) -> ImageRecord? {
        images[id]
    }

    // Apply a per-field mutation to the in-memory record, then recompute
    // the dirty bit for that field by semantic-comparing current vs the
    // last-saved baseline. Reversing the edit (typing "foo" then deleting
    // back) naturally clears the bit -- the comparison drives the set
    // membership, not a write-once "ever touched" flag.
    func update(_ id: String, field: EditableField, _ transform: (inout ImageRecord) -> Void) {
        guard var rec = images[id] else { return }
        transform(&rec)
        images[id] = rec
        recomputeDirty(id: id, field: field)
    }

    private func recomputeDirty(id: String, field: EditableField) {
        guard let current = images[id], let baseline = lastSaved[id] else { return }
        var set = dirty[id] ?? []
        if field.equals(current, baseline) {
            set.remove(field)
        } else {
            set.insert(field)
        }
        if set.isEmpty { dirty[id] = nil } else { dirty[id] = set }
    }

    // Apply snapshot values (NOT current images[id] values -- that's the
    // invariant that lets a mid-flight edit survive markSaved without
    // being falsely marked clean) into lastSaved for the listed fields,
    // then recompute dirty for those fields against current images[id].
    func markSaved(_ id: String, fields: Set<EditableField>, snapshot: ImageRecord) {
        if lastSaved[id] == nil {
            lastSaved[id] = snapshot
        } else {
            var baseline = lastSaved[id]!
            for f in fields {
                f.apply(from: snapshot, into: &baseline)
            }
            lastSaved[id] = baseline
        }
        for f in fields { recomputeDirty(id: id, field: f) }
    }

    func dirtyFields(_ id: String) -> Set<EditableField> {
        dirty[id] ?? []
    }

    func isDirty(_ id: String) -> Bool {
        !(dirty[id]?.isEmpty ?? true)
    }

    var totalDirtyCount: Int {
        dirty.values.reduce(0) { $0 + $1.count }
    }

    var allDirtyIDs: [String] {
        dirty.compactMap { $0.value.isEmpty ? nil : $0.key }
    }

    func reset() {
        images.removeAll(keepingCapacity: false)
        lastSaved.removeAll(keepingCapacity: false)
        dirty.removeAll(keepingCapacity: false)
    }
}
