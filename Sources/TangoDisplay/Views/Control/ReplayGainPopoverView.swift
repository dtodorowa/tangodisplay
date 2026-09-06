import SwiftUI
import TangoDisplayCore

struct ReplayGainPopoverView: View {
    @ObservedObject var player: LocalPlayerSource
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ReplayGain")
                .font(.caption)
                .foregroundStyle(.secondary)

            ReplayGainModePicker(mode: $settings.replayGainMode)

            Divider()

            Toggle("Prevent clipping", isOn: $settings.replayGainPreventClipping)
                .disabled(settings.replayGainMode == .off)

            LabeledContent("Preamp") {
                HStack(spacing: 6) {
                    AppSlider(value: $settings.replayGainPreampDb, range: -12...6, step: 0.5)
                    Text(String(format: "%+.1f dB", settings.replayGainPreampDb))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 56, alignment: .trailing)
                }
            }
            .disabled(settings.replayGainMode == .off)

            LabeledContent("Target") {
                HStack(spacing: 6) {
                    AppSlider(value: $settings.replayGainTargetLufs, range: -23...(-14), step: 0.5)
                    Text(String(format: "%.1f LUFS", settings.replayGainTargetLufs))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 64, alignment: .trailing)
                }
            }
            .disabled(settings.replayGainMode != .auto)

            if !player.replayGainStatus.isEmpty {
                Divider()
                Text(player.replayGainStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(12)
        .frame(width: 290)
    }
}
