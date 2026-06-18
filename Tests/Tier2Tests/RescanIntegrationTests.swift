// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
@testable import Mantle

// End-to-end folder open + Rescan against a real temp folder. Exercises the
// async scan pipeline and the chosen rescan selection rule: keep the current
// selection if its file survives, otherwise select nothing (no fall-back to
// the first entry, unlike a fresh open).
@MainActor
final class RescanIntegrationTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mantle-rescan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        try super.tearDownWithError()
    }

    private func file(_ name: String) -> URL { dir.appendingPathComponent(name) }

    // Yield the main actor until `cond` holds or we time out, so the async
    // scan/select Tasks can run.
    private func waitUntil(_ timeout: TimeInterval = 5, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // The scanner canonicalises paths (e.g. /var -> /private/var), so always
    // compare against the ids the library actually produced, not hand-built
    // paths.
    private func id(_ basename: String, in state: AppState) throws -> String {
        try XCTUnwrap(state.library.first { $0.basename == basename }?.id,
                      "no library entry named \(basename)")
    }

    func testRescanDropsDeletedFilesAndKeepsSurvivingSelection() async throws {
        for n in ["a.jpg", "b.jpg", "c.jpg"] { try Fixture.writeJPEG(at: file(n)) }
        let state = AppState()
        state.openFolder(dir, autoSelect: true)
        await waitUntil { state.library.count == 3 && state.selectedID != nil }

        XCTAssertEqual(state.library.count, 3)
        let aID = try id("a", in: state)
        XCTAssertEqual(state.selectedID, aID)   // first, ascending

        // a.jpg stays selected; delete c.jpg and rescan.
        try FileManager.default.removeItem(at: file("c.jpg"))
        state.rescan()
        await waitUntil { state.library.count == 2 }

        XCTAssertEqual(Set(state.library.map(\.basename)), ["a", "b"])
        XCTAssertEqual(state.selectedID, aID)   // survivor keeps selection
    }

    func testRescanClearsSelectionWhenTheSelectedFileVanishes() async throws {
        for n in ["a.jpg", "b.jpg"] { try Fixture.writeJPEG(at: file(n)) }
        let state = AppState()
        state.openFolder(dir, autoSelect: true)
        await waitUntil { state.library.count == 2 && state.selectedID != nil }

        let bID = try id("b", in: state)
        state.select(bID)
        XCTAssertEqual(state.selectedID, bID)

        try FileManager.default.removeItem(at: file("b.jpg"))
        state.rescan()
        await waitUntil { state.library.count == 1 }

        XCTAssertEqual(state.library.count, 1)
        XCTAssertNil(state.selectedID)   // vanished selection lands on nothing
    }
}
