import SwiftUI

@main
struct MetadaterApp: App {
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
    }
}
