import SwiftUI

// MARK: - Sidebar navigation items

enum SidebarItem: String, Hashable, CaseIterable {
    case live
    case setlist
    case reports
    case startup
    case cortinaRules
    case appearance
    case display
    case player
    case advanced
    case profiles

    var label: String {
        switch self {
        case .live:          return "Live"
        case .setlist:       return "Setlist"
        case .reports:       return "Reports"
        case .startup:       return "Startup"
        case .cortinaRules:  return "Cortina Rules"
        case .appearance:    return "Appearance"
        case .display:       return "Display"
        case .player:        return "Player"
        case .advanced:      return "Advanced"
        case .profiles:      return "Profiles"
        }
    }

    var icon: String {
        switch self {
        case .live:          return "play.circle.fill"
        case .setlist:       return "list.number"
        case .reports:       return "chart.bar.doc.horizontal"
        case .startup:       return "power"
        case .cortinaRules:  return "music.note"
        case .appearance:    return "paintbrush"
        case .display:       return "display"
        case .player:        return "music.note.list"
        case .advanced:      return "slider.horizontal.3"
        case .profiles:      return "paintpalette"
        }
    }

    var section: String {
        switch self {
        case .live, .setlist, .reports:                                            return "Live"
        case .startup, .cortinaRules, .appearance, .display, .player, .advanced:   return "Settings"
        case .profiles:                                                            return "Profiles"
        }
    }
}

// MARK: - Main control view

struct ControlView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var reportStore = SetlistReportStore()
    @State private var selectedItem: SidebarItem? = .live
    @State private var pendingSelection: SidebarItem? = nil
    @State private var showingUnsavedChangesAlert = false
    @State private var showingOverride = false
    @AppStorage("focusMode") private var focusMode: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preFocusSelectedItem: SidebarItem? = nil
    @State private var didApplyStartupPreferences = false
    @AppStorage(PrelistenDefaults.docked) private var prelistenDocked = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            PrelistenDockContainer {
                detail
            }
        }
        .environmentObject(reportStore)
        .frame(minWidth: 820, minHeight: 660)
        .preferredColorScheme(.dark)
        .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
            Button("Leave Without Saving", role: .destructive) {
                appState.hasUnsavedAppearanceChanges = false
                selectedItem = pendingSelection
                pendingSelection = nil
            }
            Button("Stay", role: .cancel) {
                pendingSelection = nil
            }
        } message: {
            Text("You have unsaved appearance changes. Leave without saving?")
        }
        .background(ControlWindowAccessor())
        .onAppear {
            focusMode = false
            if !didApplyStartupPreferences {
                didApplyStartupPreferences = true
                applyStartupPreferences()
            } else {
                WindowManager.ensureOpen(openWindow: openWindow)
            }
            appState.reopenPresentationWindow = { openWindow(id: "presentation") }
            if let displayID = appState.settings.targetDisplayID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    WindowManager.moveTo(displayID: displayID)
                }
            }
        }
        .sheet(isPresented: $showingOverride) {
            OverrideDialog(isPresented: $showingOverride)
                .environmentObject(appState)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .showOverrideDialog)
        ) { _ in
            showingOverride = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .hotkeyPermissionRequired)
        ) { _ in
            appState.appendDebugLog("⚠ Global hotkeys require Input Monitoring in System Settings › Privacy & Security")
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .navigateToSetlist)
        ) { _ in
            selectedItem = .setlist
        }
        .toolbar {
            ToolbarItem {
                Button {
                    prelistenDocked.toggle()
                } label: {
                    Label(prelistenDocked ? "Hide Prelisten" : "Prelisten",
                          systemImage: prelistenDocked ? "headphones.circle.fill" : "headphones")
                }
                .help(prelistenDocked ? "Hide Prelisten (⌘⇧L)" : "Prelisten Music playlists in this window (⌘⇧L)")
            }
            ToolbarItem {
                Button {
                    focusMode.toggle()
                } label: {
                    Label(focusMode ? "Exit Focus" : "Focus Mode",
                          systemImage: focusMode ? "eye.fill" : "eye")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .help(focusMode ? "Exit Focus Mode (⌘⇧F)" : "Focus Mode: setlist + live preview (⌘⇧F)")
            }
        }
        .onChange(of: focusMode) { newValue in
            if newValue {
                preFocusSelectedItem = selectedItem
                columnVisibility = .detailOnly
            } else {
                columnVisibility = .all
                selectedItem = preFocusSelectedItem
            }
        }
        .onChange(of: columnVisibility) { newValue in
            if newValue != .detailOnly && focusMode {
                focusMode = false
            }
        }
    }

    // MARK: - Startup preferences

    private func applyStartupPreferences() {
        if appState.settings.hideLeftMenuBarOnStartup {
            columnVisibility = .detailOnly
        }
        switch appState.settings.startupMode {
        case .fullExperience:
            WindowManager.ensureOpen(openWindow: openWindow)
            // Bring the Settings window in front of the Live Display so the user
            // can configure things before moving the presentation to its monitor.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                WindowManager.showControlWindow()
            }
        case .playerFocused:
            selectedItem = .setlist
            WindowManager.ensureOpen(openWindow: openWindow)
            // Wait for WindowAccessor to register the NSWindow, then miniaturise
            // and bring the Control window forward.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                WindowManager.presentationWindow?.miniaturize(nil)
                WindowManager.showControlWindow()
            }
        }
    }

    // MARK: - Sidebar

    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { selectedItem },
            set: { newValue in
                if selectedItem == .appearance,
                   appState.hasUnsavedAppearanceChanges,
                   newValue != .appearance {
                    pendingSelection = newValue
                    showingUnsavedChangesAlert = true
                } else {
                    selectedItem = newValue
                }
            }
        )
    }

    private var sidebar: some View {
        List(selection: selectionBinding) {
            Section("Live") {
                sidebarRow(.live)
                sidebarRow(.setlist)
                sidebarRow(.reports)
            }
            Section("Global Settings") {
                sidebarRow(.startup)
                sidebarRow(.cortinaRules)
                sidebarRow(.display)
                sidebarRow(.player)
                sidebarRow(.advanced)
            }
            Section("Profile Settings") {
                sidebarRow(.appearance)
                sidebarRow(.profiles)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VersionBadgeView()
                .environmentObject(appState.versionChecker)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.label, systemImage: item.icon)
            .tag(item)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if focusMode {
            FocusModeView()
        } else {
            switch selectedItem {
            case .live, .none:
                liveView
            case .setlist:
                setlistView
            case .reports:
                SetlistReportingView()
            case .startup:
                StartupSettingsView()
                    .environmentObject(appState.settings)
            case .cortinaRules:
                CortinaSettingsView()
                    .environmentObject(appState)
                    .environmentObject(appState.settings)
            case .appearance:
                AppearanceSettingsView()
                    .environmentObject(appState)
                    .environmentObject(appState.settings)
            case .display:
                DisplaySettingsView()
                    .environmentObject(appState)
                    .environmentObject(appState.settings)
            case .player:
                PlayerSettingsView()
                    .environmentObject(appState)
                    .environmentObject(appState.settings)
            case .advanced:
                AdvancedSettingsView()
                    .environmentObject(appState.settings)
            case .profiles:
                ProfilesView()
                    .environmentObject(appState.settings)
            }
        }
    }

    private var liveView: some View {
        HSplitView {
            VStack(spacing: 0) {
                if appState.settings.mirrorMode {
                    PreviewPane()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(CGFloat(16) / CGFloat(9), contentMode: .fit)
                }
                StatusPane(showingOverride: $showingOverride)
                    .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 380)
        }
    }

    @ViewBuilder
    private var setlistView: some View {
        if let lp = appState.localPlayer {
            SetlistView(setlist: appState.setlist, player: lp)
                .environmentObject(appState)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "list.number")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("Switch to Built-in Player to use the setlist")
                    .foregroundColor(.secondary)
                Button("Switch to Built-in Player") {
                    appState.settings.selectedPlayer = .builtIn
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let showOverrideDialog = Notification.Name("com.tangodisplay.showOverrideDialog")
    static let hotkeyPermissionRequired = Notification.Name("com.tangodisplay.hotkeyPermissionRequired")
    static let navigateToSetlist = Notification.Name("com.tangodisplay.navigateToSetlist")
}

// MARK: - Control window accessor

/// Captures the control window's NSWindow and attaches CloseGuard so the
/// red ✕ button triggers a quit confirmation instead of silently closing.
private struct ControlWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window {
                window.delegate = CloseGuard.shared
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
