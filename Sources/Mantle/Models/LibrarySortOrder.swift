// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation

// How the browser grid orders its entries. The only sort key is the
// filename (LibraryEntry.basename); the toolbar's sort button flips the
// direction. Kept deliberately small -- a single criterion, two directions.
enum LibrarySortOrder: Sendable {
    case nameAscending
    case nameDescending

    var toggled: LibrarySortOrder {
        self == .nameAscending ? .nameDescending : .nameAscending
    }

    // SF Symbol for the toolbar button: a downward arrow reads as "A at the
    // top, going down to Z" (ascending), an upward arrow as the reverse.
    var symbolName: String {
        self == .nameAscending ? "arrow.down" : "arrow.up"
    }

    var help: String {
        self == .nameAscending
            ? "Sorted by name, A to Z (click to reverse)"
            : "Sorted by name, Z to A (click to reverse)"
    }
}
