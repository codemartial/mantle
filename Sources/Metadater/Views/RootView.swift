import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {

            if state.folderURL == nil {
                EmptyStateView(onOpen: openFolder)
                    .frame(maxHeight: .infinity)
            } else {
                ThreePane()
                    .frame(maxHeight: .infinity)
            }

            Rectangle()
                .fill(Theme.line1)
                .frame(height: 1)

            StatusBar(state: state)
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

    private func openFolder() {
        FolderPicker.present { url in
            state.openFolder(url)
        }
    }
}

private struct ThreePane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 0) {

            BrowserPanePlaceholder()
                .frame(width: 252)
                .background(Theme.bgPanel)

            hairline()

            CenterPanePlaceholder()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bgWindow)

            hairline()

            MetadataPanePlaceholder()
                .frame(width: 252)
                .background(Theme.bgPanel)
        }
    }

    private func hairline() -> some View {
        Rectangle()
            .fill(Theme.line1)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

private struct BrowserPanePlaceholder: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Browser")
                    .font(Typo.label)
                    .foregroundStyle(Theme.fgDim)
                Spacer()
                Text("\(state.library.count) items")
                    .font(Typo.small)
                    .foregroundStyle(Theme.fgFaint)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            Spacer()
            Text("(scan pending in step 3)")
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
            Text("Select an image")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.fgMute)
            Spacer()
        }
    }
}

private struct MetadataPanePlaceholder: View {
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

struct StatusBar: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 12) {
            if let folderURL = state.folderURL {
                Text("\(state.library.count) items")
                    .font(Typo.small)
                    .foregroundStyle(Theme.fgDim)
                Text("|")
                    .foregroundStyle(Theme.fgFaint)
                Text(folderURL.path)
                    .font(Typo.mono)
                    .foregroundStyle(Theme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("no folder open")
                    .font(Typo.small)
                    .foregroundStyle(Theme.fgFaint)
            }

            Spacer()

            Text(state.status.displayText)
                .font(Typo.small)
                .foregroundStyle(Theme.fgDim)

            Text("|")
                .foregroundStyle(Theme.fgFaint)

            Text("Metadater 0.1")
                .font(Typo.small)
                .foregroundStyle(Theme.fgFaint)
        }
        .padding(.horizontal, 12)
    }
}
