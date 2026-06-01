// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI

// Horizontal alternating bands used as the backdrop for the preview frame
// and the empty state, per the prototype's repeating-linear-gradient.
struct StripedBackground: View {
    var bandHeight: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            var alt = false
            while y < size.height {
                let height = min(bandHeight, size.height - y)
                let band = CGRect(x: 0, y: y, width: size.width, height: height)
                context.fill(
                    Path(band),
                    with: .color(alt ? Theme.bgStripeB : Theme.bgStripeA)
                )
                y += bandHeight
                alt.toggle()
            }
        }
    }
}
