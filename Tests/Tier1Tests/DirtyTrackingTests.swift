// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
@testable import Mantle

// The dirty-tracker is the spine of the save model: a field is "dirty" only
// when it semantically differs from the last-saved baseline. These tests pin
// the semantic-equality rules (trim, set-compare keywords, second-precision
// dates, coordinate tolerance, offset-only timezone) and the markSaved
// snapshot invariant.
@MainActor
final class DirtyTrackingTests: XCTestCase {

    private let id = "/lib/a.jpg"

    private func store(_ rec: ImageRecord) -> EditStore {
        let s = EditStore()
        s.ingest(rec)
        return s
    }

    func testFreshIngestIsClean() {
        let s = store(Fix.record(id: id, headline: "Title", keywords: ["a", "b"]))
        XCTAssertFalse(s.isDirty(id))
        XCTAssertEqual(s.totalDirtyCount, 0)
        XCTAssertEqual(s.dirtyFields(id), [])
    }

    func testEditThenRevertReturnsToClean() {
        let s = store(Fix.record(id: id, headline: "Original"))
        s.update(id, field: .headline) { $0.headline = "Changed" }
        XCTAssertTrue(s.isDirty(id))
        XCTAssertEqual(s.dirtyFields(id), [.headline])

        s.update(id, field: .headline) { $0.headline = "Original" }
        XCTAssertFalse(s.isDirty(id))   // reverting clears the bit, not a one-way flag
    }

    func testWhitespaceOnlyHeadlineChangeStaysClean() {
        let s = store(Fix.record(id: id, headline: "Title"))
        s.update(id, field: .headline) { $0.headline = "  Title  " }
        XCTAssertFalse(s.isDirty(id))   // trim-equal
    }

    func testKeywordReorderIsCleanButAddIsDirty() {
        let s = store(Fix.record(id: id, keywords: ["a", "b", "c"]))
        s.update(id, field: .keywords) { $0.keywords = ["c", "b", "a"] }
        XCTAssertFalse(s.isDirty(id))   // order-insensitive set compare

        s.update(id, field: .keywords) { $0.keywords = ["c", "b", "a", "d"] }
        XCTAssertTrue(s.isDirty(id))
    }

    func testDuplicateKeywordsCollapseToClean() {
        // A sidecar with duplicate keywords must not read as dirty the moment
        // it loads, and removing the duplicate stays clean.
        let s = store(Fix.record(id: id, keywords: ["x", "x", "y"]))
        s.update(id, field: .keywords) { $0.keywords = ["x", "y"] }
        XCTAssertFalse(s.isDirty(id))
    }

    func testKeywordCaseIsSignificant() {
        let s = store(Fix.record(id: id, keywords: ["Beach"]))
        s.update(id, field: .keywords) { $0.keywords = ["beach"] }
        XCTAssertTrue(s.isDirty(id))    // "Beach" != "beach"
    }

    func testCaptureDateSubSecondDriftStaysClean() {
        let base = Fix.date(2024, 1, 1, 10, 0, 0)
        let s = store(Fix.record(id: id, captureDate: base))
        s.update(id, field: .captureDate) { $0.captureDate = base.addingTimeInterval(0.4) }
        XCTAssertFalse(s.isDirty(id))   // rounds to the second

        s.update(id, field: .captureDate) { $0.captureDate = base.addingTimeInterval(2) }
        XCTAssertTrue(s.isDirty(id))
    }

    func testCoordinateWithinToleranceStaysClean() {
        let s = store(Fix.record(id: id, latitude: 12.3456789, longitude: -45.6))
        s.update(id, field: .location) { $0.latitude = 12.3456789 + 1e-9 }
        XCTAssertFalse(s.isDirty(id))   // ~1e-7 tolerance absorbs round-trip drift

        s.update(id, field: .location) { $0.latitude = 12.35 }
        XCTAssertTrue(s.isDirty(id))
    }

    func testTimezoneLabelChangeIsCleanButOffsetDirties() {
        let s = store(Fix.record(id: id,
                                 timezone: .fixed(offsetMinutes: -480, label: "Los Angeles")))
        s.update(id, field: .timezone) {
            $0.timezone = .fixed(offsetMinutes: -480, label: "America/Los_Angeles")
        }
        XCTAssertFalse(s.isDirty(id))   // labels are cosmetic; offset is what matters

        s.update(id, field: .timezone) { $0.timezone = .fixed(offsetMinutes: -420, label: "x") }
        XCTAssertTrue(s.isDirty(id))
    }

    func testMarkSavedAdvancesBaseline() {
        let s = store(Fix.record(id: id, headline: "Old"))
        s.update(id, field: .headline) { $0.headline = "New" }
        let snap = s.record(id)!
        s.markSaved(id, fields: [.headline], snapshot: snap)
        XCTAssertFalse(s.isDirty(id))
    }

    func testMidFlightEditSurvivesMarkSaved() {
        // markSaved patches the baseline from the SNAPSHOT, not current values,
        // so an edit typed during the in-flight save stays dirty afterwards.
        let s = store(Fix.record(id: id, headline: "v0"))
        s.update(id, field: .headline) { $0.headline = "v1" }
        let snapshot = s.record(id)!                                   // captured for the write
        s.update(id, field: .headline) { $0.headline = "v2" }          // typed mid-flight
        s.markSaved(id, fields: [.headline], snapshot: snapshot)
        XCTAssertTrue(s.isDirty(id))                                   // v2 != saved baseline v1
    }

    func testTotalDirtyCountAndIDsAcrossImages() {
        let s = EditStore()
        s.ingest(Fix.record(id: "/a.jpg", headline: "a"))
        s.ingest(Fix.record(id: "/b.jpg", headline: "b"))
        s.update("/a.jpg", field: .headline) { $0.headline = "a2" }
        s.update("/b.jpg", field: .rating) { $0.rating = 3 }
        XCTAssertEqual(s.totalDirtyCount, 2)
        XCTAssertEqual(Set(s.allDirtyIDs), ["/a.jpg", "/b.jpg"])
    }
}
