import SwiftUI

// Reusable section label: 10pt uppercase tracked, fgDim.
struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    init(_ title: String) {
        self.title = title
        self.trailing = nil
    }

    init<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 10 * 1.15, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.fgDim)

            Spacer(minLength: 6)

            if let trailing {
                trailing
            }
        }
    }
}
