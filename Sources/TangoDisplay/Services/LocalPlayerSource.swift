import AVFoundation
import AppKit
import Combine
import CoreAudioKit
import Foundation
import OSLog
import TangoDisplayCore
import TangoDisplayObjC

final class LocalPlayerSource: NSObject, ObservableObject, MusicPlayerSource {

    // MARK: - MusicPlayerSource callbacks

    var onTrackUpdate: ((Track?, PlayerState) -> Void)?
    var onPlaylistUpdate: ((tracks: [Track], currentIndex: Int)?) -> Void = { _ in }
    var onNextTrackUpdate: ((Track?) -> Void)?
    var onWatchdogChanged: ((Bool) -> Void)?
    var supportsPlaylist: Bool { true }
    var isTransportControllable: Bool { true }

    // MARK: - Observable playback state (for PlayerControlsView)

    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentEntryID: UUID?
    @Published private(set) var isCurrentEntryMarkedAsPlayed: Bool = false
    @Published private(set) var isActivePlaying: Bool = false {
        didSet {
            guard isActivePlaying != oldValue else { return }
            // ponytail: idle-sleep assertion only, not a full power-source watcher — battery's
            // shorter idle-sleep timeout was suspending playback mid-track on unplug.
            if isActivePlaying {
                sleepAssertionToken = ProcessInfo.processInfo.beginActivity(
                    options: .idleSystemSleepDisabled,
                    reason: "TangoDisplay setlist playback"
                )
            } else if let token = sleepAssertionToken {
                ProcessInfo.processInfo.endActivity(token)
                sleepAssertionToken = nil
            }
        }
    }
    private var sleepAssertionToken: NSObjectProtocol?

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = max(0, min(1, newValue)) }
    }

    private var _balance: Float = 0
    var balance: Float {
        get { _balance }
        set { _balance = max(-1, min(1, newValue)); applyBalance(_balance) }
    }

    // MARK: - Diagnostics

    @Published private(set) var replayGainStatus: String = ""
    @Published private(set) var hogModeConflict: Bool = false
    @Published private(set) var hogDeviceStolenAlert: Bool = false
    @Published private(set) var isChangingDevice: Bool = false

    // MARK: - Private — audio engine

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 5)
    // ShellacFilters restoration, ahead of the EQ so the record is repaired before it
    // is tone-shaped. nil when registration failed — the app then runs without them.
    private var declickUnit: AVAudioUnit?
    private var dehumUnit: AVAudioUnit?
    /// Which restoration nodes belong in the graph for the track being loaded. Read by
    /// connectAudioGraph, which is also called from paths that have no entry to hand.
    private var activeRestoration: (declick: Bool, dehum: Bool) = (false, false)
    private let replayGainMixer = AVAudioMixerNode()
    private let balanceMixer = AVAudioMixerNode()
    private var audioFile: AVAudioFile?
    private var seekOffset: Double = 0

    // MARK: - Level meter

    private(set) var levelMeter: AudioLevelMeter!

    // MARK: - Private — state

    let setlist: SetlistManager
    private let settings: AppSettings
    private let configStore: PluginConfigurationStore

    // Snapshot of chain state captured just before the first per-track config is applied.
    // Restored when the next unassigned track (with no default config) plays.
    private var preConfigSnapshot: PreConfigSnapshot? = nil

    private struct PreConfigSnapshot {
        let chainEnabled: Bool
        let chainBypassed: Bool
        let slotStates: [PluginSlotState]
    }
    private var timeObserverTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var earlyMarkedEntryIDs: Set<UUID> = []
    private var scheduleGeneration: Int = 0
    private var hoggedDeviceUID: String? = nil
    private let audioDeviceQueue = DispatchQueue(label: "com.tangodisplay.audio-device", qos: .userInitiated)

    // MARK: - Private — Audio Unit plugin chain

    private let pluginManager = AudioUnitPluginManager()

    private final class SlotRuntime {
        var avUnit: AVAudioUnit?
        var status: AudioUnitPluginStatus = .noPluginSelected
        var presetManager: AudioUnitPresetManager?
        var availablePresets: [AudioUnitPreset] = []
        var activePresetID: UUID? = nil
        var pluginWindow: NSWindow?
        var pluginWindowVC: PluginWindowViewController?
        var paramObserverTree: AUParameterTree?
        var paramObserverToken: AUParameterObserverToken?
        var currentPresetObservation: NSKeyValueObservation?
        var loadGeneration: Int = 0
        var loadTask: Task<Void, Never>?
        var isApplyingPreset: Bool = false
    }

    private var slotRuntimes: [UUID: SlotRuntime] = [:]
    @Published private(set) var audioUnitPluginStatus: AudioUnitPluginStatus = .noPluginSelected
    @Published private(set) var slotStatuses: [UUID: AudioUnitPluginStatus] = [:]
    @Published private(set) var slotPresets: [UUID: [AudioUnitPreset]] = [:]
    @Published private(set) var slotActivePresetIDs: [UUID: UUID] = [:]

    // MARK: - Private — auto-gap

    private var currentPaddingFrames: AVAudioFrameCount = 0
    private var preparedAutoGap: PreparedAutoGap?     // silence analysis bound to a specific (current, next) transition
    private var autoGapAnalysisTask: Task<Void, Never>?
    private var audioStartSampleTime: AVAudioFramePosition = 0
    private var silencePending: Bool = false
    private var manualStopPending = false             // set by a user-initiated stop; consumed by the next loadEntry

    // MARK: - Private — loudness analysis

    private var inFlightAnalysisURLs = Set<URL>()
    private let loudnessCache = LoudnessAnalysisCache.shared

    // MARK: - Init

    init(setlist: SetlistManager, settings: AppSettings, configStore: PluginConfigurationStore, volume: Float = 1.0) {
        self.setlist = setlist
        self.settings = settings
        self.configStore = configStore
        super.init()
        setupAudioEngine()
        levelMeter = AudioLevelMeter(mixerNode: audioEngine.mainMixerNode)
        playerNode.volume = max(0, min(1, volume))
        applyOutputDevice(settings.builtInOutputDeviceUID)
        applyEQGains(settings.eqGains)
        _balance = max(-1, min(1, settings.builtInBalance))
        applyBalance(_balance)
    }

    // MARK: - Audio engine setup

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        audioEngine.attach(eq)
        audioEngine.attach(replayGainMixer)
        audioEngine.attach(balanceMixer)
        setupRestorationUnits()
        connectAudioGraph(format: nil)

        let frequencies: [Float]          = [60, 250, 1000, 4000, 12000]
        let filterTypes: [AVAudioUnitEQFilterType] = [.lowShelf, .parametric, .parametric, .parametric, .highShelf]
        for (i, band) in eq.bands.enumerated() {
            band.filterType = filterTypes[i]
            band.frequency  = frequencies[i]
            band.bandwidth  = 1.0
            band.gain       = 0.0
            band.bypass     = false
        }

        try? audioEngine.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
    }

    // MARK: - Shellac restoration

    /// Instantiates the two in-process units by description. They are registered with
    /// AudioComponent rather than published to AVAudioUnitComponentManager, so they
    /// never appear in the plugin picker and never occupy one of the four user slots.
    private func setupRestorationUnits() {
        guard TDRestorationRegister() else {
            os_log(.error, "TangoDisplay: shellac restoration unavailable; continuing without it")
            return
        }

        func make(_ subType: OSType) -> AVAudioUnit {
            var acd = AudioComponentDescription()
            acd.componentType = kAudioUnitType_Effect
            acd.componentSubType = subType
            acd.componentManufacturer = TDRestorationManufacturer
            return AVAudioUnitEffect(audioComponentDescription: acd)
        }

        let declick = make(TDDeclickSubType)
        let dehum = make(TDDehumSubType)
        audioEngine.attach(declick)
        audioEngine.attach(dehum)
        declickUnit = declick
        dehumUnit = dehum

        applyRestorationParams(settings.restoration)
        // Connected from the first graph build, so start them bypassed.
        applyRestorationEngagement((false, false))
    }

    /// Which restoration nodes this entry wants. A per-track override outranks both the
    /// master switch and the cortina rule — marking one transfer for repair is meant to
    /// work whether or not restoration is on for the set.
    private func restorationNodes(for entry: SetlistEntry?) -> (declick: Bool, dehum: Bool) {
        guard let entry else { return (false, false) }
        let r = settings.restoration

        let isCortina = r.skipOnCortinas && settings.makeDetector().isCortina(genre: entry.track.genre)
        let on = entry.restorationApplied(globalDefault: r.appliesByDefault(isCortina: isCortina))
        return (declick: on && r.declickEnabled && declickUnit != nil,
                dehum:   on && r.dehumEnabled   && dehumUnit   != nil)
    }

    /// Parameter moves are written straight through; the cores retune in place, so this
    /// never needs a graph rewire. Only engagement does.
    private func applyRestorationParams(_ r: RestorationSettings) {
        func write(_ unit: AVAudioUnit?, _ values: [Float]) {
            guard let tree = unit?.auAudioUnit.parameterTree else { return }
            for (address, value) in values.enumerated() {
                tree.parameter(withAddress: AUParameterAddress(address))?.value = value
            }
        }
        write(declickUnit, r.declickValues)
        write(dehumUnit, r.dehumValues)
    }

    /// Engagement is bypass, not graph topology. Both units stay connected, so switching
    /// restoration on or off mid-track is one atomic store rather than an engine restart —
    /// which is what used to drop a chunk of audio and jump the position by up to the 0.5 s
    /// poll interval. A bypassed unit runs its DSP with a wet mix of zero: output is the dry
    /// signal bit for bit, declick's pipeline stays primed and dehum keeps tracking its line,
    /// so switching back is instant and sample-aligned.
    private func applyRestorationEngagement(_ wanted: (declick: Bool, dehum: Bool),
                                            scoutIfNewlyOn: Bool = true) {
        let dehumNewlyOn = scoutIfNewlyOn && wanted.dehum && !activeRestoration.dehum
        activeRestoration = wanted
        declickUnit?.auAudioUnit.shouldBypassEffect = !wanted.declick
        dehumUnit?.auAudioUnit.shouldBypassEffect   = !wanted.dehum

        // Engaged part-way through a record, dehum has no scout behind it and would spend
        // 9-43 s acquiring the line with the hum still audible. loadEntry does its own
        // scouting; a later one supersedes it.
        if dehumNewlyOn,
           let entry = currentEntryID.flatMap({ id in setlist.entries.first { $0.id == id } }) {
            TDRestorationScout(dehumUnit?.auAudioUnit, entry.fileURL)
        }
    }

    /// Each record carries its own clicks and its own hum, so nothing carries over.
    /// Scouting reads the opening of the file off-thread and pre-seeds dehum's detector,
    /// which otherwise needs 9-43 s of playback before it engages.
    private func startRestorationForTrack(_ entry: SetlistEntry) {
        TDRestorationForgetTrack(declickUnit?.auAudioUnit)
        TDRestorationForgetTrack(dehumUnit?.auAudioUnit)
        if activeRestoration.dehum {
            TDRestorationScout(dehumUnit?.auAudioUnit, entry.fileURL)
        }
    }

    @objc private func handleEngineConfigChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Invalidate any pending dataPlayedBack callbacks so the system-forced engine stop
            // (e.g. headphone removal on System Default) doesn't spuriously fire handleTrackEnd → skipNext().
            self.scheduleGeneration += 1
            // Graph rewire must happen with engine stopped; engine is already stopped when this fires.
            if self.audioFile != nil {
                self.connectAudioGraph(format: self.audioFile?.processingFormat)
            }

            // Capture all state before leaving the main thread.
            guard let audioUnit = self.audioEngine.outputNode.audioUnit else { return }
            let uid = self.settings.builtInOutputDeviceUID
            let hogEnabled = self.settings.builtInHogMode
            let wasPlaying = self.isActivePlaying
            let savedElapsed = self.elapsed

            // Dispatch blocking CoreAudio work off the main thread to avoid a UI spinner.
            self.audioDeviceQueue.async { [weak self] in
                guard let self else { return }

                // Re-assert the user's chosen output device before restarting.
                self.setOutputDeviceProperty(audioUnit: audioUnit, uid: uid)

                // Detect hog-mode theft by another process.
                let deviceStolenByOther: Bool
                if !uid.isEmpty && !hogEnabled {
                    let owner = AudioDeviceManager.hogOwner(forUID: uid)
                    deviceStolenByOther = owner != -1 && owner != getpid()
                } else {
                    deviceStolenByOther = false
                }

                if deviceStolenByOther && wasPlaying {
                    self.playerNode.stop()
                }

                do {
                    try self.audioEngine.start()
                } catch {
                    os_log(.error, "TangoDisplay: engine restart failed: %{public}@", error.localizedDescription)
                }

                DispatchQueue.main.async {
                    if deviceStolenByOther {
                        self.hogModeConflict = true
                        if wasPlaying {
                            self.isActivePlaying = false
                            self.reportCurrentState()
                            self.hogDeviceStolenAlert = true
                            // Pulse back to false so future interruptions can re-trigger the alert.
                            DispatchQueue.main.async { self.hogDeviceStolenAlert = false }
                        }
                    } else {
                        self.levelMeter.reinstallTap()
                        self.applyBalance(self._balance)
                        if self.audioFile != nil {
                            self.seekTo(savedElapsed)
                            if wasPlaying { self.playerNode.play() }
                        }
                    }
                }
            }
        }
    }

    private func applyOutputDevice(_ uid: String) {
        // Fast pre-check on the calling thread — if another process owns the hog, leave the
        // engine on its current device so play continues to work without hanging.
        if !uid.isEmpty {
            let owner = AudioDeviceManager.hogOwner(forUID: uid)
            if owner != -1 && owner != getpid() {
                hogModeConflict = true
                os_log(.error, "TangoDisplay: device %{public}@ is hogged by pid %d", uid, owner)
                return
            }
        }
        hogModeConflict = false

        // Capture values on the calling thread (main) before dispatching blocking work.
        guard let audioUnit = audioEngine.outputNode.audioUnit else { return }
        let wasPlaying = isActivePlaying
        let savedElapsed = elapsed
        let hogEnabled = settings.builtInHogMode
        // Invalidate any pending dataPlayedBack callbacks before stopping the player node,
        // so the stop doesn't spuriously fire handleTrackEnd → skipNext().
        scheduleGeneration += 1

        isChangingDevice = true

        audioDeviceQueue.async { [weak self] in
            guard let self else { return }

            // Release hog on the previous device.
            if let prev = self.hoggedDeviceUID {
                AudioDeviceManager.releaseHogMode(forUID: prev)
                self.hoggedDeviceUID = nil
            }

            // CoreAudio stop/start can block — must be off the main thread.
            if self.audioEngine.isRunning {
                self.playerNode.stop()
                self.audioEngine.stop()
            }

            self.setOutputDeviceProperty(audioUnit: audioUnit, uid: uid)

            do {
                try self.audioEngine.start()

                // Acquire hog mode on the audio queue (CoreAudio property set).
                if hogEnabled && !uid.isEmpty {
                    if AudioDeviceManager.acquireHogMode(forUID: uid) {
                        self.hoggedDeviceUID = uid
                        DispatchQueue.main.async { self.hogModeConflict = false }
                    } else {
                        DispatchQueue.main.async { self.hogModeConflict = true }
                        os_log(.error, "TangoDisplay: failed to acquire hog mode on %{public}@", uid)
                    }
                }

                // AVAudioEngine player ops and tap reinstall must be on main.
                DispatchQueue.main.async {
                    self.levelMeter.reinstallTap()
                    if self.audioFile != nil {
                        self.seekTo(savedElapsed)
                        if wasPlaying { self.playerNode.play() }
                    }
                    self.isChangingDevice = false
                }
            } catch {
                os_log(.error, "TangoDisplay: applyOutputDevice engine restart failed: %{public}@",
                       error.localizedDescription)
                DispatchQueue.main.async { self.isChangingDevice = false }
            }
        }
    }

    private func applyHogMode(enabled: Bool, deviceUID: String) {
        // Must be called from audioDeviceQueue. All @Published writes dispatch back to main.
        if let prev = hoggedDeviceUID {
            AudioDeviceManager.releaseHogMode(forUID: prev)
            hoggedDeviceUID = nil
        }
        guard enabled, !deviceUID.isEmpty else {
            let conflict: Bool
            if !deviceUID.isEmpty {
                let owner = AudioDeviceManager.hogOwner(forUID: deviceUID)
                conflict = owner != -1 && owner != getpid()
            } else {
                conflict = false
            }
            DispatchQueue.main.async { self.hogModeConflict = conflict }
            return
        }
        if AudioDeviceManager.acquireHogMode(forUID: deviceUID) {
            hoggedDeviceUID = deviceUID
            DispatchQueue.main.async { self.hogModeConflict = false }
        } else {
            DispatchQueue.main.async { self.hogModeConflict = true }
            os_log(.error, "TangoDisplay: failed to acquire hog mode on device %{public}@", deviceUID)
        }
    }

    deinit {
        let uid = hoggedDeviceUID
        audioDeviceQueue.async {
            if let uid { AudioDeviceManager.releaseHogMode(forUID: uid) }
        }
    }

    private func setOutputDeviceProperty(audioUnit: AudioUnit, uid: String) {
        if uid.isEmpty {
            // Restore default device by reading system default
            var defaultID = AudioDeviceID(0)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &defaultID)
            AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &defaultID, size)
        } else if var deviceID = AudioDeviceManager.audioDeviceID(forUID: uid) {
            AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &deviceID,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }
    }

    private func applyEQGains(_ gains: [Float]) {
        for (i, band) in eq.bands.enumerated() where i < gains.count {
            band.gain = gains[i]
        }
    }

    private func applyBalance(_ pan: Float) {
        balanceMixer.pan = pan
    }

    private func applyReplayGain(for entry: SetlistEntry) {
        let rgSettings = ReplayGainSettings(
            mode: settings.replayGainMode,
            preampDb: Double(settings.replayGainPreampDb),
            preventClipping: settings.replayGainPreventClipping,
            targetLoudnessLufs: Double(settings.replayGainTargetLufs)
        )
        let info = entry.track.replayGainInfo
        let cacheKey = loudnessCacheKey(for: entry)
        let rawAnalysis = cacheKey.flatMap { loudnessCache.result(for: $0) }

        // Recalculate gain from cached integrated loudness if target has changed since analysis
        let analysis: LoudnessAnalysisResult? = rawAnalysis.map { cached in
            guard cached.targetLoudnessLufs != rgSettings.targetLoudnessLufs else { return cached }
            let newGainDb = rgSettings.targetLoudnessLufs - cached.integratedLoudnessLufs
            return LoudnessAnalysisResult(
                filePath: cached.filePath, fileSize: cached.fileSize,
                modifiedDate: cached.modifiedDate, duration: cached.duration,
                integratedLoudnessLufs: cached.integratedLoudnessLufs,
                calculatedReplayGainDb: newGainDb,
                targetLoudnessLufs: rgSettings.targetLoudnessLufs,
                samplePeak: cached.samplePeak, truePeak: cached.truePeak,
                analysedAt: cached.analysedAt
            )
        }

        let result = calculateReplayGain(info: info, analysis: analysis, settings: rgSettings)
        var finalGain = result.linearGain
        let cortinaCutDb = settings.cortinaVolumeReductionDb
        if cortinaCutDb < 0 {
            let detector = settings.makeDetector()
            if detector.isCortina(genre: entry.track.genre) {
                finalGain *= Float(pow(10.0, cortinaCutDb / 20.0))
            }
        }
        replayGainMixer.outputVolume = finalGain

        let analysisInFlight = inFlightAnalysisURLs.contains(entry.fileURL)
        replayGainStatus = replayGainStatusString(result: result, settings: rgSettings,
                                                   analysisInFlight: analysisInFlight)

        if settings.replayGainMode == .auto,
           info?.trackGainDb == nil,
           analysis == nil {
            queueLoudnessAnalysis(for: entry, isCurrentTrack: true)
        }
    }

    private func replayGainStatusString(result: ReplayGainCalculationResult,
                                         settings: ReplayGainSettings,
                                         analysisInFlight: Bool) -> String {
        guard settings.mode != .off else { return "" }
        switch result.source {
        case .none:
            if analysisInFlight { return "ReplayGain: Analysing…" }
            return settings.mode == .album ? "ReplayGain: No album metadata" : "ReplayGain: No metadata"
        case .metadataTrack:
            let suffix = result.clippingProtectionApplied ? " (clipping limited)" : ""
            return String(format: "ReplayGain: Track %+.1f dB\(suffix)", result.gainDb ?? 0)
        case .metadataAlbum:
            let suffix = result.clippingProtectionApplied ? " (clipping limited)" : ""
            return String(format: "ReplayGain: Album %+.1f dB\(suffix)", result.gainDb ?? 0)
        case .analysed:
            let lufsStr = result.integratedLoudnessLufs.map { String(format: " · %.1f LUFS", $0) } ?? ""
            let suffix = result.clippingProtectionApplied ? " (clipping limited)" : ""
            return String(format: "ReplayGain: Auto %+.1f dB\(lufsStr)\(suffix)", result.gainDb ?? 0)
        }
    }

    private static func analysisStatusForError(_ error: Error) -> String {
        if error is CancellationError { return "ReplayGain: Cancelled" }
        switch error as? LoudnessAnalysisError {
        case .cannotOpenFile:    return "ReplayGain: Cannot read file"
        case .unsupportedFormat: return "ReplayGain: Unsupported format"
        case .insufficientData:  return "ReplayGain: Insufficient audio"
        case .none:              return "ReplayGain: Analysis failed"
        }
    }

    private func queueLoudnessAnalysis(for entry: SetlistEntry, isCurrentTrack: Bool) {
        let url = entry.fileURL
        guard !inFlightAnalysisURLs.contains(url) else { return }
        inFlightAnalysisURLs.insert(url)
        if isCurrentTrack { replayGainStatus = "ReplayGain: Analysing…" }

        let entryID = entry.id
        let targetLufs = Double(settings.replayGainTargetLufs)
        let cache = loudnessCache

        Task.detached(priority: .background) { [weak self] in
            let analysisResult: LoudnessAnalysisResult?
            let errorStatus: String?
            do {
                analysisResult = try await LoudnessAnalyzer.shared.analyse(
                    url: url, targetLoudnessLufs: targetLufs)
                errorStatus = nil
            } catch {
                analysisResult = nil
                errorStatus = LocalPlayerSource.analysisStatusForError(error)
            }

            if let result = analysisResult { cache.store(result) }

            let succeeded = analysisResult != nil
            let failStatus = errorStatus
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlightAnalysisURLs.remove(url)               // always runs
                guard self.currentEntryID == entryID else { return }
                if let currentEntry = self.setlist.entries.first(where: { $0.id == entryID }) {
                    self.applyReplayGain(for: currentEntry)         // re-reads cache or falls through
                }
                if !succeeded, let status = failStatus {
                    self.replayGainStatus = status
                }
            }
        }
    }

    private func preAnalyseIfNeeded(_ entry: SetlistEntry) {
        guard settings.replayGainMode == .auto,
              entry.track.replayGainInfo?.trackGainDb == nil else { return }
        if let key = loudnessCacheKey(for: entry),
           loudnessCache.result(for: key) != nil { return }
        queueLoudnessAnalysis(for: entry, isCurrentTrack: false)
    }

    private func loudnessCacheKey(for entry: SetlistEntry) -> LoudnessAnalysisCacheKey? {
        let path = entry.fileURL.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? Int64,
              let modDate = attrs[.modificationDate] as? Date else { return nil }
        return LoudnessAnalysisCacheKey(filePath: path, fileSize: fileSize, modifiedDate: modDate)
    }

    private func reapplyReplayGainIfLoaded() {
        guard let id = currentEntryID,
              let entry = setlist.entries.first(where: { $0.id == id }) else {
            replayGainStatus = ""
            return
        }
        applyReplayGain(for: entry)
    }

    // MARK: - MusicPlayerSource lifecycle

    func start() {
        setupObservers()
        reportCurrentState()
        reportPlaylist()
        initializePluginStatus()
    }

    func stop() {
        for runtime in slotRuntimes.values {
            runtime.loadTask?.cancel()
            runtime.loadTask = nil
            runtime.pluginWindow?.close()
            runtime.pluginWindow = nil
            runtime.pluginWindowVC = nil
        }
        currentEntryID = nil
        isCurrentEntryMarkedAsPlayed = false
        isActivePlaying = false
        replayGainStatus = ""
        replayGainMixer.outputVolume = 1.0
        inFlightAnalysisURLs.removeAll()
        playerNode.stop()
        audioEngine.stop()
        levelMeter.reset()
        audioFile = nil
        elapsed = 0
        duration = 0
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
        autoGapAnalysisTask?.cancel()
        preparedAutoGap = nil
        teardownObservers()
    }

    func pollNow() {
        reportCurrentState()
        reportPlaylist()
    }

    func triggerPlaylistFetch() {
        reportPlaylist()
    }

    func fetchArtwork(for track: Track) async -> NSImage? {
        guard let url = URL(string: track.persistentID), url.isFileURL else { return nil }
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        guard let item = items.first,
              let data = try? await item.load(.dataValue) else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Transport controls

    func play() {
        if let id = currentEntryID, earlyMarkedEntryIDs.contains(id) || currentEntryIsPlayed() {
            skipNext()
            return
        }
        // The topmost not-yet-played entry always wins. If a reorder dragged a queued track
        // above the currently loaded/paused entry, discard the stale load and start the top one
        // — the paused entry reverts to a normal queued track (its pause position is dropped).
        if let id = currentEntryID, audioFile != nil,
           let firstUnplayed = setlist.entries.first(where: { $0.state != .played }),
           firstUnplayed.id != id {
            setlist.markQueued(id: id)
            playerNode.stop()
            audioFile = nil
            seekOffset = 0
            elapsed = 0
            currentEntryID = firstUnplayed.id
        }
        if audioFile == nil {
            // Prefer currentEntryID if set (e.g. pause() advanced it to the next track);
            // fall back to first non-played entry for a fresh start.
            let entry: SetlistEntry?
            if let id = currentEntryID {
                entry = setlist.entries.first(where: { $0.id == id })
            } else {
                entry = setlist.entries.first(where: { $0.state != .played })
            }
            guard let entry else { return }
            loadEntry(entry)
            playerNode.play()
            isActivePlaying = true
        } else if let id = currentEntryID {
            // Resuming the track that was stopped: the pending stop is spent, so its
            // natural end must not suppress the following track's gap.
            manualStopPending = false
            setlist.markPlaying(id: id)
            seekTo(0) { [weak self] in
                self?.playerNode.play()
                self?.isActivePlaying = true
            }
        }
        reportCurrentState()
    }

    func pause() {
        manualStopPending = true
        scheduleGeneration += 1
        playerNode.stop()
        isActivePlaying = false
        if let id = currentEntryID, !earlyMarkedEntryIDs.contains(id), !currentEntryIsPlayed() {
            setlist.markPaused(id: id)
            seekTo(0)
            elapsed = 0
            reportCurrentState()
        } else if let id = currentEntryID, let nextEntry = setlist.firstUnplayed(after: id) {
            audioFile = nil
            seekOffset = 0
            currentEntryID = nextEntry.id
            elapsed = 0
            duration = nextEntry.duration ?? 0
            reportCurrentState()
            reportPlaylist()
            onNextTrackUpdate?(setlist.entry(after: nextEntry.id)?.track)
        } else {
            audioFile = nil
            seekOffset = 0
            currentEntryID = nil
            elapsed = 0
            duration = 0
            reportCurrentState()
            reportPlaylist()
            onNextTrackUpdate?(nil)
        }
    }

    func stopTrack() {
        manualStopPending = true
        if let id = currentEntryID, !earlyMarkedEntryIDs.contains(id), !currentEntryIsPlayed() {
            setlist.markQueued(id: id)
        }
        scheduleGeneration += 1
        currentEntryID = nil
        isCurrentEntryMarkedAsPlayed = false
        isActivePlaying = false
        replayGainStatus = ""
        playerNode.stop()
        audioFile = nil
        elapsed = 0
        duration = 0
        seekOffset = 0
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
        autoGapAnalysisTask?.cancel()
        preparedAutoGap = nil
        reportCurrentState()
        reportPlaylist()
        onNextTrackUpdate?(nil)
    }

    func skipNext() {
        guard let id = currentEntryID else { play(); return }
        let finishedEntry = setlist.entries.first(where: { $0.id == id })
        let stopForPerformance = (finishedEntry?.isPerformance == true) && settings.stopAfterEachPerformanceTrack
        let shouldStop = (id == setlist.stopAfterEntryID) || stopForPerformance
        // Repeat: loop the same non-dance track (stop-after wins via shouldStop above)
        if !shouldStop, finishedEntry?.repeatTrack == true, let entry = finishedEntry {
            loadEntry(entry, bypassAutoGap: true)
            playerNode.play()
            isActivePlaying = true
            reportCurrentState()
            return
        }
        setlist.markPlayed(id: id)
        if id == setlist.stopAfterEntryID { setlist.stopAfterEntryID = nil }
        if !shouldStop, let next = setlist.firstUnplayed(after: id) {
            loadEntry(next)
            playerNode.play()
            isActivePlaying = true
            reportCurrentState()
        } else {
            currentEntryID = nil
            isActivePlaying = false
            replayGainStatus = ""
            playerNode.stop()
            audioFile = nil
            elapsed = 0
            duration = 0
            seekOffset = 0
            reportCurrentState()
            reportPlaylist()
            onNextTrackUpdate?(nil)
        }
    }

    func skipNextImmediate() {
        guard let id = currentEntryID else { play(); return }
        let finishedEntry = setlist.entries.first(where: { $0.id == id })
        let stopForPerformance = (finishedEntry?.isPerformance == true) && settings.stopAfterEachPerformanceTrack
        let shouldStop = (id == setlist.stopAfterEntryID) || stopForPerformance
        // Repeat: loop the same non-dance track (stop-after wins via shouldStop above)
        if !shouldStop, finishedEntry?.repeatTrack == true, let entry = finishedEntry {
            loadEntry(entry, bypassAutoGap: true)
            playerNode.play()
            isActivePlaying = true
            reportCurrentState()
            return
        }
        setlist.markPlayed(id: id)
        if id == setlist.stopAfterEntryID { setlist.stopAfterEntryID = nil }
        if !shouldStop, let next = setlist.firstUnplayed(after: id) {
            loadEntry(next, bypassAutoGap: true)
            playerNode.play()
            isActivePlaying = true
            reportCurrentState()
        } else {
            currentEntryID = nil
            isActivePlaying = false
            replayGainStatus = ""
            playerNode.stop()
            audioFile = nil
            elapsed = 0
            duration = 0
            seekOffset = 0
            reportCurrentState()
            reportPlaylist()
            onNextTrackUpdate?(nil)
        }
    }

    func skipPrevious() {
        if elapsed > 3 {
            seek(to: 0)
            return
        }
        guard let id = currentEntryID else { return }
        if let prev = setlist.entry(before: id) {
            let wasPlaying = isActivePlaying
            loadEntry(prev)
            if wasPlaying { playerNode.play(); isActivePlaying = true; reportCurrentState() }
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        seekTo(seconds)
    }

    // MARK: - Jump to a specific entry (double-click in SetlistView)

    func jumpTo(_ entry: SetlistEntry) {
        loadEntry(entry)
        playerNode.play()
        isActivePlaying = true
        reportCurrentState()
    }

    func retryOutputDevice() {
        applyOutputDevice(settings.builtInOutputDeviceUID)
    }

    // MARK: - Private: seek implementation

    private func seekTo(_ seconds: Double, completion: (() -> Void)? = nil) {
        guard let file = audioFile else { completion?(); return }
        let sampleRate = file.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        let totalFrames = file.length
        guard startFrame < totalFrames else { completion?(); return }
        let frameCount = AVAudioFrameCount(totalFrames - startFrame)
        let wasPlaying = playerNode.isPlaying
        playerNode.stop()
        seekOffset = seconds
        elapsed = seconds
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
        scheduleGeneration += 1
        let gen = scheduleGeneration
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount,
                                   at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.handleTrackEnd(generation: gen) }
        }
        if wasPlaying { playerNode.play() }
        completion?()
    }

    // MARK: - Private: entry loading

    private func loadEntry(_ entry: SetlistEntry, bypassAutoGap: Bool = false) {
        earlyMarkedEntryIDs.remove(entry.id)
        isCurrentEntryMarkedAsPlayed = false
        playerNode.stop()
        scheduleGeneration += 1
        let gen = scheduleGeneration
        do {
            let file = try AVAudioFile(forReading: entry.fileURL)
            audioFile = file
            seekOffset = 0
            elapsed = 0
            duration = Double(file.length) / file.fileFormat.sampleRate
            // scheduleFile requires the file format to exactly match the output bus format.
            // Stop the engine before reconnecting so the graph is in a clean state; a mono
            // AIFF scheduled against the stereo-defaulted startup connection produces silence.
            audioEngine.stop()
            // startRestorationForTrack owns the scout for a track load, so don't fire a
            // second one from here.
            applyRestorationEngagement(restorationNodes(for: entry), scoutIfNewlyOn: false)
            connectAudioGraph(format: file.processingFormat)
            try audioEngine.start()
            levelMeter.reinstallTap()
            startRestorationForTrack(entry)
            applyReplayGain(for: entry)

            // Pre-warm loudness analysis for the next track so it's cached before it starts.
            if let nextEntry = setlist.entry(after: entry.id) {
                preAnalyseIfNeeded(nextEntry)
            }

            // Auto-gap: schedule silence before the file if needed.
            // preparedAutoGap is pre-populated by the background analysis from the previous track's loadEntry.
            currentPaddingFrames = 0
            silencePending = false
            audioStartSampleTime = 0
            let isFirstTrack = setlist.entries.first?.id == entry.id
                && !setlist.entries.contains(where: { $0.state == .played })
            var autoGapApplied = false
            let autoGapIgnored = entry.autoGapIgnored(isFirstTrack: isFirstTrack,
                                                      ignoreFirstTrack: settings.autoGapIgnoreFirstTrack)
            // A manual stop already created the gap; don't add a second one on the next start.
            let skipForManualStop = settings.autoGapSkipAfterManualStop && manualStopPending
            if !bypassAutoGap && !skipForManualStop && !autoGapIgnored && settings.autoGapEnabled {
                // Use the analysis prepared for this exact (outgoing, incoming) pair.
                // currentEntryID still holds the outgoing track here (set to the new
                // entry below). A stale/mismatched pair → nil → conservative full target.
                let padding = preparedAutoGap?.injectedDuration(
                    currentID: currentEntryID ?? entry.id,
                    nextID: entry.id,
                    target: settings.autoGapDuration
                ) ?? settings.autoGapDuration
                if padding > 0 {
                    let frames = AVAudioFrameCount(padding * file.fileFormat.sampleRate)
                    silencePending = true
                    let entryID = entry.id
                    playerNode.scheduleBuffer(
                        makeSilenceBuffer(format: file.processingFormat, frameCount: frames),
                        completionCallbackType: .dataConsumed
                    ) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self,
                                  let nodeTime = self.playerNode.lastRenderTime,
                                  nodeTime.isSampleTimeValid,
                                  let pt = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
                            self.audioStartSampleTime = pt.sampleTime
                            self.silencePending = false
                            self.setlist.setAutoGapApplied(id: entryID, applied: false)
                        }
                    }
                    currentPaddingFrames = frames
                    autoGapApplied = true
                }
            }
            setlist.setAutoGapApplied(id: entry.id, applied: autoGapApplied)
            preparedAutoGap = nil
            manualStopPending = false

            if entry.trimStartSeconds != nil || entry.trimEndSeconds != nil {
                // Trim: play only [start, end]. Repeat re-loads this entry, so it re-schedules
                // from startF; duration stays full-file so waveform/progress map to absolute time.
                let sr = file.fileFormat.sampleRate
                let startF = AVAudioFramePosition(max(0, (entry.trimStartSeconds ?? 0)) * sr)
                let endF = AVAudioFramePosition(min(duration, entry.trimEndSeconds ?? duration) * sr)
                seekOffset = Double(startF) / sr
                elapsed = seekOffset
                let count = AVAudioFrameCount(max(0, endF - startF))
                playerNode.scheduleSegment(file, startingFrame: startF, frameCount: count,
                                           at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async { self?.handleTrackEnd(generation: gen) }
                }
            } else {
                playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async { self?.handleTrackEnd(generation: gen) }
                }
            }

            // Pre-warm silence analysis for the next automatic transition, bound to the
            // exact (current, next) pair. Analyze firstUnplayed(after:) — the real
            // transition target — not the immediate neighbour, which may be played.
            autoGapAnalysisTask?.cancel()
            let currentID = entry.id
            let next = setlist.firstUnplayed(after: entry.id)
            let currentURL = entry.fileURL
            let nextURL = next?.fileURL
            let nextID = next?.id
            // Trim clamps: silence past a trimmed end / before a trimmed start never plays,
            // so it must not be credited against the auto-gap target (else the gap collapses).
            let outTrimEnd = entry.trimEndSeconds
            let outDuration = entry.duration
            let inTrimStart = next?.trimStartSeconds
            autoGapAnalysisTask = Task { [weak self] in
                let cur = await AudioSilenceAnalyzer.shared.analyze(url: currentURL)
                guard !Task.isCancelled else { return }
                let lead: Double
                if let nextURL {
                    lead = await AudioSilenceAnalyzer.shared.analyze(url: nextURL).silenceAtStart
                } else {
                    lead = 0
                }
                guard !Task.isCancelled, let nextID else { return }
                // Effective trailing silence at the trim point: last `silenceAtEnd` of a
                // `dur`-long file, trimmed to end at `e`. nil duration → conservatively 0.
                var effTrailing = cur.silenceAtEnd
                if let e = outTrimEnd {
                    effTrailing = outDuration.map { max(0, cur.silenceAtEnd - ($0 - e)) } ?? 0
                }
                // Effective leading silence after skipping a trimmed start `s`.
                let effLeading = inTrimStart.map { max(0, lead - $0) } ?? lead
                await MainActor.run { [weak self] in
                    guard let self,
                          self.currentEntryID == currentID,
                          self.setlist.firstUnplayed(after: currentID)?.id == nextID else { return }
                    self.preparedAutoGap = PreparedAutoGap(
                        currentID: currentID,
                        nextID: nextID,
                        trailing: effTrailing,
                        leading: effLeading
                    )
                }
            }
        } catch {
            os_log(.error, "TangoDisplay: failed to load %{public}@: %{public}@",
                   entry.fileURL.path, error.localizedDescription)
            audioFile = nil
        }
        currentEntryID = entry.id
        setlist.markPlaying(id: entry.id)
        let resolvedConfigID = entry.pluginConfigurationID ?? configStore.defaultConfigurationID
        if let configID = resolvedConfigID, let config = configStore.configuration(id: configID) {
            if preConfigSnapshot == nil {
                preConfigSnapshot = PreConfigSnapshot(
                    chainEnabled: settings.audioUnitPluginEnabled,
                    chainBypassed: settings.audioUnitPluginBypassed,
                    slotStates: captureChainConfiguration()
                )
            }
            if !settings.audioUnitPluginEnabled { enableAudioUnitPlugin() }
            applyChainConfiguration(config)
        } else if let snapshot = preConfigSnapshot {
            restorePreConfigSnapshot(snapshot)
            preConfigSnapshot = nil
        }
        reportCurrentState()
        reportPlaylist()
        onNextTrackUpdate?(setlist.entry(after: entry.id)?.track)
    }

    private func handleTrackEnd(generation: Int) {
        guard generation == scheduleGeneration else { return }
        skipNext()
    }

    private func makeSilenceBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
        // AVAudioPCMBuffer is zero-initialized, so this is already silent.
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buf.frameLength = frameCount
        return buf
    }

    private func currentEntryIsPlayed() -> Bool {
        guard let id = currentEntryID else { return false }
        return setlist.entries.first(where: { $0.id == id })?.state == .played
    }

    // MARK: - Private: audio graph

    private func liveChainUnits() -> [(slot: AudioUnitChainSlot, unit: AVAudioUnit)] {
        guard settings.audioUnitPluginEnabled, !settings.audioUnitPluginBypassed else { return [] }
        return settings.audioUnitPluginChain.compactMap { slot in
            guard slot.isEnabled,
                  let runtime = slotRuntimes[slot.id],
                  let unit = runtime.avUnit else { return nil }
            return (slot, unit)
        }
    }

    // MARK: - Plugin chain configuration capture / apply

    func captureChainConfiguration() -> [PluginSlotState] {
        settings.audioUnitPluginChain.compactMap { slot in
            guard let runtime = slotRuntimes[slot.id],
                  let unit = runtime.avUnit,
                  let fullState = unit.auAudioUnit.fullState,
                  let encoded = try? AUStateCodec.encode(fullState)
            else { return nil }
            return PluginSlotState(
                slotID: slot.id,
                componentSubType: slot.selection.componentSubType,
                auState: encoded,
                isEnabled: slot.isEnabled
            )
        }
    }

    func applyChainConfiguration(_ config: PluginChainConfiguration) {
        for slotState in config.slotStates {
            guard let runtime = slotRuntimes[slotState.slotID],
                  let unit = runtime.avUnit else { continue }
            applySlotState(slotState, to: unit, runtime: runtime)
            setSlotEnabled(id: slotState.slotID, enabled: slotState.isEnabled)
        }
    }

    private func restorePreConfigSnapshot(_ snapshot: PreConfigSnapshot) {
        for slotState in snapshot.slotStates {
            guard let runtime = slotRuntimes[slotState.slotID],
                  let unit = runtime.avUnit else { continue }
            applySlotState(slotState, to: unit, runtime: runtime)
            setSlotEnabled(id: slotState.slotID, enabled: slotState.isEnabled)
        }
        if snapshot.chainBypassed != settings.audioUnitPluginBypassed {
            bypassAudioUnitPlugin(snapshot.chainBypassed)
        }
        if snapshot.chainEnabled != settings.audioUnitPluginEnabled {
            if snapshot.chainEnabled { enableAudioUnitPlugin() } else { disableAudioUnitPlugin() }
        }
    }

    private func applySlotState(_ slotState: PluginSlotState, to unit: AVAudioUnit, runtime: SlotRuntime) {
        guard let fullState = try? AUStateCodec.decode(slotState.auState) else { return }
        runtime.isApplyingPreset = true
        unit.auAudioUnit.fullState = fullState
        runtime.activePresetID = nil
        slotActivePresetIDs.removeValue(forKey: slotState.slotID)
        updateSlotPresetName(slotId: slotState.slotID, name: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak runtime] in
            runtime?.isApplyingPreset = false
        }
    }

    private func connectAudioGraph(format: AVAudioFormat?) {
        audioEngine.disconnectNodeOutput(playerNode)
        if let unit = declickUnit { audioEngine.disconnectNodeOutput(unit) }
        if let unit = dehumUnit { audioEngine.disconnectNodeOutput(unit) }
        audioEngine.disconnectNodeOutput(eq)
        audioEngine.disconnectNodeOutput(replayGainMixer)
        for runtime in slotRuntimes.values {
            if let unit = runtime.avUnit {
                audioEngine.disconnectNodeOutput(unit)
            }
        }
        audioEngine.disconnectNodeOutput(balanceMixer)

        // Shellac restoration first: repair the record before shaping it. Wired with the
        // file's own format, mono included — declick works on mono, unlike the Airwindows
        // declicker it derives from. Both nodes stay in the graph whether or not they are
        // engaged: engagement is expressed as bypass (see applyRestorationEngagement), which
        // costs an atomic store instead of the engine restart a rewire would need. The price
        // is declick's ~20 ms of latency and a little DSP on every track.
        var preEQ: AVAudioNode = playerNode
        if let unit = declickUnit {
            audioEngine.connect(preEQ, to: unit, format: format)
            preEQ = unit
        }
        if let unit = dehumUnit {
            audioEngine.connect(preEQ, to: unit, format: format)
            preEQ = unit
        }
        audioEngine.connect(preEQ, to: eq, format: format)
        audioEngine.connect(eq, to: replayGainMixer, format: format)

        // AU plugins often don't support mono. Upmix to stereo here so replayGainMixer
        // (AVAudioMixerNode) does the channel conversion before the plugin chain sees any data.
        let pluginFormat: AVAudioFormat? = {
            guard let fmt = format, fmt.channelCount < 2 else { return format }
            return AVAudioFormat(standardFormatWithSampleRate: fmt.sampleRate, channels: 2)
        }()

        var prev: AVAudioNode = replayGainMixer
        var failedSlots: [(id: UUID, reason: String)] = []
        for (slot, unit) in liveChainUnits() {
            if let fmt = pluginFormat {
                do {
                    try unit.auAudioUnit.inputBusses[0].setFormat(fmt)
                } catch {
                    os_log(.error, "TangoDisplay: plugin '%{public}@' rejected format; disabling: %{public}@",
                           slot.selection.name, error.localizedDescription)
                    failedSlots.append((id: slot.id, reason: error.localizedDescription))
                    continue
                }
            }
            var connectReason: NSString?
            if TDTryAudioEngineConnect(audioEngine, prev, unit, pluginFormat, &connectReason) {
                prev = unit
            } else {
                let msg = (connectReason as String?) ?? "NSException during connect"
                os_log(.error, "TangoDisplay: plugin '%{public}@' connect threw exception; disabling: %{public}@",
                       slot.selection.name, msg)
                failedSlots.append((id: slot.id, reason: msg))
            }
        }
        for (id, reason) in failedSlots {
            markSlotFailed(id: id, reason: reason)
        }
        audioEngine.connect(prev, to: balanceMixer, format: pluginFormat)
        audioEngine.connect(balanceMixer, to: audioEngine.mainMixerNode, format: pluginFormat)
    }

    private func rewireGraphSafely() {
        let wasPlaying = isActivePlaying
        let savedElapsed = elapsed
        let format = audioFile?.processingFormat

        playerNode.stop()
        audioEngine.stop()
        connectAudioGraph(format: format)

        // If a plugin in the live chain breaks engine startup (e.g. format incompatibility),
        // drop slots from the end of the live chain one at a time and retry until it starts
        // — this preserves the working portion of the chain.
        while true {
            do {
                try audioEngine.start()
                break
            } catch {
                let live = liveChainUnits()
                guard let last = live.last else {
                    os_log(.error, "TangoDisplay: engine start failed with no live plugins: %{public}@",
                           error.localizedDescription)
                    try? audioEngine.start()
                    break
                }
                os_log(.error, "TangoDisplay: engine start failed; disabling slot %{public}@: %{public}@",
                       last.slot.selection.name, error.localizedDescription)
                markSlotFailed(id: last.slot.id, reason: error.localizedDescription)
                audioEngine.stop()
                connectAudioGraph(format: format)
            }
        }

        levelMeter.reinstallTap()
        applyBalance(_balance)
        if audioFile != nil {
            seekTo(savedElapsed)
            if wasPlaying { playerNode.play() }
        }
        recomputeChainStatus()
    }

    private func markSlotFailed(id: UUID, reason: String) {
        guard let runtime = slotRuntimes[id] else { return }
        let name = settings.audioUnitPluginChain.first(where: { $0.id == id })?.selection.name ?? ""
        runtime.status = .failed(name, reason: reason)
        slotStatuses[id] = runtime.status
        if let unit = runtime.avUnit {
            audioEngine.disconnectNodeOutput(unit)
            audioEngine.detach(unit)
        }
        teardownSlotObservers(runtime)
        runtime.avUnit = nil
    }

    // MARK: - Audio Unit chain actions

    /// Append a plugin to the chain. No-op if the chain is already at the max.
    @discardableResult
    func addPluginSlot(_ selection: AudioUnitPluginSelection) -> UUID? {
        guard settings.audioUnitPluginChain.count < AudioUnitChainSlot.maxSlots else { return nil }
        let slot = AudioUnitChainSlot(selection: selection, isEnabled: true)
        settings.audioUnitPluginChain.append(slot)
        slotRuntimes[slot.id] = SlotRuntime()
        slotStatuses[slot.id] = .loading(selection.name)
        if settings.audioUnitPluginEnabled {
            startSlotLoad(slot)
        } else {
            slotStatuses[slot.id] = .disabled
        }
        recomputeChainStatus()
        return slot.id
    }

    /// Replace what's loaded in an existing slot. Preserves the slot's id and position.
    func replacePluginSlot(id: UUID, with selection: AudioUnitPluginSelection) {
        guard let index = settings.audioUnitPluginChain.firstIndex(where: { $0.id == id }) else { return }
        tearDownSlot(id: id, detachAVUnit: true)
        var updated = settings.audioUnitPluginChain[index]
        updated.selection = selection
        updated.lastUsedPresetName = nil
        settings.audioUnitPluginChain[index] = updated
        slotRuntimes[id] = SlotRuntime()
        if settings.audioUnitPluginEnabled {
            startSlotLoad(updated)
        } else {
            slotStatuses[id] = .disabled
        }
        rewireGraphSafely()
    }

    func removePluginSlot(id: UUID) {
        tearDownSlot(id: id, detachAVUnit: true)
        slotRuntimes.removeValue(forKey: id)
        slotStatuses.removeValue(forKey: id)
        slotPresets.removeValue(forKey: id)
        slotActivePresetIDs.removeValue(forKey: id)
        settings.audioUnitPluginChain.removeAll { $0.id == id }
        rewireGraphSafely()
    }

    func moveSlot(from source: Int, to destination: Int) {
        var chain = settings.audioUnitPluginChain
        guard source >= 0, source < chain.count,
              destination >= 0, destination <= chain.count,
              source != destination else { return }
        let item = chain.remove(at: source)
        let target = destination > source ? destination - 1 : destination
        chain.insert(item, at: min(target, chain.count))
        settings.audioUnitPluginChain = chain
        rewireGraphSafely()
    }

    func setSlotEnabled(id: UUID, enabled: Bool) {
        guard let index = settings.audioUnitPluginChain.firstIndex(where: { $0.id == id }) else { return }
        settings.audioUnitPluginChain[index].isEnabled = enabled
        rewireGraphSafely()
        recomputeChainStatus()
    }

    func enableAudioUnitPlugin() {
        settings.audioUnitPluginEnabled = true
        // Kick off any slots that didn't load yet.
        for slot in settings.audioUnitPluginChain where slotRuntimes[slot.id]?.avUnit == nil {
            startSlotLoad(slot)
        }
        rewireGraphSafely()
    }

    func disableAudioUnitPlugin() {
        settings.audioUnitPluginEnabled = false
        rewireGraphSafely()
        recomputeChainStatus()
    }

    func bypassAudioUnitPlugin(_ bypassed: Bool) {
        settings.audioUnitPluginBypassed = bypassed
        rewireGraphSafely()
        recomputeChainStatus()
    }

    func openPluginWindow(slotId: UUID) {
        guard let runtime = slotRuntimes[slotId], let avUnit = runtime.avUnit else { return }
        if let existing = runtime.pluginWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let title = settings.audioUnitPluginChain.first(where: { $0.id == slotId })?.selection.name ?? "Plugin"
        avUnit.auAudioUnit.requestViewController { [weak self] viewController in
            DispatchQueue.main.async {
                guard let self, let runtime = self.slotRuntimes[slotId] else { return }
                guard let vc = viewController else {
                    runtime.status = .failed(title, reason: "Plugin editor unavailable")
                    self.slotStatuses[slotId] = runtime.status
                    self.recomputeChainStatus()
                    return
                }
                let wrapper = PluginWindowViewController(pluginVC: vc, player: self, slotId: slotId)
                // Force loadView/viewDidLoad so wrapper.view is sized.
                _ = wrapper.view
                let initialSize: NSSize = wrapper.view.frame.size != .zero
                    ? wrapper.view.frame.size
                    : NSSize(width: 600, height: 400)

                let window = NSWindow(
                    contentRect: NSRect(origin: .zero, size: initialSize),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable],
                    backing: .buffered,
                    defer: false
                )
                window.title = title
                // Each plugin window stays standalone — never auto-merged into a
                // tab group (which would also disable the resize handle). A
                // unique tabbingIdentifier means even if macOS tries to group,
                // there's no other window it could group with.
                window.tabbingMode = .disallowed
                window.tabbingIdentifier = "tangodisplay.plugin.\(slotId.uuidString)"
                window.isRestorable = false
                // Bypass `contentViewController = wrapper` deliberately: that
                // setter binds the window's content size to the VC's
                // preferredContentSize, which silently overrides manual resize
                // and our own setContentSize calls. Setting contentView
                // directly keeps the window freely resizable. We then hold the
                // wrapper VC strongly in SlotRuntime since the window doesn't.
                window.contentView = wrapper.view
                window.contentMinSize = NSSize(width: 200, height: 100)
                window.contentMaxSize = NSSize(width: 4096, height: 4096)
                window.isReleasedWhenClosed = false
                window.center()
                window.makeKeyAndOrderFront(nil)
                // Defensive: if macOS somehow grouped us anyway, break out.
                if window.tabGroup != nil {
                    window.moveTabToNewWindow(nil)
                }
                runtime.pluginWindow = window
                runtime.pluginWindowVC = wrapper
            }
        }
    }

    func closePluginWindow(slotId: UUID) {
        slotRuntimes[slotId]?.pluginWindow?.close()
        slotRuntimes[slotId]?.pluginWindow = nil
        slotRuntimes[slotId]?.pluginWindowVC = nil
    }

    // MARK: - Presets (per slot)

    func applyPreset(_ preset: AudioUnitPreset, toSlot slotId: UUID) {
        guard let runtime = slotRuntimes[slotId],
              let avUnit = runtime.avUnit,
              let manager = runtime.presetManager else { return }
        runtime.isApplyingPreset = true
        do {
            try manager.applyPreset(preset, to: avUnit, originator: runtime.paramObserverToken)
            runtime.activePresetID = preset.id
            slotActivePresetIDs[slotId] = preset.id
            updateSlotPresetName(slotId: slotId, name: preset.name)
        } catch {
            os_log(.error, "TangoDisplay: applyPreset failed: %{public}@", error.localizedDescription)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak runtime] in
            runtime?.isApplyingPreset = false
        }
    }

    func saveCurrentAsPreset(named name: String, forSlot slotId: UUID) throws {
        guard let runtime = slotRuntimes[slotId],
              let avUnit = runtime.avUnit,
              let manager = runtime.presetManager else { return }
        let preset = try manager.savePreset(name: name, from: avUnit)
        let all = manager.factoryPresets(for: avUnit) + manager.userPresets()
        runtime.availablePresets = all
        runtime.activePresetID = preset.id
        slotPresets[slotId] = all
        slotActivePresetIDs[slotId] = preset.id
        updateSlotPresetName(slotId: slotId, name: preset.name)
    }

    func deletePreset(_ preset: AudioUnitPreset, fromSlot slotId: UUID) throws {
        guard let runtime = slotRuntimes[slotId],
              let avUnit = runtime.avUnit,
              let manager = runtime.presetManager else { return }
        try manager.deletePreset(preset)
        let all = manager.factoryPresets(for: avUnit) + manager.userPresets()
        runtime.availablePresets = all
        slotPresets[slotId] = all
        if runtime.activePresetID == preset.id {
            runtime.activePresetID = nil
            slotActivePresetIDs.removeValue(forKey: slotId)
            updateSlotPresetName(slotId: slotId, name: nil)
        }
    }

    private func updateSlotPresetName(slotId: UUID, name: String?) {
        guard let index = settings.audioUnitPluginChain.firstIndex(where: { $0.id == slotId }) else { return }
        settings.audioUnitPluginChain[index].lastUsedPresetName = name
    }

    // MARK: - Private: chain internals

    private func initializePluginStatus() {
        guard !settings.audioUnitPluginChain.isEmpty else {
            audioUnitPluginStatus = .noPluginSelected
            return
        }
        for slot in settings.audioUnitPluginChain {
            if slotRuntimes[slot.id] == nil {
                slotRuntimes[slot.id] = SlotRuntime()
            }
            if !settings.audioUnitPluginEnabled {
                slotStatuses[slot.id] = .disabled
                continue
            }
            if slotRuntimes[slot.id]?.avUnit != nil { continue }
            if pluginManager.isAvailable(slot.selection) {
                startSlotLoad(slot)
            } else {
                slotStatuses[slot.id] = .unavailable(slot.selection.name)
            }
        }
        recomputeChainStatus()
    }

    private func startSlotLoad(_ slot: AudioUnitChainSlot) {
        let runtime = slotRuntimes[slot.id] ?? SlotRuntime()
        slotRuntimes[slot.id] = runtime
        runtime.loadTask?.cancel()
        runtime.loadGeneration += 1
        let gen = runtime.loadGeneration
        let slotId = slot.id
        let selection = slot.selection
        runtime.status = .loading(selection.name)
        slotStatuses[slotId] = runtime.status
        recomputeChainStatus()

        runtime.loadTask = Task { [weak self, weak runtime] in
            guard let self else { return }
            do {
                let avUnit = try await pluginManager.instantiate(selection)
                await MainActor.run { [weak self, weak runtime] in
                    guard let self, let runtime,
                          runtime.loadGeneration == gen,
                          self.settings.audioUnitPluginChain.contains(where: { $0.id == slotId })
                    else { return }
                    self.audioEngine.attach(avUnit)
                    runtime.avUnit = avUnit
                    runtime.status = .active(selection.name)
                    self.slotStatuses[slotId] = runtime.status

                    let manager = AudioUnitPresetManager(for: selection)
                    runtime.presetManager = manager
                    let all = manager.factoryPresets(for: avUnit) + manager.userPresets()
                    runtime.availablePresets = all
                    self.slotPresets[slotId] = all

                    self.installSlotObservers(slotId: slotId, runtime: runtime, avUnit: avUnit)

                    // Apply the track's assigned configuration (or default), falling back to last-used preset.
                    var appliedConfig = false
                    if let entryID = self.currentEntryID,
                       let entry = self.setlist.entries.first(where: { $0.id == entryID }) {
                        let resolvedID = entry.pluginConfigurationID ?? self.configStore.defaultConfigurationID
                        if let configID = resolvedID,
                           let config = self.configStore.configuration(id: configID),
                           let slotState = config.slotStates.first(where: { $0.slotID == slotId }) {
                            self.applySlotState(slotState, to: avUnit, runtime: runtime)
                            appliedConfig = true
                        }
                    }

                    if !appliedConfig {
                        // Restore last-used preset for this slot.
                        let savedName = self.settings.audioUnitPluginChain
                            .first(where: { $0.id == slotId })?.lastUsedPresetName
                        if let savedName, let match = all.first(where: { $0.name == savedName }) {
                            runtime.isApplyingPreset = true
                            try? manager.applyPreset(match, to: avUnit, originator: runtime.paramObserverToken)
                            runtime.activePresetID = match.id
                            self.slotActivePresetIDs[slotId] = match.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak runtime] in
                                runtime?.isApplyingPreset = false
                            }
                        }
                    }

                    self.rewireGraphSafely()
                }
            } catch {
                await MainActor.run { [weak self, weak runtime] in
                    guard let self, let runtime, runtime.loadGeneration == gen else { return }
                    runtime.status = .failed(selection.name, reason: error.localizedDescription)
                    self.slotStatuses[slotId] = runtime.status
                    self.recomputeChainStatus()
                }
            }
        }
    }

    private func installSlotObservers(slotId: UUID, runtime: SlotRuntime, avUnit: AVAudioUnit) {
        if let tree = avUnit.auAudioUnit.parameterTree {
            runtime.paramObserverTree = tree
            runtime.paramObserverToken = tree.token(byAddingParameterObserver: { [weak self, weak runtime] _, _ in
                DispatchQueue.main.async {
                    guard let self, let runtime, !runtime.isApplyingPreset else { return }
                    runtime.activePresetID = nil
                    self.slotActivePresetIDs.removeValue(forKey: slotId)
                    self.updateSlotPresetName(slotId: slotId, name: nil)
                }
            })
        }
        // KVO on currentPreset catches V2 AU UIs (e.g. AUGraphicEQ "Flat") that bypass the parameter tree.
        runtime.currentPresetObservation = avUnit.auAudioUnit.observe(\.currentPreset, options: [.new]) {
            [weak self, weak runtime] _, _ in
            DispatchQueue.main.async {
                guard let self, let runtime, !runtime.isApplyingPreset else { return }
                runtime.activePresetID = nil
                self.slotActivePresetIDs.removeValue(forKey: slotId)
                self.updateSlotPresetName(slotId: slotId, name: nil)
            }
        }
    }

    private func teardownSlotObservers(_ runtime: SlotRuntime) {
        if let tree = runtime.paramObserverTree, let token = runtime.paramObserverToken {
            tree.removeParameterObserver(token)
        }
        runtime.paramObserverTree = nil
        runtime.paramObserverToken = nil
        runtime.currentPresetObservation = nil
    }

    private func tearDownSlot(id: UUID, detachAVUnit: Bool) {
        guard let runtime = slotRuntimes[id] else { return }
        runtime.loadTask?.cancel()
        runtime.loadTask = nil
        runtime.pluginWindow?.close()
        runtime.pluginWindow = nil
        runtime.pluginWindowVC = nil
        teardownSlotObservers(runtime)
        if detachAVUnit, let unit = runtime.avUnit {
            audioEngine.disconnectNodeOutput(unit)
            audioEngine.detach(unit)
        }
        runtime.avUnit = nil
        runtime.presetManager = nil
        runtime.availablePresets = []
        runtime.activePresetID = nil
        slotPresets.removeValue(forKey: id)
        slotActivePresetIDs.removeValue(forKey: id)
    }

    private func recomputeChainStatus() {
        let chain = settings.audioUnitPluginChain
        guard !chain.isEmpty else {
            audioUnitPluginStatus = .noPluginSelected
            return
        }
        if !settings.audioUnitPluginEnabled {
            audioUnitPluginStatus = .disabled
            return
        }
        // Surface a failure if any slot is broken.
        if let failed = chain.compactMap({ slot -> (String, String)? in
            if case .failed(let n, let r) = slotStatuses[slot.id] ?? .noPluginSelected {
                return (n, r)
            }
            return nil
        }).first {
            audioUnitPluginStatus = .failed(failed.0, reason: failed.1)
            return
        }
        if settings.audioUnitPluginBypassed {
            audioUnitPluginStatus = .bypassed(chainSummaryName(chain))
            return
        }
        // Loading wins over active so the UI shows progress.
        if chain.contains(where: { if case .loading = slotStatuses[$0.id] ?? .noPluginSelected { return true } else { return false } }) {
            audioUnitPluginStatus = .loading(chainSummaryName(chain))
            return
        }
        audioUnitPluginStatus = .active(chainSummaryName(chain))
    }

    private func chainSummaryName(_ chain: [AudioUnitChainSlot]) -> String {
        if chain.count == 1 { return chain[0].selection.name }
        return "\(chain.count) plugins"
    }

    // MARK: - Private: observers

    private func setupObservers() {
        timeObserverTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateTime() }

        settings.$builtInOutputDeviceUID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uid in self?.applyOutputDevice(uid) }
            .store(in: &cancellables)

        settings.$builtInHogMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                let uid = self.settings.builtInOutputDeviceUID
                self.isChangingDevice = true
                self.audioDeviceQueue.async {
                    self.applyHogMode(enabled: enabled, deviceUID: uid)
                    DispatchQueue.main.async { self.isChangingDevice = false }
                }
            }
            .store(in: &cancellables)

        settings.$eqBand0Gain.sink { [weak self] v in self?.eq.bands[0].gain = v }.store(in: &cancellables)
        settings.$eqBand1Gain.sink { [weak self] v in self?.eq.bands[1].gain = v }.store(in: &cancellables)
        settings.$eqBand2Gain.sink { [weak self] v in self?.eq.bands[2].gain = v }.store(in: &cancellables)
        settings.$eqBand3Gain.sink { [weak self] v in self?.eq.bands[3].gain = v }.store(in: &cancellables)
        settings.$eqBand4Gain.sink { [weak self] v in self?.eq.bands[4].gain = v }.store(in: &cancellables)

        settings.$builtInBalance
            .dropFirst()
            .sink { [weak self] v in self?.balance = v }
            .store(in: &cancellables)

        // Parameter moves are written straight through, and engagement toggles bypass —
        // neither touches the graph, so restoration never interrupts playback.
        settings.$restoration
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] r in
                guard let self else { return }
                self.applyRestorationParams(r)
                let entry = self.currentEntryID.flatMap { id in
                    self.setlist.entries.first { $0.id == id }
                }
                let wanted = self.restorationNodes(for: entry)
                if wanted != self.activeRestoration {
                    self.applyRestorationEngagement(wanted)
                }
            }
            .store(in: &cancellables)

        // receive(on: DispatchQueue.main) defers the sink to the next run-loop cycle so that
        // the @Published property (which fires in willSet) is fully committed before we read it.
        settings.$replayGainMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyReplayGainIfLoaded() }
            .store(in: &cancellables)
        settings.$replayGainPreampDb
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyReplayGainIfLoaded() }
            .store(in: &cancellables)
        settings.$replayGainPreventClipping
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyReplayGainIfLoaded() }
            .store(in: &cancellables)
        settings.$replayGainTargetLufs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyReplayGainIfLoaded() }
            .store(in: &cancellables)
        settings.$cortinaVolumeReductionDb
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyReplayGainIfLoaded() }
            .store(in: &cancellables)

        setlist.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                guard let self else { return }
                // Remove early-mark for entries removed from setlist or explicitly unmarked as played.
                let playedIDs = Set(entries.filter { $0.state == .played }.map(\.id))
                self.earlyMarkedEntryIDs.formIntersection(playedIDs)
                // Per-track restoration override on the track that is already playing:
                // act only when engagement actually changed, so ordinary setlist edits
                // don't touch the units.
                if let id = self.currentEntryID {
                    let wanted = self.restorationNodes(for: entries.first { $0.id == id })
                    if wanted != self.activeRestoration {
                        self.applyRestorationEngagement(wanted)
                    }
                }
                if let id = self.currentEntryID, !self.earlyMarkedEntryIDs.contains(id) {
                    self.isCurrentEntryMarkedAsPlayed = false
                }
                if let id = self.currentEntryID,
                   !entries.contains(where: { $0.id == id }) {
                    self.currentEntryID = nil
                    self.isActivePlaying = false
                    self.replayGainStatus = ""
                    self.playerNode.stop()
                    self.audioFile = nil
                    self.elapsed = 0
                    self.duration = 0
                    self.seekOffset = 0
                    self.reportCurrentState()
                    self.reportPlaylist()
                    self.onNextTrackUpdate?(nil)
                }
                if let id = self.currentEntryID, self.audioFile == nil,
                   let entry = entries.first(where: { $0.id == id }),
                   let d = entry.duration, d != self.duration {
                    self.duration = d
                }
                if let id = self.currentEntryID, self.audioFile == nil, !self.isActivePlaying,
                   entries.first(where: { $0.id == id })?.state == .played {
                    if let next = self.setlist.firstUnplayed(after: id) {
                        self.currentEntryID = next.id
                        self.elapsed = 0
                        self.duration = next.duration ?? 0
                        self.reportCurrentState()
                        self.reportPlaylist()
                        self.onNextTrackUpdate?(self.setlist.entry(after: next.id)?.track)
                    } else {
                        self.currentEntryID = nil
                        self.elapsed = 0
                        self.duration = 0
                        self.reportCurrentState()
                        self.reportPlaylist()
                        self.onNextTrackUpdate?(nil)
                    }
                }
                if self.currentEntryID == nil, self.audioFile == nil,
                   let firstQueued = entries.first(where: { $0.state == .queued }) {
                    self.currentEntryID = firstQueued.id
                    self.elapsed = 0
                    self.duration = firstQueued.duration ?? 0
                    self.reportCurrentState()
                    self.reportPlaylist()
                    self.onNextTrackUpdate?(self.setlist.entry(after: firstQueued.id)?.track)
                }
                // A reorder may have inserted a queued track before our queued-but-not-yet-loaded
                // current entry. Promote the new first-queued entry to be the current one.
                if let id = self.currentEntryID, self.audioFile == nil, !self.isActivePlaying,
                   entries.first(where: { $0.id == id })?.state == .queued,
                   let firstQueued = entries.first(where: { $0.state == .queued }),
                   firstQueued.id != id {
                    self.currentEntryID = firstQueued.id
                    self.elapsed = 0
                    self.duration = firstQueued.duration ?? 0
                    self.reportCurrentState()
                    self.reportPlaylist()
                    self.onNextTrackUpdate?(self.setlist.entry(after: firstQueued.id)?.track)
                }
                // Always report so AppState recalculates tanda position on any entries
                // change, including pure reorders that don't trigger any branch above.
                self.reportPlaylist()
            }
            .store(in: &cancellables)
    }

    private func teardownObservers() {
        timeObserverTimer = nil
        cancellables.removeAll()
    }

    // MARK: - Private: time update

    private func updateTime() {
        guard isActivePlaying,
              let file = audioFile,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }

        guard !silencePending else { elapsed = 0; return }
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else { return }
        let audioFrames = max(0, playerTime.sampleTime - audioStartSampleTime)
        let newElapsed = seekOffset + Double(audioFrames) / sampleRate
        elapsed = max(0, min(newElapsed, duration))
        duration = Double(file.length) / sampleRate

        if !settings.markAsPlayedAfterCompletion,
           let id = currentEntryID,
           !earlyMarkedEntryIDs.contains(id),
           duration > 0,
           elapsed >= Double(settings.markAsPlayedAfterSeconds) {
            earlyMarkedEntryIDs.insert(id)
            isCurrentEntryMarkedAsPlayed = true
            setlist.markPlayed(id: id)
            reportPlaylist()
        }
    }

    // MARK: - Private: state reporting

    private func reportCurrentState() {
        guard let id = currentEntryID,
              let entry = setlist.entries.first(where: { $0.id == id })
        else {
            isActivePlaying = false
            onTrackUpdate?(nil, .stopped)
            return
        }
        let state: PlayerState = isActivePlaying ? .playing : .paused
        onTrackUpdate?(entry.track, state)
    }

    private func reportPlaylist() {
        let entries = setlist.entries
        guard !entries.isEmpty else { onPlaylistUpdate(nil); return }
        let tracks = entries.map { $0.track }
        let idx = entries.firstIndex(where: { $0.id == currentEntryID }) ?? 0
        onPlaylistUpdate((tracks: tracks, currentIndex: idx))
    }
}
