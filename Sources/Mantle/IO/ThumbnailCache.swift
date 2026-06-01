// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import AppKit
import ImageIO
import os.log

// Thumbnail extraction service. Each browser cell drives its own load via
// the async `requestThumbnail` API, with `@State` holding the result.
// Avoids relying on a single @Observable dict invalidating all 144 cells
// at once, which was the source of the "decode gets stuck after a few"
// behaviour -- the cascade of body re-evaluations on every per-thumb
// completion overwhelmed the layout / observation pipeline.
//
// Concurrency: classic GCD queue + DispatchSemaphore. ImageIO is sync; a
// blocking semaphore on GCD threads is safe (each GCD thread is independent
// of the Swift cooperative pool, so blocking doesn't starve it).

private let thumbLog = Logger(subsystem: "com.tahirhashmi.mantle", category: "thumb")

private let thumbQueue = DispatchQueue(
    label: "com.tahirhashmi.mantle.thumbs",
    qos: .userInitiated,
    attributes: .concurrent
)
private let thumbGate = DispatchSemaphore(value: 4)

@MainActor
final class ThumbnailCache {

    // Cache lives on the main actor. Holds decoded NSImages keyed by file
    // path. Crude eviction: when over `maxEntries`, drop everything.
    private var cached: [String: NSImage] = [:]
    private let maxEntries = 1024

    // Async per-cell request. Hot path is the dict lookup; cold path hops
    // to the dispatch queue, waits behind the semaphore, decodes, returns.
    func requestThumbnail(for url: URL, side: CGFloat = 320) async -> NSImage? {
        let key = url.path

        if let cached = self.cached[key] {
            return cached
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelSide = side * scale

        thumbLog.debug("decode start: \(url.lastPathComponent, privacy: .public)")

        let image: NSImage? = await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
            thumbQueue.async {
                thumbGate.wait()
                let result = ImageIOFastThumb.makeThumbnail(
                    url: url,
                    maxPixelSide: pixelSide,
                    scale: scale
                )
                thumbGate.signal()
                cont.resume(returning: result)
            }
        }

        if let image {
            thumbLog.debug("decode ok: \(url.lastPathComponent, privacy: .public)")
            if cached.count >= maxEntries {
                cached.removeAll(keepingCapacity: true)
            }
            cached[key] = image
        } else {
            thumbLog.error("decode failed: \(url.path, privacy: .public)")
        }
        return image
    }

    func reset() {
        cached.removeAll(keepingCapacity: false)
    }
}

// Pure functions. Safe from any thread.
//
// Two paths, branched on whether the file is a RAW format:
//
//   Non-RAW (JPEG, HEIC, PNG, TIFF): the file IS the image. Synthesise the
//   thumb from the full image -- ImageIO downsamples efficiently and we
//   get a sharp preview at the requested size.
//
//   RAW (NEF, CR2/3, ARW, RAF, ORF, DNG): never decode the RAW pixel data.
//   Extract the camera's embedded JPEG preview at index 0, then try higher
//   indices (some formats stash usable JPEG previews there), then fall back
//   to ExifTool which can pull `-PreviewImage / -JpgFromRaw` from formats
//   Apple's RAW framework refuses (Nikon Z8 HE NEFs at the time of writing).
enum ImageIOFastThumb {

    static func makeThumbnail(url: URL, maxPixelSide: CGFloat, scale: CGFloat) -> NSImage? {
        decode(url: url, maxPixelSide: maxPixelSide, scale: scale)
    }

    static func makePreview(url: URL, maxPixelSide: CGFloat, scale: CGFloat) -> NSImage? {
        decode(url: url, maxPixelSide: maxPixelSide, scale: scale)
    }

    private static func decode(url: URL, maxPixelSide: CGFloat, scale: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            // Even CGImageSource refused. Only RAW formats would benefit
            // from the ExifTool fallback here.
            if LibraryIndex.rawExtensions.contains(url.pathExtension.lowercased()) {
                return ExifToolOneShot.extractPreview(url: url, maxPixelSide: maxPixelSide, scale: scale)
            }
            return nil
        }

        let isRaw = LibraryIndex.rawExtensions.contains(url.pathExtension.lowercased())

        if !isRaw {
            return decodeNonRaw(source: source, maxPixelSide: maxPixelSide, scale: scale)
        }
        return decodeRaw(source: source, url: url, maxPixelSide: maxPixelSide, scale: scale)
    }

    // MARK: - Non-RAW path

    private static func decodeNonRaw(
        source: CGImageSource,
        maxPixelSide: CGFloat,
        scale: CGFloat
    ) -> NSImage? {
        // Synthesise from the full image. For a JPEG/HEIC/PNG/TIFF, the
        // "full image" is the only image in the file -- this is just a
        // straight downsample, fast and sharp.
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true,
            kCGImageSourceShouldCacheImmediately:         true,
            kCGImageSourceThumbnailMaxPixelSize:          maxPixelSide,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }
        return wrap(cg, scale: scale)
    }

    // MARK: - RAW path

    private static func decodeRaw(
        source: CGImageSource,
        url: URL,
        maxPixelSide: CGFloat,
        scale: CGFloat
    ) -> NSImage? {
        // Embedded-only: never synthesise from the RAW pixel grid.
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways:   false,
            kCGImageSourceCreateThumbnailWithTransform:     true,
            kCGImageSourceShouldCacheImmediately:           true,
            kCGImageSourceThumbnailMaxPixelSize:            maxPixelSide,
        ]

        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
            return wrap(cg, scale: scale)
        }

        // Try higher indices (multi-image RAWs).
        let count = CGImageSourceGetCount(source)
        var best: CGImage?
        for i in 1..<count {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, i, opts as CFDictionary) else { continue }
            if let cur = best, cg.width <= cur.width { continue }
            best = cg
        }
        if let best { return wrap(best, scale: scale) }

        // ExifTool fallback for formats Apple's RAW framework can't open.
        return ExifToolOneShot.extractPreview(
            url: url,
            maxPixelSide: maxPixelSide,
            scale: scale
        )
    }

    private static func wrap(_ cg: CGImage, scale: CGFloat) -> NSImage {
        NSImage(
            cgImage: cg,
            size: NSSize(width: CGFloat(cg.width) / scale,
                         height: CGFloat(cg.height) / scale)
        )
    }
}
