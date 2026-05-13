import SwiftUI

// Each cell drives its own thumbnail load via .task + @State. No reliance
// on a global @Observable dict that would force-invalidate every cell on
// each decode -- this is what kept stalling out the browser after the
// first few thumbs decoded.

struct ThumbnailCell: View {
    let entry: LibraryEntry
    let isSelected: Bool
    let cache: ThumbnailCache

    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ZStack {
                    Theme.bgThumb
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
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

            // Selection / format badge
            if isSelected {
                selectionBadge
                    .padding(4)
            } else if entry.format == "RAW + JPEG" || entry.format == "RAW" {
                formatBadge
                    .padding(4)
            }
        }
        .aspectRatio(cellAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isSelected ? Theme.accent : Color.clear,
                    lineWidth: 1.5
                )
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

    /// Prefer the decoded image's actual aspect once it's loaded -- the
    /// extracted preview JPEG has reliable dimensions for every file we can
    /// decode, including Z8 NEFs whose dimensions ImageIO can't read off
    /// the parent. Falls back to the scan-time estimate, then 3:2.
    private var cellAspectRatio: CGFloat {
        if let image, image.size.width > 0, image.size.height > 0 {
            return image.size.width / image.size.height
        }
        return entry.aspectRatio
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
