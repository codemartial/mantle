// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation
import CoreGraphics
import ImageIO
import os.log

private let scanLog = Logger(subsystem: "com.tahirhashmi.mantle", category: "scan")

// One-level folder scan, RAW+JPEG basename pairing, sidecar association.
// Bare foo.xmp wins over foo.NEF.xmp when both exist for the same basename.

enum LibraryIndex {

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff",
        "nef", "cr2", "cr3", "arw", "raf", "orf", "dng",
    ]

    static let rawExtensions: Set<String> = [
        "nef", "cr2", "cr3", "arw", "raf", "orf", "dng",
    ]

    static func scan(_ folder: URL) -> [LibraryEntry] {
        let fm = FileManager.default
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            return []
        }

        var imagesByBasename: [String: [URL]] = [:]
        var bareSidecars: [String: URL] = [:]
        var extSidecars: [String: URL] = [:]

        for url in items {
            let ext = url.pathExtension.lowercased()

            if ext == "xmp" {
                let inner = url.deletingPathExtension().lastPathComponent.lowercased()
                let innerExt = (inner as NSString).pathExtension.lowercased()
                if imageExtensions.contains(innerExt) {
                    extSidecars[inner] = url
                } else {
                    bareSidecars[inner] = url
                }
                continue
            }

            guard imageExtensions.contains(ext) else { continue }

            if let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
               isDir {
                continue
            }

            let basename = url.deletingPathExtension().lastPathComponent.lowercased()
            imagesByBasename[basename, default: []].append(url)
        }

        var entries: [LibraryEntry] = []
        for (basename, urls) in imagesByBasename {
            var sidecar: URL? = bareSidecars[basename]
            if sidecar == nil {
                for u in urls {
                    let extKey = basename + "." + u.pathExtension.lowercased()
                    if let s = extSidecars[extKey] {
                        sidecar = s
                        break
                    }
                }
            }

            let hasRaw    = urls.contains { rawExtensions.contains($0.pathExtension.lowercased()) }
            let hasNonRaw = urls.contains { !rawExtensions.contains($0.pathExtension.lowercased()) }

            let format: String
            switch (hasRaw, hasNonRaw) {
            case (true, true):   format = "RAW + JPEG"
            case (true, false):  format = "RAW"
            case (false, true):  format = formatLabel(forExt: urls.first!.pathExtension.lowercased())
            default:             continue
            }

            let displayURL = urls.first { !rawExtensions.contains($0.pathExtension.lowercased()) }
                          ?? urls.first!

            entries.append(LibraryEntry(
                id: displayURL.path,
                basename: displayURL.deletingPathExtension().lastPathComponent,
                displayURL: displayURL,
                siblingURLs: urls.sorted { $0.path < $1.path },
                sidecarURL: sidecar,
                format: format,
                displaySize: readDisplaySize(displayURL)
            ))
        }

        let withSidecar = entries.filter { $0.sidecarURL != nil }.count
        scanLog.debug("scanned \(entries.count) images, \(withSidecar) with sidecars in \(folder.lastPathComponent, privacy: .public)")

        return entries.sorted {
            $0.basename.localizedCaseInsensitiveCompare($1.basename) == .orderedAscending
        }
    }

    /// Reads pixel dimensions + EXIF orientation via ImageIO and returns the
    /// orientation-applied (display) size. Returns .zero if the metadata
    /// can't be read; the consumer falls back to a default aspect ratio.
    /// This is metadata-only, so it works even for RAW formats whose pixel
    /// data ImageIO can't decode (e.g. Nikon Z8 HE NEFs).
    private static func readDisplaySize(_ url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .zero
        }
        let w = (props[kCGImagePropertyPixelWidth]  as? NSNumber)?.intValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard w > 0, h > 0 else { return .zero }

        // EXIF orientations 5..8 imply a 90 or 270 rotation; the display
        // dimensions are then swapped.
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if [5, 6, 7, 8].contains(orientation) {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }

    private static func formatLabel(forExt ext: String) -> String {
        switch ext {
        case "jpg", "jpeg":  return "JPEG"
        case "heic", "heif": return "HEIC"
        case "png":          return "PNG"
        case "tif", "tiff":  return "TIFF"
        default:             return ext.uppercased()
        }
    }
}
