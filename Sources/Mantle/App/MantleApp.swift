// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

import SwiftUI

@main
struct MantleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .task {
                    appDelegate.attach(state: state)
                    state.bootstrap()
                }
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        // Hide the title-bar background + title text. Traffic-light buttons
        // remain visible (AppKit draws them as overlay window controls), so
        // the custom Titlebar in RootView fills the full 44pt strip from
        // y=0 and the traffic lights float on top of it instead of stacking
        // above it.
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(state: state)
        }

        Settings {
            PreferencesView()
                .environment(state)
        }
    }
}
