import Foundation

/// Settings for the ShellacFilters declick and dehum filters.
///
/// Persisted as a single JSON blob rather than 18 UserDefaults keys — the same shape
/// `AppSettings` already uses for the plugin chain, genre colour rules and track
/// transforms. Every field decodes with a fallback, so a blob written by an older
/// build keeps its defaults instead of failing to decode.
///
/// Numeric defaults mirror `declick::Params::defaults()` and `dehum::Params::defaults()`
/// exactly; the rationale for each is in `Sources/TangoDisplayObjC/shellac/*_core.h`,
/// and the tooltips in RestorationPopoverView condense it. If those defaults ever
/// change upstream, change them here too — the self-test does not catch a mismatch.
public struct RestorationSettings: Codable, Equatable {

    // MARK: Engagement

    /// Off for existing users: nothing about playback changes until this is switched on.
    public var enabled: Bool = false
    public var declickEnabled: Bool = true
    public var dehumEnabled: Bool = true
    /// Cortinas are almost always modern digital files, where a declicker only ever
    /// substitutes guesswork and the 67 Hz rumble filter costs real bass.
    public var skipOnCortinas: Bool = true

    // MARK: Declick — in TDDeclickParam order

    public var declickSensitivity: Float = 0.6
    public var declickExtent: Float = 0.5
    public var declickMaxLengthMs: Float = 4.0
    public var declickDepth: Float = 0.0
    public var declickPasses: Float = 2
    public var declickOrder: Float = 64
    public var declickDryWet: Float = 1.0

    // MARK: Dehum — in TDDehumParam order

    public var dehumSensitivity: Float = 0.5
    public var dehumBandwidth: Float = 1.0
    public var dehumSearchTo: Float = 100.0
    public var dehumHarmonics: Float = 1
    /// 0 = detect automatically; any other value pins the notch and turns the search off.
    public var dehumFrequency: Float = 0.0
    /// 0 = off. Broadband rumble is a different defect from hum but shares the band.
    public var dehumRumbleHz: Float = 67.0
    public var dehumDryWet: Float = 1.0

    public init() {}

    public static let defaults = RestorationSettings()

    /// Whether a track is restored when it carries no per-track override.
    public func appliesByDefault(isCortina: Bool) -> Bool {
        guard enabled else { return false }
        return !(skipOnCortinas && isCortina)
    }

    /// Values in parameter-address order, so the host can write them in one loop.
    public var declickValues: [Float] {
        [declickSensitivity, declickExtent, declickMaxLengthMs,
         declickDepth, declickPasses, declickOrder, declickDryWet]
    }

    public var dehumValues: [Float] {
        [dehumSensitivity, dehumBandwidth, dehumSearchTo,
         dehumHarmonics, dehumFrequency, dehumRumbleHz, dehumDryWet]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RestorationSettings.defaults

        func f(_ key: CodingKeys, _ fallback: Float) throws -> Float {
            try c.decodeIfPresent(Float.self, forKey: key) ?? fallback
        }
        func b(_ key: CodingKeys, _ fallback: Bool) throws -> Bool {
            try c.decodeIfPresent(Bool.self, forKey: key) ?? fallback
        }

        enabled        = try b(.enabled, d.enabled)
        declickEnabled = try b(.declickEnabled, d.declickEnabled)
        dehumEnabled   = try b(.dehumEnabled, d.dehumEnabled)
        skipOnCortinas = try b(.skipOnCortinas, d.skipOnCortinas)

        declickSensitivity = try f(.declickSensitivity, d.declickSensitivity)
        declickExtent      = try f(.declickExtent, d.declickExtent)
        declickMaxLengthMs = try f(.declickMaxLengthMs, d.declickMaxLengthMs)
        declickDepth       = try f(.declickDepth, d.declickDepth)
        declickPasses      = try f(.declickPasses, d.declickPasses)
        declickOrder       = try f(.declickOrder, d.declickOrder)
        declickDryWet      = try f(.declickDryWet, d.declickDryWet)

        dehumSensitivity = try f(.dehumSensitivity, d.dehumSensitivity)
        dehumBandwidth   = try f(.dehumBandwidth, d.dehumBandwidth)
        dehumSearchTo    = try f(.dehumSearchTo, d.dehumSearchTo)
        dehumHarmonics   = try f(.dehumHarmonics, d.dehumHarmonics)
        dehumFrequency   = try f(.dehumFrequency, d.dehumFrequency)
        dehumRumbleHz    = try f(.dehumRumbleHz, d.dehumRumbleHz)
        dehumDryWet      = try f(.dehumDryWet, d.dehumDryWet)
    }
}
