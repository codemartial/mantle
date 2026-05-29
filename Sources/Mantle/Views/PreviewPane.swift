import SwiftUI

struct PreviewPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            if let entry = state.selectedEntry {
                ZoomablePreview(url: entry.displayURL)
            } else {
                Text("Select an image")
                    .font(.system(size: 14 * 1.15, weight: .medium))
                    .foregroundStyle(Theme.fgMute)
            }
        }
    }
}

// The photo, fit to the pane with live zoom and pan. Uses the same
// embedded-preview extraction path as the thumbnail cache so big RAW
// files don't push memory pressure -- we only ever decode the camera's
// embedded JPEG preview (typically 2-4 MP), never the full RAW grid.
//
// `scale` is points-per-image-pixel and is only consulted when `isFit`
// is false. In fit mode we recompute the fit scale live from the current
// pane size, so the photo keeps filling the pane as the window resizes.
private struct ZoomablePreview: View {
    let url: URL

    @State private var image: NSImage?
    @State private var loadingURL: URL?
    @State private var pixelSize: CGSize = .zero

    @State private var isFit = true
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var gestureStartScale: CGFloat?
    @State private var gestureStartOffset: CGSize?

    // Leave the same 12pt breathing room around the fitted photo that the
    // old static layout used.
    private let inset: CGFloat = 12
    // Cap zoom-in at 800% of the preview's own pixels.
    private let maxScale: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            let fit = fitScale(in: container)
            let eff = isFit ? fit : scale

            ZStack {
                if let image {
                    let display = CGSize(width: pixelSize.width * eff,
                                         height: pixelSize.height * eff)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: display.width, height: display.height)
                        .offset(clamp(offset, display: display, container: container))
                        .frame(width: container.width, height: container.height)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(eff: eff, container: container))
                        .simultaneousGesture(magnifyGesture(fit: fit))
                        .onTapGesture(count: 2, coordinateSpace: .local) { loc in
                            toggle(at: loc, fit: fit, container: container)
                        }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.fgDim)
                        .frame(width: container.width, height: container.height)
                }

                VStack {
                    Spacer()
                    HStack {
                        zoomToolbar
                            .padding(.leading, 16)
                            .padding(.bottom, 16)
                        Spacer()
                        if image != nil {
                            zoomReadout(eff: eff)
                                .padding(.trailing, 16)
                                .padding(.bottom, 16)
                        }
                    }
                }
            }
            .clipped()
        }
        .task(id: url) { await load() }
    }

    // MARK: - Zoom overlays

    private var zoomToolbar: some View {
        HStack(spacing: 6) {
            zoomButton(system: "arrow.up.left.and.arrow.down.right",
                       label: "Fit",
                       active: isFit) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFit = true
                    offset = .zero
                }
            }
            zoomButton(label: "1:1",
                       active: !isFit && abs(scale - 1) < 0.001) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFit = false
                    scale = 1
                    offset = .zero
                }
            }
        }
        .padding(4)
        .background(.black.opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func zoomButton(
        system: String? = nil,
        label: String? = nil,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let system { Image(systemName: system).font(.system(size: 9 * 1.15, weight: .medium)) }
                if let label  { Text(label).font(.system(size: 10 * 1.15, design: .monospaced)) }
            }
            .foregroundStyle(.white.opacity(active ? 1 : 0.78))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(.white.opacity(active ? 0.16 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func zoomReadout(eff: CGFloat) -> some View {
        Text("\(Int((eff * 100).rounded()))%")
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

    // MARK: - Gestures

    private func magnifyGesture(fit: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start: CGFloat
                if let s = gestureStartScale {
                    start = s
                } else {
                    start = isFit ? fit : scale
                    gestureStartScale = start
                    isFit = false
                }
                let lower = min(fit, 1)
                let upper = max(maxScale, fit)
                scale = min(max(start * value.magnification, lower), upper)
            }
            .onEnded { _ in
                gestureStartScale = nil
                if scale <= fit {
                    isFit = true
                    offset = .zero
                }
            }
    }

    private func dragGesture(eff: CGFloat, container: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isFit else { return }
                let start = gestureStartOffset ?? offset
                if gestureStartOffset == nil { gestureStartOffset = start }
                let display = CGSize(width: pixelSize.width * eff,
                                     height: pixelSize.height * eff)
                offset = clamp(
                    CGSize(width: start.width + value.translation.width,
                           height: start.height + value.translation.height),
                    display: display,
                    container: container
                )
            }
            .onEnded { _ in gestureStartOffset = nil }
    }

    private func toggle(at loc: CGPoint, fit: CGFloat, container: CGSize) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if isFit {
                // Switching to 1:1: recentre on the clicked point, as close
                // to the middle as the pan limits allow. While fitted the
                // image is centred (offset == .zero) at scale `fit`, so the
                // image-pixel offset of the click from the image centre is
                // (loc - paneCentre) / fit. Negating it (times the new
                // scale) puts that same point back at the pane centre.
                let centre = CGPoint(x: container.width / 2, y: container.height / 2)
                isFit = false
                scale = 1
                let want = CGSize(width: -(loc.x - centre.x) / fit * scale,
                                  height: -(loc.y - centre.y) / fit * scale)
                let display = CGSize(width: pixelSize.width * scale,
                                     height: pixelSize.height * scale)
                offset = clamp(want, display: display, container: container)
            } else {
                isFit = true
                offset = .zero
            }
        }
    }

    // MARK: - Geometry

    private func fitScale(in container: CGSize) -> CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return 1 }
        let availW = max(1, container.width - inset * 2)
        let availH = max(1, container.height - inset * 2)
        return min(availW / pixelSize.width, availH / pixelSize.height)
    }

    // Keep the photo's overflow centred: you can pan a zoomed-in image up to
    // the point where its edge meets the pane edge, no further. When the
    // image is smaller than the pane on an axis it stays pinned to centre.
    private func clamp(_ o: CGSize, display: CGSize, container: CGSize) -> CGSize {
        let maxX = max(0, (display.width - container.width) / 2)
        let maxY = max(0, (display.height - container.height) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX),
                      height: min(max(o.height, -maxY), maxY))
    }

    // MARK: - Loading

    private func load() async {
        loadingURL = url
        let snapshot = url
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        let loaded: NSImage? = await Task.detached(priority: .userInitiated) {
            ImageIOFastThumb.makePreview(url: snapshot, maxPixelSide: 3600, scale: scaleFactor)
        }.value
        guard loadingURL == snapshot else { return }
        image = loaded
        pixelSize = loaded.map(Self.pixelSize) ?? .zero
        // New photo: start fitted and centred.
        isFit = true
        scale = 1
        offset = .zero
    }

    private static func pixelSize(_ img: NSImage) -> CGSize {
        if let rep = img.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return img.size
    }
}
