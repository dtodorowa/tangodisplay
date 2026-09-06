import AppKit
import iTunesLibrary

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Injected by TangoDisplayApp after initialisation
    var appState: AppState?

    private let hotkeyService = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable macOS automatic window tabbing app-wide. Plugin editor
        // windows would otherwise get auto-merged into a tabbed container,
        // which disables the resize handle and breaks setContentSize calls.
        NSWindow.allowsAutomaticWindowTabbing = false

        guard let appState else { return }
        appState.profileStore.load()
        appState.start()
        hotkeyService.register(appState: appState)
        requestMediaLibraryAccess()
    }

    // Triggers the macOS Media Library permission prompt on first launch.
    // Required so that drags of iTunes-purchased tracks from Music.app are
    // allowed by TCC; without this the cross-process drag is silently gated
    // until something else (e.g. a SwiftUI .onDrop call) probes the library.
    // Constructing ITLibrary is the documented way to request this access on
    // macOS. Warming the trim cache does exactly that, and leaves a usable
    // snapshot behind so the first Music drag doesn't wait for the scan.
    private func requestMediaLibraryAccess() {
        SetlistManager.warmMusicTrims()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Quit TangoDisplay?"
        alert.informativeText = "This will close the display and stop polling Music."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService.unregister()
        // Turn Setlist Remote off on quit: cancels the listener cleanly and persists the
        // toggle as off so the next launch starts quiet and the user opts back in.
        if let appState {
            appState.settings.remoteControlEnabled = false
            appState.setlistRemoteBridge.teardown()
        }
    }

    /// Keep the app alive when all windows are closed so polling continues
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the dock icon when windows are hidden/minimised restores them
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            WindowManager.presentationWindow?.deminiaturize(nil)
            WindowManager.presentationWindow?.makeKeyAndOrderFront(nil)
            WindowManager.showControlWindow()
        }
        return true
    }
}
