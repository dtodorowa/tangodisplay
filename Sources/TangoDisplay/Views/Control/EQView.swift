import AppKit
import SwiftUI

private struct EQBand: Identifiable {
    let id: Int
    let label: String
    let keyPath: ReferenceWritableKeyPath<AppSettings, Float>
}

private let bands: [EQBand] = [
    EQBand(id: 0, label: "60",   keyPath: \.eqBand0Gain),
    EQBand(id: 1, label: "250",  keyPath: \.eqBand1Gain),
    EQBand(id: 2, label: "1k",   keyPath: \.eqBand2Gain),
    EQBand(id: 3, label: "4k",   keyPath: \.eqBand3Gain),
    EQBand(id: 4, label: "12k",  keyPath: \.eqBand4Gain),
]

struct EQView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 10) {
            Text("Equaliser")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(bands) { band in
                    BandColumn(
                        label: band.label,
                        value: Binding(
                            get: { settings[keyPath: band.keyPath] },
                            set: { settings[keyPath: band.keyPath] = $0 }
                        )
                    )
                }
            }

            Button("Flat") {
                for band in bands { settings[keyPath: band.keyPath] = 0 }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 220)
    }
}

private struct BandColumn: View {
    let label: String
    @Binding var value: Float

    var body: some View {
        VStack(spacing: 4) {
            Text(gainLabel)
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(height: 14)

            VerticalSlider(value: $value, range: -12...12)
                .frame(width: 20, height: 100)

            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(width: 36)
    }

    private var gainLabel: String {
        let v = value
        if v == 0 { return "0" }
        return v > 0 ? "+\(Int(v.rounded()))" : "\(Int(v.rounded()))"
    }
}

private struct VerticalSlider: NSViewRepresentable {
    @Binding var value: Float
    let range: ClosedRange<Float>

    // KnobDrawingSlider for the macOS 26 unpainted-knob defect — see AppSlider.swift. It
    // bites hardest here: these default to 0 dB, which is also NSSlider's own default, so
    // the value never changes and a flat EQ shows five knobless tracks.
    func makeNSView(context: Context) -> KnobDrawingSlider {
        let slider = KnobDrawingSlider()
        slider.isVertical = true
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
        slider.numberOfTickMarks = 5
        slider.allowsTickMarkValuesOnly = false
        slider.doubleValue = Double(value)
        slider.pendingValue = Double(value)
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        return slider
    }

    func updateNSView(_ nsView: KnobDrawingSlider, context: Context) {
        nsView.pendingValue = Double(value)
        if Float(nsView.doubleValue) != value {
            nsView.doubleValue = Double(value)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    class Coordinator: NSObject {
        var value: Binding<Float>
        init(value: Binding<Float>) { self.value = value }
        @objc func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = Float(sender.doubleValue)
        }
    }
}
