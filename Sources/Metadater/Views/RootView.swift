import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {

            ThreePane()
                .frame(maxHeight: .infinity)

            Rectangle()
                .fill(Theme.line1)
                .frame(height: 1)

            StatusBar()
                .frame(height: 24)
                .background(Theme.bgToolbar)
        }
        .frame(minWidth: 940, minHeight: 500)
        .background(Theme.bgWindow)
        .preferredColorScheme(.dark)
        .acceptingFolderDrop { url in
            state.openFolder(url)
        }
        .navigationTitle(state.folderURL == nil ? "Metadater" : state.folderDisplayName)
    }
}

// Browser stays at a fixed 252pt. Center pane and right pane share the
// remaining width in the same 1.73:1 ratio the prototype uses at its 940pt
// minimum window width -- so as the window scales up, both the preview
// area and the metadata column grow together, instead of the preview
// devouring all the extra space.
private struct ThreePane: View {
    @Environment(AppState.self) private var state

    private let browserWidth: CGFloat = 252
    private let hairlineWidth: CGFloat = 1
    // 252 / (436 + 252) = 0.366. Right pane gets this fraction of the
    // non-browser width, with a 252pt floor at the minimum window width.
    private let rightFraction: CGFloat = 0.366
    private let rightMin: CGFloat = 252

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let nonBrowser = max(0, totalWidth - browserWidth - 2 * hairlineWidth)
            let rightWidth = max(rightMin, nonBrowser * rightFraction)
            let centerWidth = max(0, nonBrowser - rightWidth)

            HStack(spacing: 0) {

                BrowserPane()
                    .frame(width: browserWidth)
                    .background(Theme.bgPanel)

                hairline()

                CenterPane()
                    .frame(width: centerWidth)

                hairline()

                MetadataPane()
                    .frame(width: rightWidth)
                    .background(Theme.bgPanel)
            }
            .frame(width: totalWidth, height: geo.size.height)
        }
    }

    private func hairline() -> some View {
        Rectangle()
            .fill(Theme.line1)
            .frame(width: hairlineWidth)
            .frame(maxHeight: .infinity)
    }
}

private struct CenterPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            if state.folderURL == nil {
                EmptyStateView(onOpen: openFolder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PreviewPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state.selectedEntry != nil {
                    CaptionBlock()
                }
            }
        }
    }

    private func openFolder() {
        FolderPicker.present { url in
            state.openFolder(url)
        }
    }
}
