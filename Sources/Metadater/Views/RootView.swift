import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 0) {

            HStack(spacing: 0) {

                // Left pane: browser
                LeftPanePlaceholder()
                    .frame(width: 252)
                    .background(Theme.bgPanel)

                hairline()

                // Center pane: preview + caption editor
                CenterPanePlaceholder()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bgWindow)

                hairline()

                // Right pane: metadata
                RightPanePlaceholder()
                    .frame(width: 252)
                    .background(Theme.bgPanel)
            }
            .frame(maxHeight: .infinity)

            Rectangle()
                .fill(Theme.line1)
                .frame(height: 1)

            StatusBarPlaceholder()
                .frame(height: 24)
                .background(Theme.bgToolbar)
        }
        .frame(minWidth: 940, minHeight: 500)
        .background(Theme.bgWindow)
        .preferredColorScheme(.dark)
    }

    private func hairline() -> some View {
        Rectangle()
            .fill(Theme.line1)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

// Placeholders for step 1 -- replaced by real views in steps 3 / 4 / 5 / 7.
private struct LeftPanePlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Browser")
                    .font(Typo.label)
                    .foregroundStyle(Theme.fgDim)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            Spacer()
            Text("(no folder open)")
                .font(Typo.small)
                .foregroundStyle(Theme.fgFaint)
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }
}

private struct CenterPanePlaceholder: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Metadater")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.fgMute)
            Text("Open a folder to begin")
                .font(Typo.body)
                .foregroundStyle(Theme.fgFaint)
                .padding(.top, 4)
            Spacer()
        }
    }
}

private struct RightPanePlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Metadata")
                    .font(Typo.label)
                    .foregroundStyle(Theme.fgDim)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            Spacer()
            Text("--")
                .font(Typo.small)
                .foregroundStyle(Theme.fgFaint)
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }
}

private struct StatusBarPlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("0 items")
                .font(Typo.small)
                .foregroundStyle(Theme.fgDim)
            Spacer()
            Text("All changes saved")
                .font(Typo.small)
                .foregroundStyle(Theme.fgDim)
            Spacer()
            Text("Metadater 0.1")
                .font(Typo.small)
                .foregroundStyle(Theme.fgFaint)
        }
        .padding(.horizontal, 12)
    }
}
