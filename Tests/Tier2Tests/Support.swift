// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
import Foundation
import AppKit
import CoreGraphics
@testable import Mantle

// Shared fixtures for the tier-2 (integration) suite. These tests touch the
// real filesystem and, where noted, the bundled ExifTool, so each test gets
// its own throwaway temp directory cleaned up in tearDown.

// A temp working directory that wipes itself. Subclass XCTestCase via this so
// every integration test gets an isolated sandbox folder.
class TempDirCase: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mantle-t2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        try super.tearDownWithError()
    }

    // Path inside the sandbox for a given filename.
    func path(_ name: String) -> URL { dir.appendingPathComponent(name) }
}

enum Fixture {

    // True when Mantle can resolve its bundled ExifTool. Under `swift test`
    // the resource bundle may not sit where ExifToolOneShot's Bundle.main
    // lookup expects, in which case ExifTool-dependent tests skip rather than
    // fail spuriously. The write/read path through the app would fall back to
    // ImageIO (which can't see XMP sidecars), so a skip is the honest outcome.
    static var exiftoolAvailable: Bool {
        ExifToolOneShot.exiftoolBinaryURL() != nil
            && ExifToolOneShot.exiftoolLibURL() != nil
    }

    // Write a minimal but valid JPEG so ImageIO and ExifTool both accept the
    // file as a real image. Content is a flat colour; only the container
    // matters for these tests.
    @discardableResult
    static func writeJPEG(at url: URL, width: Int = 16, height: Int = 16) throws -> URL {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let data = rep.representation(using: .jpeg, properties: [:]) else {
            throw NSError(domain: "Fixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "failed to encode JPEG"])
        }
        try data.write(to: url)
        return url
    }

    // Touch an empty file (0 bytes). Used to fabricate a RAW whose lazy
    // CGImageSource reports a zero image count -- the deleted/empty-file
    // condition that used to trap decodeRaw.
    @discardableResult
    static func touch(_ url: URL) throws -> URL {
        try Data().write(to: url)
        return url
    }

    // An ImageRecord pointing at a real file, with the editable fields the
    // caller wants to round-trip. Read-only EXIF fields are left blank --
    // the writer never touches them.
    static func record(
        file: URL,
        sidecar: URL? = nil,
        headline: String = "",
        caption: String = "",
        keywords: [String] = [],
        captureDate: Date? = nil,
        timezone: TZRule = .unknown,
        latitude: Double? = nil,
        longitude: Double? = nil,
        rating: Int = 0
    ) -> ImageRecord {
        ImageRecord(
            id: file.path,
            file: file,
            sidecarURL: sidecar,
            fmt: "JPEG",
            dim: CGSize(width: 16, height: 16),
            size: 0,
            colorProfile: "",
            camera: "", lens: "", shutter: "", aperture: "", iso: 0, focal: "",
            originalCaptureDate: captureDate,
            latitude: latitude, longitude: longitude, altitude: nil, direction: nil,
            headline: headline,
            caption: caption,
            keywords: keywords,
            captureDate: captureDate,
            timezone: timezone,
            rating: rating
        )
    }
}
