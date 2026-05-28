@preconcurrency import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var aligners: [TrafficLightAligner] = []
    private var becameMainTask: Task<Void, Never>?
    // Weak ref so the AppState owned by MantleApp can drive the
    // terminate-flush handshake. Set from MantleApp's .task.
    weak var stateRef: AppState?

    @MainActor
    func attach(state: AppState) {
        self.stateRef = state
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows {
            attachAligner(to: window)
        }

        // Async-sequence notification API: the for-await body inherits this
        // method's MainActor isolation, so there's no @Sendable closure to
        // bridge across. The task is held for the app's lifetime.
        becameMainTask = Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: NSWindow.didBecomeMainNotification) {
                guard let self, let window = note.object as? NSWindow else { continue }
                self.attachAligner(to: window)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Quit-time: synthesize any in-flight batch draft into per-image edits,
    // then flush every dirty image to its sidecar before AppKit actually
    // terminates. Returning .later defers termination while we run the
    // async flush; reply(...) lets AppKit proceed when done.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let stateRef else { return .terminateNow }
        Task { @MainActor in
            stateRef.exitBatch(selecting: nil)
            await stateRef.saver.flushAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func attachAligner(to window: NSWindow) {
        if aligners.contains(where: { $0.window === window }) { return }
        // Empirically derived: under .windowStyle(.hiddenTitleBar), the
        // system traffic-light buttons live in an NSTitlebarView (not
        // themeFrame directly) with non-flipped local coords. The titlebar
        // is 28pt tall and the buttons default to origin.y = 6 (centered
        // in that 28pt strip, button center at y_window_top = 14).
        //
        // The custom SwiftUI Titlebar is 44pt with controls vertically
        // centered at y_window_top = 22. To put the buttons at that same
        // y in non-flipped NSTitlebarView coords:
        //   button center (in titlebar coords) = 28 - 22 = 6
        //   button origin.y = 6 - buttonHeight/2 = 6 - 8 = -2
        // (button height observed at 16pt; spilling 2pt below titlebar
        //  bounds is fine because NSTitlebarView doesn't clip subviews.)
        //
        // horizontalShift nudges the whole group right of AppKit's default
        // origin.x so the left gap matches the top/bottom gap around the
        // buttons. Applied as a delta from each button's captured baseline
        // so per-button spacing (close/miniaturize/zoom) is preserved.
        aligners.append(TrafficLightAligner(window: window, targetOriginY: -2, horizontalShift: 8))
    }
}

// Reposition close / miniaturize / zoom buttons by setting frame.origin.y
// to an absolute target each time AppKit re-lays them out. Idempotent --
// repeated calls converge on the same position regardless of how many
// notifications fire between AppKit's re-layouts.
@MainActor
final class TrafficLightAligner {
    weak var window: NSWindow?
    private let targetOriginY: CGFloat
    private let horizontalShift: CGFloat
    private var baselineX: [NSWindow.ButtonType: CGFloat] = [:]
    private var observers: [NSObjectProtocol] = []

    init(window: NSWindow, targetOriginY: CGFloat, horizontalShift: CGFloat) {
        self.window = window
        self.targetOriginY = targetOriginY
        self.horizontalShift = horizontalShift

        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.realign()
                }
            }
            observers.append(token)
        }

        realign()
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func realign() {
        guard let window else { return }
        if window.styleMask.contains(.fullScreen) { return }

        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in types {
            guard let button = window.standardWindowButton(type) else { continue }
            // Capture AppKit's default origin.x once per button, then offset
            // from that baseline. Reading button.frame.origin.x after we've
            // already written to it would let the shift accumulate.
            if baselineX[type] == nil {
                baselineX[type] = button.frame.origin.x
            }
            let base = baselineX[type] ?? button.frame.origin.x
            button.frame.origin.x = base + horizontalShift
            button.frame.origin.y = targetOriginY
        }
    }
}
