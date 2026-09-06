import Foundation

/// Rounds `raw` to the nearest `step` and clamps it into `lower...upper`.
///
/// Used by `AppSlider`, which snaps values itself rather than letting `NSSlider` do it:
/// `allowsTickMarkValuesOnly` needs tick marks, and the tick marks are the stray dotted
/// line this exists to avoid.
///
/// Snapping is measured **from `lower`**, not from zero. A range whose span is not a whole
/// number of steps — Max repair is 0.2...20 by 0.5 — would otherwise never reach its own
/// lower bound, because 0.2 is not a multiple of 0.5.
///
/// A nil, zero or negative `step` means continuous: clamped, otherwise untouched.
public func snapToStep(_ raw: Double, step: Double?, lower: Double, upper: Double) -> Double {
    guard lower <= upper else { return raw }

    var v = min(max(raw, lower), upper)

    if let step, step > 0 {
        v = lower + ((v - lower) / step).rounded() * step
        v = min(max(v, lower), upper)
    }

    return v
}
