// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation

enum TZRule: Equatable, Hashable, Sendable {
    case unknown                                    // no TZ info available
    case auto                                       // resolved from GPS each render
    case fixed(offsetMinutes: Int, label: String)
}
