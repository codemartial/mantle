import Foundation

// A row in the browser. Real population happens in step 3 (LibraryIndex).
// For step 2 the library list is empty after a folder open; just placeholder.
struct LibraryEntry: Identifiable, Hashable {
    let id: String           // stable key -- the basename without extension
    let basename: String     // e.g. "DSC_0421"
    let displayURL: URL      // preferred file for preview (JPEG if paired with RAW)
    let siblingURLs: [URL]   // all the original files this entry represents
    let sidecarURL: URL?     // existing .xmp neighbor, if any
    let format: String       // "JPEG" | "RAW" | "RAW + JPEG" | ...
}
