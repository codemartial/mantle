import Foundation

// Last-selected file ID persistence. Read on bootstrap to restore the
// previously-open photo; restoration falls back to "first entry" when
// the saved ID isn't present in the freshly-scanned library (file was
// moved, deleted, or renamed since last quit).

enum SelectionBookmark {

    private static let key = "lastSelectedFileID"

    static func save(_ id: String) {
        UserDefaults.standard.set(id, forKey: key)
    }

    static func load() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
