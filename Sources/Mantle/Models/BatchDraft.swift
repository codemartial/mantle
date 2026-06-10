// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation

// In-flight edits for batch mode. Lives on AppState while batchOrder is
// non-empty. Reset to defaults on every batch entry -- blank fields here
// mean "do not modify the corresponding field on any image". Synthesis
// (AppState.synthesizeBatch) is the only consumer.
//
// The master's own date / timezone / location are NOT drafted here -- they
// are edited directly on the master's ImageRecord through the same path as
// single-mode editing. Only fields that need broadcasting across the whole
// batch live here.
struct BatchDraft: Equatable {

    enum CaptionMode: Hashable { case replace, append }

    var headline: String = ""
    var captionMode: CaptionMode = .replace
    var captionReplace: String = ""
    var captionAppend: String = ""
    var dateShiftHours: Int = 0
    var dateShiftMinutes: Int = 0

    var hasDateShift: Bool { dateShiftHours != 0 || dateShiftMinutes != 0 }

    var dateShiftInterval: TimeInterval {
        TimeInterval(dateShiftHours * 3600 + dateShiftMinutes * 60)
    }

    // Which logical field differs between two drafts, for undo coalescing
    // (consecutive changes to the same key merge into one step) and the
    // Edit menu label. Caption mode + both caption texts share one key, so
    // flipping replace/append and typing coalesce into a single undo step.
    static func changedField(_ a: BatchDraft, _ b: BatchDraft) -> (key: String, label: String)? {
        if a.headline != b.headline {
            return ("headline", "Edit Batch Title")
        }
        if a.captionMode != b.captionMode
            || a.captionReplace != b.captionReplace
            || a.captionAppend != b.captionAppend {
            return ("caption", "Edit Batch Description")
        }
        if a.dateShiftHours != b.dateShiftHours || a.dateShiftMinutes != b.dateShiftMinutes {
            return ("dateShift", "Edit Batch Date Shift")
        }
        return nil
    }
}
