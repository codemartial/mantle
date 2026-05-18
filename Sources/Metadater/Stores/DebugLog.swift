import Foundation
import Observation

// In-process log buffer for the debug strip at the top of the metadata
// pane. Cleared on app restart (process restart = automatic). Bounded
// to avoid unbounded growth in long sessions.

@MainActor
@Observable
final class DebugLog {
    private static let maxLines = 500
    private static let stampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private(set) var lines: [String] = []

    func append(_ line: String) {
        lines.append("\(Self.stampFormatter.string(from: Date())) \(line)")
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }

    func clear() {
        lines.removeAll(keepingCapacity: true)
    }
}
