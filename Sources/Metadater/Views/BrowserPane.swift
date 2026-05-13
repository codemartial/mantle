import SwiftUI

struct BrowserPane: View {
    @Environment(AppState.self) private var state

    // Density-m default per the prototype: 2 columns, 8px gap.
    private let columns = [
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .center),
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .center),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            header
                .padding(.horizontal, 12)
                .frame(height: 28)

            Rectangle()
                .fill(Theme.lineSoft)
                .frame(height: 1)

            if state.folderURL == nil {
                placeholder("No folder open")
            } else if state.library.isEmpty && !state.isScanning {
                placeholder("No images in this folder")
            } else {
                grid
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(headerLabel)
                .font(.system(size: 11 * 1.15, weight: .semibold))
                .tracking(0.65)
                .textCase(.uppercase)
                .foregroundStyle(Theme.fgMute)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if state.isScanning {
                Text("scanning")
                    .font(.system(size: 11 * 1.15))
                    .foregroundStyle(Theme.fgFaint)
            } else {
                Text(headerCount)
                    .font(.system(size: 11 * 1.15, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.fgFaint)
            }
        }
    }

    private var headerLabel: String {
        if let url = state.folderURL {
            return url.lastPathComponent
        }
        return "Browser"
    }

    private var headerCount: String {
        guard state.folderURL != nil else { return "--" }
        return "\(state.library.count)"
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(state.library) { entry in
                    ThumbnailCell(
                        entry: entry,
                        isSelected: state.selectedID == entry.id,
                        cache: state.thumbs
                    )
                    .onTapGesture {
                        state.select(entry.id)
                    }
                }
            }
            .padding(8)
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgFaint)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
