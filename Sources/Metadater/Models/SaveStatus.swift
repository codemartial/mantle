import Foundation

enum SaveStatus: Equatable {
    case idle
    case unsaved(count: Int)
    case saving
    case saved
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:            return "All changes saved"
        case .unsaved(let n):  return n == 1 ? "1 unsaved" : "\(n) unsaved"
        case .saving:          return "Saving..."
        case .saved:           return "Saved"
        case .failed(let m):   return "Save failed: \(m)"
        }
    }
}
