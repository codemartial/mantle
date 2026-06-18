// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
import CoreGraphics
@testable import Mantle

// Plain value-type behaviour: the small computed properties and combinators
// that the UI and save paths depend on.
final class ValueTypeTests: XCTestCase {

    // MARK: - BatchDraft

    func testDateShiftIntervalCombinesHoursAndMinutes() {
        var d = BatchDraft()
        XCTAssertFalse(d.hasDateShift)
        XCTAssertEqual(d.dateShiftInterval, 0)

        d.dateShiftHours = 2
        d.dateShiftMinutes = 30
        XCTAssertTrue(d.hasDateShift)
        XCTAssertEqual(d.dateShiftInterval, 2 * 3600 + 30 * 60)

        d.dateShiftHours = -1
        d.dateShiftMinutes = 0
        XCTAssertTrue(d.hasDateShift)
        XCTAssertEqual(d.dateShiftInterval, -3600)
    }

    func testChangedFieldIdentifiesTheEditedKey() {
        let base = BatchDraft()

        var h = base; h.headline = "x"
        XCTAssertEqual(BatchDraft.changedField(base, h)?.key, "headline")

        var c = base; c.captionAppend = "y"
        XCTAssertEqual(BatchDraft.changedField(base, c)?.key, "caption")

        var m = base; m.captionMode = .append
        XCTAssertEqual(BatchDraft.changedField(base, m)?.key, "caption")

        var s = base; s.dateShiftMinutes = 5
        XCTAssertEqual(BatchDraft.changedField(base, s)?.key, "dateShift")

        XCTAssertNil(BatchDraft.changedField(base, base))
    }

    // MARK: - SaveStatus

    func testUnsavedCountPluralizes() {
        XCTAssertEqual(SaveStatus.unsaved(count: 1).displayText, "1 unsaved")
        XCTAssertEqual(SaveStatus.unsaved(count: 4).displayText, "4 unsaved")
    }

    // MARK: - ByteSize

    func testByteSizeBlankForNonPositive() {
        XCTAssertEqual(ByteSize.format(0), "")
        XCTAssertEqual(ByteSize.format(-10), "")
        XCTAssertFalse(ByteSize.format(2_000_000).isEmpty)
    }

    // MARK: - LibrarySortOrder

    func testSortOrderToggleAndSymbols() {
        XCTAssertTrue(LibrarySortOrder.nameAscending.toggled == .nameDescending)
        XCTAssertTrue(LibrarySortOrder.nameDescending.toggled == .nameAscending)
        XCTAssertEqual(LibrarySortOrder.nameAscending.symbolName, "arrow.down")
        XCTAssertEqual(LibrarySortOrder.nameDescending.symbolName, "arrow.up")
    }

    // MARK: - LibraryEntry

    func testAspectRatioFallsBackWhenSizeZero() {
        let zero = LibraryEntry(id: "/a.jpg", basename: "a",
                                displayURL: URL(fileURLWithPath: "/a.jpg"),
                                siblingURLs: [], sidecarURL: nil, format: "JPEG",
                                displaySize: .zero)
        XCTAssertEqual(zero.aspectRatio, 1.5, accuracy: 1e-9)   // documented fallback

        let wide = LibraryEntry(id: "/b.jpg", basename: "b",
                                displayURL: URL(fileURLWithPath: "/b.jpg"),
                                siblingURLs: [], sidecarURL: nil, format: "JPEG",
                                displaySize: CGSize(width: 200, height: 100))
        XCTAssertEqual(wide.aspectRatio, 2.0, accuracy: 1e-9)
    }

    // MARK: - LibraryFilter / AttributeFilter

    func testAttributeFilterConstrains() {
        XCTAssertFalse(AttributeFilter.ignore.constrains)
        XCTAssertTrue(AttributeFilter.present.constrains)
        XCTAssertTrue(AttributeFilter.absent.constrains)
        XCTAssertFalse(AttributeFilter.matches("   ").constrains)   // blank text is inert
        XCTAssertTrue(AttributeFilter.matches("sun").constrains)
        XCTAssertFalse(AttributeFilter.chips([FilterChip(text: "  ")]).constrains)
        XCTAssertTrue(AttributeFilter.chips([FilterChip(text: "beach")]).constrains)
    }

    func testLibraryFilterActiveAttributes() {
        var f = LibraryFilter()
        XCTAssertFalse(f.isActive)
        XCTAssertEqual(f.status(.xmp), .ignore)        // default when unset

        f.statuses[.headline] = .matches("x")
        f.statuses[.keywords] = .ignore                // present but inert
        XCTAssertTrue(f.isActive)
        XCTAssertEqual(f.activeAttributes, [.headline])
    }
}
