// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation
import AppKit
import ImageIO
import CoreImage

// One-shot ExifTool wrapper. Single process per file: invokes
// `exiftool -j -b -JpgFromRaw -PreviewImage -Orientation# <file>`
// and parses the JSON output, which carries base64-encoded preview bytes
// and the parent RAW's Orientation tag together.
//
// The daemon (long-lived `-stay_open True`) is the next optimisation pass.

struct ExifToolPreview {
    let bytes: Data
    let orientation: Int            // EXIF 1..8
}

enum ExifToolOneShot {

    static func extractPreview(url: URL, maxPixelSide: CGFloat, scale: CGFloat) -> NSImage? {
        guard let bundle = extractBundle(url: url) else { return nil }
        return decodeJPEG(bundle.bytes,
                          exifOrientation: bundle.orientation,
                          maxPixelSide: maxPixelSide,
                          scale: scale)
    }

    /// Reads merged metadata (image + optional XMP sidecar). ExifTool
    /// returns each input file as its own dict in the JSON array -- it
    /// does *not* auto-merge a sidecar into the image's dict. We do the
    /// merge here, with sidecar values overriding the image's for any
    /// matching tag (spec section 7 read priority for the owned fields).
    static func extractMetadata(image: URL, sidecar: URL?) -> [String: Any]? {
        guard let exiftool = exiftoolBinaryURL(),
              let lib      = exiftoolLibURL() else {
            return nil
        }

        var args = [
            exiftool.path,
            "-j",
            "-G1",
            "-struct",
            "-charset", "utf8",
            image.path,
        ]
        if let sidecar {
            args.append(sidecar.path)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PERL5LIB"] = lib.path
        env["LANG"]     = env["LANG"]   ?? "en_US.UTF-8"
        env["LC_ALL"]   = env["LC_ALL"] ?? "en_US.UTF-8"
        proc.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError  = stderr

        do { try proc.run() } catch { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }

        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !parsed.isEmpty else {
            return nil
        }

        // First entry is the image; subsequent entries are extra inputs
        // (the sidecar, if we passed one). Merge with the sidecar's tags
        // taking precedence so dc:Title in a .xmp wins over any embedded
        // headline in the parent NEF -- except for File / System / ExifTool
        // tags, which describe the *file being inspected*. If we let the
        // sidecar override those, the format reads as "XMP", the size as
        // the sidecar's size, etc.
        var merged: [String: Any] = parsed[0]
        for extra in parsed.dropFirst() {
            for (key, value) in extra where key != "SourceFile" {
                if key.hasPrefix("File:") || key.hasPrefix("System:") || key.hasPrefix("ExifTool:") {
                    continue
                }
                merged[key] = value
            }
        }
        return merged
    }

    /// Single ExifTool invocation that returns both the embedded preview
    /// (as raw JPEG bytes) and the parent RAW's Orientation tag in one go.
    static func extractBundle(url: URL) -> ExifToolPreview? {
        guard let exiftool = exiftoolBinaryURL(),
              let lib      = exiftoolLibURL() else {
            return nil
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [
            exiftool.path,
            "-j",                // JSON output
            "-b",                // binary fields base64-encoded inline
            "-JpgFromRaw",       // Nikon NEF embedded preview tag
            "-PreviewImage",     // generic embedded preview tag
            "-Orientation#",     // numeric EXIF orientation (1..8)
            url.path,
        ]

        var env = ProcessInfo.processInfo.environment
        env["PERL5LIB"] = lib.path
        env["LANG"]     = env["LANG"]   ?? "en_US.UTF-8"
        env["LC_ALL"]   = env["LC_ALL"] ?? "en_US.UTF-8"
        proc.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError  = stderr

        do { try proc.run() } catch { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }

        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = parsed.first else {
            return nil
        }

        let orientation = (first["Orientation"] as? NSNumber)?.intValue ?? 1

        // Prefer JpgFromRaw (Nikon's tag for the full-size embedded JPEG)
        // over PreviewImage (which can be a smaller embedded variant).
        let candidate = (first["JpgFromRaw"] as? String) ?? (first["PreviewImage"] as? String)
        guard let str = candidate else { return nil }

        // ExifTool prefixes base64 binary in JSON with "base64:".
        let prefix = "base64:"
        let stripped = str.hasPrefix(prefix) ? String(str.dropFirst(prefix.count)) : str
        guard let bytes = Data(base64Encoded: stripped, options: .ignoreUnknownCharacters),
              !bytes.isEmpty else {
            return nil
        }

        return ExifToolPreview(bytes: bytes, orientation: orientation)
    }

    private static func decodeJPEG(_ data: Data, exifOrientation: Int, maxPixelSide: CGFloat, scale: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform:     true,
            kCGImageSourceShouldCacheImmediately:           true,
            kCGImageSourceThumbnailMaxPixelSize:            maxPixelSide,
        ]

        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }

        let oriented = applyOrientation(cg, exifOrientation: exifOrientation) ?? cg
        return NSImage(
            cgImage: oriented,
            size: NSSize(width: CGFloat(oriented.width) / scale,
                         height: CGFloat(oriented.height) / scale)
        )
    }

    private static func applyOrientation(_ cg: CGImage, exifOrientation: Int) -> CGImage? {
        guard (2...8).contains(exifOrientation) else { return cg }
        let ci = CIImage(cgImage: cg)
            .oriented(forExifOrientation: Int32(exifOrientation))
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(ci, from: ci.extent)
    }

    // MARK: - Bundle resource lookup

    // The SPM-generated `Bundle.module` accessor only probes
    // `Bundle.main.bundleURL/Mantle_Mantle.bundle` and *fatalErrors* on a
    // miss. That path holds for `swift run` (the bundle sits next to the
    // binary) but not for the packaged .app, where bundleURL is the .app
    // root and build-app.sh installs the bundle under Contents/Resources --
    // so the first metadata read used to trap. We resolve the resource
    // bundle ourselves across the real candidate locations and return nil
    // (callers handle it) instead of crashing.
    private static let resourceBundle: Bundle? = {
        let bundleName = "Mantle_Mantle.bundle"
        var bases: [URL] = []
        if let r = Bundle.main.resourceURL { bases.append(r) }   // .app/Contents/Resources
        bases.append(Bundle.main.bundleURL)                      // .app root, or dev bin dir
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            bases.append(exe)                                    // .app/Contents/MacOS
        }
        for base in bases {
            if let bundle = Bundle(url: base.appendingPathComponent(bundleName)) {
                return bundle
            }
        }
        return nil
    }()

    private static func exiftoolResourceDir() -> URL? {
        resourceBundle?.url(forResource: "exiftool", withExtension: nil)
    }

    static func exiftoolBinaryURL() -> URL? {
        guard let dir = exiftoolResourceDir() else {
            return nil
        }
        let exe = dir.appendingPathComponent("exiftool")
        return FileManager.default.isExecutableFile(atPath: exe.path) ? exe : nil
    }

    static func exiftoolLibURL() -> URL? {
        guard let dir = exiftoolResourceDir() else {
            return nil
        }
        let lib = dir.appendingPathComponent("lib")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: lib.path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }
        return lib
    }
}
