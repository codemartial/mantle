// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
@testable import Mantle

// Folder scanning: RAW+JPEG pairing into one row, sidecar precedence
// (bare beats extension-specific), format labelling, non-image filtering, and
// name sort. No ExifTool needed -- this is filesystem + ImageIO.
final class LibraryScanTests: TempDirCase {

    func testRawAndJpegPairIntoOneEntryWithJpegAsDisplay() throws {
        try Fixture.writeJPEG(at: path("shot.jpg"))
        try Fixture.touch(path("shot.nef"))   // RAW sibling; pairing is by basename
        let entries = LibraryIndex.scan(dir)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].format, "RAW + JPEG")
        XCTAssertEqual(entries[0].displayURL.pathExtension.lowercased(), "jpg")
        XCTAssertEqual(entries[0].siblingURLs.count, 2)
    }

    func testLoneJpegAndLoneRawGetTheirFormatLabels() throws {
        try Fixture.writeJPEG(at: path("only.jpg"))
        try Fixture.touch(path("raw.nef"))
        let byName = Dictionary(uniqueKeysWithValues:
            LibraryIndex.scan(dir).map { ($0.basename.lowercased(), $0) })
        XCTAssertEqual(byName["only"]?.format, "JPEG")
        XCTAssertEqual(byName["raw"]?.format, "RAW")
    }

    func testBareSidecarWinsOverExtensionSpecific() throws {
        try Fixture.touch(path("img.nef"))
        try Fixture.touch(path("img.xmp"))       // bare
        try Fixture.touch(path("img.nef.xmp"))   // extension-specific
        let entries = LibraryIndex.scan(dir)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].sidecarURL?.lastPathComponent, "img.xmp")
    }

    func testExtensionSpecificSidecarUsedWhenNoBareExists() throws {
        try Fixture.touch(path("img.nef"))
        try Fixture.touch(path("img.nef.xmp"))
        XCTAssertEqual(LibraryIndex.scan(dir).first?.sidecarURL?.lastPathComponent, "img.nef.xmp")
    }

    func testNonImagesIgnoredAndEntriesSortedAscending() throws {
        try Fixture.writeJPEG(at: path("c.jpg"))
        try Fixture.writeJPEG(at: path("a.jpg"))
        try Fixture.writeJPEG(at: path("b.jpg"))
        try Data().write(to: path("notes.txt"))
        XCTAssertEqual(LibraryIndex.scan(dir).map(\.basename), ["a", "b", "c"])
    }

    func testEmptyFolderScansToNothing() throws {
        XCTAssertTrue(LibraryIndex.scan(dir).isEmpty)
    }
}
