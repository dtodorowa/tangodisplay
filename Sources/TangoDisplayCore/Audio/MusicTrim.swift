import Foundation

/// Converts Music's per-track start/stop (Song Info → Options), given in milliseconds,
/// into playback-trim seconds. Music reports `startMs == 0` and `stopMs == 0`-or-`totalMs`
/// when the checkboxes are off, so those map to `nil` (no trim on that end).
public func musicTrimSeconds(startMs: Int, stopMs: Int, totalMs: Int) -> (start: Double?, end: Double?) {
    let start = startMs > 0 ? Double(startMs) / 1000 : nil
    let end   = (stopMs > 0 && stopMs < totalMs) ? Double(stopMs) / 1000 : nil
    return (start, end)
}

/// Music's persistent IDs for the tracks in a drag, read from the metadata plist Music puts
/// on the pasteboard (`com.apple.tv.metadata` / the legacy `'itun'` flavor). That plist gives
/// `Location` and `Persistent ID` but *not* the start/stop times, so the ID is what lets us
/// look the times up without the ~4s cost of asking ITLibrary for every track's location.
///
/// The filename fallback covers file-promise drops, where Music materialises a copy into our
/// app-support cache and the dropped URL's full path never matches the library's.
public struct MusicDragIDs {
    private var byPath: [String: String] = [:]
    private var byName: [String: String] = [:]

    public init() {}

    /// Accepts both plist shapes Music has used: `{"Tracks": {id: {...}}}` and a bare `{id: {...}}`.
    public init(musicMetadataPlist plist: [String: Any]) {
        let tracks = (plist["Tracks"] as? [String: Any]) ?? plist
        for (_, value) in tracks {
            guard let track = value as? [String: Any],
                  let persistentID = track["Persistent ID"] as? String,
                  let location = track["Location"] as? String,
                  let path = MusicDragIDs.path(fromLocation: location)
            else { continue }
            byPath[path] = persistentID
            byName[(path as NSString).lastPathComponent] = persistentID
        }
    }

    /// `Location` is either a "file://…" URL or a "~/…" tilde path, depending on Music version.
    static func path(fromLocation location: String) -> String? {
        guard !location.isEmpty else { return nil }
        if location.hasPrefix("file:") {
            guard let path = URL(string: location)?.path, !path.isEmpty else { return nil }
            return path
        }
        return (location as NSString).expandingTildeInPath
    }

    public var isEmpty: Bool { byPath.isEmpty }
    public var count: Int { byPath.count }

    /// nil means this URL wasn't part of a Music drag — no trim import for it.
    public func persistentID(for url: URL) -> String? {
        byPath[url.path] ?? byName[url.lastPathComponent]
    }
}
