import Foundation
import os.log

private let log = Logger(subsystem: "dev.metadater", category: "writer")

// Writes only the fields the caller asks for to a bare-basename `.xmp`
// sidecar next to the image. One ExifTool invocation per save -- no
// write-all dump. If the sidecar doesn't exist yet, it gets created via
// `-o`. On next load, SidecarIO merges the sidecar's tags over the
// embedded ones, so this minimal-write approach round-trips cleanly.

enum ExifToolWriter {

    enum WriteError: Error {
        case exiftoolNotFound
        case processFailed(status: Int32, stderr: String)
    }

    // Returns the sidecar URL that received the write (so AppState can
    // adopt it onto the LibraryEntry if it was newly created).
    static func write(record: ImageRecord, fields: Set<EditableField>) throws -> URL {
        guard !fields.isEmpty else {
            // Nothing dirty; nothing to do. Return the would-be path for
            // bookkeeping symmetry, but skip the process entirely.
            return sidecarPath(for: record.file)
        }

        guard let exiftool = ExifToolOneShot.exiftoolBinaryURL(),
              let lib      = ExifToolOneShot.exiftoolLibURL() else {
            throw WriteError.exiftoolNotFound
        }

        let sidecar = sidecarPath(for: record.file)

        var args: [String] = [exiftool.path]
        args += ["-overwrite_original", "-charset", "utf8", "-codedcharacterset=UTF8"]

        // -sep applies to all subsequent list-tag writes in the same
        // invocation. Unit Separator (U+001F) never appears in normal
        // text. Process API doesn't shell-interpret, so the raw byte
        // is fine.
        if fields.contains(.keywords) {
            args += ["-sep", "\u{001F}"]
        }

        args += headlineArgs(record: record, fields: fields)
        args += captionArgs(record: record, fields: fields)
        args += keywordArgs(record: record, fields: fields)
        args += dateAndTimeArgs(record: record, fields: fields)

        // Target sidecar. -o creates a fresh file from the supplied tags;
        // without -o, exiftool updates an existing file in place.
        if FileManager.default.fileExists(atPath: sidecar.path) {
            args.append(sidecar.path)
        } else {
            args += ["-o", sidecar.path]
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PERL5LIB"] = lib.path
        env["LANG"]     = env["LANG"]   ?? "en_US.UTF-8"
        env["LC_ALL"]   = env["LC_ALL"] ?? "en_US.UTF-8"
        proc.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError  = stderrPipe

        do {
            try proc.run()
        } catch {
            throw WriteError.processFailed(status: -1, stderr: error.localizedDescription)
        }

        _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? "exit \(proc.terminationStatus)"
            log.error("exiftool write failed: \(msg, privacy: .public)")
            throw WriteError.processFailed(status: proc.terminationStatus, stderr: msg)
        }

        log.debug("wrote \(fields.count) field(s) to \(sidecar.lastPathComponent, privacy: .public)")
        return sidecar
    }

    static func sidecarPath(for image: URL) -> URL {
        image.deletingPathExtension().appendingPathExtension("xmp")
    }

    // MARK: - Per-field arg builders

    private static func headlineArgs(record: ImageRecord, fields: Set<EditableField>) -> [String] {
        guard fields.contains(.headline) else { return [] }
        let value = record.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "-XMP-photoshop:Headline=\(value)",
            "-XMP-dc:Title-x-default=\(value)",
        ]
    }

    private static func captionArgs(record: ImageRecord, fields: Set<EditableField>) -> [String] {
        guard fields.contains(.caption) else { return [] }
        let value = record.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["-XMP-dc:Description-x-default=\(value)"]
    }

    private static func keywordArgs(record: ImageRecord, fields: Set<EditableField>) -> [String] {
        guard fields.contains(.keywords) else { return [] }
        let normalized = normaliseKeywords(record.keywords)
        let joined = normalized.joined(separator: "\u{001F}")
        return ["-XMP-dc:Subject=\(joined)"]
    }

    // Trim, drop empties, dedupe-preserving-first-occurrence. Matches the
    // dedupe rule in EditableField.keywordSet so writes are stable across
    // re-loads.
    private static func normaliseKeywords(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for s in raw {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
        }
        return out
    }

    private static func dateAndTimeArgs(record: ImageRecord, fields: Set<EditableField>) -> [String] {
        let dateDirty = fields.contains(.captureDate)
        let tzDirty   = fields.contains(.timezone)
        guard dateDirty || tzDirty else { return [] }

        let offsetMinutes: Int = {
            if case .fixed(let mins, _) = record.timezone { return mins }
            return 0
        }()
        let offsetStr = formatOffset(offsetMinutes)

        if dateDirty {
            // Date carries the offset baked into the ISO 8601 string, so a
            // single tag write reflects both date and tz when both are dirty.
            if let date = record.captureDate {
                let iso = formatISO8601(date, offsetMinutes: offsetMinutes)
                return [
                    "-XMP-photoshop:DateCreated=\(iso)",
                    "-XMP-exif:OffsetTimeOriginal=\(offsetStr)",
                ]
            }
            return [
                "-XMP-photoshop:DateCreated=",
                "-XMP-exif:OffsetTimeOriginal=",
            ]
        }
        // Only timezone is dirty.
        return ["-XMP-exif:OffsetTimeOriginal=\(offsetStr)"]
    }

    private static func formatISO8601(_ date: Date, offsetMinutes: Int) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60) ?? TimeZone(identifier: "UTC")!
        return df.string(from: date)
    }

    private static func formatOffset(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : "+"
        let absMin = Swift.abs(minutes)
        return String(format: "%@%02d:%02d", sign, absMin / 60, absMin % 60)
    }
}
