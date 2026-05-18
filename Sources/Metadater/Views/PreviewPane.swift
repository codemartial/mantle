import SwiftUI

struct PreviewPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            if let entry = state.selectedEntry {
                PreviewImage(url: entry.displayURL)
                    .padding(12)
            } else {
                Text("Select an image")
                    .font(.system(size: 14 * 1.15, weight: .medium))
                    .foregroundStyle(Theme.fgMute)
            }

            // Zoom toolbar overlay sits on top of the photo at the bottom
            // corners. Visual-only for now -- live zoom controls land when
            // the preview gets MapKit / pan-zoom.
            if state.selectedEntry != nil {
                VStack {
                    Spacer()
                    HStack {
                        zoomToolbar
                            .padding(.leading, 16)
                            .padding(.bottom, 16)
                        Spacer()
                        zoomReadout
                            .padding(.trailing, 16)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
    }

    // MARK: - Zoom overlays

    private var zoomToolbar: some View {
        HStack(spacing: 6) {
            zoomButton(system: "arrow.up.left.and.arrow.down.right", label: "Fit")
            zoomButton(label: "1:1")
            zoomButton(system: "arrow.clockwise")
        }
        .padding(4)
        .background(.black.opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func zoomButton(system: String? = nil, label: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let system { Image(systemName: system).font(.system(size: 9 * 1.15, weight: .medium)) }
            if let label  { Text(label).font(.system(size: 10 * 1.15, design: .monospaced)) }
        }
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var zoomReadout: some View {
        Text("Fit")
            .font(.system(size: 10 * 1.15, design: .monospaced))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// The photo, fit to the pane. No frame, no corner marks, no padding,
// no shadow -- just the image scaled-to-fit with the window background
// showing through on whichever axis has leftover space. Uses the same
// embedded-preview extraction path as the thumbnail cache so big RAW
// files don't push memory pressure -- we only ever decode the camera's
// embedded JPEG preview (typically 2-4 MP), never the full RAW grid.
private struct PreviewImage: View {
    let url: URL
    @State private var image: NSImage?
    @State private var loadingURL: URL?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.fgDim)
            }
        }
        .task(id: url) {
            loadingURL = url
            let snapshot = url
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let loaded: NSImage? = await Task.detached(priority: .userInitiated) {
                ImageIOFastThumb.makePreview(url: snapshot, maxPixelSide: 3600, scale: scale)
            }.value
            if loadingURL == snapshot {
                image = loaded
            }
        }
    }
}
