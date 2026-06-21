// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation

// User preference for numeric rating shortcuts while multiple images are
// selected. Single-image mode always accepts 0...5 when text input is not
// focused; batch mode asks the first time unless the user has chosen here.
enum BatchRatingNumberShortcutPreference: String, CaseIterable, Identifiable, Sendable {
    case unset
    case enabled
    case disabled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unset:    return "Ask the first time"
        case .enabled:  return "Enable in batch mode"
        case .disabled: return "Disable in batch mode"
        }
    }

    private static let key = "batchRatingNumberShortcut.v1"

    static func load() -> BatchRatingNumberShortcutPreference {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let value = BatchRatingNumberShortcutPreference(rawValue: raw) else {
            return .unset
        }
        return value
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}
