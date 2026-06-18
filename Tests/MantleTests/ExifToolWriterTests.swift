// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
import Foundation
import CoreGraphics
@testable import Mantle

// Covers the "save to a file deleted from disk" behavior: the write must be
// a successful no-op that creates NO sidecar, so the session can mark the
// metadata saved without leaving an orphan .xmp behind. This is the path that
// keeps batch exit coherent when one member's file is gone.
final class ExifToolWriterTests: XCTestCase {

    // Build a record whose primary file does not exist on disk.
    private func missingFileRecord() -> (record: ImageRecord, sidecar: URL) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("mantle-missing-\(UUID().uuidString).jpg")
        let record = ImageRecord(
            id: file.path,
            file: file,
            sidecarURL: nil,
            fmt: "JPEG",
            dim: CGSize(width: 100, height: 100),
            size: 0,
            colorProfile: "",
            camera: "", lens: "", shutter: "", aperture: "", iso: 0, focal: "",
            originalCaptureDate: nil,
            latitude: nil, longitude: nil, altitude: nil, direction: nil,
            headline: "Edited headline",
            caption: "",
            keywords: [],
            captureDate: nil,
            timezone: .unknown,
            rating: 0
        )
        return (record, ExifToolWriter.sidecarPath(for: file))
    }

    func testWriteToMissingFileSucceedsAsNoOp() throws {
        let (record, sidecar) = missingFileRecord()
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.file.path),
                       "precondition: the primary file should not exist")

        let result = ExifToolWriter.write(record: record, fields: [.headline])

        switch result {
        case .success(let res):
            // Treated as success so the session marks the metadata saved...
            XCTAssertNil(res.sidecar, "no sidecar should be reported for a missing file")
        case .failure(let err):
            XCTFail("expected success for a missing file, got \(err)")
        }

        // ...and crucially, NO orphan sidecar was created on disk.
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path),
                       "missing-file write must not create a sidecar")
    }

    func testEmptyFieldSetReportsNoSidecar() throws {
        let (record, sidecar) = missingFileRecord()
        let result = ExifToolWriter.write(record: record, fields: [])

        guard case .success(let res) = result else {
            return XCTFail("empty field set should succeed as a no-op")
        }
        XCTAssertNil(res.sidecar, "an empty write should report no sidecar")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
    }
}
