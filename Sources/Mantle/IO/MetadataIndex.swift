// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation
import os.log

// Bulk, filter-only metadata reader for the whole library. Used by the
// headline and keyword filters, which need a title and keyword list for
// every file -- not just the lazily-ingested selection.
//
// Unlike SidecarIO.read (one perl/exiftool spawn per file, plus base64
// preview extraction), this runs ONE exiftool process over many files at
// once and asks only for the title- and keyword-family tags. That keeps both
// the process count and the JSON payload small, so a few hundred files
// resolve in a couple of seconds instead of minutes.
//
// Fidelity note: the sweep requests a fixed set of named tags, so the
// vendor-namespace fuzzy fallback in SidecarIO.resolveHeadline cannot fire
// here (those keys aren't in the JSON). The standard XMP / IPTC locations
// are covered; a precise resolve still happens on full ingest when the file
// is selected.

private let log = Logger(subsystem: "com.tahirhashmi.mantle", category: "metadata-index")

// The title + keyword fields the filters need, read for every file.
struct SweptMetadata: Sendable {
    var headline: String
    var keywords: [String]
}

enum MetadataIndex {

    // The title- and keyword-family tags the sweep requests, matching the
    // named locations in SidecarIO.resolveHeadline / resolveKeywords.
    // -struct keeps XMP lang-alt values as { "x-default": "..." } so
    // langDefault can read them.
    private static let tagArgs = [
        "-XMP-dc:Title",
        "-XMP-photoshop:Headline",
        "-XMP-iptcCore:Headline",
        "-XMP-iptcExt:Headline",
        "-IPTC:Headline",
        "-IPTC:ObjectName",
        "-XMP-dc:Subject",
        "-XMP-iptcCore:Keywords",
        "-XMP-lr:HierarchicalSubject",
        "-IPTC:Keywords",
    ]

    // How many input paths to pass per exiftool invocation. Keeps the
    // argument vector well under the OS limit on large folders.
    private static let chunkSize = 400

    /// Resolve title + keywords per entry id. A headline of "" means a
    /// title tag was read and is empty (known-absent); likewise [] for
    /// keywords. An id absent from the result means the read failed entirely
    /// (treated as unknown by callers).
    static func scan(entries: [LibraryEntry]) -> [String: SweptMetadata] {
        guard !entries.isEmpty,
              let exiftool = ExifToolOneShot.exiftoolBinaryURL(),
              let lib      = ExifToolOneShot.exiftoolLibURL() else {
            return [:]
        }

        // Collect the unique input paths (each image, plus its sidecar) and
        // read them all, then resolve per entry afterward.
        var inputs: [String] = []
        var seen: Set<String> = []
        for entry in entries {
            for url in [entry.displayURL, entry.sidecarURL].compactMap({ $0 }) {
                if seen.insert(url.path).inserted { inputs.append(url.path) }
            }
        }

        var byPath: [String: [String: Any]] = [:]
        for chunk in stride(from: 0, to: inputs.count, by: chunkSize).map({
            Array(inputs[$0 ..< min($0 + chunkSize, inputs.count)])
        }) {
            for (path, dict) in readChunk(chunk, exiftool: exiftool, lib: lib) {
                byPath[path] = dict
            }
        }

        // Look a URL up under either the raw or standardized path form.
        func dict(for url: URL) -> [String: Any]? {
            byPath[url.path] ?? byPath[url.standardizedFileURL.path]
        }

        var result: [String: SweptMetadata] = [:]
        for entry in entries {
            // Sidecar values win; fall back to embedded. Matches the
            // sidecar-overrides-image precedence in
            // ExifToolOneShot.extractMetadata.
            let sidecarDict = entry.sidecarURL.flatMap { dict(for: $0) }
            let imageDict   = dict(for: entry.displayURL)

            var headline = sidecarDict.map { SidecarIO.resolveHeadline(from: $0) } ?? ""
            if headline.isEmpty, let d = imageDict {
                headline = SidecarIO.resolveHeadline(from: d)
            }

            var keywords = sidecarDict.map { SidecarIO.resolveKeywords(from: $0) } ?? []
            if keywords.isEmpty, let d = imageDict {
                keywords = SidecarIO.resolveKeywords(from: d)
            }

            result[entry.id] = SweptMetadata(headline: headline, keywords: keywords)
        }
        return result
    }

    // Run one exiftool invocation over a chunk of paths. Returns a map of
    // SourceFile path -> tag dict. Best-effort: a failed chunk yields [:].
    private static func readChunk(_ paths: [String], exiftool: URL, lib: URL) -> [String: [String: Any]] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [exiftool.path, "-j", "-G1", "-struct", "-charset", "utf8"]
            + tagArgs + paths

        var env = ProcessInfo.processInfo.environment
        env["PERL5LIB"] = lib.path
        env["LANG"]     = env["LANG"]   ?? "en_US.UTF-8"
        env["LC_ALL"]   = env["LC_ALL"] ?? "en_US.UTF-8"
        proc.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError  = stderr

        do { try proc.run() } catch {
            log.error("exiftool launch failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        // exiftool can exit non-zero when some inputs warn yet still emit
        // valid JSON for the rest, so parse stdout regardless of status.
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }

        var out: [String: [String: Any]] = [:]
        for dict in parsed {
            guard let src = dict["SourceFile"] as? String else { continue }
            // exiftool echoes the path we passed; key on both the raw string
            // and its standardized form so lookups by entry path always hit.
            out[src] = dict
            out[URL(fileURLWithPath: src).standardizedFileURL.path] = dict
        }
        return out
    }
}
