// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
import AppKit
@testable import Mantle

// Thumbnail decoding over real files, including the crash regression: an empty
// RAW yields a lazy CGImageSource whose image count is 0, which used to trap
// decodeRaw's `for i in 1..<count` (1..<0). It must now return nil, not crash.
final class ThumbnailDecodeTests: TempDirCase {

    func testDecodesARealJpegThumbnail() throws {
        let file = try Fixture.writeJPEG(at: path("pic.jpg"), width: 64, height: 48)
        XCTAssertNotNil(ImageIOFastThumb.makeThumbnail(url: file, maxPixelSide: 128, scale: 2))
    }

    func testMissingFileReturnsNilWithoutCrashing() {
        XCTAssertNil(ImageIOFastThumb.makeThumbnail(url: path("nope.jpg"), maxPixelSide: 128, scale: 2))
    }

    func testEmptyRawFileDoesNotTrapTheRuntime() throws {
        // 0-byte .nef -> lazy source, image count 0 -> decodeRaw's guarded
        // range. Returns nil (ExifTool fallback also yields nothing here).
        let empty = try Fixture.touch(path("broken.nef"))
        XCTAssertNil(ImageIOFastThumb.makeThumbnail(url: empty, maxPixelSide: 128, scale: 2))
    }
}
