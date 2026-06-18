// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
@testable import Mantle

// The browser grid renders `visibleLibrary` = filter then sort. These tests
// drive the per-attribute filter (xmp / headline / keywords), the all/any
// combinator, and the name sort, all against in-memory records.
@MainActor
final class FilterAndSortTests: XCTestCase {

    // MARK: - XMP sidecar presence

    func testXmpPresenceFilter() {
        let withX = Fix.entry(id: "/a.jpg", sidecar: URL(fileURLWithPath: "/a.xmp"))
        let without = Fix.entry(id: "/b.jpg")
        let state = makeState(library: [withX, without])

        state.filter = LibraryFilter(statuses: [.xmp: .present])
        XCTAssertEqual(state.visibleLibrary.map(\.id), ["/a.jpg"])

        state.filter = LibraryFilter(statuses: [.xmp: .absent])
        XCTAssertEqual(state.visibleLibrary.map(\.id), ["/b.jpg"])
    }

    // MARK: - Headline

    func testHeadlineSubstringIsCaseInsensitive() {
        let state = makeState(
            records: [Fix.record(id: "/a.jpg", headline: "Sunset over the bay"),
                      Fix.record(id: "/b.jpg", headline: "Mountains")],
            library: [Fix.entry(id: "/a.jpg"), Fix.entry(id: "/b.jpg")])
        state.filter = LibraryFilter(statuses: [.headline: .matches("SUNSET")])
        XCTAssertEqual(state.visibleLibrary.map(\.id), ["/a.jpg"])
    }

    func testHeadlinePresentAndAbsent() {
        let state = makeState(
            records: [Fix.record(id: "/a.jpg", headline: "Has a title"),
                      Fix.record(id: "/b.jpg", headline: "   ")],   // blank == absent
            library: [Fix.entry(id: "/a.jpg"), Fix.entry(id: "/b.jpg")])

        state.filter = LibraryFilter(statuses: [.headline: .present])
        XCTAssertEqual(state.visibleLibrary.map(\.id), ["/a.jpg"])

        state.filter = LibraryFilter(statuses: [.headline: .absent])
        XCTAssertEqual(state.visibleLibrary.map(\.id), ["/b.jpg"])
    }

    // MARK: - Keywords (chip include / exclude)

    func testKeywordChipsIncludeAndExclude() {
        let state = makeState(
            records: [Fix.record(id: "/a.jpg", keywords: ["Beach", "Sky"]),
                      Fix.record(id: "/b.jpg", keywords: ["Sky"]),
                      Fix.record(id: "/c.jpg", keywords: ["Beach", "Night"])],
            library: [Fix.entry(id: "/a.jpg"), Fix.entry(id: "/b.jpg"), Fix.entry(id: "/c.jpg")])
        // must have "beach" (case-insensitive), must not have "night"
        state.filter = LibraryFilter(statuses: [.keywords: .chips([
            FilterChip(text: "beach"),
            FilterChip(text: "night", exclude: true),
        ])])
        XCTAssertEqual(state.visibleLibrary.map(\.id), ["/a.jpg"])
    }

    // MARK: - Combine

    func testCombineAllVersusAny() {
        let state = makeState(
            records: [Fix.record(id: "/a.jpg", headline: "Sunset")],
            library: [Fix.entry(id: "/a.jpg")])   // no sidecar
        let statuses: [FilterAttribute: AttributeFilter] =
            [.headline: .matches("sunset"), .xmp: .present]   // headline true, xmp false

        state.filter = LibraryFilter(statuses: statuses, combine: .all)
        XCTAssertTrue(state.visibleLibrary.isEmpty)           // all -> fails on xmp

        state.filter = LibraryFilter(statuses: statuses, combine: .any)
        XCTAssertEqual(state.visibleLibrary.map(\.id), ["/a.jpg"])   // any -> headline passes
    }

    func testUnclassifiedFileStaysVisibleUnderHeadlineFilter() {
        // No record ingested and nothing swept -> headline unknown (nil) ->
        // the file stays visible until the background sweep classifies it,
        // instead of flickering out.
        let state = makeState(library: [Fix.entry(id: "/a.jpg")])
        state.filter = LibraryFilter(statuses: [.headline: .matches("anything")])
        XCTAssertEqual(state.visibleLibrary.map(\.id), ["/a.jpg"])
    }

    func testLiveEditOverridesSweepForFiltering() {
        // An ingested (possibly unsaved) edit must filter immediately.
        let state = makeState(
            records: [Fix.record(id: "/a.jpg", headline: "Renamed title")],
            library: [Fix.entry(id: "/a.jpg")])
        state.filter = LibraryFilter(statuses: [.headline: .matches("renamed")])
        XCTAssertEqual(state.visibleLibrary.map(\.id), ["/a.jpg"])
    }

    // MARK: - Sort

    func testSortByNameAscendingThenDescending() {
        let state = makeState(library: [Fix.entry(id: "/c.jpg"),
                                        Fix.entry(id: "/a.jpg"),
                                        Fix.entry(id: "/b.jpg")])
        state.sortOrder = .nameAscending
        XCTAssertEqual(state.visibleLibrary.map(\.basename), ["a", "b", "c"])
        state.sortOrder = .nameDescending
        XCTAssertEqual(state.visibleLibrary.map(\.basename), ["c", "b", "a"])
    }

    func testSortIsCaseInsensitive() {
        let state = makeState(library: [Fix.entry(id: "/B.jpg"), Fix.entry(id: "/a.jpg")])
        state.sortOrder = .nameAscending
        XCTAssertEqual(state.visibleLibrary.map(\.basename), ["a", "B"])
    }
}
