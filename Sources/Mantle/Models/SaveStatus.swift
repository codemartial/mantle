// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation

enum SaveStatus: Equatable {
    case idle
    case unsaved(count: Int)
    case saving
    case saved
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:            return "All changes saved"
        case .unsaved(let n):  return n == 1 ? "1 unsaved" : "\(n) unsaved"
        case .saving:          return "Saving..."
        case .saved:           return "Saved"
        case .failed(let m):   return "Save failed: \(m)"
        }
    }
}
