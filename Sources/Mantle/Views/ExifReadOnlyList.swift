// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI

// kv-list per spec: grid auto/1fr with 3px row gap, 12px column gap. Labels
// fgDim, values tabular-num monospace right-aligned, ellipsised.

struct ExifReadOnlyList: View {
    let title: String
    let items: [(String, String)]
    var trailing: AnyView? = nil

    init(title: String, items: [(String, String)]) {
        self.title = title
        self.items = items
        self.trailing = nil
    }

    init<Trailing: View>(title: String, items: [(String, String)], @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.items = items
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let trailing {
                SectionHeader(title) { trailing }
            } else {
                SectionHeader(title)
            }

            VStack(spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.0)
                            .font(.system(size: 11 * 1.15))
                            .foregroundStyle(Theme.fgDim)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Text(item.1.isEmpty ? "--" : item.1)
                            .font(.system(size: 11 * 1.15, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(item.1.isEmpty ? Theme.fgFaint : Theme.fg)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }
}
