// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI
import AppKit

// Folder picker via NSOpenPanel -- more native than SwiftUI's fileImporter,
// matches what photo apps on macOS use.
@MainActor
enum FolderPicker {
    static func present(onPick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder of photos."
        panel.title = "Open Folder"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                onPick(url)
            }
        }
    }
}

struct AppCommands: Commands {
    let state: AppState

    var body: some Commands {
        // Replace the system undo items with the app's own history. Menu key
        // equivalents resolve before the focused field editor sees Cmd+Z, so
        // while these items are enabled the global stack always wins -- which
        // is what we want, since every keystroke already flowed through
        // updateField and coalescing restores the whole field via the binding.
        CommandGroup(replacing: .undoRedo) {
            Button(state.undo.undoMenuTitle) {
                state.performUndo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!state.undo.canUndo)

            Button(state.undo.redoMenuTitle) {
                state.performRedo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!state.undo.canRedo)
        }
        CommandGroup(replacing: .newItem) {
            Button("Open Folder...") {
                FolderPicker.present { url in
                    state.openFolder(url)
                }
            }
            .keyboardShortcut("o", modifiers: .command)
        }
    }
}
