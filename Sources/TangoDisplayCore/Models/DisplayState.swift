import Foundation

public enum DisplayMode: Equatable, Hashable {
    case playing
    case cortina
    case idle
    case paused
    case override
    case performance
}

public struct TandaPosition: Equatable, Hashable {
    public let current: Int
    public let total: Int?   // nil when playlist scan unavailable

    public init(current: Int, total: Int?) {
        self.current = current
        self.total = total
    }

    public var label: String {
        if let total { return "Track \(current) of \(total)" }
        return "Track \(current)"
    }
}

public struct DisplayState: Equatable, Hashable {
    public var mode: DisplayMode = .idle
    public var currentTrack: Track?
    public var nextTrack: Track?           // non-nil in .cortina mode: first track of next tanda
    public var tandaPosition: TandaPosition?
    public var overrideText: String?
    public var nextTrackIsPerformance: Bool = false  // true when next tanda starts with a performance track
    public var nextTrackOverride: UpcomingOverride?  // DJ-edited Coming Up details for this cortina

    public init(
        mode: DisplayMode = .idle,
        currentTrack: Track? = nil,
        nextTrack: Track? = nil,
        tandaPosition: TandaPosition? = nil,
        overrideText: String? = nil,
        nextTrackIsPerformance: Bool = false,
        nextTrackOverride: UpcomingOverride? = nil
    ) {
        self.mode = mode
        self.currentTrack = currentTrack
        self.nextTrack = nextTrack
        self.tandaPosition = tandaPosition
        self.overrideText = overrideText
        self.nextTrackIsPerformance = nextTrackIsPerformance
        self.nextTrackOverride = nextTrackOverride
    }
}
