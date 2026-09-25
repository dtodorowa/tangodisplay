import Foundation
import TangoDisplayCore

/// Maps a profile's Singer Source to the matching transform field.
func singerTrackInfoField(_ source: SingerSource) -> TrackInfoField {
    switch source {
    case .albumArtist: return .albumArtist
    case .comments:    return .comments
    case .grouping:    return .grouping
    }
}

private let customPlaceholderRegex = try! NSRegularExpression(pattern: "\\{([A-Za-z ]+)\\}")

/// Resolves a custom-line template against a track's metadata. Tags are matched
/// case-insensitively (`{Artist}`, `{artist}`, …); unknown tags resolve to empty.
/// Field values are run through the profile's transforms / genre label mapping so
/// they match how the built-in lines render. Singer honours `profile.singerSource`.
func resolveCustomPlaceholders(_ template: String, track: Track?,
                               profile: AppearanceProfile, settings: AppSettings,
                               override: UpcomingOverride? = nil) -> String {
    guard let track = track else {
        // No track: strip all placeholders.
        let range = NSRange(template.startIndex..., in: template)
        return customPlaceholderRegex.stringByReplacingMatches(
            in: template, range: range, withTemplate: "")
    }

    var values: [String: String] = [
        "title":       settings.transform(track.title,  for: .title),
        "artist":      settings.transform(track.artist, for: .artist),
        "genre":       settings.displayLabel(for: track.genre),
        "year":        track.year.map { settings.transform(String($0), for: .year) } ?? "",
        "albumartist": settings.transform(track.albumArtist ?? "", for: .albumArtist),
        "comment":     settings.transform(track.comment ?? "",     for: .comments),
        "grouping":    settings.transform(track.grouping ?? "",     for: .grouping),
    ]
    if let rawSinger = profile.singerValue(from: track), !rawSinger.isEmpty {
        values["singer"] = settings.transform(rawSinger, for: singerTrackInfoField(profile.singerSource))
    } else {
        values["singer"] = ""
    }

    // Cortina "Coming Up" override wins over the real metadata, verbatim.
    if let o = override {
        if let a = o.artistValue { values["artist"] = a }
        if let s = o.singerValue { values["singer"] = s }
        if let y = o.yearValue   { values["year"]   = y }
    }

    let ns = template as NSString
    let matches = customPlaceholderRegex.matches(in: template, range: NSRange(location: 0, length: ns.length))
    var result = ""
    var cursor = 0
    for match in matches {
        result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let tag = ns.substring(with: match.range(at: 1)).lowercased()
        result += values[tag] ?? ""
        cursor = match.range.location + match.range.length
    }
    result += ns.substring(from: cursor)
    return result
}
