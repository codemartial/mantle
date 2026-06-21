// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI
import AppKit

struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var ratingKeyMonitor: Any?
    @State private var pendingBatchRatingValue: Int?
    @State private var showBatchRatingShortcutPrompt = false

    var body: some View {
        VStack(spacing: 0) {

            Titlebar()

            ThreePane()
                .frame(maxHeight: .infinity)

            Rectangle()
                .fill(Theme.line1)
                .frame(height: 1)

            StatusBar()
                .frame(height: 24)
                .background(Theme.bgToolbar)
        }
        .frame(minWidth: 940, minHeight: 500)
        .background(Theme.bgWindow)
        .preferredColorScheme(.dark)
        // With .windowStyle(.hiddenTitleBar) the window's title bar is
        // gone, but SwiftUI still treats the top of the window as a
        // safe-area inset and pushes content 28pt down. Ignoring the
        // top edge lets the custom Titlebar fill from y=0, so the
        // traffic-light buttons float inside its 44pt strip.
        .ignoresSafeArea(edges: .top)
        .acceptingFolderDrop { url in
            state.openFolder(url)
        }
        // Esc collapses an in-progress batch: synthesize + save all dirty,
        // then land on the master. No-op when not in batch.
        .focusable()
        .onKeyPress(.escape) {
            if state.batchMode {
                state.exitBatch(selecting: state.masterID)
                return .handled
            }
            return .ignored
        }
        .onAppear { installRatingKeyMonitor() }
        .onDisappear { removeRatingKeyMonitor() }
        .alert("Use number keys for batch ratings?",
               isPresented: $showBatchRatingShortcutPrompt) {
            Button("Enable") {
                state.batchRatingNumberShortcut = .enabled
                if let value = pendingBatchRatingValue {
                    state.applyRatingToAll(value)
                }
                pendingBatchRatingValue = nil
            }
            Button("Disable") {
                state.batchRatingNumberShortcut = .disabled
                pendingBatchRatingValue = nil
            }
        } message: {
            Text("Number keys can set ratings for every selected image in batch mode. You can change this later in Preferences.")
        }
    }

    private func installRatingKeyMonitor() {
        guard ratingKeyMonitor == nil else { return }
        ratingKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRatingKey(event) ? nil : event
        }
    }

    private func removeRatingKeyMonitor() {
        if let ratingKeyMonitor {
            NSEvent.removeMonitor(ratingKeyMonitor)
            self.ratingKeyMonitor = nil
        }
    }

    private func handleRatingKey(_ event: NSEvent) -> Bool {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty,
              let chars = event.charactersIgnoringModifiers,
              chars.count == 1,
              let value = Int(chars),
              (0...5).contains(value),
              !keyboardFocusIsTextEntry() else {
            return false
        }

        if state.batchMode {
            switch state.batchRatingNumberShortcut {
            case .enabled:
                state.applyRatingToAll(value)
            case .disabled:
                return false
            case .unset:
                pendingBatchRatingValue = value
                showBatchRatingShortcutPrompt = true
            }
        } else if let id = state.selectedID, state.selectedRecord != nil {
            state.updateRating(id: id, to: value)
        } else {
            return false
        }
        return true
    }

    private func keyboardFocusIsTextEntry() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
}

// Browser stays at a fixed 252pt. Center pane and right pane share the
// remaining width in the same 1.73:1 ratio the prototype uses at its 940pt
// minimum window width -- so as the window scales up, both the preview
// area and the metadata column grow together, instead of the preview
// devouring all the extra space.
private struct ThreePane: View {
    @Environment(AppState.self) private var state

    private let browserWidth: CGFloat = 252
    private let hairlineWidth: CGFloat = 1
    // 252 / (436 + 252) = 0.366. Right pane gets this fraction of the
    // non-browser width, with a 252pt floor at the minimum window width.
    private let rightFraction: CGFloat = 0.366
    private let rightMin: CGFloat = 252

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let nonBrowser = max(0, totalWidth - browserWidth - 2 * hairlineWidth)
            let rightWidth = max(rightMin, nonBrowser * rightFraction)
            let centerWidth = max(0, nonBrowser - rightWidth)

            HStack(spacing: 0) {

                BrowserPane()
                    .frame(width: browserWidth)
                    .background(Theme.bgPanel)

                hairline()

                CenterPane()
                    .frame(width: centerWidth)

                hairline()

                if state.batchMode {
                    MetaPanelBatch()
                        .frame(width: rightWidth)
                        .background(Theme.bgPanel)
                } else {
                    MetadataPane()
                        .frame(width: rightWidth)
                        .background(Theme.bgPanel)
                }
            }
            .frame(width: totalWidth, height: geo.size.height)
        }
    }

    private func hairline() -> some View {
        Rectangle()
            .fill(Theme.line1)
            .frame(width: hairlineWidth)
            .frame(maxHeight: .infinity)
    }
}

private struct CenterPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            if state.folderURL == nil {
                EmptyStateView(onOpen: openFolder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.batchMode {
                BatchCenter()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                BatchCaptionBlock()
            } else {
                PreviewPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state.selectedEntry != nil {
                    CaptionBlock()
                }
            }
        }
    }

    private func openFolder() {
        FolderPicker.present { url in
            state.openFolder(url)
        }
    }
}
