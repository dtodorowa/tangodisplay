import Foundation

// Pure logic behind the Prelisten window: nesting Music playlists, walking a queue by
// position, filtering rows. Kept free of iTunesLibrary so the test runner can cover it.

/// One Music playlist or folder as read from the library, before nesting.
public struct PrelistenPlaylistSummary: Equatable {
    public let id: String
    public let parentID: String?
    public let name: String
    public let isFolder: Bool
    public let isSmart: Bool

    public init(id: String, parentID: String?, name: String, isFolder: Bool, isSmart: Bool) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.isFolder = isFolder
        self.isSmart = isSmart
    }
}

public struct PrelistenPlaylistNode: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let isFolder: Bool
    public let isSmart: Bool
    /// nil for playlists so OutlineGroup draws no disclosure triangle; [] for an empty folder.
    public let children: [PrelistenPlaylistNode]?
}

/// Nests playlists under their folders, folders first and names in Finder order, the way
/// Music's sidebar shows them. A playlist whose folder isn't in the list stays at the top
/// level rather than disappearing.
public func buildPrelistenPlaylistTree(_ summaries: [PrelistenPlaylistSummary]) -> [PrelistenPlaylistNode] {
    let folderIDs = Set(summaries.lazy.filter(\.isFolder).map(\.id))
    var childrenByFolder: [String: [PrelistenPlaylistSummary]] = [:]
    var roots: [PrelistenPlaylistSummary] = []
    for summary in summaries {
        if let parent = summary.parentID, parent != summary.id, folderIDs.contains(parent) {
            childrenByFolder[parent, default: []].append(summary)
        } else {
            roots.append(summary)
        }
    }

    func sorted(_ list: [PrelistenPlaylistSummary]) -> [PrelistenPlaylistSummary] {
        list.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    func node(for summary: PrelistenPlaylistSummary) -> PrelistenPlaylistNode {
        PrelistenPlaylistNode(
            id: summary.id, name: summary.name, isFolder: summary.isFolder, isSmart: summary.isSmart,
            children: summary.isFolder ? sorted(childrenByFolder[summary.id] ?? []).map(node(for:)) : nil)
    }

    return sorted(roots).map(node(for:))
}

// MARK: - Queue navigation

/// Next stop in the queue, or nil at the end. Positions, never track identity: Music.app
/// resolves "what's next" by track, which is why a song listed twice makes it jump.
public func prelistenNextIndex(after current: Int, count: Int) -> Int? {
    let next = current + 1
    return next < count ? next : nil
}

public enum PrelistenPreviousAction: Equatable {
    case restart
    case play(Int)
}

/// Like Music: Previous restarts the track once it has played a few seconds, and goes back
/// a track only near the start.
public func prelistenPreviousAction(current: Int, elapsed: Double,
                                    restartAfter threshold: Double = 3) -> PrelistenPreviousAction {
    if elapsed > threshold || current == 0 { return .restart }
    return .play(current - 1)
}

// MARK: - Filtering and display

/// Every word of the query has to appear in one of the fields, ignoring case and accents,
/// so "pena canaro" finds "Peña Mulata" by Francisco Canaro.
public func prelistenRowMatches(_ query: String, fields: [String]) -> Bool {
    let words = query.split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return true }
    let haystack = fields.joined(separator: " ")
    return words.allSatisfy {
        haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

public func formatPrelistenTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}
