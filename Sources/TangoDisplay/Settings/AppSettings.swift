import Foundation
import Combine
import CoreGraphics
import TangoDisplayCore

private let kPrefix = "TangoDisplay."

struct GenreColorRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var keyword: String
    var colorHex: String
}

enum StartupMode: String, CaseIterable, Identifiable {
    case fullExperience
    case playerFocused

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullExperience: return "Full Experience"
        case .playerFocused:  return "Player Focused"
        }
    }
}

/// All user-configurable settings, persisted to UserDefaults.
/// Arrays are stored as comma-joined strings to avoid UserDefaults type-registration issues.
final class AppSettings: ObservableObject {

    // MARK: - Display labels

    @Published var cortinaLabel: String {
        didSet { UserDefaults.standard.set(cortinaLabel, forKey: kPrefix + "cortinaLabel") }
    }
    @Published var nextUpLabel: String {
        didSet { UserDefaults.standard.set(nextUpLabel, forKey: kPrefix + "nextUpLabel") }
    }
    @Published var idleMessage: String {
        didSet { UserDefaults.standard.set(idleMessage, forKey: kPrefix + "idleMessage") }
    }
    @Published var lastTandaLabel: String {
        didSet { UserDefaults.standard.set(lastTandaLabel, forKey: kPrefix + "lastTandaLabel") }
    }

    // MARK: - Cortina rules

    @Published var useAllowlist: Bool {
        didSet { UserDefaults.standard.set(useAllowlist, forKey: kPrefix + "useAllowlist") }
    }
    @Published var allowlistGenres: [String] {
        didSet { AppSettings.saveGenreList(allowlistGenres, key: kPrefix + "allowlistGenres") }
    }
    @Published var useDenylist: Bool {
        didSet { UserDefaults.standard.set(useDenylist, forKey: kPrefix + "useDenylist") }
    }
    @Published var denylistGenres: [String] {
        didSet {
            AppSettings.saveGenreList(denylistGenres, key: kPrefix + "denylistGenres")
            // Prune entries no longer in the denylist
            denylistPartialMatchGenres = denylistPartialMatchGenres.filter {
                denylistGenres.contains($0)
            }
            denylistLabelOverrides = denylistLabelOverrides.filter {
                denylistGenres.contains($0.key)
            }
        }
    }
    @Published var denylistPartialMatchGenres: Set<String> {
        didSet {
            AppSettings.saveGenreList(Array(denylistPartialMatchGenres),
                                      key: kPrefix + "denylistPartialMatchGenres")
        }
    }
    @Published var denylistLabelOverrides: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(denylistLabelOverrides) {
                UserDefaults.standard.set(data, forKey: kPrefix + "denylistLabelOverrides")
            }
        }
    }

    // MARK: - Player source

    @Published var selectedPlayer: MusicPlayerChoice {
        didSet { UserDefaults.standard.set(selectedPlayer.rawValue, forKey: kPrefix + "selectedPlayer") }
    }

    @Published var jriverZoneID: Int {
        didSet { UserDefaults.standard.set(jriverZoneID, forKey: kPrefix + "jriverZoneID") }
    }

    @Published var builtInVolume: Float {
        didSet { UserDefaults.standard.set(builtInVolume, forKey: kPrefix + "builtInVolume") }
    }
    @Published var builtInBalance: Float {
        didSet { UserDefaults.standard.set(builtInBalance, forKey: kPrefix + "builtInBalance") }
    }

    @Published var builtInFadeDuration: Double {
        didSet { UserDefaults.standard.set(builtInFadeDuration, forKey: kPrefix + "builtInFadeDuration") }
    }

    @Published var builtInOutputDeviceUID: String {
        didSet { UserDefaults.standard.set(builtInOutputDeviceUID, forKey: kPrefix + "builtInOutputDeviceUID") }
    }

    @Published var builtInHogMode: Bool {
        didSet { UserDefaults.standard.set(builtInHogMode, forKey: kPrefix + "builtInHogMode") }
    }

    @Published var eqBand0Gain: Float {
        didSet { UserDefaults.standard.set(eqBand0Gain, forKey: kPrefix + "eqBand0Gain") }
    }
    @Published var eqBand1Gain: Float {
        didSet { UserDefaults.standard.set(eqBand1Gain, forKey: kPrefix + "eqBand1Gain") }
    }
    @Published var eqBand2Gain: Float {
        didSet { UserDefaults.standard.set(eqBand2Gain, forKey: kPrefix + "eqBand2Gain") }
    }
    @Published var eqBand3Gain: Float {
        didSet { UserDefaults.standard.set(eqBand3Gain, forKey: kPrefix + "eqBand3Gain") }
    }
    @Published var eqBand4Gain: Float {
        didSet { UserDefaults.standard.set(eqBand4Gain, forKey: kPrefix + "eqBand4Gain") }
    }

    var eqGains: [Float] { [eqBand0Gain, eqBand1Gain, eqBand2Gain, eqBand3Gain, eqBand4Gain] }

    @Published var replayGainMode: ReplayGainMode {
        didSet { UserDefaults.standard.set(replayGainMode.rawValue, forKey: kPrefix + "replayGainMode") }
    }
    @Published var replayGainPreampDb: Float {
        didSet { UserDefaults.standard.set(replayGainPreampDb, forKey: kPrefix + "replayGainPreampDb") }
    }
    @Published var replayGainPreventClipping: Bool {
        didSet { UserDefaults.standard.set(replayGainPreventClipping, forKey: kPrefix + "replayGainPreventClipping") }
    }
    @Published var replayGainTargetLufs: Float {
        didSet { UserDefaults.standard.set(replayGainTargetLufs, forKey: kPrefix + "replayGainTargetLufs") }
    }

    @Published var markAsPlayedAfterCompletion: Bool {
        didSet { UserDefaults.standard.set(markAsPlayedAfterCompletion, forKey: kPrefix + "markAsPlayedAfterCompletion") }
    }

    @Published var markAsPlayedAfterSeconds: Int {
        didSet { UserDefaults.standard.set(markAsPlayedAfterSeconds, forKey: kPrefix + "markAsPlayedAfterSeconds") }
    }

    @Published var autoGapEnabled: Bool {
        didSet { UserDefaults.standard.set(autoGapEnabled, forKey: kPrefix + "autoGapEnabled") }
    }

    @Published var autoGapDuration: Double {
        didSet { UserDefaults.standard.set(autoGapDuration, forKey: kPrefix + "autoGapDuration") }
    }

    @Published var autoGapIgnoreFirstTrack: Bool {
        didSet { UserDefaults.standard.set(autoGapIgnoreFirstTrack, forKey: kPrefix + "autoGapIgnoreFirstTrack") }
    }

    @Published var autoGapSkipAfterManualStop: Bool {
        didSet { UserDefaults.standard.set(autoGapSkipAfterManualStop, forKey: kPrefix + "autoGapSkipAfterManualStop") }
    }

    @Published var autoFadeCortinasEnabled: Bool {
        didSet { UserDefaults.standard.set(autoFadeCortinasEnabled, forKey: kPrefix + "autoFadeCortinasEnabled") }
    }

    @Published var cortinaPlayTime: Double {
        didSet { UserDefaults.standard.set(cortinaPlayTime, forKey: kPrefix + "cortinaPlayTime") }
    }

    @Published var cortinaVolumeReductionDb: Double {
        didSet { UserDefaults.standard.set(cortinaVolumeReductionDb, forKey: kPrefix + "cortinaVolumeReductionDb") }
    }

    // MARK: - Setlist Remote

    @Published var remoteControlEnabled: Bool {
        didSet { UserDefaults.standard.set(remoteControlEnabled, forKey: kPrefix + "remoteControlEnabled") }
    }

    /// Regenerated on every app launch — not persisted.
    @Published private(set) var remoteControlPin: String = ""

    func regenerateRemoteControlPin() {
        remoteControlPin = String(format: "%04d", Int.random(in: 0...9999))
    }

    // MARK: - Built-in player track info

    @Published var duplicateTrackProtection: Bool {
        didSet { UserDefaults.standard.set(duplicateTrackProtection, forKey: kPrefix + "duplicateTrackProtection") }
    }
    @Published var showYear: Bool {
        didSet { UserDefaults.standard.set(showYear, forKey: kPrefix + "showYear") }
    }
    @Published var showTime: Bool {
        didSet { UserDefaults.standard.set(showTime, forKey: kPrefix + "showTime") }
    }
    @Published var showComments: Bool {
        didSet { UserDefaults.standard.set(showComments, forKey: kPrefix + "showComments") }
    }
    @Published var showAlbumArtist: Bool {
        didSet { UserDefaults.standard.set(showAlbumArtist, forKey: kPrefix + "showAlbumArtist") }
    }
    @Published var showGrouping: Bool {
        didSet { UserDefaults.standard.set(showGrouping, forKey: kPrefix + "showGrouping") }
    }
    @Published var genreColorsEnabled: Bool {
        didSet { UserDefaults.standard.set(genreColorsEnabled, forKey: kPrefix + "genreColorsEnabled") }
    }
    @Published var genreColorRules: [GenreColorRule] {
        didSet {
            if let data = try? JSONEncoder().encode(genreColorRules) {
                UserDefaults.standard.set(data, forKey: kPrefix + "genreColorRules")
            }
        }
    }
    @Published var genreColorTitleEnabled: Bool {
        didSet { UserDefaults.standard.set(genreColorTitleEnabled, forKey: kPrefix + "genreColorTitleEnabled") }
    }

    // MARK: - Appearance / presentation

    @Published var activeProfileID: UUID? {
        didSet { UserDefaults.standard.set(activeProfileID?.uuidString,
                                           forKey: kPrefix + "activeProfileID") }
    }
    @Published var targetDisplayID: CGDirectDisplayID? {
        didSet { UserDefaults.standard.set(targetDisplayID.map { Int($0) },
                                           forKey: kPrefix + "targetDisplayID") }
    }
    @Published var mirrorMode: Bool {
        didSet { UserDefaults.standard.set(mirrorMode, forKey: kPrefix + "mirrorMode") }
    }
    @Published var showTrackCounter: Bool {
        didSet { UserDefaults.standard.set(showTrackCounter, forKey: kPrefix + "showTrackCounter") }
    }
    @Published var trackCounterPosition: TrackCounterPosition {
        didSet { UserDefaults.standard.set(trackCounterPosition.rawValue, forKey: kPrefix + "trackCounterPosition") }
    }
    @Published var showTdjName: Bool {
        didSet { UserDefaults.standard.set(showTdjName, forKey: kPrefix + "showTdjName") }
    }
    @Published var tdjName: String {
        didSet { UserDefaults.standard.set(tdjName, forKey: kPrefix + "tdjName") }
    }
    @Published var tdjNamePosition: TrackCounterPosition {
        didSet { UserDefaults.standard.set(tdjNamePosition.rawValue, forKey: kPrefix + "tdjNamePosition") }
    }
    @Published var tdjNameVisibility: TdjNameVisibility {
        didSet { UserDefaults.standard.set(tdjNameVisibility.rawValue, forKey: kPrefix + "tdjNameVisibility") }
    }

    // MARK: - Track info transformations

    @Published var trackTransforms: [String: TransformRule] {
        didSet {
            if let data = try? JSONEncoder().encode(trackTransforms) {
                UserDefaults.standard.set(data, forKey: kPrefix + "trackTransforms")
            }
        }
    }

    // MARK: - Audio Unit plugin

    @Published var audioUnitPluginEnabled: Bool {
        didSet { UserDefaults.standard.set(audioUnitPluginEnabled, forKey: kPrefix + "audioUnitPluginEnabled") }
    }
    @Published var audioUnitPluginBypassed: Bool {
        didSet { UserDefaults.standard.set(audioUnitPluginBypassed, forKey: kPrefix + "audioUnitPluginBypassed") }
    }
    @Published var audioUnitPluginChain: [AudioUnitChainSlot] {
        didSet {
            // Enforce the cap at the model boundary so any caller is safe.
            if audioUnitPluginChain.count > AudioUnitChainSlot.maxSlots {
                audioUnitPluginChain = Array(audioUnitPluginChain.prefix(AudioUnitChainSlot.maxSlots))
                return
            }
            if let data = try? JSONEncoder().encode(audioUnitPluginChain) {
                UserDefaults.standard.set(data, forKey: kPrefix + "audioUnitPluginChain")
            }
        }
    }

    // MARK: - Decibel meter

    @Published var decibelMeterEnabled: Bool {
        didSet { UserDefaults.standard.set(decibelMeterEnabled, forKey: kPrefix + "decibelMeterEnabled") }
    }
    @Published var decibelMeterLowThreshold: Int {
        didSet { UserDefaults.standard.set(decibelMeterLowThreshold, forKey: kPrefix + "decibelMeterLowThreshold") }
    }
    @Published var decibelMeterHighThreshold: Int {
        didSet { UserDefaults.standard.set(decibelMeterHighThreshold, forKey: kPrefix + "decibelMeterHighThreshold") }
    }

    @Published var hidePlayed: Bool {
        didSet { UserDefaults.standard.set(hidePlayed, forKey: kPrefix + "hidePlayed") }
    }

    // MARK: - Startup

    @Published var startupMode: StartupMode {
        didSet { UserDefaults.standard.set(startupMode.rawValue, forKey: kPrefix + "startupMode") }
    }
    @Published var hideLeftMenuBarOnStartup: Bool {
        didSet { UserDefaults.standard.set(hideLeftMenuBarOnStartup, forKey: kPrefix + "hideLeftMenuBarOnStartup") }
    }

    // MARK: - Performance mode

    @Published var stopAfterEachPerformanceTrack: Bool {
        didSet { UserDefaults.standard.set(stopAfterEachPerformanceTrack, forKey: kPrefix + "stopAfterEachPerformanceTrack") }
    }
    @Published var performanceBackgroundImageFilename: String? {
        didSet { UserDefaults.standard.set(performanceBackgroundImageFilename, forKey: kPrefix + "performanceBackgroundImageFilename") }
    }
    @Published var performanceBackgroundDuringCortina: Bool {
        didSet { UserDefaults.standard.set(performanceBackgroundDuringCortina, forKey: kPrefix + "performanceBackgroundDuringCortina") }
    }
    @Published var performanceTextLines: [PerformanceTextLine] {
        didSet {
            if let data = try? JSONEncoder().encode(performanceTextLines) {
                UserDefaults.standard.set(data, forKey: kPrefix + "performanceTextLines")
            }
        }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        cortinaLabel    = ud.string(forKey: kPrefix + "cortinaLabel")    ?? "CORTINA"
        nextUpLabel     = ud.string(forKey: kPrefix + "nextUpLabel")     ?? "COMING UP"
        idleMessage     = ud.string(forKey: kPrefix + "idleMessage")     ?? ""
        lastTandaLabel  = ud.string(forKey: kPrefix + "lastTandaLabel")  ?? ""
        useAllowlist  = ud.object(forKey: kPrefix + "useAllowlist")
                           .flatMap { $0 as? Bool } ?? true
        allowlistGenres = AppSettings.loadGenreList(
            ud, key: kPrefix + "allowlistGenres", default: ["Cortina"])
        useDenylist   = ud.object(forKey: kPrefix + "useDenylist")
                           .flatMap { $0 as? Bool } ?? true
        let loadedDenylist = AppSettings.loadGenreList(
            ud, key: kPrefix + "denylistGenres", default: ["Tango", "Vals", "Milonga"])
        denylistGenres = loadedDenylist
        if ud.object(forKey: kPrefix + "denylistPartialMatchGenres") != nil {
            denylistPartialMatchGenres = Set(AppSettings.loadGenreList(
                ud, key: kPrefix + "denylistPartialMatchGenres", default: []))
        } else {
            // First launch after update: enable partial match for all current denylist genres
            denylistPartialMatchGenres = Set(loadedDenylist)
        }
        if let data = ud.data(forKey: kPrefix + "denylistLabelOverrides"),
           let overrides = try? JSONDecoder().decode([String: String].self, from: data) {
            denylistLabelOverrides = overrides
        } else {
            denylistLabelOverrides = [:]
        }
        let rawPlayer = ud.string(forKey: kPrefix + "selectedPlayer") ?? ""
        selectedPlayer = MusicPlayerChoice(rawValue: rawPlayer) ?? .builtIn
        jriverZoneID = ud.object(forKey: kPrefix + "jriverZoneID").flatMap { $0 as? Int } ?? -1
        builtInVolume = ud.object(forKey: kPrefix + "builtInVolume").flatMap { $0 as? Float } ?? 1.0
        builtInBalance = ud.object(forKey: kPrefix + "builtInBalance").flatMap { $0 as? Float } ?? 0.0
        builtInFadeDuration = ud.object(forKey: kPrefix + "builtInFadeDuration").flatMap { $0 as? Double } ?? 5.0
        builtInOutputDeviceUID = ud.string(forKey: kPrefix + "builtInOutputDeviceUID") ?? ""
        builtInHogMode = ud.object(forKey: kPrefix + "builtInHogMode").flatMap { $0 as? Bool } ?? false
        eqBand0Gain = ud.object(forKey: kPrefix + "eqBand0Gain").flatMap { $0 as? Float } ?? 0.0
        eqBand1Gain = ud.object(forKey: kPrefix + "eqBand1Gain").flatMap { $0 as? Float } ?? 0.0
        eqBand2Gain = ud.object(forKey: kPrefix + "eqBand2Gain").flatMap { $0 as? Float } ?? 0.0
        eqBand3Gain = ud.object(forKey: kPrefix + "eqBand3Gain").flatMap { $0 as? Float } ?? 0.0
        eqBand4Gain = ud.object(forKey: kPrefix + "eqBand4Gain").flatMap { $0 as? Float } ?? 0.0
        let rawRGMode = ud.string(forKey: kPrefix + "replayGainMode") ?? ""
        replayGainMode = ReplayGainMode(rawValue: rawRGMode) ?? .off
        replayGainPreampDb = ud.object(forKey: kPrefix + "replayGainPreampDb").flatMap { $0 as? Float } ?? 0.0
        replayGainPreventClipping = ud.object(forKey: kPrefix + "replayGainPreventClipping").flatMap { $0 as? Bool } ?? true
        replayGainTargetLufs = ud.object(forKey: kPrefix + "replayGainTargetLufs").flatMap { $0 as? Float } ?? -18.0
        markAsPlayedAfterCompletion = ud.object(forKey: kPrefix + "markAsPlayedAfterCompletion")
            .flatMap { $0 as? Bool } ?? false
        let savedSeconds = ud.integer(forKey: kPrefix + "markAsPlayedAfterSeconds")
        markAsPlayedAfterSeconds = savedSeconds > 0 ? savedSeconds : 10
        autoGapEnabled = ud.object(forKey: kPrefix + "autoGapEnabled").flatMap { $0 as? Bool } ?? false
        autoGapDuration = ud.object(forKey: kPrefix + "autoGapDuration").flatMap { $0 as? Double } ?? 4.0
        autoGapIgnoreFirstTrack = ud.object(forKey: kPrefix + "autoGapIgnoreFirstTrack").flatMap { $0 as? Bool } ?? true
        autoGapSkipAfterManualStop = ud.object(forKey: kPrefix + "autoGapSkipAfterManualStop").flatMap { $0 as? Bool } ?? false
        autoFadeCortinasEnabled = ud.object(forKey: kPrefix + "autoFadeCortinasEnabled").flatMap { $0 as? Bool } ?? false
        cortinaPlayTime = ud.object(forKey: kPrefix + "cortinaPlayTime").flatMap { $0 as? Double } ?? 30.0
        cortinaVolumeReductionDb = ud.object(forKey: kPrefix + "cortinaVolumeReductionDb").flatMap { $0 as? Double } ?? 0.0
        remoteControlEnabled = ud.object(forKey: kPrefix + "remoteControlEnabled").flatMap { $0 as? Bool } ?? false
        remoteControlPin = String(format: "%04d", Int.random(in: 0...9999))
        duplicateTrackProtection = ud.object(forKey: kPrefix + "duplicateTrackProtection")
            .flatMap { $0 as? Bool } ?? false
        showYear = ud.object(forKey: kPrefix + "showYear").flatMap { $0 as? Bool } ?? true
        showTime = ud.object(forKey: kPrefix + "showTime").flatMap { $0 as? Bool } ?? true
        showComments = ud.object(forKey: kPrefix + "showComments").flatMap { $0 as? Bool } ?? false
        showAlbumArtist = ud.object(forKey: kPrefix + "showAlbumArtist").flatMap { $0 as? Bool } ?? false
        showGrouping = ud.object(forKey: kPrefix + "showGrouping").flatMap { $0 as? Bool } ?? false
        genreColorsEnabled = ud.object(forKey: kPrefix + "genreColorsEnabled").flatMap { $0 as? Bool } ?? false
        if let data = ud.data(forKey: kPrefix + "genreColorRules"),
           let rules = try? JSONDecoder().decode([GenreColorRule].self, from: data) {
            genreColorRules = rules
        } else {
            genreColorRules = []
        }
        genreColorTitleEnabled = ud.object(forKey: kPrefix + "genreColorTitleEnabled").flatMap { $0 as? Bool } ?? false
        if let idString = ud.string(forKey: kPrefix + "activeProfileID") {
            activeProfileID = UUID(uuidString: idString)
        } else {
            activeProfileID = AppearanceProfile.classic.id
        }
        if ud.object(forKey: kPrefix + "targetDisplayID") != nil {
            let raw = ud.integer(forKey: kPrefix + "targetDisplayID")
            targetDisplayID = CGDirectDisplayID(raw)
        } else {
            targetDisplayID = nil
        }
        mirrorMode = ud.object(forKey: kPrefix + "mirrorMode").flatMap { $0 as? Bool } ?? true
        showTrackCounter = ud.object(forKey: kPrefix + "showTrackCounter").flatMap { $0 as? Bool } ?? true
        let rawPos = ud.string(forKey: kPrefix + "trackCounterPosition") ?? ""
        trackCounterPosition = TrackCounterPosition(rawValue: rawPos) ?? .bottomRight
        showTdjName = ud.object(forKey: kPrefix + "showTdjName").flatMap { $0 as? Bool } ?? false
        tdjName = ud.string(forKey: kPrefix + "tdjName") ?? ""
        let rawTdjPos = ud.string(forKey: kPrefix + "tdjNamePosition") ?? ""
        tdjNamePosition = TrackCounterPosition(rawValue: rawTdjPos) ?? .bottomLeft
        let rawTdjVis = ud.string(forKey: kPrefix + "tdjNameVisibility") ?? ""
        tdjNameVisibility = TdjNameVisibility(rawValue: rawTdjVis) ?? .always
        if let data = ud.data(forKey: kPrefix + "trackTransforms") {
            if let rules = try? JSONDecoder().decode([String: TransformRule].self, from: data) {
                trackTransforms = rules
            } else {
                NSLog("[TangoDisplay] WARNING: trackTransforms decode failed — resetting to empty")
                trackTransforms = [:]
            }
        } else {
            trackTransforms = [:]
        }
        audioUnitPluginEnabled = ud.object(forKey: kPrefix + "audioUnitPluginEnabled").flatMap { $0 as? Bool } ?? false
        audioUnitPluginBypassed = ud.object(forKey: kPrefix + "audioUnitPluginBypassed").flatMap { $0 as? Bool } ?? false
        if let data = ud.data(forKey: kPrefix + "audioUnitPluginChain"),
           let chain = try? JSONDecoder().decode([AudioUnitChainSlot].self, from: data) {
            audioUnitPluginChain = Array(chain.prefix(AudioUnitChainSlot.maxSlots))
        } else if let data = ud.data(forKey: kPrefix + "selectedAudioUnitPlugin"),
                  let sel = try? JSONDecoder().decode(AudioUnitPluginSelection.self, from: data) {
            // Migrate the legacy single-plugin setting into a one-slot chain.
            let legacyPreset = ud.string(forKey: kPrefix + "lastUsedAUPresetName")
            let migrated = [AudioUnitChainSlot(
                selection: sel,
                isEnabled: true,
                lastUsedPresetName: legacyPreset
            )]
            audioUnitPluginChain = migrated
            // didSet does not fire from init — persist + clean legacy keys manually.
            if let migratedData = try? JSONEncoder().encode(migrated) {
                ud.set(migratedData, forKey: kPrefix + "audioUnitPluginChain")
            }
            ud.removeObject(forKey: kPrefix + "selectedAudioUnitPlugin")
            ud.removeObject(forKey: kPrefix + "lastUsedAUPresetName")
        } else {
            audioUnitPluginChain = []
        }
        decibelMeterEnabled = ud.object(forKey: kPrefix + "decibelMeterEnabled").flatMap { $0 as? Bool } ?? false
        decibelMeterLowThreshold  = ud.object(forKey: kPrefix + "decibelMeterLowThreshold").flatMap { $0 as? Int } ?? 60
        decibelMeterHighThreshold = ud.object(forKey: kPrefix + "decibelMeterHighThreshold").flatMap { $0 as? Int } ?? 80
        hidePlayed = ud.object(forKey: kPrefix + "hidePlayed").flatMap { $0 as? Bool } ?? false
        let rawStartup = ud.string(forKey: kPrefix + "startupMode") ?? ""
        startupMode = StartupMode(rawValue: rawStartup) ?? .fullExperience
        hideLeftMenuBarOnStartup = ud.object(forKey: kPrefix + "hideLeftMenuBarOnStartup")
            .flatMap { $0 as? Bool } ?? false
        stopAfterEachPerformanceTrack = ud.object(forKey: kPrefix + "stopAfterEachPerformanceTrack")
            .flatMap { $0 as? Bool } ?? true
        performanceBackgroundImageFilename = ud.string(forKey: kPrefix + "performanceBackgroundImageFilename")
        performanceBackgroundDuringCortina = ud.object(forKey: kPrefix + "performanceBackgroundDuringCortina")
            .flatMap { $0 as? Bool } ?? false
        if let data = ud.data(forKey: kPrefix + "performanceTextLines"),
           let lines = try? JSONDecoder().decode([PerformanceTextLine].self, from: data) {
            performanceTextLines = lines
        } else {
            performanceTextLines = []
        }
    }

    // MARK: - Helpers

    private static func parseGenres(_ raw: String?, default defaultValue: [String]) -> [String] {
        guard let raw, !raw.isEmpty else { return defaultValue }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func saveGenreList(_ list: [String], key: String) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // JSON array if present, else legacy comma-string (one-time migration).
    // Comma is a valid genre character, so comma-joined storage is ambiguous — JSON isn't.
    private static func loadGenreList(_ ud: UserDefaults, key: String, default def: [String]) -> [String] {
        if let data = ud.data(forKey: key),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr
        }
        return parseGenres(ud.string(forKey: key), default: def)
    }

    func displayLabel(for genre: String) -> String {
        let trimmed = genre.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        // Exact case-insensitive match
        if let match = denylistGenres.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }),
           let override = denylistLabelOverrides[match], !override.isEmpty {
            return override
        }

        // Partial (prefix) match — mirrors CortinaDetector's hasPrefix($0 + " ") logic
        if let match = denylistPartialMatchGenres.first(where: { lower.hasPrefix($0.lowercased() + " ") }),
           let override = denylistLabelOverrides[match], !override.isEmpty {
            return override
        }

        return trimmed
    }

    func transform(_ value: String, for field: TrackInfoField) -> String {
        guard let rule = trackTransforms[field.rawValue],
              rule.enabled, !rule.pattern.isEmpty else { return value }
        guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        let prepared = Self.encodeReplacementEscapes(rule.replacement)
        let result = regex.stringByReplacingMatches(in: value, range: range, withTemplate: prepared)
        let decoded = Self.restoreReplacementSentinels(result)
        return decoded.trimmingCharacters(in: .whitespaces).isEmpty ? value : decoded
    }

    // Substitute user-typed escapes with sentinel chars BEFORE the NSRegularExpression
    // template engine runs, so the engine doesn't consume the leading backslash.
    static func encodeReplacementEscapes(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\\", with: "\u{0000}")
            .replacingOccurrences(of: "\\n", with: "\u{0001}")
            .replacingOccurrences(of: "\\r", with: "\u{0002}")
            .replacingOccurrences(of: "\\t", with: "\u{0003}")
    }

    static func restoreReplacementSentinels(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{0000}", with: "\\")
            .replacingOccurrences(of: "\u{0001}", with: "\n")
            .replacingOccurrences(of: "\u{0002}", with: "\r")
            .replacingOccurrences(of: "\u{0003}", with: "\t")
    }

    func makeDetector() -> CortinaDetector {
        CortinaDetector(
            useAllowlist: useAllowlist,
            allowlistGenres: Set(allowlistGenres.map { $0.lowercased() }),
            useDenylist: useDenylist,
            denylistGenres: Set(denylistGenres.map { $0.lowercased() }),
            denylistPartialGenres: Set(denylistPartialMatchGenres.map { $0.lowercased() })
        )
    }
}
