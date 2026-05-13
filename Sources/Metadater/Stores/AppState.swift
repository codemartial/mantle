import Foundation
import Observation

@MainActor
@Observable
final class AppState {

    var folderURL: URL?
    var library: [LibraryEntry] = []
    var selectedID: String?
    var status: SaveStatus = .idle

    func bootstrap() {
        if let url = FolderBookmark.load() {
            openFolder(url)
        }
    }

    func openFolder(_ url: URL) {
        folderURL = url
        FolderBookmark.save(url)
        // Step 3 fills these via LibraryIndex.scan
        library = []
        selectedID = nil
        status = .idle
    }

    var folderDisplayName: String {
        folderURL?.lastPathComponent ?? ""
    }
}
