import SwiftUI

struct PreviewPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            StripedBackground()

            if let entry = state.selectedEntry {
                PreviewFrame(url: entry.displayURL)
                    .padding(16)
            } else {
                Text("Select an image")
                    .font(.system(size: 14 * 1.15, weight: .medium))
                    .foregroundStyle(Theme.fgMute)
            }

            // Zoom toolbar overlays the bottom-left of the frame area.
            if state.selectedEntry != nil {
                VStack {
                    Spacer()
                    HStack {
                        zoomToolbar
                            .padding(.leading, 28)
                            .padding(.bottom, 28)
                        Spacer()
                        zoomReadout
                            .padding(.trailing, 28)
                            .padding(.bottom, 28)
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
        Text("Fit  -  100%")
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

// The actual photo with corner crop marks + frame shadow. Uses the same
// embedded-preview extraction path as the thumbnail cache so big RAW files
// don't push memory pressure -- we only ever decode the camera's embedded
// JPEG preview (typically 2-4 MP), never the full RAW pixel grid.
private struct PreviewFrame: View {
    let url: URL
    @State private var image: NSImage?
    @State private var loadingURL: URL?

    var body: some View {
        ZStack {
            // Frame background
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.bgThumb)

            // Image fit-to-frame
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(8)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.fgDim)
            }

            // Corner crop marks (4 brackets, 8px inset)
            CropMarks()
                .padding(8)
        }
        .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.black.opacity(0.5), lineWidth: 0.5)
        )
        .aspectRatio(3.0/2.0, contentMode: .fit)
        .task(id: url) {
            loadingURL = url
            let snapshot = url
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            // Use the higher-fidelity preview path so a small embedded
            // preview falls back to a full-image decode at the requested
            // size. Capped at 3600px which covers up to 4K HiDPI displays.
            let loaded: NSImage? = await Task.detached(priority: .userInitiated) {
                ImageIOFastThumb.makePreview(url: snapshot, maxPixelSide: 3600, scale: scale)
            }.value
            if loadingURL == snapshot {
                image = loaded
            }
        }
    }
}

private struct CropMarks: View {
    let armLength: CGFloat = 10
    let strokeWidth: CGFloat = 1
    let color = Color.white.opacity(0.25)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // Top-left
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: armLength, y: 0))
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 0, y: armLength))
                // Top-right
                p.move(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w - armLength, y: 0))
                p.move(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: armLength))
                // Bottom-left
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: armLength, y: h))
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: h - armLength))
                // Bottom-right
                p.move(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w - armLength, y: h))
                p.move(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w, y: h - armLength))
            }
            .stroke(color, lineWidth: strokeWidth)
        }
    }
}
