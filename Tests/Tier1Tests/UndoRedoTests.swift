// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
@testable import Mantle

// Undo/redo across the editable fields: value restoration, typing-burst
// coalescing, the selection boundary that breaks coalescing, redo
// invalidation on a fresh edit, and atomic grouped (batch) steps.
@MainActor
final class UndoRedoTests: XCTestCase {

    // selectedID is pre-set so an undo that re-selects the affected image is a
    // no-op (keeps the test off the disk-reading selection path).
    private func single() -> AppState {
        let state = makeState(records: [Fix.record(id: "/a.jpg", headline: "v0", rating: 0)],
                              library: [Fix.entry(id: "/a.jpg")])
        state.selectedID = "/a.jpg"
        return state
    }

    func testUndoThenRedoRestoresFieldValue() {
        let state = single()
        state.updateField(id: "/a.jpg", field: .headline) { $0.headline = "v1" }
        XCTAssertTrue(state.undo.canUndo)
        XCTAssertEqual(state.edits.record("/a.jpg")?.headline, "v1")

        state.performUndo()
        XCTAssertEqual(state.edits.record("/a.jpg")?.headline, "v0")
        XCTAssertTrue(state.undo.canRedo)

        state.performRedo()
        XCTAssertEqual(state.edits.record("/a.jpg")?.headline, "v1")
    }

    func testConsecutiveSameFieldEditsCoalesceIntoOneStep() {
        let state = single()
        state.updateField(id: "/a.jpg", field: .headline) { $0.headline = "a" }
        state.updateField(id: "/a.jpg", field: .headline) { $0.headline = "ab" }
        state.updateField(id: "/a.jpg", field: .headline) { $0.headline = "abc" }
        XCTAssertEqual(state.undo.undoEntries.count, 1)

        state.performUndo()
        XCTAssertEqual(state.edits.record("/a.jpg")?.headline, "v0")   // whole burst unwinds at once
    }

    func testSelectionChangeBreaksCoalescing() {
        let state = single()
        state.edits.ingest(Fix.record(id: "/b.jpg", headline: "w0"))
        state.library.append(Fix.entry(id: "/b.jpg"))

        state.updateField(id: "/a.jpg", field: .headline) { $0.headline = "a1" }
        state.selectedID = "/b.jpg"     // closes the coalescing window
        state.selectedID = "/a.jpg"
        state.updateField(id: "/a.jpg", field: .headline) { $0.headline = "a2" }
        XCTAssertEqual(state.undo.undoEntries.count, 2)
    }

    func testFreshEditInvalidatesRedo() {
        let state = single()
        state.updateField(id: "/a.jpg", field: .headline) { $0.headline = "v1" }
        state.performUndo()
        XCTAssertTrue(state.undo.canRedo)

        state.updateField(id: "/a.jpg", field: .rating) { $0.rating = 2 }
        XCTAssertFalse(state.undo.canRedo)   // a new edit clears the redo stack
    }

    func testGroupedEditsUndoAtomically() {
        let state = single()
        state.edits.ingest(Fix.record(id: "/b.jpg", headline: "w0"))

        state.withUndoGroup(label: "Group") {
            state.updateField(id: "/a.jpg", field: .headline) { $0.headline = "x" }
            state.updateField(id: "/b.jpg", field: .headline) { $0.headline = "y" }
        }
        XCTAssertEqual(state.undo.undoEntries.count, 1)

        state.performUndo()
        XCTAssertEqual(state.edits.record("/a.jpg")?.headline, "v0")
        XCTAssertEqual(state.edits.record("/b.jpg")?.headline, "w0")
    }

    func testEmptyGroupRecordsNothing() {
        let state = single()
        state.withUndoGroup(label: "Empty") {
            state.updateField(id: "/a.jpg", field: .headline) { $0.headline = "v0" }  // no-op
        }
        XCTAssertFalse(state.undo.canUndo)
    }

    func testUpdateRatingClampsToRange() {
        let state = single()
        state.updateRating(id: "/a.jpg", to: 9)
        XCTAssertEqual(state.edits.record("/a.jpg")?.rating, 5)
        state.updateRating(id: "/a.jpg", to: -3)
        XCTAssertEqual(state.edits.record("/a.jpg")?.rating, 0)
    }
}
