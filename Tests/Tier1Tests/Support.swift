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

// Shared fixtures for the tier-1 (fast, in-memory) suite. Nothing here touches
// the disk, ExifTool, or ImageIO: records are built by hand and fed straight
// into the stores, so these helpers stay valid no matter how on-disk reading
// evolves.

enum Fix {

    // An ImageRecord with sensible blank defaults. Pass only the editable
    // fields a test cares about; `id` doubles as the file path (the app keys
    // identity on the path everywhere).
    static func record(
        id: String = "/lib/a.jpg",
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
            id: id,
            file: URL(fileURLWithPath: id),
            sidecarURL: sidecar,
            fmt: "JPEG",
            dim: CGSize(width: 100, height: 100),
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

    // A browser entry. `id` is the path; basename defaults to the filename
    // stem so sort tests read naturally.
    static func entry(
        id: String,
        basename: String? = nil,
        sidecar: URL? = nil,
        format: String = "JPEG"
    ) -> LibraryEntry {
        let url = URL(fileURLWithPath: id)
        return LibraryEntry(
            id: id,
            basename: basename ?? url.deletingPathExtension().lastPathComponent,
            displayURL: url,
            siblingURLs: [url],
            sidecarURL: sidecar,
            format: format,
            displaySize: CGSize(width: 100, height: 100)
        )
    }

    // A UTC Date from components, for deterministic capture-date tests.
    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}

// Build an AppState pre-loaded with records (ingested into EditStore) and a
// library of entries. Because the records are already ingested, the lazy
// `ingestIfNeeded` disk read inside selection methods short-circuits, so the
// selection/batch logic runs entirely in memory.
@MainActor
func makeState(records: [ImageRecord] = [], library: [LibraryEntry] = []) -> AppState {
    let state = AppState()
    state.library = library
    for r in records { state.edits.ingest(r) }
    return state
}
