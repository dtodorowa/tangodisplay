import Foundation
import iTunesLibrary
import TangoDisplayCore

/// One occurrence of a track in a playlist. `id` is the position, not the track, so a song
/// listed twice is two rows with two identities.
struct PrelistenRow: Identifiable, Hashable {
    let id: Int
    let persistentID: String
    let title: String
    let artist: String
    let album: String
    let composer: String
    let genre: String
    let year: Int?
    let comment: String?
    let grouping: String?
    let plays: Int
    let dateAdded: Date?
    let duration: Double
    /// False when the track has no file on this Mac (cloud-only, or a file that's gone missing).
    var isLocalFile: Bool
    /// nil until the location has been looked up, which happens after the rows show.
    var fileURL: URL?
    let trimStart: Double?
    let trimEnd: Double?

    var playDuration: Double { (trimEnd ?? duration) - (trimStart ?? 0) }
}

/// File locations of library tracks, each looked up at most once. Reading a track's location
/// from iTunesLibrary is a synchronous round trip to Music's library service, slow enough that
/// doing it for every row kept a large playlist spinning for minutes. Rows load without
/// locations; they're filled in the background, or looked up when a track is played, dragged
/// or copied.
final class PrelistenTrackFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: ITLibMediaItem] = [:]
    /// A stored nil means the track has no file on this Mac.
    private var locations: [String: URL?] = [:]

    func register(_ item: ITLibMediaItem, persistentID: String) {
        lock.lock()
        defer { lock.unlock() }
        if items[persistentID] == nil { items[persistentID] = item }
    }

    /// After a library reload items are new objects and files may have moved.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
        locations.removeAll()
    }

    /// Blocks on Music's library service when the location isn't cached, so the main thread
    /// only calls this for the few tracks a user action needs.
    func location(forPersistentID id: String) -> URL? {
        lock.lock()
        if let cached = locations[id] {
            lock.unlock()
            return cached
        }
        let item = items[id]
        lock.unlock()
        guard let item else { return nil }
        let url = item.location.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        lock.lock()
        locations[id] = url
        lock.unlock()
        return url
    }

    /// The row with its location filled in, if it has been looked up.
    func filling(_ row: PrelistenRow) -> PrelistenRow {
        guard row.isLocalFile, row.fileURL == nil else { return row }
        lock.lock()
        let cached = locations[row.persistentID]
        lock.unlock()
        guard let cached else { return row }
        var filled = row
        filled.fileURL = cached
        filled.isLocalFile = cached != nil
        return filled
    }
}

/// Reads playlists through the iTunesLibrary framework, which still works on Tahoe where
/// scripting Music does not. The framework is read-only: edits made in Music show up after
/// a reload, and nothing here writes back.
@MainActor
final class MusicLibraryBrowser: ObservableObject {
    enum Status: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var playlists: [PrelistenPlaylistNode] = []
    @Published private(set) var rows: [PrelistenRow] = []
    @Published private(set) var isLoadingRows = false
    @Published var selectedPlaylistID: String? {
        didSet { if selectedPlaylistID != oldValue { loadRows() } }
    }

    let trackFiles = PrelistenTrackFiles()
    private let reader: MusicLibraryReader
    private var rowsTask: Task<Void, Never>?
    private var locationsTask: Task<Void, Never>?

    init() {
        reader = MusicLibraryReader(trackFiles: trackFiles)
    }

    var selectedPlaylistName: String? {
        guard let selectedPlaylistID else { return nil }
        func find(_ nodes: [PrelistenPlaylistNode]) -> String? {
            for node in nodes {
                if node.id == selectedPlaylistID { return node.name }
                if let found = node.children.flatMap(find) { return found }
            }
            return nil
        }
        return find(playlists)
    }

    func loadIfNeeded() {
        if status == .idle { refresh() }
    }

    func refresh() {
        let reload = status != .idle
        status = .loading
        locationsTask?.cancel()
        Task {
            do {
                let summaries = try await reader.playlists(reload: reload)
                playlists = buildPrelistenPlaylistTree(summaries)
                status = .ready
                loadRows()
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func loadRows() {
        rowsTask?.cancel()
        locationsTask?.cancel()
        guard let id = selectedPlaylistID else {
            rows = []
            isLoadingRows = false
            return
        }
        isLoadingRows = true
        rowsTask = Task {
            let loaded = await reader.rows(forPlaylist: id)
            guard !Task.isCancelled, selectedPlaylistID == id else { return }
            rows = loaded
            isLoadingRows = false
            lookUpLocations(for: loaded, playlist: id)
        }
    }

    /// Runs off the actor so the next playlist's rows never wait behind it, and stops when
    /// the playlist changes. Locations found so far stay cached for the next visit.
    private func lookUpLocations(for loaded: [PrelistenRow], playlist id: String) {
        var seen = Set<String>()
        let pending = loaded
            .filter { $0.isLocalFile && $0.fileURL == nil && seen.insert($0.persistentID).inserted }
            .map(\.persistentID)
        guard !pending.isEmpty else { return }
        let files = trackFiles
        locationsTask = Task.detached(priority: .utility) { [weak self] in
            var lastShown = Date()
            for (index, persistentID) in pending.enumerated() {
                if Task.isCancelled { return }
                _ = files.location(forPersistentID: persistentID)
                // Batched, so the table isn't redrawn for every track.
                if index == pending.count - 1 || Date().timeIntervalSince(lastShown) > 0.5 {
                    lastShown = Date()
                    await self?.showLocations(forPlaylist: id)
                }
            }
        }
    }

    private func showLocations(forPlaylist id: String) {
        guard selectedPlaylistID == id else { return }
        rows = rows.map(trackFiles.filling)
    }
}

private actor MusicLibraryReader {
    private let trackFiles: PrelistenTrackFiles
    private var library: ITLibrary?
    private var playlistsByID: [String: ITLibPlaylist] = [:]

    init(trackFiles: PrelistenTrackFiles) {
        self.trackFiles = trackFiles
    }

    func playlists(reload: Bool) throws -> [PrelistenPlaylistSummary] {
        if let library {
            if reload {
                library.reloadData()
                trackFiles.removeAll()
            }
        } else {
            library = try ITLibrary(apiVersion: "1.1")
        }
        guard let library else { return [] }

        var summaries: [PrelistenPlaylistSummary] = []
        var byID: [String: ITLibPlaylist] = [:]
        for playlist in library.allPlaylists {
            // Skip the whole-library list and Music's built-ins (Purchased, Genius, …).
            guard !playlist.isPrimary, playlist.distinguishedKind.rawValue == 0 else { continue }
            switch playlist.kind {
            case .regular, .smart, .folder: break
            default: continue
            }
            let id = Self.hexID(playlist.persistentID)
            byID[id] = playlist
            summaries.append(PrelistenPlaylistSummary(
                id: id,
                parentID: playlist.parentID.map(Self.hexID),
                name: playlist.name,
                isFolder: playlist.kind == .folder,
                isSmart: playlist.kind == .smart))
        }
        playlistsByID = byID
        return summaries
    }

    /// Reads no file locations; `PrelistenTrackFiles` fills those in afterwards.
    func rows(forPlaylist id: String) -> [PrelistenRow] {
        guard let playlist = playlistsByID[id] else { return [] }
        return playlist.items.enumerated().map { index, item in
            let persistentID = Self.hexID(item.persistentID)
            trackFiles.register(item, persistentID: persistentID)
            let totalMs = Int(item.totalTime)
            let trim = musicTrimSeconds(startMs: Int(item.startTime), stopMs: Int(item.stopTime),
                                        totalMs: totalMs)
            return trackFiles.filling(PrelistenRow(
                id: index,
                persistentID: persistentID,
                title: item.title,
                artist: item.artist?.name ?? "",
                album: item.album.title ?? "",
                composer: item.composer,
                genre: item.genre,
                year: item.year > 0 ? Int(item.year) : nil,
                comment: item.comments.flatMap { $0.isEmpty ? nil : $0 },
                grouping: item.grouping.flatMap { $0.isEmpty ? nil : $0 },
                plays: Int(item.playCount),
                dateAdded: item.addedDate,
                duration: Double(totalMs) / 1000,
                // Unknown counts as local until the lookup says otherwise, so a file whose type
                // isn't recorded doesn't show dimmed and unplayable.
                isLocalFile: item.locationType == .file || item.locationType == .unknown,
                fileURL: nil,
                trimStart: trim.start,
                trimEnd: trim.end))
        }
    }

    // Same formatting as the setlist's Music trim cache, so IDs match across the app.
    private static func hexID(_ number: NSNumber) -> String {
        String(format: "%016llX", number.uint64Value)
    }
}
