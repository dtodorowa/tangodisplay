import SwiftUI

@main
struct TangoDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var sparkleUpdater = SparkleUpdater()
    @State private var hasAutoChecked = false

    init() {
        // Wire the delegate's appState reference before applicationDidFinishLaunching fires.
        // The delegate adaptor is initialised before the App body runs, so this is safe.
    }

    var body: some Scene {
        // Control window — singleton (uses Window, not WindowGroup)
        Window("TangoDisplay", id: "control") {
            ControlView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .environmentObject(appState.configStore)
                .environmentObject(sparkleUpdater)
                .onAppear {
                    // Pass appState to the delegate (cannot be done in init because
                    // @StateObject is not available until the first render)
                    appDelegate.appState = appState
                }
                .onChange(of: appState.versionChecker.updateAvailable) { isAvailable in
                    guard isAvailable, !hasAutoChecked else { return }
                    hasAutoChecked = true
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        sparkleUpdater.checkForUpdatesInBackground()
                    }
                }
        }
        .defaultSize(width: 700, height: 540)
        .commands {
            CommandGroup(after: .help) {
                Button("Tango Display Website") {
                    NSWorkspace.shared.open(URL(string: "https://tangodisplay.com")!)
                }
                Button("Facebook Group") {
                    NSWorkspace.shared.open(URL(string: "https://www.facebook.com/groups/tangodisplay")!)
                }
            }
        }

        // Set Timings window — floating info panel opened from the status bar
        Window("Set Timings", id: "set-timings") {
            SetTimingsWindowContent()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 580, height: 530)

        // Waveform window — shows amplitude waveform for the currently playing track
        Window("Waveform", id: "waveform") {
            WaveformWindowContent()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 700, height: 80)

        // Track start & end time editor — trims playback to a sub-range (built-in player only)
        Window("Track start & end time", id: "trackTiming") {
            TrackTimingWindowContent()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 700, height: 160)

        // Prelisten window — browse Music playlists and cue tracks on a separate output
        Window("Prelisten", id: "prelisten") {
            PrelistenPane(presentation: .window, library: appState.musicLibrary, player: appState.prelistenPlayer)
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1000, height: 640)
        .commands { PrelistenCommands() }

        // Presentation window — WindowGroup allows dragging to external monitors
        WindowGroup(id: "presentation") {
            PresentationView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .environmentObject(appState.configStore)
        }
        .defaultSize(width: 1280, height: 720)

        // Menu bar icon — MenuBarExtra (macOS 13+) replaces deprecated NSStatusItem
        MenuBarExtra("TangoDisplay", systemImage: "tv") {
            Button("Show Display Window") {
                WindowManager.showPresentationWindow(appState: appState)
            }
            Button("Show Settings Window") {
                WindowManager.showControlWindow()
            }
            Button("Show Setlist") {
                WindowManager.showControlWindow()
                NotificationCenter.default.post(name: .navigateToSetlist, object: nil)
            }
            PrelistenMenuButton()
            Divider()
            Button("Quit TangoDisplay") {
                NSApp.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
