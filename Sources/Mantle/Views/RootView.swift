// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @FocusState private var keyboardFocused: Bool

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
        // The root is the lowest-priority key handler: Esc exits a batch,
        // arrows walk the browser. onKeyPress only fires while this view holds
        // focus, so we make it focusable and claim focus on launch -- without
        // that the window itself is first responder and bare arrow / Esc keys
        // go nowhere. A focused text field (cursor movement) or the map (pan)
        // still gets the key first; it only bubbles up here when nothing else
        // consumes it.
        //
        // No focusEffectDisabled here: it propagates to descendants and would
        // strip the focus ring off the text fields too. A container focusable
        // like this doesn't draw a visible ring for pointer users.
        .focusable()
        .focused($keyboardFocused)
        .defaultFocus($keyboardFocused, true)
        .onAppear {
            // defaultFocus declares the intent; re-assert once after the first
            // layout because macOS sometimes lands first-responder on the
            // window rather than the focusable content at launch.
            DispatchQueue.main.async { keyboardFocused = true }
        }
        .onKeyPress(.escape) {
            if state.batchMode {
                state.exitBatch(selecting: state.masterID)
                return .handled
            }
            return .ignored
        }
        // down / right -> next image, up / left -> previous.
        .onKeyPress(keys: [.downArrow, .rightArrow]) { _ in
            state.selectAdjacent(1) ? .handled : .ignored
        }
        .onKeyPress(keys: [.upArrow, .leftArrow]) { _ in
            state.selectAdjacent(-1) ? .handled : .ignored
        }
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
