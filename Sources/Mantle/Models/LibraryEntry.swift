// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation
import CoreGraphics

// A row in the browser. One entry per basename group: a lone JPEG, a lone
// RAW, or a RAW+JPEG pair sharing a basename. The pair shares one sidecar.
//
// `displaySize` is the orientation-applied pixel size (so a portrait reads
// as taller than it is wide). Used by ThumbnailCell to pick its aspect
// ratio so portraits make the cell taller, panoramas make it wider, and
// the column width stays constant.
struct LibraryEntry: Identifiable, Hashable, Sendable {
    let id: String
    let basename: String
    let displayURL: URL
    let siblingURLs: [URL]
    let sidecarURL: URL?
    let format: String
    let displaySize: CGSize

    var aspectRatio: CGFloat {
        guard displaySize.width > 0, displaySize.height > 0 else { return 1.5 }
        return displaySize.width / displaySize.height
    }
}
