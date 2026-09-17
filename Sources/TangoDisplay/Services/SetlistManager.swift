import AppKit
import AVFoundation
import AudioToolbox
import Combine
import Foundation
import iTunesLibrary
import os.log
import TangoDisplayCore

enum SetlistEntryState: String, Codable {
    case queued, playing, paused, played
}

enum TagColor: String, Codable, CaseIterable {
    case none, red, orange, yellow, green, blue, purple
}

struct SetlistEntry: Identifiable, Codable {
    let id: UUID
    let fileURL: URL
    var track: Track
    var state: SetlistEntryState
    var duration: TimeInterval?
    var autoGapOverride: Bool? = nil   // nil = follow global rule; true = force skip; false = force apply
    var ignoresAutoFade: Bool = false
    var isLastTanda: Bool = false      // marks this cortina as the last-tanda trigger
    var isPerformance: Bool = false    // track is part of a guest performance
    var repeatTrack: Bool = false      // non-dance track loops until stop-after or un-marked
    var pluginConfigurationID: UUID? = nil
    var tagColor: TagColor = .none
    var trimStartSeconds: Double? = nil   // nil = play from file start
    var trimEndSeconds: Double? = nil      // nil = play to file end
    var restorationOverride: Bool? = nil   // nil = follow global rule; true = force skip; false = force apply
    var upcomingOverride: UpcomingOverride? = nil  // cortina only: DJ-edited "Coming Up" details for the next tanda
    var autoGapApplied: Bool = false   // transient: true while auto-gap preroll is scheduled before this track

    enum CodingKeys: String, CodingKey {
        case id, fileURL, track, state, duration, autoGapOverride, ignoresAutoFade, isLastTanda, isPerformance, repeatTrack, pluginConfigurationID, tagColor, trimStartSeconds, trimEndSeconds, restorationOverride, upcomingOverride
        // autoGapApplied is intentionally excluded — reset each playback session
    }

    // Legacy one-directional flag (pre-tri-state); read for migration only.
    private enum LegacyKeys: String, CodingKey { case ignoresAutoGap }

    // Effective "gap skipped before this track". Assumes auto-gap is globally enabled.
    func autoGapIgnored(isFirstTrack: Bool, ignoreFirstTrack: Bool) -> Bool {
        autoGapOverride ?? (ignoreFirstTrack && isFirstTrack)
    }

    /// Effective "restore this track". `globalDefault` already folds in the master
    /// switch and the cortina rule; an explicit override outranks both.
    func restorationApplied(globalDefault: Bool) -> Bool {
        if let o = restorationOverride { return !o }
        return globalDefault
    }

    init(id: UUID = UUID(), fileURL: URL, track: Track, state: SetlistEntryState = .queued) {
        self.id = id
        self.fileURL = fileURL
        self.track = track
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fileURL = try c.decode(URL.self, forKey: .fileURL)
        track = try c.decode(Track.self, forKey: .track)
        state = try c.decode(SetlistEntryState.self, forKey: .state)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        if let o = try c.decodeIfPresent(Bool.self, forKey: .autoGapOverride) {
            autoGapOverride = o
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            autoGapOverride = (try legacy.decodeIfPresent(Bool.self, forKey: .ignoresAutoGap) == true) ? true : nil
        }
        ignoresAutoFade = try c.decodeIfPresent(Bool.self, forKey: .ignoresAutoFade) ?? false
        isLastTanda = try c.decodeIfPresent(Bool.self, forKey: .isLastTanda) ?? false
        isPerformance = try c.decodeIfPresent(Bool.self, forKey: .isPerformance) ?? false
        repeatTrack = try c.decodeIfPresent(Bool.self, forKey: .repeatTrack) ?? false
        pluginConfigurationID = try c.decodeIfPresent(UUID.self, forKey: .pluginConfigurationID) ?? nil
        tagColor = try c.decodeIfPresent(TagColor.self, forKey: .tagColor) ?? .none
        trimStartSeconds = try c.decodeIfPresent(Double.self, forKey: .trimStartSeconds)
        trimEndSeconds = try c.decodeIfPresent(Double.self, forKey: .trimEndSeconds)
        restorationOverride = try c.decodeIfPresent(Bool.self, forKey: .restorationOverride)
        upcomingOverride = try c.decodeIfPresent(UpcomingOverride.self, forKey: .upcomingOverride)
        autoGapApplied = false
    }
}

enum DuplicateSessionDecision { case alwaysAdd, neverAdd }

final class SetlistManager: ObservableObject {
    @Published private(set) var entries: [SetlistEntry] = []
    @Published var stopAfterEntryID: UUID?
    private(set) var duplicateSessionDecision: DuplicateSessionDecision? = nil

    func setDuplicateSessionDecision(_ decision: DuplicateSessionDecision?) {
        duplicateSessionDecision = decision
    }

    var totalPlaylistDuration: TimeInterval {
        entries.compactMap { $0.duration }.reduce(0, +)
    }

    private let saveURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("TangoDisplay")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("setlist.json")
    }()

    init() { load() }

    // MARK: - Queue mutations (all called on main)

    func addURLs(_ urls: [URL]) {
        insertURLs(urls, before: nil)
    }

    // anchorID is the UUID of the entry to insert before; nil means append to end.
    // Capturing a UUID (rather than an Int) prevents stale-index bugs when the
    // list mutates during the async metadata read.
    func insertURLs(_ urls: [URL], before anchorID: UUID?, importMusicTimes: Bool = false,
                    musicIDs: MusicDragIDs = MusicDragIDs()) {
        let audioURLs = urls.filter { isAudioURL($0) }
        guard !audioURLs.isEmpty else { return }
        // Insert with a filename placeholder first so the row appears instantly;
        // the async metadata read below fills real tags. Reading metadata before
        // inserting made drags look like they failed, prompting a re-drag that then
        // hit a spurious duplicate warning.
        let placeholders = audioURLs.map { url in
            SetlistEntry(fileURL: url,
                         track: Track(title: url.deletingPathExtension().lastPathComponent,
                                      artist: "", genre: "", persistentID: url.path))
        }
        insert(placeholders, before: anchorID)   // already calls save() + loadMissingDurations()
        for p in placeholders {
            let id = p.id, url = p.fileURL
            // Only tracks that came from a Music drag carry a persistent ID, and only they
            // get trim imported. Nothing here touches the main thread or Music itself.
            let musicID = importMusicTimes ? musicIDs.persistentID(for: url) : nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                let track = await SetlistManager.readMetadata(from: url)
                // Trim from Music's per-track start/stop (Song Info → Options). Normally
                // instant — draggingEntered started the scan about a second ago.
                var trim: (start: Double?, end: Double?)? = nil
                if let musicID { trim = await SetlistManager.musicTrimAsync(id: musicID) }
                guard let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
                self.entries[i].track = track
                if let trim {
                    self.entries[i].trimStartSeconds = trim.start
                    self.entries[i].trimEndSeconds = trim.end
                }
                self.save()
            }
        }
    }

    func insert(_ newEntries: [SetlistEntry], before anchorID: UUID?) {
        let index = anchorID
            .flatMap { id in entries.firstIndex(where: { $0.id == id }) }
            ?? entries.count
        entries.insert(contentsOf: newEntries, at: index)
        save()
        loadMissingDurations()
    }

    func remove(at offsets: IndexSet) {
        if let stopID = stopAfterEntryID, offsets.map({ entries[$0].id }).contains(stopID) {
            stopAfterEntryID = nil
        }
        entries.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        // Filter out played/playing entries — they cannot be reordered.
        // Using filter (not reject) handles the case where a playing track is
        // selected alongside queued tracks and SwiftUI includes all selected
        // indices in the drag source.
        let movable = IndexSet(source.filter {
            let s = entries[$0].state
            return s == .queued || s == .paused
        })
        guard !movable.isEmpty else { return }
        entries.move(fromOffsets: movable, toOffset: destination)
        save()
    }

    func clear() {
        stopAfterEntryID = nil
        duplicateSessionDecision = nil
        entries.removeAll()
        save()
    }

    // MARK: - Playback state tracking

    func markPlaying(id: UUID) {
        for i in entries.indices {
            if entries[i].id == id {
                entries[i].state = .playing
            } else if entries[i].state == .playing || entries[i].state == .paused {
                entries[i].state = .played
            }
        }
        save()
    }

    func markPaused(id: UUID) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].state = .paused
            save()
        }
    }

    func markQueued(id: UUID) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].state = .queued
            save()
        }
    }

    func markPlayed(id: UUID) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].state = .played
            save()
        }
    }

    func markPlayed(ids: Set<UUID>) {
        for i in entries.indices where ids.contains(entries[i].id) {
            entries[i].state = .played
        }
        save()
    }

    func markUnplayed(ids: Set<UUID>) {
        for i in entries.indices where ids.contains(entries[i].id) {
            entries[i].state = .queued
        }
        save()
    }

    func setAutoGapOverride(id: UUID, ignore: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].autoGapOverride = ignore
        save()
    }

    /// `skip` of nil clears the override and returns the track to the global rule.
    func setRestorationOverride(id: UUID, skip: Bool?) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].restorationOverride = skip
        save()
    }

    func toggleIgnoresAutoFade(id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].ignoresAutoFade.toggle()
        save()
    }

    func setIsLastTanda(id: UUID, value: Bool) {
        for i in entries.indices { entries[i].isLastTanda = false }
        if value, let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].isLastTanda = true
        }
        save()
    }

    func setPerformance(_ value: Bool, for ids: Set<UUID>) {
        for i in entries.indices where ids.contains(entries[i].id) {
            entries[i].isPerformance = value
        }
        save()
    }

    func setRepeat(_ value: Bool, for id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].repeatTrack = value
        // stop-after and repeat are mutually exclusive on the same entry
        if value && stopAfterEntryID == id { stopAfterEntryID = nil }
        save()
    }

    func setTrim(start: Double?, end: Double?, for id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].trimStartSeconds = start
        entries[i].trimEndSeconds = end
        save()
    }

    func clearTrim(for id: UUID) { setTrim(start: nil, end: nil, for: id) }

    func setUpcomingOverride(_ o: UpcomingOverride?, for id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].upcomingOverride = (o?.isEmpty ?? true) ? nil : o
        save()
    }

    func setPluginConfiguration(_ configID: UUID?, for ids: Set<UUID>) {
        for id in ids {
            guard let i = entries.firstIndex(where: { $0.id == id }) else { continue }
            entries[i].pluginConfigurationID = configID
        }
        save()
    }

    func setTagColor(_ color: TagColor, for ids: Set<UUID>) {
        for i in entries.indices where ids.contains(entries[i].id) {
            entries[i].tagColor = color
        }
        save()
    }

    func setAutoGapApplied(id: UUID, applied: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].autoGapApplied = applied
    }

    func remove(ids: Set<UUID>) {
        if let stopID = stopAfterEntryID, ids.contains(stopID) {
            stopAfterEntryID = nil
        }
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func entry(after id: UUID) -> SetlistEntry? {
        guard let i = entries.firstIndex(where: { $0.id == id }), i + 1 < entries.count else { return nil }
        return entries[i + 1]
    }

    func firstUnplayed(after id: UUID) -> SetlistEntry? {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries[(i + 1)...].first(where: { $0.state != .played })
    }

    func entry(before id: UUID) -> SetlistEntry? {
        guard let i = entries.firstIndex(where: { $0.id == id }), i > 0 else { return nil }
        return entries[i - 1]
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              var decoded = try? JSONDecoder().decode([SetlistEntry].self, from: data) else { return }
        decoded = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        for i in decoded.indices where decoded[i].state == .playing || decoded[i].state == .paused {
            decoded[i].state = .queued
        }
        entries = decoded
        loadMissingDurations()
        if !UserDefaults.standard.bool(forKey: "setlistGroupingMigrationV1") {
            loadMissingGroupings()
        }
    }

    private func loadMissingGroupings() {
        let ids = entries.filter { $0.track.grouping == nil }.map { $0.id }
        guard !ids.isEmpty else {
            UserDefaults.standard.set(true, forKey: "setlistGroupingMigrationV1")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for id in ids {
                guard let idx = self.entries.firstIndex(where: { $0.id == id }) else { continue }
                let url  = self.entries[idx].fileURL
                let meta = await SetlistManager.readMetadata(from: url)
                guard let grouping = meta.grouping else { continue }
                guard let i = self.entries.firstIndex(where: { $0.id == id }) else { continue }
                let old = self.entries[i].track
                self.entries[i].track = Track(
                    title: old.title, artist: old.artist, genre: old.genre,
                    persistentID: old.persistentID, year: old.year,
                    comment: old.comment, albumArtist: old.albumArtist,
                    grouping: grouping, replayGainInfo: old.replayGainInfo)
            }
            UserDefaults.standard.set(true, forKey: "setlistGroupingMigrationV1")
            self.save()
        }
    }

    private func loadMissingDurations() {
        let needsLoad = entries.filter { $0.duration == nil }.map { $0.id }
        for id in needsLoad {
            Task {
                guard let idx = self.entries.firstIndex(where: { $0.id == id }) else { return }
                let url = self.entries[idx].fileURL
                let asset = AVURLAsset(url: url)
                guard let cmDuration = try? await asset.load(.duration) else { return }
                let seconds = CMTimeGetSeconds(cmDuration)
                guard seconds.isFinite && seconds > 0 else { return }
                await MainActor.run {
                    guard let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
                    self.entries[i].duration = seconds
                    self.save()
                }
            }
        }
    }

    // MARK: - Metadata reading

    static func readMetadata(from url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.metadata)) ?? []

        // Treat empty strings the same as missing: return nil so the ?? chain keeps searching.
        func string(for id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id).first else { return nil }
            guard let val = try? await item.load(.stringValue), !val.isEmpty else { return nil }
            return val
        }

        // Raw-key scan for formats (FLAC/Vorbis) where AVFoundation has no typed identifier,
        // also catches stray tags where identifier mapping fails.
        func string(forRawKey rawKey: String) async -> String? {
            guard let item = metadata.first(where: { ($0.key as? String)?.lowercased() == rawKey.lowercased() }) else { return nil }
            guard let val = try? await item.load(.stringValue), !val.isEmpty else { return nil }
            return val
        }

        // Old iTunes (v4.x era) M4A files store itsk keys as packed NSNumber 4-char codes rather
        // than NSString, so filteredByIdentifier misses them. Match by packed int32 value instead.
        // Uses unicodeScalars (not utf8) so that multi-byte UTF-8 chars like © (U+00A9 = 0xA9)
        // are treated as a single byte — matching the 4-char atom code convention.
        func string(forITunesAtom atomCode: String) async -> String? {
            let scalars = Array(atomCode.unicodeScalars)
            guard scalars.count == 4 else { return nil }
            let bytes = scalars.map { UInt8($0.value & 0xFF) }
            let packed = Int32(bitPattern: (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3]))
            guard let item = metadata.first(where: { ($0.key as? NSNumber)?.int32Value == packed && $0.keySpace == .iTunes }) else { return nil }
            guard let val = try? await item.load(.stringValue), !val.isEmpty else { return nil }
            return val
        }

        // Skips Apple machine-generated COMM frames (iTunNORM, iTunSMPB, iTunPGAP, etc.) that
        // store binary data as hex strings — AVFoundation returns all COMM frames and .first may
        // land on one of these instead of the human-readable comment.
        func humanReadableComment() async -> String? {
            let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .id3MetadataComments)
            for item in items {
                let info = (try? await item.load(.extraAttributes))?[AVMetadataExtraAttributeKey.info] as? String ?? ""
                guard !info.hasPrefix("iTun") else { continue }
                if let val = try? await item.load(.stringValue), !val.isEmpty { return val }
            }
            return nil
        }

        // Resolves raw ID3 TCON values that encode genre as a number rather than text.
        // Handles "(N)", "(N)Text", and plain "N" forms; passes real text through unchanged.
        func resolveID3Genre(_ raw: String?) -> String? {
            guard let raw, !raw.isEmpty else { return nil }
            if raw.hasPrefix("("), let close = raw.firstIndex(of: ")") {
                let numStr = String(raw[raw.index(after: raw.startIndex)..<close])
                let text = String(raw[raw.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return text }
                if let n = Int(numStr), n >= 0, n < id3GenreNames.count { return id3GenreNames[n] }
            }
            if let n = Int(raw), n >= 0, n < id3GenreNames.count { return id3GenreNames[n] }
            return raw
        }

        // M4A predefined genre: `gnre` atom stores an integer (ID3v1 index + 1).
        // Music.app uses this when the user picks from its genre dropdown rather than typing.
        func predefinedGenreName() async -> String? {
            guard let item = AVMetadataItem.metadataItems(
                from: metadata, filteredByIdentifier: .iTunesMetadataPredefinedGenre).first
            else { return nil }
            if let str = try? await item.load(.stringValue), !str.isEmpty { return str }
            guard let n = (try? await item.load(.numberValue))?.intValue, n > 0, n <= id3GenreNames.count
            else { return nil }
            return id3GenreNames[n - 1]
        }

        let title = await string(for: .commonIdentifierTitle)
            ?? url.deletingPathExtension().lastPathComponent
        let artistFromAVF = await string(for: .commonIdentifierArtist)
        let artist = artistFromAVF
            ?? SetlistManager.iTunesLibrary[SetlistManager.iTunesMediaRelativeKey(url.path)]?.artist
            ?? ""
        // Genre: search across all common tagging conventions; falls back to iTunes Library.xml
        // for tracks whose genre lives only in Music.app's library and was never embedded in the file.
        // Empty values are treated as absent so a stale empty tag doesn't block the next lookup.
        // (await cannot appear inside ?? autoclosures, so each lookup is a separate binding.)
        let genreID3        = resolveID3Genre(await string(for: .id3MetadataContentType)) // MP3: TCON frame (resolved)
        let genreiTunes     = await string(for: .iTunesMetadataUserGenre)                  // M4A: ©gen text atom
        let genrePredefined = await predefinedGenreName()                                  // M4A: gnre integer atom (Music.app dropdown)
        let genreVorbis     = await string(forRawKey: "genre")                             // FLAC/Vorbis comment
        let genreRawTcon    = resolveID3Genre(await string(forRawKey: "tcon"))             // raw ID3 key fallback (resolved)
        let genreEmbedded = genreID3 ?? genreiTunes ?? genrePredefined ?? genreVorbis ?? genreRawTcon
        let genre = genreEmbedded
            ?? SetlistManager.genreFromAudioToolbox(url)
            ?? SetlistManager.iTunesLibrary[SetlistManager.iTunesMediaRelativeKey(url.path)]?.genre
            ?? ""

        let yearFromTYER    = (await string(for: .id3MetadataYear)).flatMap { Int($0) }
        let yearFromiTunes  = (await string(for: .iTunesMetadataReleaseDate)).flatMap { Int(String($0.prefix(4))) }
        let yearFromRawTdrc = (await string(forRawKey: "tdrc")).flatMap { Int(String($0.prefix(4))) }
        let year: Int?      = yearFromTYER ?? yearFromiTunes ?? yearFromRawTdrc
                           ?? SetlistManager.yearFromAudioToolbox(url)               // AIFF ID3v2.2 TYE frame
                           ?? SetlistManager.iTunesLibrary[SetlistManager.iTunesMediaRelativeKey(url.path)]?.year
        let commentFromID3    = await humanReadableComment()
        let commentFromiTunes = await string(for: .iTunesMetadataUserComment)
        let comment = commentFromID3 ?? commentFromiTunes
        let albumArtistFromID3       = await string(for: .id3MetadataBand)
        let albumArtistFromiTunes    = await string(for: .iTunesMetadataAlbumArtist)
        let albumArtistOldiTunes     = await string(forITunesAtom: "aART") // old M4A: NSNumber key
        let albumArtist = albumArtistFromID3 ?? albumArtistFromiTunes ?? albumArtistOldiTunes
        let groupingFromID3       = await string(for: .id3MetadataContentGroupDescription) // MP3: TIT1
        let groupingFromiTunes    = await string(for: .iTunesMetadataGrouping)             // modern M4A
        let groupingOldiTunes     = await string(forITunesAtom: "©grp")                   // old M4A: NSNumber key
        let groupingVorbis        = await string(forRawKey: "grouping")                    // FLAC/Vorbis
        let groupingRawTit1       = await string(forRawKey: "tit1")                        // raw ID3 fallback
        let grouping = groupingFromID3 ?? groupingFromiTunes ?? groupingOldiTunes ?? groupingVorbis ?? groupingRawTit1
            ?? SetlistManager.iTunesLibrary[SetlistManager.iTunesMediaRelativeKey(url.path)]?.grouping

        // ID3 TXXX frame lookup (MP3 ReplayGain). The description/tag-name lives in extraAttributes[.info].
        func txxx(key: String) async -> String? {
            let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .id3MetadataUserText)
            for item in items {
                let attrs = (try? await item.load(.extraAttributes)) ?? [:]
                guard (attrs[AVMetadataExtraAttributeKey.info] as? String)?.lowercased() == key.lowercased() else { continue }
                if let val = try? await item.load(.stringValue), !val.isEmpty { return val }
            }
            return nil
        }

        // ReplayGain: Vorbis comments (FLAC) via raw key, ID3 TXXX frames (MP3), M4A raw key fallback.
        // (await cannot appear inside ?? autoclosures, so each lookup is a separate binding.)
        let rgTrackGainVorbis = await string(forRawKey: "replaygain_track_gain")
        let rgTrackGainTxxx   = await txxx(key: "replaygain_track_gain")
        let rgTrackPeakVorbis = await string(forRawKey: "replaygain_track_peak")
        let rgTrackPeakTxxx   = await txxx(key: "replaygain_track_peak")
        let rgAlbumGainVorbis = await string(forRawKey: "replaygain_album_gain")
        let rgAlbumGainTxxx   = await txxx(key: "replaygain_album_gain")
        let rgAlbumPeakVorbis = await string(forRawKey: "replaygain_album_peak")
        let rgAlbumPeakTxxx   = await txxx(key: "replaygain_album_peak")
        let rgTrackGainStr = rgTrackGainVorbis ?? rgTrackGainTxxx
        let rgTrackPeakStr = rgTrackPeakVorbis ?? rgTrackPeakTxxx
        let rgAlbumGainStr = rgAlbumGainVorbis ?? rgAlbumGainTxxx
        let rgAlbumPeakStr = rgAlbumPeakVorbis ?? rgAlbumPeakTxxx
        let rgTrackGain = parseReplayGainDb(rgTrackGainStr)
        let rgTrackPeak = Double(rgTrackPeakStr?.trimmingCharacters(in: .whitespaces) ?? "")
        let rgAlbumGain = parseReplayGainDb(rgAlbumGainStr)
        let rgAlbumPeak = Double(rgAlbumPeakStr?.trimmingCharacters(in: .whitespaces) ?? "")
        let replayGainInfo: ReplayGainInfo? = (rgTrackGain != nil || rgTrackPeak != nil || rgAlbumGain != nil || rgAlbumPeak != nil)
            ? ReplayGainInfo(trackGainDb: rgTrackGain, trackPeak: rgTrackPeak,
                             albumGainDb: rgAlbumGain, albumPeak: rgAlbumPeak)
            : nil

        return Track(
            title: title,
            artist: artist,
            genre: genre,
            persistentID: url.absoluteString,
            year: year,
            comment: comment,
            albumArtist: albumArtist,
            grouping: grouping,
            replayGainInfo: replayGainInfo
        )
    }

    private struct iTunesLibraryEntry {
        let genre: String?
        let year: Int?
        let artist: String?
        let grouping: String?
    }

    // Lazy one-time parse of iTunes Library.xml → relative path key → track metadata.
    // Fallback for tracks whose genre/year/artist lives only in Music.app's library
    // and was never embedded in the file's tags.
    // Returns [:] silently if the XML is absent, unreadable, or malformed — no errors thrown.
    private static let iTunesLibrary: [String: iTunesLibraryEntry] = loadITunesLibrary()

    nonisolated static func musicTrimAsync(id: String) async -> (start: Double?, end: Double?) {
        await MusicTrimCache.shared.trim(forID: id)
    }

    // Rescans Music's start/stop table off the main thread. Called when a drag enters the
    // window — the only moment guaranteed to be after the user's edit in Music and roughly
    // a second before the drop — and once at launch, where it also triggers the Media
    // Library TCC prompt.
    nonisolated static func warmMusicTrims() {
        Task.detached(priority: .userInitiated) { await MusicTrimCache.shared.refresh() }
    }

    // Artist+title → genre lookup for players (e.g. MegaSeg) that expose no file path.
    // Parsed separately so the existing path-keyed lookup is unaffected.
    private static let iTunesGenreByArtistTitle: [String: String] = loadITunesGenreByArtistTitle()

    static func genre(forArtist artist: String, title: String) -> String? {
        iTunesGenreByArtistTitle[artistTitleLookupKey(artist, title)]
    }

    private static func artistTitleLookupKey(_ artist: String, _ title: String) -> String {
        let n: (String) -> String = { $0.decomposedStringWithCanonicalMapping.lowercased() }
        return "\(n(artist))\u{0}\(n(title))"
    }

    private static func loadITunesGenreByArtistTitle() -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Music/Music/iTunes/iTunes Library.xml"),
            home.appendingPathComponent("Music/iTunes/iTunes Library.xml"),
            home.appendingPathComponent("Music/Music/iTunes/iTunes Music Library.xml"),
        ]
        for xmlURL in candidates {
            guard let data = try? Data(contentsOf: xmlURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let root = plist as? [String: Any],
                  let tracks = root["Tracks"] as? [String: Any]
            else { continue }
            var result: [String: String] = [:]
            for (_, trackAny) in tracks {
                guard let track = trackAny as? [String: Any],
                      let title  = (track["Name"]   as? String).flatMap({ $0.isEmpty ? nil : $0 }),
                      let genre  = (track["Genre"]  as? String).flatMap({ $0.isEmpty ? nil : $0 })
                else { continue }
                let artist = (track["Artist"] as? String) ?? ""
                result[artistTitleLookupKey(artist, title)] = genre
            }
            return result
        }
        return [:]
    }

    private static func loadITunesLibrary() -> [String: iTunesLibraryEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Music/Music/iTunes/iTunes Library.xml"),
            home.appendingPathComponent("Music/iTunes/iTunes Library.xml"),
            home.appendingPathComponent("Music/Music/iTunes/iTunes Music Library.xml"),
        ]
        for xmlURL in candidates {
            guard let data = try? Data(contentsOf: xmlURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let root = plist as? [String: Any],
                  let tracks = root["Tracks"] as? [String: Any]
            else { continue }

            var result: [String: iTunesLibraryEntry] = [:]
            for (_, trackAny) in tracks {
                guard let track = trackAny as? [String: Any],
                      let location = track["Location"] as? String,
                      let fileURL = URL(string: location)
                else { continue }
                // Key by the path relative to "iTunes Media/" so this works even when
                // the library was migrated from a different user account (different home prefix).
                let genre    = (track["Genre"]    as? String).flatMap { $0.isEmpty ? nil : $0 }
                let year     = track["Year"] as? Int
                let artist   = (track["Artist"]   as? String).flatMap { $0.isEmpty ? nil : $0 }
                let grouping = (track["Grouping"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                guard genre != nil || year != nil || artist != nil || grouping != nil else { continue }
                result[iTunesMediaRelativeKey(fileURL.path)] = iTunesLibraryEntry(genre: genre, year: year, artist: artist, grouping: grouping)
            }
            return result
        }
        return [:]
    }

    // Returns the substring after the last occurrence of "/iTunes Media/" (lowercased, NFD-normalised),
    // or the full lowercased path if that marker is absent.
    private static func iTunesMediaRelativeKey(_ path: String) -> String {
        let normalised = path.decomposedStringWithCanonicalMapping.lowercased()
        if let range = normalised.range(of: "/itunes media/", options: .backwards) {
            return String(normalised[range.upperBound...])
        }
        return normalised
    }

    private static func genreFromAudioToolbox(_ url: URL) -> String? {
        var audioFile: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFile) == noErr,
              let af = audioFile else { return nil }
        defer { AudioFileClose(af) }

        var dataSize = UInt32(MemoryLayout<CFDictionary>.size)
        var cfDictRef: Unmanaged<CFDictionary>? = nil
        guard AudioFileGetProperty(af, kAudioFilePropertyInfoDictionary, &dataSize, &cfDictRef) == noErr,
              let info = cfDictRef?.takeRetainedValue() as? [String: Any],
              let genre = info[kAFInfoDictionary_Genre as String] as? String,
              !genre.isEmpty else { return nil }
        return genre
    }

    private static func yearFromAudioToolbox(_ url: URL) -> Int? {
        var audioFile: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFile) == noErr,
              let af = audioFile else { return nil }
        defer { AudioFileClose(af) }

        var dataSize = UInt32(MemoryLayout<CFDictionary>.size)
        var cfDictRef: Unmanaged<CFDictionary>? = nil
        guard AudioFileGetProperty(af, kAudioFilePropertyInfoDictionary, &dataSize, &cfDictRef) == noErr,
              let info = cfDictRef?.takeRetainedValue() as? [String: Any] else { return nil }
        if let s = info[kAFInfoDictionary_Year as String] as? String, !s.isEmpty,
           let y = Int(s.prefix(4)) { return y }
        if let s = info[kAFInfoDictionary_RecordedDate as String] as? String, !s.isEmpty,
           let y = Int(s.prefix(4)) { return y }
        return nil
    }
}

private func isAudioURL(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ["mp3", "m4a", "aiff", "aif", "wav", "flac", "caf", "opus"].contains(ext)
}

// Standard iTunes/ID3v1/Winamp genre list (192 entries).
// The M4A `gnre` atom stores (index + 1), so gnre=114 → index 113 → "Tango".
private let id3GenreNames: [String] = [
    "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge",
    "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B",
    "Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska",
    "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop",
    "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical", "Instrumental",
    "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise", "AlternRock",
    "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop",
    "Instrumental Rock", "Ethnic", "Gothic", "Darkwave", "Techno-Industrial",
    "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy",
    "Cult", "Gangsta", "Top 40", "Christian Rap", "Pop/Funk", "Jungle",
    "Native American", "Cabaret", "New Wave", "Psychedelic", "Rave", "Showtunes",
    "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro",
    "Musical", "Rock & Roll", "Hard Rock",
    // Winamp extensions (80+)
    "Folk", "Folk-Rock", "National Folk", "Swing", "Fast Fusion", "Bebop",
    "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde", "Gothic Rock",
    "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock",
    "Big Band", "Chorus", "Easy Listening", "Acoustic", "Humour", "Speech",
    "Chanson", "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass",
    "Primus", "Porn Groove", "Satire", "Slow Jam", "Club",
    "Tango",         // index 113
    "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle",
    "Duet", "Punk Rock", "Drum Solo", "A Cappella", "Euro-House", "Dance Hall",
    "Goa", "Drum & Bass", "Club-House", "Hardcore", "Terror", "Indie",
    "BritPop", "Negerpunk", "Polsk Punk", "Beat", "Christian Gangsta Rap",
    "Heavy Metal", "Black Metal", "Crossover", "Contemporary Christian",
    "Christian Rock", "Merengue", "Salsa", "Thrash Metal", "Anime", "JPop",
    "Synthpop",
]

private let trimLog = OSLog(subsystem: "com.tangodisplay", category: "musicdrop")

// Music's per-track start/stop (Song Info → Options), keyed by Music's persistent ID.
// Read via the iTunesLibrary framework so it works without the deprecated "Share Library
// XML" preference. Times are milliseconds.
//
// Keyed by persistent ID, never by file path: on a 24k-track library, reading
// `item.location` for every track costs ~3.9s of a ~5.3s scan, while the persistent ID
// plus the three time fields costs ~45ms on top of the unavoidable ~1.35s
// `allMediaItems`. The IDs to look up come free off the drag pasteboard (`MusicDragIDs`).
//
// Rescanned explicitly via `refresh()` when a drag enters the window and at launch — never
// lazily inside `trim(forID:)`, so a drop never waits on a scan it started itself. Users
// edit start/stop in Music mid-session, so a once-per-session snapshot goes stale.
private actor MusicTrimCache {
    static let shared = MusicTrimCache()

    private let library = try? ITLibrary(apiVersion: "1.1")
    private var times: [String: (startMs: Int, stopMs: Int, totalMs: Int)] = [:]
    private var loadedAt: Date?

    // Actor isolation does the coordination: a lookup arriving mid-scan queues behind it
    // and gets the fresh answer.
    func trim(forID id: String) -> (start: Double?, end: Double?) {
        if loadedAt == nil { reload() }
        guard let t = times[id] else { return (nil, nil) }
        return musicTrimSeconds(startMs: t.startMs, stopMs: t.stopMs, totalMs: t.totalMs)
    }

    // Rescans unless the snapshot is newer than minAge, which coalesces the repeat
    // draggingEntered calls a single hover produces.
    func refresh(minAge: TimeInterval = 1) {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < minAge { return }
        reload()
    }

    private func reload() {
        let isFirstLoad = loadedAt == nil
        loadedAt = Date()
        guard let library else { return }
        let started = Date()
        if !isFirstLoad { library.reloadData() }   // the initial ITLibrary is already fresh
        var result: [String: (startMs: Int, stopMs: Int, totalMs: Int)] = [:]
        let items = library.allMediaItems
        result.reserveCapacity(items.count)
        for item in items {
            result[String(format: "%016llX", item.persistentID.uint64Value)] =
                (item.startTime, item.stopTime, item.totalTime)
        }
        times = result
        os_log("music trim scan: %d track(s) in %.0fms", log: trimLog, type: .info,
               result.count, Date().timeIntervalSince(started) * 1000)
    }
}
