import Foundation
import CoreGraphics
import os.log

// Builds an ImageRecord from ExifTool's JSON output, applying the read
// priority from spec section 7. ExifTool merges the sidecar onto the
// embedded metadata when both paths are passed, so the precedence falls
// out naturally for the six owned fields.

private let log = Logger(subsystem: "dev.metadater", category: "sidecar")

enum SidecarIO {

    static func read(file: URL, sidecar: URL?) -> ImageRecord {
        if let sidecar {
            log.debug("ingest \(file.lastPathComponent, privacy: .public) + sidecar \(sidecar.lastPathComponent, privacy: .public)")
        } else {
            log.debug("ingest \(file.lastPathComponent, privacy: .public) (no sidecar)")
        }

        if let json = ExifToolOneShot.extractMetadata(image: file, sidecar: sidecar) {
            return build(json: json, file: file, sidecar: sidecar)
        }
        return ImageIOReader.read(file: file, sidecar: sidecar)
    }

    private static func build(json: [String: Any], file: URL, sidecar: URL?) -> ImageRecord {

        // Headline read priority. Different tools write to different places:
        // Lightroom uses XMP-dc:Title, Photoshop and Photo Mechanic use
        // XMP-photoshop:Headline, modern IPTC Core uses XMP-iptcCore:Headline,
        // legacy IPTC IIM uses IPTC:Headline + IPTC:ObjectName. After all
        // those, fuzzy-match any other key ending in :Title / :Headline /
        // :ObjectName so weird vendor namespaces still surface.
        let headline = firstNonEmpty(
            langDefault(json["XMP-dc:Title"]),
            string(json, "XMP-photoshop:Headline"),
            string(json, "XMP-iptcCore:Headline"),
            string(json, "XMP-iptcExt:Headline"),
            string(json, "IPTC:Headline"),
            string(json, "IPTC:ObjectName"),
            fuzzyMatch(json, suffixes: ["title", "headline", "objectname"])
        )

        let caption = firstNonEmpty(
            langDefault(json["XMP-dc:Description"]),
            langDefault(json["XMP-tiff:ImageDescription"]),
            string(json, "XMP-iptcCore:Description"),
            string(json, "XMP-MicrosoftPhoto:Comments"),
            string(json, "XMP-acdsee:Caption"),
            string(json, "XMP-acdsee:Notes"),
            string(json, "IPTC:Caption-Abstract"),
            string(json, "EXIF:ImageDescription"),
            string(json, "IFD0:ImageDescription"),
            string(json, "ExifIFD:UserComment"),
            fuzzyMatch(json, suffixes: ["description", "caption", "caption-abstract", "comments", "imagedescription"])
        )

        let keywords = firstNonEmptyList(
            stringArray(json, "XMP-dc:Subject"),
            stringArray(json, "XMP-iptcCore:Keywords"),
            stringArray(json, "XMP-lr:HierarchicalSubject"),
            stringArray(json, "IPTC:Keywords")
        )

        // Timezone first -- needed to correctly parse offset-less date
        // strings (EXIF dates have no offset baked in; XMP dates do).
        //
        // XMP-photoshop:DateCreated wins over the EXIF offset tags so a
        // user-edited sidecar can override the camera's recorded zone.
        // OffsetTimeOriginal is an EXIF-only tag and can't be written
        // back to a sidecar, so the offset on the XMP date string is the
        // only knob the user has for changing TZ.
        let offsetStr = firstNonEmpty(
            extractISOOffset(string(json, "XMP-photoshop:DateCreated")),
            string(json, "ExifIFD:OffsetTimeOriginal"),
            string(json, "ExifIFD:OffsetTime"),
            string(json, "ExifIFD:OffsetTimeDigitized")
        )
        let placeName = extractPlace(json)

        // We need GPS up front because the TZRule .auto case implies "GPS
        // resolves it" -- claiming Auto on a file without GPS is wrong.
        // Hemisphere comes from the explicit Ref tag whenever it's present,
        // because the raw magnitude tag's format varies (DMS-with-suffix,
        // bare decimal, numeric, etc.) and a bare decimal would silently
        // drop the sign through parseGPS's Double()-fallback.
        let lat = readSignedGPS(json: json,
                                magnitudeKeys: ["XMP-exif:GPSLatitude", "EXIF:GPSLatitude"],
                                refKeys: ["XMP-exif:GPSLatitudeRef", "EXIF:GPSLatitudeRef",
                                          "Composite:GPSLatitudeRef"],
                                compositeKey: "Composite:GPSLatitude",
                                negativeHemispheres: ["S"])
        let lon = readSignedGPS(json: json,
                                magnitudeKeys: ["XMP-exif:GPSLongitude", "EXIF:GPSLongitude"],
                                refKeys: ["XMP-exif:GPSLongitudeRef", "EXIF:GPSLongitudeRef",
                                          "Composite:GPSLongitudeRef"],
                                compositeKey: "Composite:GPSLongitude",
                                negativeHemispheres: ["W"])
        let hasGPS = (lat != nil) && (lon != nil)

        let tzRule: TZRule = {
            if let r = parseOffsetRule(offsetStr, place: placeName) { return r }
            return hasGPS ? .auto : .unknown
        }()

        let cameraTZ: TimeZone = {
            if case .fixed(let mins, _) = tzRule {
                return TimeZone(secondsFromGMT: mins * 60) ?? TimeZone(identifier: "UTC")!
            }
            return TimeZone(identifier: "UTC")!
        }()

        let captureDate = firstDateIn(
            json,
            keys: [
                "XMP-photoshop:DateCreated",
                "ExifIFD:DateTimeOriginal",
                "EXIF:DateTimeOriginal",
                "ExifIFD:DateTimeDigitized",
                "EXIF:DateTimeDigitized",
            ],
            timezone: cameraTZ
        )

        let camera = combine(
            string(json, "IFD0:Make"),
            string(json, "IFD0:Model")
        )

        let lens = firstNonEmpty(
            string(json, "Composite:LensID"),
            string(json, "ExifIFD:LensModel"),
            string(json, "MakerNotes:LensModel"),
            string(json, "XMP-aux:Lens")
        )

        let shutter = firstNonEmpty(
            string(json, "Composite:ShutterSpeed"),
            string(json, "ExifIFD:ExposureTime")
        )

        let aperture = firstNonEmpty(
            string(json, "Composite:Aperture"),
            string(json, "ExifIFD:FNumber")
        )

        let iso = int(json, "ExifIFD:ISO", "Composite:ISO")

        let focal = firstNonEmpty(
            string(json, "Composite:FocalLength"),
            string(json, "ExifIFD:FocalLength")
        )

        let alt = parseAltitude(json["Composite:GPSAltitude"]) ?? double(json, "XMP-exif:GPSAltitude")
        // No Composite:GPSImgDirection -- the underlying tag is already a
        // signed decimal, so ExifTool doesn't synthesise a composite for
        // it. Read GPS:GPSImgDirection (embedded EXIF, group-1 form) first,
        // then the XMP-exif sidecar form.
        let dir = double(json,
                         "GPS:GPSImgDirection",
                         "XMP-exif:GPSImgDirection",
                         "Composite:GPSImgDirection")

        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?
            .int64Value ?? 0

        let dim = imageSize(json)

        let profile = firstNonEmpty(
            string(json, "ICC_Profile:ProfileDescription"),
            string(json, "ICC-Profile:ProfileDescription"),
            string(json, "ExifIFD:ColorSpace")
        )

        let fmt = firstNonEmpty(
            string(json, "File:FileType"),
            file.pathExtension.uppercased()
        )

        return ImageRecord(
            id: file.path,
            file: file,
            sidecarURL: sidecar,
            fmt: fmt,
            dim: dim,
            size: size,
            colorProfile: profile,
            camera: camera,
            lens: lens,
            shutter: shutter,
            aperture: aperture,
            iso: iso,
            focal: focal,
            originalCaptureDate: captureDate,
            latitude: lat,
            longitude: lon,
            altitude: alt,
            direction: dir,
            place: "",
            headline: headline,
            caption: caption,
            keywords: keywords,
            captureDate: captureDate,
            timezone: tzRule
        )
    }
}

// MARK: - JSON helpers

private func string(_ d: [String: Any], _ key: String) -> String {
    if let s = d[key] as? String { return s }
    if let n = d[key] as? NSNumber { return n.stringValue }
    return ""
}

private func int(_ d: [String: Any], _ keys: String...) -> Int {
    for k in keys {
        if let n = d[k] as? NSNumber { return n.intValue }
        if let s = d[k] as? String, let n = Int(s) { return n }
    }
    return 0
}

private func double(_ d: [String: Any], _ keys: String...) -> Double? {
    for k in keys {
        if let n = d[k] as? NSNumber { return n.doubleValue }
        if let s = d[k] as? String, let n = Double(s) { return n }
    }
    return nil
}

private func stringArray(_ d: [String: Any], _ key: String) -> [String] {
    let raw: [String]
    if let a = d[key] as? [String] {
        raw = a
    } else if let a = d[key] as? [Any] {
        raw = a.compactMap { $0 as? String }
    } else if let s = d[key] as? String {
        raw = s.split(separator: ",").map { String($0) }
    } else {
        return []
    }
    return raw.compactMap {
        let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// XMP language-alternative values (-struct emits them as { "x-default": "..." }).
private func langDefault(_ raw: Any?) -> String {
    if let s = raw as? String { return s }
    if let dict = raw as? [String: Any] {
        if let v = dict["x-default"] as? String { return v }
        if let first = dict.values.first as? String { return first }
    }
    return ""
}

private func firstNonEmpty(_ values: String...) -> String {
    for v in values {
        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    return ""
}

private func firstNonEmptyList(_ values: [String]...) -> [String] {
    for v in values where !v.isEmpty { return v }
    return []
}

/// Last-resort fuzzy match: iterate every key in the JSON and return the
/// longest non-empty value whose key (lowercased) ends in any of the given
/// suffixes. Catches obscure vendor namespaces that don't match our known
/// priority list -- e.g., Nikon's MakerNote field for a "Title" stashed
/// somewhere unusual.
private func fuzzyMatch(_ d: [String: Any], suffixes: [String]) -> String {
    var best = ""
    for (k, v) in d {
        let lower = k.lowercased()
        let match = suffixes.contains { lower.hasSuffix(":" + $0) || lower == $0 }
        guard match else { continue }
        let candidate: String
        if let s = v as? String { candidate = s }
        else if let dict = v as? [String: Any] {
            if let x = dict["x-default"] as? String { candidate = x }
            else if let f = dict.values.first as? String { candidate = f }
            else { continue }
        }
        else { continue }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > best.count { best = trimmed }
    }
    return best
}

private func combine(_ a: String, _ b: String) -> String {
    let lhs = a.trimmingCharacters(in: .whitespaces)
    let rhs = b.trimmingCharacters(in: .whitespaces)
    if lhs.isEmpty { return rhs }
    if rhs.isEmpty { return lhs }
    if rhs.lowercased().contains(lhs.lowercased()) { return rhs }
    return "\(lhs) \(rhs)"
}

private func imageSize(_ d: [String: Any]) -> CGSize {
    if let composite = d["Composite:ImageSize"] as? String {
        let parts = composite.split(separator: "x").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        if parts.count == 2 {
            return CGSize(width: parts[0], height: parts[1])
        }
    }
    let w = double(d, "ExifIFD:ExifImageWidth", "File:ImageWidth", "IFD0:ImageWidth") ?? 0
    let h = double(d, "ExifIFD:ExifImageHeight", "File:ImageHeight", "IFD0:ImageHeight") ?? 0
    return CGSize(width: w, height: h)
}

private let dateFormats = [
    "yyyy:MM:dd HH:mm:ss.SSSZZZZZ",
    "yyyy:MM:dd HH:mm:ssZZZZZ",
    "yyyy:MM:dd HH:mm:ss.SSS",
    "yyyy:MM:dd HH:mm:ss",
    "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
    "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
    "yyyy-MM-dd'T'HH:mm:ss",
    "yyyy-MM-dd HH:mm:ssZZZZZ",
    "yyyy-MM-dd HH:mm:ss",
]

/// Parses a date string against each known EXIF / XMP format, using the
/// supplied timezone as the assumption for strings that don't carry an
/// explicit offset. (XMP dates do carry one; EXIF DateTimeOriginal doesn't.)
private func firstDateIn(_ d: [String: Any], keys: [String], timezone: TimeZone) -> Date? {
    for k in keys {
        guard let s = d[k] as? String, !s.isEmpty else { continue }
        for fmt in dateFormats {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = timezone
            if let date = df.date(from: s) { return date }
        }
    }
    return nil
}

/// Read a signed GPS coordinate, preferring the explicit Ref tag over any
/// sign hint that may or may not be baked into the magnitude string. Falls
/// back to the Composite tag only when no ref + magnitude pair is found.
///
/// Why this matters: ExifTool's output format for the magnitude varies by
/// version, file type, and how the tag was originally written. The raw
/// magnitude can come back as a DMS string with a trailing N/S/E/W (which
/// parseGPS handles), but it can also come back as a bare decimal -- and a
/// bare positive decimal silently means "north / east" via parseGPS's
/// Double-init path, even when the real value was south or west. The Ref
/// tag is the one place ExifTool always reports the hemisphere reliably.
private func readSignedGPS(json: [String: Any],
                           magnitudeKeys: [String],
                           refKeys: [String],
                           compositeKey: String,
                           negativeHemispheres: Set<String>) -> Double? {
    let refLetter: String? = {
        for k in refKeys {
            if let s = json[k] as? String, let first = s.uppercased().first {
                return String(first)
            }
        }
        return nil
    }()

    if let ref = refLetter {
        for k in magnitudeKeys {
            if let mag = parseGPS(json[k]) {
                let sign: Double = negativeHemispheres.contains(ref) ? -1 : 1
                return sign * abs(mag)
            }
        }
    }

    // No ref tag (or no magnitude under the expected keys) -- fall back to
    // the Composite tag, which usually embeds the hemisphere as a letter.
    return parseGPS(json[compositeKey])
}

/// Parses ExifTool's Composite:GPSLatitude / GPSLongitude string format
/// (e.g. `37 deg 34' 42.95" N`) into a signed decimal degree value.
/// Also accepts a bare numeric value (already-decimalised tags).
private func parseGPS(_ raw: Any?) -> Double? {
    if let n = raw as? NSNumber { return n.doubleValue }
    guard let s = raw as? String else { return nil }
    if let d = Double(s) { return d }

    // Pattern: "DD deg MM' SS[.fff]\" [NSEW]"
    // ASCII-only; ExifTool emits ASCII quote / apostrophe by default.
    let pattern = #"(\d+(?:\.\d+)?)\s*deg\s*(\d+(?:\.\d+)?)'\s*(\d+(?:\.\d+)?)"\s*([NSEWnsew])"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          m.numberOfRanges == 5,
          let dR = Range(m.range(at: 1), in: s),
          let mR = Range(m.range(at: 2), in: s),
          let sR = Range(m.range(at: 3), in: s),
          let hR = Range(m.range(at: 4), in: s),
          let deg = Double(s[dR]),
          let min = Double(s[mR]),
          let sec = Double(s[sR]) else {
        return nil
    }
    let hem = String(s[hR]).uppercased()
    let magnitude = deg + min / 60.0 + sec / 3600.0
    return (hem == "S" || hem == "W") ? -magnitude : magnitude
}

/// Best-effort place name for a TZ rule label. Nikon writes the camera's
/// configured zone with a place hint in MakerNote like `-08:00 (Los
/// Angeles, Vancouver)`. IPTC fields are the next-best source.
private func extractPlace(_ d: [String: Any]) -> String {
    if let tz = d["Nikon:TimeZone"] as? String,
       let open = tz.firstIndex(of: "("),
       let close = tz[tz.index(after: open)...].firstIndex(of: ")") {
        let inside = tz[tz.index(after: open)..<close]
        return String(inside).trimmingCharacters(in: .whitespaces)
    }
    let cityKeys = [
        "XMP-iptcCore:City",
        "XMP-iptcExt:LocationCreatedCity",
        "IPTC:City",
    ]
    for k in cityKeys {
        if let v = d[k] as? String {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
    }
    return ""
}

/// Parses ExifTool's Composite:GPSAltitude string format (e.g.
/// `89 m Above Sea Level` or `15 m Below Sea Level`) into signed metres.
private func parseAltitude(_ raw: Any?) -> Double? {
    if let n = raw as? NSNumber { return n.doubleValue }
    guard let s = raw as? String else { return nil }
    if let d = Double(s) { return d }

    let pattern = #"([-\d.]+)\s*m\s*(Below)?"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          let valR = Range(m.range(at: 1), in: s),
          let value = Double(s[valR]) else {
        return nil
    }
    let isBelow = m.range(at: 2).location != NSNotFound
    return isBelow ? -value : value
}

/// Pulls the offset suffix off an ISO 8601 date-time string
/// (e.g. `2026-05-17T15:23:55-08:00` -> `-08:00`,
/// `2026-05-17T22:23:55Z` -> `+00:00`). Returns `""` when the input
/// carries no offset suffix, letting callers fall back to other sources.
private func extractISOOffset(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    if trimmed.hasSuffix("Z") || trimmed.hasSuffix("z") { return "+00:00" }

    let pattern = #"([+-])(\d{2}):?(\d{2})$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let m = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
          m.numberOfRanges == 4,
          let signR  = Range(m.range(at: 1), in: trimmed),
          let hoursR = Range(m.range(at: 2), in: trimmed),
          let minsR  = Range(m.range(at: 3), in: trimmed) else {
        return ""
    }
    return "\(trimmed[signR])\(trimmed[hoursR]):\(trimmed[minsR])"
}

/// Parses an offset string like `-08:00` or `+05:30` into a TZRule.
/// Label format follows the design directive:
///   `UTC+HH:MM - Auto`   when no place name is known
///   `UTC+HH:MM - <place>`  when a place name was extracted
/// Returns nil for empty / malformed input so callers can fall back.
private func parseOffsetRule(_ offset: String, place: String) -> TZRule? {
    let trimmed = offset.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let pattern = #"^([+-])(\d{1,2}):?(\d{2})?"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let m = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
          let signR = Range(m.range(at: 1), in: trimmed),
          let hoursR = Range(m.range(at: 2), in: trimmed),
          let hours = Int(trimmed[hoursR]) else {
        return nil
    }
    let sign = String(trimmed[signR]) == "-" ? -1 : 1
    let minutes: Int = {
        if m.range(at: 3).location == NSNotFound { return 0 }
        guard let r = Range(m.range(at: 3), in: trimmed),
              let v = Int(trimmed[r]) else { return 0 }
        return v
    }()
    let total = sign * (hours * 60 + minutes)
    let suffix = place.isEmpty ? "Auto" : place
    let label = String(format: "UTC%@%02d:%02d - %@", sign < 0 ? "-" : "+", abs(hours), minutes, suffix)
    return .fixed(offsetMinutes: total, label: label)
}
