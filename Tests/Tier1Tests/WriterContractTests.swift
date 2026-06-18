// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
@testable import Mantle

// The writer's no-spawn contracts: sidecar naming, and the "save to a file
// that was deleted from disk" path, which must be a successful no-op that
// creates NO sidecar so a batch exit can mark the metadata saved without
// leaving an orphan .xmp behind. These never invoke ExifTool, so they stay in
// the fast tier.
final class WriterContractTests: XCTestCase {

    func testSidecarPathSwapsExtensionToXmp() {
        XCTAssertEqual(
            ExifToolWriter.sidecarPath(for: URL(fileURLWithPath: "/photos/IMG_0001.JPG")).lastPathComponent,
            "IMG_0001.xmp")
        XCTAssertEqual(
            ExifToolWriter.sidecarPath(for: URL(fileURLWithPath: "/photos/scene.NEF")).lastPathComponent,
            "scene.xmp")
    }

    func testWriteToMissingFileSucceedsWithoutCreatingASidecar() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("mantle-missing-\(UUID().uuidString).jpg")
        let sidecar = ExifToolWriter.sidecarPath(for: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        let result = ExifToolWriter.write(record: Fix.record(id: file.path, headline: "Edited"),
                                          fields: [.headline])
        guard case .success(let res) = result else {
            return XCTFail("expected success for a missing file, got \(result)")
        }
        XCTAssertNil(res.sidecar)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path),
                       "a missing-file write must not create an orphan sidecar")
    }

    func testEmptyFieldSetReportsNoSidecar() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("mantle-empty-\(UUID().uuidString).jpg")
        guard case .success(let res) = ExifToolWriter.write(record: Fix.record(id: file.path),
                                                            fields: []) else {
            return XCTFail("an empty field set should succeed as a no-op")
        }
        XCTAssertNil(res.sidecar)
    }
}
