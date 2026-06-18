// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
@testable import Mantle

// Cmd-click (toggleBatch), Shift-click (selectRange), and collapsing the batch
// (exitBatch). The master is always batchOrder[0] and selectedID tracks it.
@MainActor
final class BatchSelectionTests: XCTestCase {

    private let ids = ["/a.jpg", "/b.jpg", "/c.jpg", "/d.jpg"]

    private func grid() -> AppState {
        makeState(records: ids.map { Fix.record(id: $0) },
                  library: ids.map { Fix.entry(id: $0) })
    }

    func testToggleBatchSeedsAppendsRemovesAndCollapses() {
        let state = grid()
        state.selectedID = "/a.jpg"
        state.selectionAnchor = "/a.jpg"

        state.toggleBatch("/b.jpg")
        XCTAssertEqual(state.batchOrder, ["/a.jpg", "/b.jpg"])
        XCTAssertTrue(state.batchMode)
        XCTAssertEqual(state.selectedID, "/a.jpg")   // master pinned

        state.toggleBatch("/c.jpg")
        XCTAssertEqual(state.batchOrder, ["/a.jpg", "/b.jpg", "/c.jpg"])

        state.toggleBatch("/b.jpg")                  // remove, still >= 2
        XCTAssertEqual(state.batchOrder, ["/a.jpg", "/c.jpg"])

        state.toggleBatch("/c.jpg")                  // drops to 1 -> collapse
        XCTAssertFalse(state.batchMode)
        XCTAssertEqual(state.selectedID, "/a.jpg")
    }

    func testSelectRangeSpansVisibleOrderAnchorFirst() {
        let state = grid()
        state.selectedID = "/b.jpg"
        state.selectionAnchor = "/b.jpg"
        state.selectRange(to: "/d.jpg")
        XCTAssertEqual(state.batchOrder, ["/b.jpg", "/c.jpg", "/d.jpg"])
        XCTAssertEqual(state.selectedID, "/b.jpg")
    }

    func testSelectRangeBackwardsKeepsAnchorAsMaster() {
        let state = grid()
        state.selectedID = "/c.jpg"
        state.selectionAnchor = "/c.jpg"
        state.selectRange(to: "/a.jpg")
        XCTAssertEqual(state.batchOrder, ["/c.jpg", "/a.jpg", "/b.jpg"])   // anchor first
    }

    func testExitBatchSynthesizesDraftAndLandsOnSelection() {
        let state = grid()
        state.selectedID = "/a.jpg"
        state.selectionAnchor = "/a.jpg"
        state.toggleBatch("/b.jpg")
        state.batchDraft.headline = "Group title"

        state.exitBatch(selecting: "/c.jpg")
        XCTAssertFalse(state.batchMode)
        XCTAssertTrue(state.batchOrder.isEmpty)
        XCTAssertEqual(state.selectedID, "/c.jpg")
        XCTAssertEqual(state.edits.record("/a.jpg")?.headline, "Group title")
        XCTAssertEqual(state.edits.record("/b.jpg")?.headline, "Group title")
    }
}
