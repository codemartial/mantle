// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI

// A five-star rating control. Stateless about the value (the parent owns
// it); reports a new rating through onSet. Clicking the star that already
// equals the current rating clears it to 0 -- the conventional "click the
// last filled star again to un-rate" gesture. Hover previews the rating the
// click would set.
struct RatingStars: View {
    let rating: Int
    var starSize: CGFloat = 15
    let onSet: (Int) -> Void

    @State private var hover: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                let shown = hover == 0 ? rating : hover
                let filled = i <= shown
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.system(size: starSize))
                    .foregroundStyle(filled ? Theme.warn : .white.opacity(0.55))
                    .contentShape(Rectangle())
                    .onTapGesture { onSet(i == rating ? 0 : i) }
                    .onHover { inside in hover = inside ? i : 0 }
                    .help(i == 1 ? "Rate 1 star" : "Rate \(i) stars")
            }
        }
    }
}
