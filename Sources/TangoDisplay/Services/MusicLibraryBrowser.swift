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
    let genre: String
    let year: Int?
    let comment: String?
    let grouping: String?
    let duration: Double
    /// nil when the track has no file on this Mac (cloud-only or moved).
    let fileURL: URL?
    let trimStart: Double?
    let trimEnd: Double?

    var playDuration: Double { (trimEnd ?? duration) - (trimStart ?? 0) }
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

    private let reader = MusicLibraryReader()
    private var rowsTask: Task<Void, Never>?

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
        guard let id = selectedPlaylistID else {
            rows = []
            return
        }
        isLoadingRows = true
        rowsTask = Task {
            let loaded = await reader.rows(forPlaylist: id)
            guard !Task.isCancelled, selectedPlaylistID == id else { return }
            rows = loaded
            isLoadingRows = false
        }
    }
}

private actor MusicLibraryReader {
    private var library: ITLibrary?
    private var playlistsByID: [String: ITLibPlaylist] = [:]

    func playlists(reload: Bool) throws -> [PrelistenPlaylistSummary] {
        if let library {
            if reload { library.reloadData() }
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

    func rows(forPlaylist id: String) -> [PrelistenRow] {
        guard let playlist = playlistsByID[id] else { return [] }
        return playlist.items.enumerated().map { index, item in
            let totalMs = Int(item.totalTime)
            let trim = musicTrimSeconds(startMs: Int(item.startTime), stopMs: Int(item.stopTime),
                                        totalMs: totalMs)
            let url = item.location.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            return PrelistenRow(
                id: index,
                persistentID: Self.hexID(item.persistentID),
                title: item.title,
                artist: item.artist?.name ?? "",
                album: item.album.title ?? "",
                genre: item.genre,
                year: item.year > 0 ? Int(item.year) : nil,
                comment: item.comments.flatMap { $0.isEmpty ? nil : $0 },
                grouping: item.grouping.flatMap { $0.isEmpty ? nil : $0 },
                duration: Double(totalMs) / 1000,
                fileURL: url,
                trimStart: trim.start,
                trimEnd: trim.end)
        }
    }

    // Same formatting as the setlist's Music trim cache, so IDs match across the app.
    private static func hexID(_ number: NSNumber) -> String {
        String(format: "%016llX", number.uint64Value)
    }
}
