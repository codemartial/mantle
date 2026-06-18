// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import XCTest
@testable import Mantle

// The core promise of the app: edits written to an XMP sidecar via ExifTool
// read back as the same values on the next ingest. Each test writes a field
// family and re-reads through SidecarIO -- the exact path used on selection.
// These guard the historically fragile cases: keyword dedupe, the GPS
// hemisphere sign, the rating-clear, and the date+offset encoding.
final class XmpRoundTripTests: TempDirCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(Fixture.exiftoolAvailable,
                          "bundled ExifTool not resolvable in this context")
    }

    // Write `fields` from `record`, assert a sidecar landed, and read the
    // image+sidecar back the way the app does.
    private func roundTrip(_ record: ImageRecord, fields: Set<EditableField>) throws -> ImageRecord {
        let result = ExifToolWriter.write(record: record, fields: fields)
        guard case .success(let res) = result else {
            XCTFail("write failed: \(result)")
            throw XCTSkip("write failed")
        }
        let sidecar = try XCTUnwrap(res.sidecar, "expected a sidecar on disk")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
        return SidecarIO.read(file: record.file, sidecar: sidecar)
    }

    func testHeadlineRoundTrips() throws {
        let file = try Fixture.writeJPEG(at: path("title.jpg"))
        let back = try roundTrip(Fixture.record(file: file, headline: "Sunrise over the bay"),
                                 fields: [.headline])
        XCTAssertEqual(back.headline, "Sunrise over the bay")
    }

    func testCaptionRoundTrips() throws {
        let file = try Fixture.writeJPEG(at: path("cap.jpg"))
        let back = try roundTrip(Fixture.record(file: file, caption: "A descriptive caption."),
                                 fields: [.caption])
        XCTAssertEqual(back.caption, "A descriptive caption.")
    }

    func testKeywordsDedupeAndRoundTripAsASet() throws {
        let file = try Fixture.writeJPEG(at: path("kw.jpg"))
        // trim + drop empties + dedupe (case-sensitive) before the write.
        let back = try roundTrip(
            Fixture.record(file: file, keywords: ["Beach", "beach", " Sky ", "", "Beach"]),
            fields: [.keywords])
        XCTAssertEqual(Set(back.keywords), ["Beach", "beach", "Sky"])
    }

    func testRatingRoundTripsThenZeroClearsIt() throws {
        let file = try Fixture.writeJPEG(at: path("rate.jpg"))
        let sidecar = ExifToolWriter.sidecarPath(for: file)

        let back = try roundTrip(Fixture.record(file: file, rating: 4), fields: [.rating])
        XCTAssertEqual(back.rating, 4)

        // 0 scrubs the tag rather than pinning a literal 0.
        let clear = ExifToolWriter.write(record: Fixture.record(file: file, sidecar: sidecar, rating: 0),
                                         fields: [.rating])
        guard case .success = clear else { return XCTFail("clear write failed: \(clear)") }
        XCTAssertEqual(SidecarIO.read(file: file, sidecar: sidecar).rating, 0)
    }

    func testGPSSouthWestHemisphereRoundTrips() throws {
        // The sign-flip regression: a south + west coordinate must come back
        // negative on both axes, not mirrored into the N/E hemisphere.
        let file = try Fixture.writeJPEG(at: path("gps.jpg"))
        let back = try roundTrip(
            Fixture.record(file: file, latitude: -12.3456700, longitude: -45.6789000),
            fields: [.location])
        XCTAssertEqual(try XCTUnwrap(back.latitude), -12.3456700, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(back.longitude), -45.6789000, accuracy: 1e-5)
    }

    func testCaptureDateWithOffsetRoundTrips() throws {
        let file = try Fixture.writeJPEG(at: path("date.jpg"))
        var c = DateComponents()
        c.year = 2024; c.month = 3; c.day = 9; c.hour = 15; c.minute = 30; c.second = 45
        c.timeZone = TimeZone(identifier: "UTC")
        let instant = Calendar(identifier: .gregorian).date(from: c)!

        let back = try roundTrip(
            Fixture.record(file: file, captureDate: instant,
                           timezone: .fixed(offsetMinutes: -480, label: "")),
            fields: [.captureDate])

        let date = try XCTUnwrap(back.captureDate)
        XCTAssertEqual(date.timeIntervalSinceReferenceDate,
                       instant.timeIntervalSinceReferenceDate, accuracy: 1.0)
        guard case .fixed(let mins, _) = back.timezone else {
            return XCTFail("expected a fixed timezone, got \(back.timezone)")
        }
        XCTAssertEqual(mins, -480)   // offset rides inside the XMP date string
    }

    func testSeparateMinimalWritesAccumulateInTheSidecar() throws {
        // Writing only one field must not clobber a previously written field:
        // the second write updates the existing sidecar in place.
        let file = try Fixture.writeJPEG(at: path("acc.jpg"))
        let sidecar = ExifToolWriter.sidecarPath(for: file)

        _ = ExifToolWriter.write(record: Fixture.record(file: file, headline: "Kept"),
                                 fields: [.headline])
        _ = ExifToolWriter.write(record: Fixture.record(file: file, sidecar: sidecar,
                                                        keywords: ["one", "two"]),
                                 fields: [.keywords])

        let back = SidecarIO.read(file: file, sidecar: sidecar)
        XCTAssertEqual(back.headline, "Kept")
        XCTAssertEqual(Set(back.keywords), ["one", "two"])
    }
}
