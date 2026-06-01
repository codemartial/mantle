// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation
import Observation

// In-process log buffer for the debug strip at the top of the metadata
// pane. Cleared on app restart (process restart = automatic). Bounded
// to avoid unbounded growth in long sessions.

@MainActor
@Observable
final class DebugLog {
    private static let maxLines = 500
    private static let stampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private(set) var lines: [String] = []

    func append(_ line: String) {
        lines.append("\(Self.stampFormatter.string(from: Date())) \(line)")
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }

    func clear() {
        lines.removeAll(keepingCapacity: true)
    }
}
