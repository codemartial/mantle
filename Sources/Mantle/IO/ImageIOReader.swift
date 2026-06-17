// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import Foundation
import ImageIO
import CoreGraphics

// Reads embedded EXIF / IPTC / GPS metadata via ImageIO. Doesn't read XMP
// sidecars yet -- that comes after the design pass when ExifTool is wired
// back in. For the design pass, headline / caption / keywords come from
// IPTC embedded fields when present, else empty (which renders as the
// faint placeholder copy in the UI).

enum ImageIOReader {

    static func read(file: URL, sidecar: URL?) -> ImageRecord {
        let source = CGImageSourceCreateWithURL(file as CFURL, nil)
        let props = source
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            ?? [:]

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        let gps  = props[kCGImagePropertyGPSDictionary]  as? [CFString: Any] ?? [:]

        // Camera + lens
        let make = (tiff[kCGImagePropertyTIFFMake]  as? String) ?? ""
        let model = (tiff[kCGImagePropertyTIFFModel] as? String) ?? ""
        let camera = combine(make, model)

        let lens =
            (exif[kCGImagePropertyExifLensModel] as? String) ??
            (exif["LensMake" as CFString] as? String).map { "\($0) lens" } ??
            ""

        // Exposure values
        let exposureTime = numeric(exif[kCGImagePropertyExifExposureTime])
        let shutter = exposureTime.map { formatShutter($0) } ?? ""

        let fNumber = numeric(exif[kCGImagePropertyExifFNumber])
        let aperture = fNumber.map { String(format: "f/%.1f", $0) } ?? ""

        let iso: Int = {
            if let arr = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let first = arr.first {
                return first.intValue
            }
            if let n = exif["ISOSpeedRatings" as CFString] as? NSNumber {
                return n.intValue
            }
            return 0
        }()

        let focal = numeric(exif[kCGImagePropertyExifFocalLength])
            .map { String(format: "%.0f mm", $0) } ?? ""

        // Date
        let dateStr =
            (exif[kCGImagePropertyExifDateTimeOriginal] as? String) ??
            (exif[kCGImagePropertyExifDateTimeDigitized] as? String) ??
            (tiff[kCGImagePropertyTIFFDateTime] as? String) ?? ""
        let captureDate = parseExifDate(dateStr)

        // GPS
        let lat = gpsCoord(gps,
                           value: kCGImagePropertyGPSLatitude,
                           ref:   kCGImagePropertyGPSLatitudeRef,
                           negativeRef: "S")
        let lon = gpsCoord(gps,
                           value: kCGImagePropertyGPSLongitude,
                           ref:   kCGImagePropertyGPSLongitudeRef,
                           negativeRef: "W")
        let alt = numeric(gps[kCGImagePropertyGPSAltitude])
        let dir = numeric(gps[kCGImagePropertyGPSImgDirection])

        // IPTC + ImageDescription
        let headline = (iptc[kCGImagePropertyIPTCHeadline] as? String) ?? ""
        let caption =
            (iptc[kCGImagePropertyIPTCCaptionAbstract] as? String) ??
            (tiff[kCGImagePropertyTIFFImageDescription] as? String) ?? ""
        let keywords = (iptc[kCGImagePropertyIPTCKeywords] as? [String]) ?? []

        // Dimensions
        let width  = numeric(props[kCGImagePropertyPixelWidth])  ?? 0
        let height = numeric(props[kCGImagePropertyPixelHeight]) ?? 0

        // Color profile
        let profile =
            (props[kCGImagePropertyProfileName] as? String) ??
            (props[kCGImagePropertyColorModel]  as? String) ?? ""

        // File size
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?
            .int64Value ?? 0

        // Format label (use UTI if present, else extension)
        let uti = source.flatMap { CGImageSourceGetType($0) as String? } ?? ""
        let fmt = formatLabel(uti: uti, ext: file.pathExtension)

        return ImageRecord(
            id: file.path,
            file: file,
            sidecarURL: sidecar,
            fmt: fmt,
            dim: CGSize(width: width, height: height),
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
            headline: headline,
            caption: caption,
            keywords: keywords,
            captureDate: captureDate,
            timezone: .unknown,
            // ImageIO doesn't surface XMP rating; the ExifTool path (the
            // default) reads it. This fallback only runs when ExifTool
            // resources can't be resolved.
            rating: 0
        )
    }
}

// MARK: - Helpers

private func combine(_ a: String, _ b: String) -> String {
    let lhs = a.trimmingCharacters(in: .whitespaces)
    let rhs = b.trimmingCharacters(in: .whitespaces)
    if lhs.isEmpty { return rhs }
    if rhs.isEmpty { return lhs }
    if rhs.lowercased().contains(lhs.lowercased()) { return rhs }
    return "\(lhs) \(rhs)"
}

private func numeric(_ value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue }
    if let s = value as? String,   let d = Double(s) { return d }
    return nil
}

private func gpsCoord(
    _ gps: [CFString: Any],
    value: CFString,
    ref: CFString,
    negativeRef: String
) -> Double? {
    guard let raw = numeric(gps[value]) else { return nil }
    let refValue = (gps[ref] as? String)?.uppercased() ?? ""
    return refValue == negativeRef ? -raw : raw
}

private func formatShutter(_ seconds: Double) -> String {
    if seconds >= 1 {
        return String(format: "%.1f s", seconds)
    }
    let denom = (1.0 / seconds).rounded()
    return "1/\(Int(denom)) s"
}

private let exifDateFormatters: [DateFormatter] = {
    let formats = [
        "yyyy:MM:dd HH:mm:ssZZZZZ",
        "yyyy:MM:dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ss",
    ]
    return formats.map { f in
        let df = DateFormatter()
        df.dateFormat = f
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        return df
    }
}()

private func parseExifDate(_ s: String) -> Date? {
    guard !s.isEmpty else { return nil }
    for f in exifDateFormatters {
        if let date = f.date(from: s) { return date }
    }
    return nil
}

private func formatLabel(uti: String, ext: String) -> String {
    let lower = ext.lowercased()
    switch lower {
    case "jpg", "jpeg":  return "JPEG"
    case "heic", "heif": return "HEIC"
    case "png":          return "PNG"
    case "tif", "tiff":  return "TIFF"
    case "nef":          return "Nikon RAW (NEF)"
    case "cr2", "cr3":   return "Canon RAW (\(lower.uppercased()))"
    case "arw":          return "Sony RAW (ARW)"
    case "raf":          return "Fuji RAW (RAF)"
    case "orf":          return "Olympus RAW (ORF)"
    case "dng":          return "Adobe DNG"
    default:             return lower.uppercased()
    }
}
