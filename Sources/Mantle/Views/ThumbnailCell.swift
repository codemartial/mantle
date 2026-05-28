import SwiftUI

// Each cell drives its own thumbnail load via .task + @State. No reliance
// on a global @Observable dict that would force-invalidate every cell on
// each decode -- this is what kept stalling out the browser after the
// first few thumbs decoded.

struct ThumbnailCell: View {
    let entry: LibraryEntry
    let isSelected: Bool
    // 1-based position in batchOrder. nil when not in batch mode (or not a
    // batch member). Index 1 = master.
    var batchIndex: Int? = nil
    let cache: ThumbnailCache

    @State private var image: NSImage?

    private var isMaster: Bool { batchIndex == 1 }
    private var isBatchMember: Bool { batchIndex != nil }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ZStack {
                    Theme.bgThumb
                    if let image {
                        // scaledToFit centers the image inside the square
                        // cell, preserving aspect ratio. Tall and wide shots
                        // get the same cell size; orientation just shows up
                        // as letterboxing in the unused axis (bgThumb
                        // shows through).
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        Image(systemName: "photo")
                            .font(Typo.size(22))
                            .foregroundStyle(Theme.fgFaint)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }

            // Filename stamp
            VStack {
                Spacer()
                HStack {
                    Text(entry.basename)
                        .font(Typo.size(9, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 5)
                        .padding(.bottom, 4)
                    Spacer()
                }
            }

            // Selection / batch / format badge
            if isBatchMember {
                batchBadge
                    .padding(4)
            } else if isSelected {
                selectionBadge
                    .padding(4)
            } else if entry.format == "RAW + JPEG" || entry.format == "RAW" {
                formatBadge
                    .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(strokeColor, lineWidth: strokeWidth)
        )
        .contentShape(Rectangle())
        .task(id: entry.displayURL) {
            // .task gets a Task that's cancelled on view disappear / id
            // change. The cache lookup is fast when hit; on miss it suspends
            // until the dispatch queue decode returns.
            let loaded = await cache.requestThumbnail(for: entry.displayURL)
            // Cancellation check: avoid stomping if the view has moved to a
            // different entry while we were awaiting.
            if !Task.isCancelled {
                image = loaded
            }
        }
    }

    private var selectionBadge: some View {
        ZStack {
            Circle().fill(Theme.accent)
            Image(systemName: "checkmark")
                .font(Typo.size(9, weight: .bold))
                .foregroundStyle(Theme.accentFg)
        }
        .frame(width: 18, height: 18)
    }

    // Batch position. Master (index 1) gets a slightly larger badge with an
    // "M" glyph; the rest show the 1-based order number.
    private var batchBadge: some View {
        ZStack {
            Circle().fill(Theme.accent)
            Group {
                if isMaster {
                    Text("M")
                        .font(Typo.size(10, weight: .bold))
                } else if let idx = batchIndex {
                    Text(String(idx))
                        .font(Typo.size(10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Theme.accentFg)
        }
        .frame(width: isMaster ? 22 : 20, height: isMaster ? 22 : 20)
    }

    private var strokeColor: Color {
        if isMaster { return Theme.accent }
        if isBatchMember { return Theme.accent.opacity(0.7) }
        if isSelected { return Theme.accent }
        return .clear
    }

    private var strokeWidth: CGFloat {
        if isMaster { return 2 }
        if isBatchMember { return 1.5 }
        if isSelected { return 1.5 }
        return 0
    }

    private var formatBadge: some View {
        Text(entry.format == "RAW + JPEG" ? "R+J" : "R")
            .font(Typo.size(9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55))
            .foregroundStyle(.white.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
