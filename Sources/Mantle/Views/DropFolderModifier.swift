import SwiftUI
import UniformTypeIdentifiers

// Accept a folder dropped onto the view. Files dropped that aren't a folder
// are ignored silently. The whole-window hover affordance is deferred to a
// later polish pass (spec section 12).
struct DropFolderModifier: ViewModifier {

    let onDrop: (URL) -> Void

    func body(content: Content) -> some View {
        content.dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                var isDir: ObjCBool = false
                let path = url.path
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                   isDir.boolValue {
                    onDrop(url)
                    return true
                }
            }
            return false
        }
    }
}

extension View {
    func acceptingFolderDrop(_ onDrop: @escaping (URL) -> Void) -> some View {
        modifier(DropFolderModifier(onDrop: onDrop))
    }
}
