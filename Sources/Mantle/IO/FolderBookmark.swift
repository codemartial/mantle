import Foundation

// Last-opened-folder persistence. Plain path string for MVP (no security
// scope, no sandbox). On miss, return nil silently so a relaunch with a
// late-mounting external drive can re-find the folder on a later launch.

enum FolderBookmark {

    private static let key = "lastFolderPath"

    static func save(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: key)
    }

    static func load() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
