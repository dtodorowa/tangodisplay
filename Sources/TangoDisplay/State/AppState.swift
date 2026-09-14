import CoreAudio
import Foundation
import AppKit
import Combine
import TangoDisplayCore

enum FadeMode: Equatable { case none, fadeAndStop, fadeAndContinue }

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published private(set) var displayState = DisplayState()
    @Published private(set) var watchdogActive = false
    @Published private(set) var availableDisplays: [DisplayInfo] = []
    @Published private(set) var availableAudioOutputDevices: [AudioOutputDevice] = []
    @Published private(set) var debugLog: [String] = []
    /// Transient override set by AppearanceSettingsView while editing.
    /// Non-nil only while the Appearance tab is visible; cleared on disappear.
    @Published var draftProfile: AppearanceProfile? = nil
    /// Set by AppearanceSettingsView when the working copy differs from the last saved state.
    @Published var hasUnsavedAppearanceChanges: Bool = false
    /// Album artwork for the current dance track. Nil during cortinas and idle.
    @Published private(set) var currentArtwork: NSImage? = nil
    /// persistentID of the track whose artwork is currently displayed; drives transition identity.
    @Published private(set) var displayedArtworkTrackID: String? = nil

    /// Entry the "Track start & end time" editor window operates on (right-clicked entry).
    @Published var trimEditorEntryID: UUID? = nil

    // MARK: - Window actions (set by ControlView; used by MenuBarController)

    /// Stored by ControlView so non-SwiftUI code can reopen the presentation window.
    var reopenPresentationWindow: (() -> Void)? = nil

    // MARK: - Services

    let settings = AppSettings()
    let profileStore = ProfileStore()
    let versionChecker = VersionChecker()
    let setlist = SetlistManager()
    let configStore = PluginConfigurationStore()
    let microphoneMonitor = MicrophoneMonitor()
    let musicLibrary = MusicLibraryBrowser()
    lazy var prelistenPlayer = PrelistenPlayer(settings: settings, trackFiles: musicLibrary.trackFiles)
    lazy var setlistRemoteBridge: RemoteControlBridge = RemoteControlBridge(appState: self, settings: self.settings)
    private var activeSource: any MusicPlayerSource = MusicPoller()  // replaced in start()
    private var cancellables = Set<AnyCancellable>()

    var localPlayer: LocalPlayerSource? { activeSource as? LocalPlayerSource }

    // MARK: - Internal state

    private var artworkCache: [String: NSImage] = [:]  // keyed by persistentID
    private var artworkCacheKeys: [String] = []        // insertion-order for LRU eviction
    private let artworkCacheMaxSize = 20
    private var trackHistory: [Track] = []           // cleared on each cortina/idle
    private var playlistTracks: [Track]? = nil       // last known playlist; nil = unavailable
    private var playlistCurrentIndex: Int = 0        // 0-based
    private var lastKnownNextTrack: Track? = nil     // from onNextTrackUpdate; used for Embrace cortina look-ahead
    private var lastSeenPersistentID: String = ""
    private var lastSeenTrack: Track? = nil
    @Published private(set) var currentPlayerState: PlayerState = .stopped
    private var isPausedByUser = false               // ⌘⇧P toggle
    private var pendingStateBeforePause: DisplayState? = nil  // state snapshot for unpausing
    private var pauseArmTask: Task<Void, Never>?     // Embrace-style pause confirmation timer
    @Published private(set) var fadeMode: FadeMode = .none
    @Published private(set) var isLastTandaActive: Bool = false
    private var fadeTask: Task<Void, Never>?
    private var autoFadeTask: Task<Void, Never>?
    private var preFadeVolume: Float = 1.0
    var isDisplayPausedByUser: Bool { isPausedByUser }
    var activeSourceSupportsPlaylist: Bool { activeSource.supportsPlaylist }

    // MARK: - Init

    init() {
        refreshDisplayList()
        registerForScreenChanges()
        refreshAudioOutputDeviceList()
        registerForAudioDeviceChanges()
        // Forward nested ObservableObject changes so PresentationView re-renders
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        profileStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        observePlayerSelection()
        observeJRiverZone()
        observeMicrophoneMonitor()
        observeRemoteControlEnabled()
    }

    private func observeRemoteControlEnabled() {
        settings.$remoteControlEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.handleRemoteControlEnabledChange(enabled) }
            .store(in: &cancellables)
    }

    private func handleRemoteControlEnabledChange(_ enabled: Bool) {
        if enabled {
            // Attach the transport on first enable; subsequent enables just resume.
            // The listener stays bound across off/on toggles to avoid the EADDRINUSE
            // (NWError 48) race that hits when a TCP listener is cancelled and rebound
            // on the same port in quick succession.
            if !setlistRemoteBridge.isRunning {
                let transport = HTTPServerTransport(htmlProvider: { AppState.loadRemoteUIHTML() })
                do {
                    try setlistRemoteBridge.attach(transport: transport)
                } catch {
                    setlistRemoteBridge.reportStartError("Failed to start server: \(error.localizedDescription)")
                    NSLog("[TangoDisplay] Setlist Remote failed to start: \(error)")
                }
            } else {
                setlistRemoteBridge.resume()
            }
        } else {
            setlistRemoteBridge.pause()
        }
    }

    private static func loadRemoteUIHTML() -> Data {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "RemoteUI"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        if let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "RemoteUI"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return Data("<!doctype html><meta charset=utf-8><h1>Setlist Remote UI missing</h1>".utf8)
    }

    // MARK: - Lifecycle

    func start() {
        activeSource = makeSource(for: settings.selectedPlayer)
        wireCallbacks(to: activeSource)
        activeSource.start()
        versionChecker.startPeriodicChecks()
        if settings.decibelMeterEnabled { microphoneMonitor.start() }
        if settings.remoteControlEnabled { handleRemoteControlEnabledChange(true) }
    }

    func pollNow() {
        activeSource.pollNow()
    }

    // MARK: - Source management

    private func makeSource(for choice: MusicPlayerChoice) -> any MusicPlayerSource {
        switch choice {
        case .musicApp: return MusicPoller()
        case .swinsian: return SwinsianMonitor()
        case .embrace:  return EmbracMonitor()
        case .jriver:   return JRiverPoller(zoneID: settings.jriverZoneID)
        case .megaSeg:  return MegaSegMonitor()
        case .builtIn:  return LocalPlayerSource(setlist: setlist, settings: settings, configStore: configStore, volume: settings.builtInVolume)
        }
    }

    private func wireCallbacks(to source: any MusicPlayerSource) {
        source.onTrackUpdate = { [weak self] track, state in
            self?.handleTrackUpdate(track: track, playerState: state)
        }
        source.onPlaylistUpdate = { [weak self] context in
            self?.handlePlaylistUpdate(context)
        }
        source.onNextTrackUpdate = { [weak self] nextTrack in
            guard let self else { return }
            self.lastKnownNextTrack = nextTrack
            if self.displayState.mode == .cortina {
                let detector = self.settings.makeDetector()
                let validNext = nextTrack.flatMap { detector.isCortina(genre: $0.genre) ? nil : $0 }
                if self.displayState.nextTrack != validNext {
                    self.displayState.nextTrack = validNext
                }
            }
        }
        source.onWatchdogChanged = { [weak self] active in
            self?.watchdogActive = active
            let name = self?.settings.selectedPlayer.displayName ?? "Player"
            self?.appendDebugLog(active
                ? "⚠ Watchdog active — \(name) unreachable"
                : "✓ \(name) reconnected")
        }
    }

    private func observePlayerSelection() {
        settings.$selectedPlayer
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] choice in self?.switchSource(to: choice) }
            .store(in: &cancellables)
    }

    private func observeJRiverZone() {
        settings.$jriverZoneID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.settings.selectedPlayer == .jriver else { return }
                self.switchSource(to: .jriver)
            }
            .store(in: &cancellables)
    }

    private func observeMicrophoneMonitor() {
        settings.$decibelMeterEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                enabled ? self?.microphoneMonitor.start() : self?.microphoneMonitor.stop()
            }
            .store(in: &cancellables)
    }

    private func switchSource(to choice: MusicPlayerChoice) {
        activeSource.stop()
        resetTransientState()
        let newSource = makeSource(for: choice)
        wireCallbacks(to: newSource)
        activeSource = newSource
        activeSource.start()
        appendDebugLog("Switched player to \(choice.displayName)")
    }

    private func cancelPauseArm() {
        pauseArmTask?.cancel()
        pauseArmTask = nil
    }

    func cancelFade() {
        guard fadeMode != .none else { return }
        fadeTask?.cancel()
        fadeTask = nil
        localPlayer?.volume = preFadeVolume
        fadeMode = .none
    }

    private func cancelAutoFade() {
        autoFadeTask?.cancel()
        autoFadeTask = nil
    }

    func setLastTanda(id: UUID, value: Bool) {
        setlist.setIsLastTanda(id: id, value: value)
        if value {
            // Activate immediately if this cortina is currently playing
            if let player = localPlayer, player.currentEntryID == id,
               displayState.mode == .cortina {
                isLastTandaActive = true
            }
        } else if isLastTandaActive {
            // Deactivate if we're removing the marker from the active entry or during its tanda
            if let player = localPlayer, player.currentEntryID == id {
                isLastTandaActive = false
            } else if displayState.mode == .playing || displayState.mode == .performance {
                isLastTandaActive = false
            }
        }
    }

    func activateLastTanda(_ active: Bool) {
        isLastTandaActive = active
    }

    func toggleIgnoresAutoFadeForEntry(id: UUID) {
        setlist.toggleIgnoresAutoFade(id: id)
        guard let entry = setlist.entries.first(where: { $0.id == id }),
              entry.state == .playing else { return }
        if entry.ignoresAutoFade {
            cancelAutoFade()
        } else {
            rescheduleAutoFadeIfNeeded()
        }
    }

    private func rescheduleAutoFadeIfNeeded() {
        guard settings.autoFadeCortinasEnabled,
              displayState.mode == .cortina,
              let player = localPlayer,
              autoFadeTask == nil else { return }
        if setlist.entries.first(where: { $0.id == player.currentEntryID })?.ignoresAutoFade == true { return }
        let dur = player.duration > 0 ? player.duration
            : (setlist.entries.first(where: { $0.state == .playing })?.duration ?? 0.0)
        let remaining = autoFadeDelay(trackDuration: dur) - player.elapsed
        if remaining <= 0 {
            triggerAutoFadeCortina()
            return
        }
        autoFadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self.triggerAutoFadeCortina()
        }
    }

    private func resetTransientState() {
        cancelPauseArm()
        cancelFade()
        cancelAutoFade()
        trackHistory.removeAll()
        playlistTracks = nil
        playlistCurrentIndex = 0
        lastSeenPersistentID = ""
        lastSeenTrack = nil
        currentPlayerState = .stopped
        isPausedByUser = false
        pendingStateBeforePause = nil
        watchdogActive = false
        lastKnownNextTrack = nil
        displayState = DisplayState()
        currentArtwork = nil
        displayedArtworkTrackID = nil
        artworkCache.removeAll()
    }

    // MARK: - Track update (core state machine)

    private func handleTrackUpdate(track: Track?, playerState: PlayerState) {
        // Skip duplicate polls — but allow through if track metadata changed (e.g. albumArtist enrichment)
        let pid = track?.persistentID ?? ""
        guard pid != lastSeenPersistentID || playerState != currentPlayerState || track != lastSeenTrack else { return }

        // Cancel any in-progress fade and pending auto-fade if the track changed externally
        if pid != lastSeenPersistentID {
            if fadeMode != .none { cancelFade() }
            cancelAutoFade()
        }

        lastSeenPersistentID = pid
        lastSeenTrack = track

        // Protect the armed state from being overwritten by periodic .playing callbacks.
        if currentPlayerState == .pauseArmed {
            if playerState == .playing && pid == lastSeenPersistentID {
                lastSeenTrack = track
                return
            }
            cancelPauseArm()   // track changed or stopped while armed — disarm silently
        }

        currentPlayerState = playerState

        // Stopped
        if playerState == .stopped || track == nil {
            cancelAutoFade()
            trackHistory.removeAll()
            displayState = DisplayState()   // mode = .idle
            isPausedByUser = false
            pendingStateBeforePause = nil
            currentArtwork = nil
            displayedArtworkTrackID = nil
            isLastTandaActive = false
            return
        }

        guard let track else { return }

        // Override mode: ignore track changes
        if displayState.mode == .override { return }

        // User-paused: update internal state but freeze display
        if isPausedByUser {
            // Still update playlist-derived info in the background but don't mutate displayState
            updateTandaPositionQuietly(track: track)
            return
        }

        // Player paused (not user-initiated): show track but indicate paused; clear artwork
        if playerState == .paused {
            if trackHistory.last?.persistentID != track.persistentID {
                trackHistory.append(track)
            }
            let detector = settings.makeDetector()
            let position = computeTandaPosition(track: track, detector: detector)
            displayState = DisplayState(
                mode: .paused,
                currentTrack: track,
                nextTrack: nil,
                tandaPosition: position,
                overrideText: nil
            )
            currentArtwork = nil
            displayedArtworkTrackID = nil
            return
        }

        let detector = settings.makeDetector()
        let trackIsCortina = detector.isCortina(genre: track.genre)

        if trackIsCortina {
            let raw = track.genre
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if raw.isEmpty {
                appendDebugLog("⚠ '\(track.title)' has empty genre — classified as cortina (check player tags)")
            } else if raw != trimmed {
                appendDebugLog("⚠ '\(track.title)' genre \(raw.debugDescription) has leading/trailing whitespace — classified as cortina after trimming to \(trimmed.debugDescription)")
            }
        }

        if trackIsCortina {
            handleCortinaTrack(track: track, detector: detector)
        } else {
            handleDanceTrack(track: track, detector: detector)
        }
    }

    private func handleCortinaTrack(track: Track, detector: CortinaDetector) {
        // Anchor playlistCurrentIndex to the cortina's real position.
        // playlistCurrentIndex may be stale if the user skipped tracks or
        // double-clicked a cortina — the playlist context only refreshes every 20s.
        // For the local player, use the UUID-based entry lookup so that duplicate
        // cortina files (same persistentID) resolve to the correct occurrence.
        if let player = localPlayer,
           let id = player.currentEntryID,
           let idx = setlist.entries.firstIndex(where: { $0.id == id }) {
            playlistCurrentIndex = idx
        } else if let tracks = playlistTracks,
           let idx = tracks.firstIndex(where: { $0.persistentID == track.persistentID }) {
            playlistCurrentIndex = idx
        }

        // Trigger a fresh playlist fetch so the look-ahead reflects the current playlist.
        // handlePlaylistUpdate will update or clear nextTrack when the result arrives.
        activeSource.triggerPlaylistFetch()

        // Find the next non-cortina track (first track of next tanda).
        // For Music.app this uses the full playlist; for Embrace it falls back to
        // lastKnownNextTrack (already set by onNextTrackUpdate before this runs).
        let nextTrack = findNextDanceTrack(after: playlistCurrentIndex, detector: detector)
            ?? lastKnownNextTrack.flatMap { detector.isCortina(genre: $0.genre) ? nil : $0 }
        trackHistory.removeAll()

        // Last tanda: deactivate (previous tanda ended); re-activate if this cortina is marked
        isLastTandaActive = false
        if let player = localPlayer,
           let id = player.currentEntryID,
           setlist.entries.first(where: { $0.id == id })?.isLastTanda == true {
            isLastTandaActive = true
        }

        // Detect whether the first dance track after this cortina is a performance track
        // (local player only — external players don't have per-entry isPerformance metadata).
        var nextIsPerformance = false
        if let player = localPlayer, let currentID = player.currentEntryID {
            let entries = setlist.entries
            if let currentIdx = entries.firstIndex(where: { $0.id == currentID }) {
                for i in (currentIdx + 1)..<entries.count {
                    let e = entries[i]
                    if e.state == .played { continue }
                    if detector.isCortina(genre: e.track.genre) { break }
                    nextIsPerformance = e.isPerformance
                    break
                }
            }
        }

        displayState = DisplayState(
            mode: .cortina,
            currentTrack: track,
            nextTrack: nextTrack,
            tandaPosition: nil,
            overrideText: nil,
            nextTrackIsPerformance: nextIsPerformance
        )
        currentArtwork = nil
        displayedArtworkTrackID = nil

        rescheduleAutoFadeIfNeeded()
    }

    private func handleDanceTrack(track: Track, detector: CortinaDetector) {
        let comingFromPlaying = (displayState.mode == .playing || displayState.mode == .performance)
        let comingFromCortina = (displayState.mode == .cortina)

        // If transitioning from cortina/idle, start fresh history
        if displayState.mode == .cortina || displayState.mode == .idle {
            trackHistory.removeAll()
        }

        // Append to history if it's a new track
        if trackHistory.last?.persistentID != track.persistentID {
            trackHistory.append(track)
        }

        // Determine whether the current entry is a performance track (local player only)
        let isPerformanceTrack: Bool
        if let player = localPlayer, let entryID = player.currentEntryID,
           let entry = setlist.entries.first(where: { $0.id == entryID }) {
            isPerformanceTrack = entry.isPerformance
        } else {
            isPerformanceTrack = false
        }
        let trackDisplayMode: DisplayMode = isPerformanceTrack ? .performance : .playing

        // If we transitioned from .playing or .cortina and the new track isn't in the
        // known playlist (different playlist loaded), reset history and fetch fresh
        // playlist data. Show "Track 1" immediately; handlePlaylistUpdate will update
        // to the full "X of Y" position when the fetch completes.
        let trackInPlaylist = playlistTracks?.contains(where: { $0.persistentID == track.persistentID }) ?? true
        if (comingFromPlaying || comingFromCortina) && !trackInPlaylist {
            trackHistory = [track]
            activeSource.triggerPlaylistFetch()
            displayState = DisplayState(
                mode: trackDisplayMode,
                currentTrack: track,
                nextTrack: nil,
                tandaPosition: TandaPosition(current: 1, total: nil),
                overrideText: nil
            )
            if !isPerformanceTrack { fetchArtworkIfNeeded(for: track) }
            return
        }

        // Guarantee a non-nil position: history always has at least 1 track at this point
        let position = computeTandaPosition(track: track, detector: detector)
            ?? TandaPosition(current: max(1, trackHistory.count), total: nil)
        displayState = DisplayState(
            mode: trackDisplayMode,
            currentTrack: track,
            nextTrack: nil,
            tandaPosition: position,
            overrideText: nil
        )
        if !isPerformanceTrack { fetchArtworkIfNeeded(for: track) }
    }

    private func updateTandaPositionQuietly(track: Track) {
        // Called when paused: keep history up to date so it's ready on unpause
        if trackHistory.last?.persistentID != track.persistentID {
            trackHistory.append(track)
        }
    }

    // MARK: - Playlist update

    private func handlePlaylistUpdate(_ context: (tracks: [Track], currentIndex: Int)?) {
        guard let context else {
            playlistTracks = nil
            return
        }
        playlistTracks = context.tracks
        playlistCurrentIndex = context.currentIndex

        // Re-derive tanda position with updated playlist data (only update if non-nil to
        // avoid clearing a working history-based position when the playlist path fails)
        if displayState.mode == .playing, let current = displayState.currentTrack {
            let detector = settings.makeDetector()
            if let position = computeTandaPosition(track: current, detector: detector),
               displayState.tandaPosition != position {
                displayState.tandaPosition = position
            }
        }

        // Re-evaluate cortina look-ahead with fresh data. If the cortina is no longer
        // in the new playlist (user switched playlists), clear the stale next-track display.
        // playlistCurrentIndex was already set to context.currentIndex above (correct for
        // all sources, including duplicate-cortina setlists on the local player), so use it
        // directly rather than re-deriving via firstIndex — which would always return the
        // first occurrence and produce the wrong look-ahead for duplicate cortina files.
        if displayState.mode == .cortina, let currentTrack = displayState.currentTrack {
            let detector = settings.makeDetector()
            if let tracks = playlistTracks {
                // Primary check: prefer the stored index (handles duplicate-cortina setlists).
                if tracks.indices.contains(playlistCurrentIndex),
                   tracks[playlistCurrentIndex].persistentID == currentTrack.persistentID {
                    var nextFromPlaylist = findNextDanceTrack(after: playlistCurrentIndex, detector: detector)
                    // Prefer lastKnownNextTrack when PIDs match: it was fetched via
                    // /File/GetInfo and carries full metadata (year, albumArtist, etc.)
                    // that the MPL playlist format may omit.
                    if let np = nextFromPlaylist, let known = lastKnownNextTrack,
                       np.persistentID == known.persistentID {
                        nextFromPlaylist = known
                    }
                    displayState.nextTrack = nextFromPlaylist
                } else {
                    // Primary check failed — playlistCurrentIndex is stale (e.g. JRiver briefly
                    // returned a wrong PlayingNowPosition). Count occurrences of this PID:
                    //  - 0: cortina genuinely not in playlist (user switched) → clear
                    //  - 1: safe to self-correct the index and re-derive nextTrack
                    //  - 2+: ambiguous (duplicate cortina files) — leave nextTrack intact;
                    //    onNextTrackUpdate will refresh it from NextFileKey within 2 s.
                    let occurrences = tracks.indices.filter {
                        tracks[$0].persistentID == currentTrack.persistentID
                    }
                    switch occurrences.count {
                    case 0:
                        displayState.nextTrack = nil
                    case 1:
                        let idx = occurrences[0]
                        playlistCurrentIndex = idx
                        var nextFromPlaylist = findNextDanceTrack(after: idx, detector: detector)
                        if let np = nextFromPlaylist, let known = lastKnownNextTrack,
                           np.persistentID == known.persistentID {
                            nextFromPlaylist = known
                        }
                        displayState.nextTrack = nextFromPlaylist
                    default:
                        break
                    }
                }
            } else {
                displayState.nextTrack = nil
            }
        }
    }

    // MARK: - Override

    func activateOverride(text: String) {
        displayState.overrideText = text
        displayState.mode = .override
        currentArtwork = nil
        displayedArtworkTrackID = nil
    }

    func clearOverride() {
        displayState.overrideText = nil
        displayState.mode = .idle
        isPausedByUser = false          // don't inherit a pre-override user-pause
        pendingStateBeforePause = nil
        lastSeenPersistentID = ""       // force re-evaluation on next poll
        lastSeenTrack = nil
        currentPlayerState = .stopped
        pollNow()                       // trigger immediately rather than waiting up to 2s
    }

    // MARK: - Pause toggle (⌘⇧P)

    func togglePaused() {
        if isPausedByUser {
            isPausedByUser = false
            pendingStateBeforePause = nil
            // Reset the dedup guard so the next poll re-evaluates current player state.
            // Restoring the pre-pause snapshot is unsafe — the player state may have changed
            // while the display was frozen, so currentPlayerState is already stale and the
            // guard would permanently skip the correction poll.
            lastSeenPersistentID = ""
            lastSeenTrack = nil
            currentPlayerState = .stopped
            displayState = DisplayState()   // idle until the poll arrives
            pollNow()                       // trigger immediately rather than waiting up to 2s
        } else {
            isPausedByUser = true
            pendingStateBeforePause = displayState
            displayState.mode = .paused
            currentArtwork = nil
            displayedArtworkTrackID = nil
        }
    }

    // MARK: - Transport passthrough (built-in player only)

    func transportPlay()  { activeSource.play() }

    func transportPause() {
        switch currentPlayerState {
        case .playing:
            currentPlayerState = .pauseArmed
            pauseArmTask?.cancel()
            pauseArmTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                if self.currentPlayerState == .pauseArmed {
                    self.currentPlayerState = .playing
                }
            }
        case .pauseArmed:
            cancelPauseArm()
            activeSource.pause()
        default:
            break
        }
    }

    func transportStop()           { cancelFade(); localPlayer?.stopTrack() }
    func transportSkipNext()       { cancelFade(); cancelPauseArm(); activeSource.skipNextImmediate() }
    func transportSkipPrevious()   { cancelFade(); cancelPauseArm(); activeSource.skipPrevious() }
    func transportSeek(to s: Double) { activeSource.seek(to: s) }

    func transportFadeAndStop() {
        if fadeMode == .fadeAndStop { cancelFade(); rescheduleAutoFadeIfNeeded(); return }
        cancelAutoFade()
        guard displayState.mode == .cortina, let player = localPlayer else { return }
        if let id = player.currentEntryID { setlist.setRepeat(false, for: id) }
        preFadeVolume = player.volume
        fadeMode = .fadeAndStop
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performFade(player: player)
            guard !Task.isCancelled, self.fadeMode == .fadeAndStop else { return }
            self.fadeMode = .none
            player.volume = self.preFadeVolume
            self.localPlayer?.stopTrack()
        }
    }

    func transportFadeAndContinue() {
        if fadeMode == .fadeAndContinue { cancelFade(); rescheduleAutoFadeIfNeeded(); return }
        cancelAutoFade()
        guard displayState.mode == .cortina, let player = localPlayer else { return }
        if let id = player.currentEntryID { setlist.setRepeat(false, for: id) }
        preFadeVolume = player.volume
        fadeMode = .fadeAndContinue
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performFade(player: player)
            guard !Task.isCancelled, self.fadeMode == .fadeAndContinue else { return }
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled, self.fadeMode == .fadeAndContinue else { return }
            self.fadeMode = .none
            player.volume = self.preFadeVolume
            self.cancelPauseArm()
            self.activeSource.skipNext()
        }
    }

    private func performFade(player: LocalPlayerSource) async {
        let startVolume = player.volume
        let steps = 200
        let interval = settings.builtInFadeDuration / Double(steps)
        for i in 1...steps {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            let t = Double(i) / Double(steps)
            player.volume = startVolume * Float(pow(1.0 - t, 2.0))
        }
        player.volume = 0
    }

    private func autoFadeDelay(trackDuration: Double) -> Double {
        let fade = settings.builtInFadeDuration
        let play = settings.cortinaPlayTime
        if trackDuration > play + fade { return play }
        if trackDuration > fade        { return trackDuration - fade }
        return 0
    }

    @MainActor private func triggerAutoFadeCortina() {
        autoFadeTask = nil
        guard settings.autoFadeCortinasEnabled else { return }
        guard let player = localPlayer, fadeMode == .none else { return }
        if let id = player.currentEntryID { setlist.setRepeat(false, for: id) }
        preFadeVolume = player.volume
        fadeMode = .fadeAndContinue
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performFade(player: player)
            guard !Task.isCancelled, self.fadeMode == .fadeAndContinue else { return }
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled, self.fadeMode == .fadeAndContinue else { return }
            self.fadeMode = .none
            player.volume = self.preFadeVolume
            self.cancelPauseArm()
            self.activeSource.skipNext()
        }
    }

    func syncVolume(_ v: Float) {
        settings.builtInVolume = v
        localPlayer?.volume = v
    }

    // MARK: - Display list

    func refreshDisplayList() {
        availableDisplays = NSScreen.screens.map { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            return DisplayInfo(
                id: displayID,
                name: screen.localizedName,
                frame: screen.frame,
                isMain: screen == NSScreen.main
            )
        }
    }

    private func registerForScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDisplayList()
            }
        }
    }

    // MARK: - Audio output device list

    func refreshAudioOutputDeviceList() {
        availableAudioOutputDevices = AudioDeviceManager.outputDevices()
    }

    private func registerForAudioDeviceChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshAudioOutputDeviceList()
            }
        }
    }

    // MARK: - Debug log

    func appendDebugLog(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(ts)] \(message)")
        if debugLog.count > 200 {
            debugLog.removeFirst(debugLog.count - 200)
        }
    }

    // MARK: - Artwork

    private func fetchArtworkIfNeeded(for track: Track) {
        let pid = track.persistentID
        displayedArtworkTrackID = pid
        if let cached = artworkCache[pid] {
            currentArtwork = cached
            return
        }
        currentArtwork = nil
        let source = activeSource
        Task { [weak self] in
            let img = await source.fetchArtwork(for: track)
            guard let self, self.displayedArtworkTrackID == pid else { return }
            if let img {
                self.artworkCacheKeys.removeAll { $0 == pid }
                self.artworkCacheKeys.append(pid)
                self.artworkCache[pid] = img
                if self.artworkCacheKeys.count > self.artworkCacheMaxSize {
                    let evict = self.artworkCacheKeys.removeFirst()
                    self.artworkCache.removeValue(forKey: evict)
                }
                self.currentArtwork = img
            }
        }
    }

    // MARK: - Helpers

    /// Finds the first non-cortina track after `afterIndex` in the known playlist.
    private func findNextDanceTrack(after afterIndex: Int, detector: CortinaDetector) -> Track? {
        guard let tracks = playlistTracks else { return nil }
        let startSearch = afterIndex + 1
        guard startSearch < tracks.count else { return nil }
        return tracks[startSearch...].first { !detector.isCortina(genre: $0.genre) }
    }

    /// Computes tanda position: playlist-based if available, history-based as fallback.
    private func computeTandaPosition(track: Track, detector: CortinaDetector) -> TandaPosition? {
        let tracker = TandaTracker()

        if let tracks = playlistTracks {
            // Find current track's index in the playlist by persistentID
            if let idx = tracks.firstIndex(where: { $0.persistentID == track.persistentID }) {
                playlistCurrentIndex = idx
                if let pos = tracker.position(tracks: tracks, currentIndex: idx, detector: detector) {
                    return pos
                }
                // position() returned nil (e.g. genre mismatch classified track as cortina in
                // the playlist copy) — fall through to history-based fallback below
            }
        }

        // Fallback: history-based
        return tracker.positionFromHistory(trackHistory)
    }
}

// MARK: - DisplayInfo

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let isMain: Bool
}
