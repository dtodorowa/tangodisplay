import AVFoundation
import AppKit
import SwiftUI

// MARK: - Fallback editor for Audio Units with no view of their own.
//
// requestViewController hands back nil for these — Airwindows and most older
// V2 effects ship no Cocoa UI at all and expect the host to draw their
// parameter tree. Without this the slot is unreachable: the window never
// opens and the plugin sits in the chain at whatever values it loaded with.
//
// Built from the parameter tree rather than AUGenericView, which wants an
// in-process AudioUnit handle. Plugins default to out-of-process hosting here
// (see PluginWindowViewController), and the tree is what survives that
// boundary.

final class GenericPluginEditorModel: ObservableObject {
    let parameters: [AUParameter]

    @Published private(set) var values: [AUParameterAddress: AUValue] = [:]

    private let tree: AUParameterTree
    private var token: AUParameterObserverToken?

    init?(auAudioUnit: AUAudioUnit) {
        guard let tree = auAudioUnit.parameterTree, !tree.allParameters.isEmpty else { return nil }
        self.tree = tree
        self.parameters = tree.allParameters
        for parameter in parameters { values[parameter.address] = parameter.value }

        // Keeps the sliders honest when something else moves the values —
        // preset recall from the bar below, or a configuration applied at
        // track start.
        token = tree.token(byAddingParameterObserver: { [weak self] address, value in
            DispatchQueue.main.async { self?.values[address] = value }
        })
    }

    deinit {
        if let token { tree.removeParameterObserver(token) }
    }

    func value(for parameter: AUParameter) -> AUValue {
        values[parameter.address] ?? parameter.value
    }

    func setValue(_ value: AUValue, for parameter: AUParameter) {
        values[parameter.address] = value
        // Passing our own token keeps the observer above from echoing the
        // change back while a slider is being dragged.
        parameter.setValue(value, originator: token)
    }

    /// The plugin's own rendering of a value — "-12 dB", "440 Hz" — falling
    /// back to two decimals for AUs that don't implement it.
    func displayString(for parameter: AUParameter) -> String {
        var raw = value(for: parameter)
        let formatted = withUnsafePointer(to: &raw) { parameter.string(fromValue: $0) }
        if formatted.isEmpty || Float(formatted) != nil {
            let unit = parameter.unitName.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
            return String(format: "%.2f", raw) + unit
        }
        return formatted
    }
}

struct GenericPluginEditorView: View {
    @ObservedObject var model: GenericPluginEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.parameters, id: \.address) { parameter in
                    row(for: parameter)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A ScrollView has no width of its own to report, so without this the
        // hosting controller's fitting size collapses and the window opens as a
        // one-pixel sliver.
        .frame(minWidth: 380, idealWidth: 440, minHeight: 100)
    }

    @ViewBuilder
    private func row(for parameter: AUParameter) -> some View {
        HStack(spacing: 10) {
            Text(parameter.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(width: 110, alignment: .trailing)

            control(for: parameter)

            Text(model.displayString(for: parameter))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)
        }
    }

    @ViewBuilder
    private func control(for parameter: AUParameter) -> some View {
        let binding = Binding<AUValue>(
            get: { model.value(for: parameter) },
            set: { model.setValue($0, for: parameter) }
        )

        if parameter.unit == .boolean {
            Toggle("", isOn: Binding(
                get: { binding.wrappedValue >= 0.5 },
                set: { binding.wrappedValue = $0 ? 1 : 0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let strings = parameter.valueStrings, !strings.isEmpty {
            Picker("", selection: Binding(
                get: { Int(binding.wrappedValue.rounded()) },
                set: { binding.wrappedValue = AUValue($0) }
            )) {
                ForEach(Array(strings.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Slider(value: binding, in: parameter.minValue...parameter.maxValue)
                .controlSize(.small)
        }
    }
}

extension GenericPluginEditorView {
    /// Wraps the editor in a view controller sized for its parameter count,
    /// ready to hand to PluginWindowViewController in place of a plugin's own.
    static func makeViewController(for auAudioUnit: AUAudioUnit) -> NSViewController? {
        guard let model = GenericPluginEditorModel(auAudioUnit: auAudioUnit) else { return nil }
        let controller = NSHostingController(rootView: GenericPluginEditorView(model: model))
        let height = min(560, max(120, CGFloat(model.parameters.count) * 34 + 32))
        let size = NSSize(width: 440, height: height)
        // Sizing stays ours. PluginWindowViewController treats preferredContentSize
        // as a resize request from the plugin, and NSHostingController will happily
        // publish SwiftUI's fitting size into it mid-layout — which is what shrank
        // the window to nothing.
        controller.sizingOptions = []
        // Both are needed: the wrapper reads the frame to size the window, and
        // an explicit autoresizing mask is what tells it the view can be resized.
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.preferredContentSize = size
        controller.view.autoresizingMask = [.width, .height]
        return controller
    }
}
