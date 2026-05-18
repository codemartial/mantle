import Foundation
import os.log

private let log = Logger(subsystem: "dev.metadater", category: "writer")

// Writes only the fields the caller asks for to a bare-basename `.xmp`
// sidecar next to the image. One ExifTool invocation per save -- no
// write-all dump. If the sidecar doesn't exist yet, it gets created via
// `-o`. On next load, SidecarIO merges the sidecar's tags over the
// embedded ones, so this minimal-write approach round-trips cleanly.

enum ExifToolWriter {

    struct WriteResult {
        let sidecar: URL
        let command: String        // shell-escaped, copy-pasteable
        let duration: TimeInterval
    }

    enum WriteError: Error {
        case exiftoolNotFound
        case processFailed(status: Int32, stderr: String, command: String, duration: TimeInterval)
    }

    static func write(record: ImageRecord, fields: Set<EditableField>) -> Result<WriteResult, WriteError> {
        let sidecar = sidecarPath(for: record.file)

        guard !fields.isEmpty else {
            return .success(WriteResult(sidecar: sidecar, command: "", duration: 0))
        }

        guard let exiftool = ExifToolOneShot.exiftoolBinaryURL(),
              let lib      = ExifToolOneShot.exiftoolLibURL() else {
            return .failure(.exiftoolNotFound)
        }

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

        let command = displayCommand(args)
        let start = Date()

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
            let dur = Date().timeIntervalSince(start)
            return .failure(.processFailed(status: -1,
                                           stderr: error.localizedDescription,
                                           command: command,
                                           duration: dur))
        }

        _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let dur = Date().timeIntervalSince(start)

        guard proc.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? "exit \(proc.terminationStatus)"
            log.error("exiftool write failed: \(msg, privacy: .public)")
            return .failure(.processFailed(status: proc.terminationStatus,
                                           stderr: msg,
                                           command: command,
                                           duration: dur))
        }

        log.debug("wrote \(fields.count) field(s) to \(sidecar.lastPathComponent, privacy: .public)")
        return .success(WriteResult(sidecar: sidecar, command: command, duration: dur))
    }

    // First arg is the bundled exiftool.pl path; replace with the literal
    // "exiftool" so logged lines stay short and copy-paste into a terminal
    // assuming exiftool is on the path.
    private static func displayCommand(_ args: [String]) -> String {
        var parts: [String] = ["exiftool"]
        for arg in args.dropFirst() {
            parts.append(shellEscape(arg))
        }
        return parts.joined(separator: " ")
    }

    private static func shellEscape(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-")
        if s.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return s
        }
        // Single-quote, escape any embedded single quotes by closing,
        // adding an escaped quote, and reopening.
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
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

    // XMP has no standalone offset tag (OffsetTimeOriginal is EXIF-only).
    // The offset rides inside the ISO 8601 string on XMP-photoshop:
    // DateCreated, so whether date, tz, or both are dirty the write looks
    // the same: format the current date in the current tz and emit one
    // tag.
    private static func dateAndTimeArgs(record: ImageRecord, fields: Set<EditableField>) -> [String] {
        guard fields.contains(.captureDate) || fields.contains(.timezone) else { return [] }

        guard let date = record.captureDate else {
            return ["-XMP-photoshop:DateCreated="]
        }
        let offsetMinutes: Int = {
            if case .fixed(let mins, _) = record.timezone { return mins }
            return 0
        }()
        return ["-XMP-photoshop:DateCreated=\(formatISO8601(date, offsetMinutes: offsetMinutes))"]
    }

    private static func formatISO8601(_ date: Date, offsetMinutes: Int) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60) ?? TimeZone(identifier: "UTC")!
        return df.string(from: date)
    }

}
