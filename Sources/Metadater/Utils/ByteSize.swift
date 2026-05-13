import Foundation

enum ByteSize {
    static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
