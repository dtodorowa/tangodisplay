import AppKit
import SwiftUI
import TangoDisplayCore

/// An `NSSlider` that lays its knob out even before it is first clicked.
///
/// On macOS 26 `NSSlider` computes its knob geometry only when the value actually *changes*
/// while the view is in a window. A value assigned in `makeNSView` — before the view has a
/// window — leaves the track and fill drawn but no knob, until the first click supplies the
/// change. Measured across six candidates in a popover matching this app's: assigning the
/// value only after the view lands in a window fixes it, forcing a real change fixes it, and
/// touching `controlSize` fixes it; re-assigning the range, invalidating layout, forcing a
/// redraw, `wantsLayer`, first-responder and making the window key all do not.
///
/// Forcing the change is the one that holds when the value equals the slider's default of 0,
/// which Balance (0 in -1...1) and Repair depth (0 in 0...1) both do.
final class KnobDrawingSlider: NSSlider {
    /// Kept up to date by the representable, and read when the nudge runs.
    var pendingValue: Double = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let target = self.pendingValue
            // Any different value will do; both writes land in the same runloop turn, so
            // nothing intermediate is ever drawn. Programmatic writes do not fire the
            // action, so no binding sees this.
            self.doubleValue = (target == self.minValue) ? self.maxValue : self.minValue
            self.doubleValue = target
        }
    }
}

/// A horizontal slider backed directly by `NSSlider`.
///
/// SwiftUI's `Slider` has the same unpainted-knob defect on macOS 26 and cannot be fixed
/// from outside, hence the wrapper. It also draws tick marks for any `step:`, so `step: 1`
/// over `0...200` puts 201 ticks under the track, which reads as a stray dotted line.
///
/// `EQView` already reached the same conclusion and wraps `NSSlider` for its band faders.
/// This is the horizontal counterpart; the two are kept separate on purpose, because
/// `VerticalSlider` deliberately shows five tick marks and merging the orientations would
/// mean adding parameters to code that has worked for thirty releases.
///
/// Generic over `BinaryFloatingPoint` so `Float` settings and `Double` ones both bind
/// directly, without a converting `Binding` at every call site.
struct AppSlider<V: BinaryFloatingPoint>: NSViewRepresentable {
    @Binding var value: V
    let range: ClosedRange<V>
    /// nil for a continuous slider. Stepping is done by snapping the value, *not* by
    /// `NSSlider.allowsTickMarkValuesOnly`, which would bring the tick marks back.
    var step: V? = nil

    /// The arithmetic lives in TangoDisplayCore's `snapToStep` so the test runner can reach
    /// it without an NSView.
    static func snap(_ raw: Double, to step: V?, in range: ClosedRange<V>) -> V {
        V(snapToStep(raw,
                     step: step.map { Double($0) },
                     lower: Double(range.lowerBound),
                     upper: Double(range.upperBound)))
    }

    func makeNSView(context: Context) -> KnobDrawingSlider {
        let slider = KnobDrawingSlider()
        slider.isVertical = false
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
        slider.numberOfTickMarks = 0
        slider.isContinuous = true          // readout tracks the drag
        slider.doubleValue = Double(value)
        slider.pendingValue = Double(value)
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        return slider
    }

    func updateNSView(_ nsView: KnobDrawingSlider, context: Context) {
        context.coordinator.step = step
        context.coordinator.range = range

        nsView.minValue = Double(range.lowerBound)
        nsView.maxValue = Double(range.upperBound)
        nsView.pendingValue = Double(value)

        // Guard the write-back, or dragging fights the binding update.
        if V(nsView.doubleValue) != value {
            nsView.doubleValue = Double(value)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, range: range, step: step)
    }

    class Coordinator: NSObject {
        var value: Binding<V>
        var range: ClosedRange<V>
        var step: V?

        init(value: Binding<V>, range: ClosedRange<V>, step: V?) {
            self.value = value
            self.range = range
            self.step = step
        }

        @objc func valueChanged(_ sender: NSSlider) {
            let snapped = AppSlider.snap(sender.doubleValue, to: step, in: range)
            // Put the knob on the step rather than between two of them.
            if step != nil, sender.doubleValue != Double(snapped) {
                sender.doubleValue = Double(snapped)
            }
            value.wrappedValue = snapped
        }
    }
}
