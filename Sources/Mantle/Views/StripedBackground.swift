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
