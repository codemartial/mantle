// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
@testable import Mantle

// Batch editing: synthesizing the draft across a selection, the broadcast
// keyword/location/timezone helpers, and the common/some keyword split. Blank
// draft fields mean "do not modify"; already-matching values are left clean.
@MainActor
final class BatchEditTests: XCTestCase {

    // Put a fresh AppState into batch mode over the given records.
    private func batch(_ records: [ImageRecord]) -> AppState {
        let state = makeState(records: records, library: records.map { Fix.entry(id: $0.id) })
        state.batchOrder = records.map(\.id)
        return state
    }

    private func tzOffset(_ state: AppState, _ id: String) -> Int? {
        if case .fixed(let m, _)? = state.edits.record(id)?.timezone { return m }
        return nil
    }

    // MARK: - Headline / caption / date synthesis

    func testHeadlineBroadcastSkipsBlankAndAlreadyEqual() {
        let state = batch([Fix.record(id: "/a.jpg", headline: "Old A"),
                           Fix.record(id: "/b.jpg", headline: "Target")])
        state.batchDraft.headline = "Target"
        state.synthesizeBatch()
        XCTAssertEqual(state.edits.record("/a.jpg")?.headline, "Target")
        XCTAssertTrue(state.edits.isDirty("/a.jpg"))
        XCTAssertFalse(state.edits.isDirty("/b.jpg"))   // already "Target" -> untouched
    }

    func testBlankHeadlineDraftLeavesEveryoneAlone() {
        let state = batch([Fix.record(id: "/a.jpg", headline: "A"),
                           Fix.record(id: "/b.jpg", headline: "B")])
        state.batchDraft.headline = "   "
        state.synthesizeBatch()
        XCTAssertEqual(state.edits.record("/a.jpg")?.headline, "A")
        XCTAssertFalse(state.edits.isDirty("/a.jpg"))
    }

    func testCaptionReplace() {
        let state = batch([Fix.record(id: "/a.jpg", caption: "Existing"),
                           Fix.record(id: "/b.jpg", caption: "")])
        state.batchDraft.captionMode = .replace
        state.batchDraft.captionReplace = "Brand new"
        state.synthesizeBatch()
        XCTAssertEqual(state.edits.record("/a.jpg")?.caption, "Brand new")
        XCTAssertEqual(state.edits.record("/b.jpg")?.caption, "Brand new")
    }

    func testCaptionAppendUsesBlankLineSeparatorAndHandlesEmptyPrior() {
        let state = batch([Fix.record(id: "/a.jpg", caption: "Existing"),
                           Fix.record(id: "/b.jpg", caption: "")])
        state.batchDraft.captionMode = .append
        state.batchDraft.captionAppend = "More"
        state.synthesizeBatch()
        XCTAssertEqual(state.edits.record("/a.jpg")?.caption, "Existing\n\nMore")
        XCTAssertEqual(state.edits.record("/b.jpg")?.caption, "More")   // empty prior -> no separator
    }

    func testDateShiftAppliesOnlyToDatedImages() {
        let base = Fix.date(2024, 6, 1, 12, 0, 0)
        let state = batch([Fix.record(id: "/a.jpg", captureDate: base),
                           Fix.record(id: "/b.jpg", captureDate: nil)])
        state.batchDraft.dateShiftHours = 1
        state.batchDraft.dateShiftMinutes = 30
        state.synthesizeBatch()
        XCTAssertEqual(state.edits.record("/a.jpg")?.captureDate, base.addingTimeInterval(5400))
        XCTAssertNil(state.edits.record("/b.jpg")?.captureDate)   // no date -> untouched
    }

    func testPendingCountMirrorsSynthesis() {
        let state = batch([Fix.record(id: "/a.jpg", headline: "old", captureDate: Fix.date(2024, 1, 1)),
                           Fix.record(id: "/b.jpg", headline: "new", captureDate: nil)])
        state.batchDraft.headline = "new"           // changes a only
        state.batchDraft.dateShiftHours = 2          // shifts a only (b has no date)
        XCTAssertEqual(state.pendingBatchEditCount, 2)
        state.synthesizeBatch()
        // a got two changes (headline + date), b got none.
        XCTAssertTrue(state.edits.isDirty("/a.jpg"))
        XCTAssertFalse(state.edits.isDirty("/b.jpg"))
    }

    func testApplyRatingToAll() {
        let state = batch([Fix.record(id: "/a.jpg", rating: 1),
                           Fix.record(id: "/b.jpg", rating: 0),
                           Fix.record(id: "/c.jpg", rating: 5)])
        state.applyRatingToAll(3)

        XCTAssertEqual(state.edits.record("/a.jpg")?.rating, 3)
        XCTAssertEqual(state.edits.record("/b.jpg")?.rating, 3)
        XCTAssertEqual(state.edits.record("/c.jpg")?.rating, 3)
    }

    func testCommonBatchRatingNilWhenMixed() {
        let state = batch([Fix.record(id: "/a.jpg", rating: 2),
                           Fix.record(id: "/b.jpg", rating: 2)])
        XCTAssertEqual(state.commonBatchRating, 2)

        state.updateRating(id: "/b.jpg", to: 4)
        XCTAssertNil(state.commonBatchRating)
    }

    // MARK: - Keyword broadcasts

    func testAddKeywordToAllDedupesCaseInsensitively() {
        let state = batch([Fix.record(id: "/a.jpg", keywords: ["Beach"]),
                           Fix.record(id: "/b.jpg", keywords: [])])
        state.addKeywordToAll("beach")
        XCTAssertEqual(state.edits.record("/a.jpg")?.keywords, ["Beach"])   // already present -> skipped
        XCTAssertEqual(state.edits.record("/b.jpg")?.keywords, ["beach"])   // added with typed casing
    }

    func testRemoveKeywordFromAllIsCaseInsensitive() {
        let state = batch([Fix.record(id: "/a.jpg", keywords: ["Beach", "Sky"]),
                           Fix.record(id: "/b.jpg", keywords: ["beach"])])
        state.removeKeywordFromAll("BEACH")
        XCTAssertEqual(state.edits.record("/a.jpg")?.keywords, ["Sky"])
        XCTAssertEqual(state.edits.record("/b.jpg")?.keywords, [])
    }

    func testCommonAndSomeKeywordSplit() {
        let state = batch([Fix.record(id: "/a.jpg", keywords: ["Beach", "Sky"]),
                           Fix.record(id: "/b.jpg", keywords: ["beach", "Night"])])
        XCTAssertEqual(state.commonKeywords, ["Beach"])         // in both (case-insensitive), first casing
        XCTAssertEqual(state.someKeywords, ["Night", "Sky"])   // sorted case-insensitive
    }

    // MARK: - Location / timezone broadcasts

    func testApplyMasterLocationToAll() {
        let state = batch([Fix.record(id: "/a.jpg", latitude: 10, longitude: 20),  // master
                           Fix.record(id: "/b.jpg", latitude: nil, longitude: nil),
                           Fix.record(id: "/c.jpg", latitude: 99, longitude: 99)])
        state.applyMasterLocationToAll()
        XCTAssertEqual(state.edits.record("/b.jpg")?.latitude, 10)
        XCTAssertEqual(state.edits.record("/c.jpg")?.longitude, 20)
        XCTAssertEqual(state.edits.record("/a.jpg")?.latitude, 10)   // master unchanged
    }

    func testApplyTimezoneResolvesPerImageDST() {
        // America/Los_Angeles: PST (-480) in winter, PDT (-420) in summer. The
        // offset is re-resolved against each image's own capture date.
        let state = batch([Fix.record(id: "/w.jpg", captureDate: Fix.date(2023, 1, 15, 12)),
                           Fix.record(id: "/s.jpg", captureDate: Fix.date(2023, 7, 15, 12))])
        state.applyTimezoneToAll(.fixed(offsetMinutes: 0, label: "America/Los_Angeles"))
        XCTAssertEqual(tzOffset(state, "/w.jpg"), -480)
        XCTAssertEqual(tzOffset(state, "/s.jpg"), -420)
    }
}
