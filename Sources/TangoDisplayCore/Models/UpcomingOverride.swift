import Foundation

/// DJ-supplied replacement for the "Coming Up" details shown during a cortina.
/// Used when the next tanda is mixed and the first track's metadata would
/// misdescribe it. nil/blank field = fall back to the real track metadata.
/// `year` is free text ("1941-43", "Golden Age") — `Track.year` is `Int?`.
public struct UpcomingOverride: Equatable, Hashable, Codable {
    public var artist: String?
    public var singer: String?
    public var year: String?

    public init(artist: String? = nil, singer: String? = nil, year: String? = nil) {
        self.artist = artist
        self.singer = singer
        self.year = year
    }

    public var isEmpty: Bool {
        [artist, singer, year].allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Non-blank value for a field, or nil.
    public static func value(_ s: String?) -> String? {
        let t = (s ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    public var artistValue: String? { Self.value(artist) }
    public var singerValue: String? { Self.value(singer) }
    public var yearValue: String? { Self.value(year) }
}
