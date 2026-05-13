import Foundation

enum SaveStatus: Equatable {
    case idle
    case saving
    case saved
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:           return "All changes saved"
        case .saving:         return "Auto-saving..."
        case .saved:          return "Auto-saved"
        case .failed(let m):  return "Save failed: \(m)"
        }
    }
}
