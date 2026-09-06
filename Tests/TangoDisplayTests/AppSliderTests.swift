import Foundation
import TangoDisplayCore

// AppSlider snaps values itself instead of letting NSSlider do it, because NSSlider's
// stepping needs tick marks and the tick marks are the stray dotted line the wrapper exists
// to remove. That makes this arithmetic load-bearing.
func runSliderSnapTests() {
    suite("AppSlider — value snapping") {
        test("rounds to the nearest step") {
            try expectEqual(snapToStep(0.7, step: 0.5, lower: 0, upper: 5), 0.5)
            try expectEqual(snapToStep(0.8, step: 0.5, lower: 0, upper: 5), 1.0)
            try expectEqual(snapToStep(0.75, step: 0.5, lower: 0, upper: 5), 1.0)
        }

        test("clamps into range") {
            try expectEqual(snapToStep(-3, step: 1, lower: 0, upper: 200), 0)
            try expectEqual(snapToStep(999, step: 1, lower: 0, upper: 200), 200)
            try expectEqual(snapToStep(-3, step: nil, lower: 0, upper: 200), 0)
            try expectEqual(snapToStep(999, step: nil, lower: 0, upper: 200), 200)
        }

        test("no step passes the value through untouched") {
            try expectEqual(snapToStep(0.6137, step: nil, lower: 0, upper: 1), 0.6137)
            try expectEqual(snapToStep(0.6137, step: 0, lower: 0, upper: 1), 0.6137)
        }

        test("a range that is not a whole number of steps still reaches both bounds") {
            // Declick "Max repair": 0.2...20 by 0.5. Snapping from zero rather than from the
            // lower bound would make 0.2 unreachable.
            try expectEqual(snapToStep(0.2, step: 0.5, lower: 0.2, upper: 20), 0.2)
            try expectEqual(snapToStep(0.0, step: 0.5, lower: 0.2, upper: 20), 0.2)
            try expectEqual(snapToStep(99, step: 0.5, lower: 0.2, upper: 20), 20)
            let mid = snapToStep(4.4, step: 0.5, lower: 0.2, upper: 20)
            try expect(mid >= 0.2 && mid <= 20, "\(mid) fell outside the range")
        }

        test("negative ranges snap correctly") {
            // ReplayGain target is -23...-14 by 0.5
            try expectEqual(snapToStep(-18.3, step: 0.5, lower: -23, upper: -14), -18.5)
            try expectEqual(snapToStep(-18.2, step: 0.5, lower: -23, upper: -14), -18.0)
        }

        test("an inverted range is returned unchanged rather than clamped to nonsense") {
            try expectEqual(snapToStep(5, step: nil, lower: 10, upper: 0), 5)
        }
    }
}
