import SwiftUI

struct BrowserPane: View {
    @Environment(AppState.self) private var state
    @Binding var mode: BrowserMode

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
                switch mode {
                case .grid: gridBody
                case .list: listBody
                }
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

    // MARK: - Grid

    private var gridBody: some View {
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

    // MARK: - List

    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(state.library) { entry in
                    ListRow(
                        entry: entry,
                        isSelected: state.selectedID == entry.id,
                        cache: state.thumbs
                    )
                    .onTapGesture {
                        state.select(entry.id)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
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

// One row in the list-mode browser. Layout matches .list-row in styles.css:
//   grid-template-columns: 36px 1fr auto
// Thumb + (filename / dimensions) + format badge.
private struct ListRow: View {
    let entry: LibraryEntry
    let isSelected: Bool
    let cache: ThumbnailCache

    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            thumb
                .frame(width: 36, height: 24)
                .background(Theme.bgThumb)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.basename)
                    .font(.system(size: 11.5 * 1.15))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(dimensions)
                    .font(.system(size: 10.5 * 1.15, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.fgFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.format)
                .font(.system(size: 10.5 * 1.15, design: .monospaced))
                .foregroundStyle(Theme.fgFaint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isSelected ? Theme.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .task(id: entry.displayURL) {
            let loaded = await cache.requestThumbnail(for: entry.displayURL)
            if !Task.isCancelled { image = loaded }
        }
    }

    @ViewBuilder
    private var thumb: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            Image(systemName: "photo")
                .font(.system(size: 11 * 1.15))
                .foregroundStyle(Theme.fgFaint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var dimensions: String {
        let w = Int(entry.displaySize.width)
        let h = Int(entry.displaySize.height)
        guard w > 0, h > 0 else { return "--" }
        return "\(w) x \(h)"
    }
}
