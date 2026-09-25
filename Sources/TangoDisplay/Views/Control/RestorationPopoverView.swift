import SwiftUI
import TangoDisplayCore
import TangoDisplayObjC

/// Controls for the ShellacFilters declick and dehum filters.
///
/// Help text is condensed from the measured rationale in
/// `Sources/TangoDisplayObjC/shellac/declick_core.h` and `dehum_core.h` — the defaults
/// were calibrated against 78 rpm tango transfers with real clicks injected into a
/// clean master at known positions, so the numbers in the tooltips are measurements,
/// not guidance.
///
/// Deliberately plain containers throughout: LabeledContent outside a Form gives the
/// label layout priority and squeezes the slider to near-zero width, which leaves the
/// knob off the visible track until a click forces a relayout, and DisclosureGroup
/// draws its own separators. Both showed up as rendering artefacts in the popover.
struct RestorationPopoverView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var showDeclickAdvanced = false
    @State private var showDehumAdvanced = false

    private var r: Binding<RestorationSettings> { $settings.restoration }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shellac restoration")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Enabled", isOn: r.enabled)
                .help("Repairs shellac transfers before the equaliser. Individual tracks can "
                    + "opt in or out from the setlist context menu.")

            // An override outranks this switch, so a track can be restored while it reads
            // off. Said out loud, because otherwise the sparkles badge looks like a lie.
            Text("Tracks marked **Restore this Track** are repaired whether this is on or not.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Skip on cortinas", isOn: r.skipOnCortinas)
                .disabled(!settings.restoration.enabled)
                .help("Cortinas are usually modern digital files, where a declicker only "
                    + "substitutes guesswork and the rumble filter costs real bass.")

            Divider()

            declickSection
            Divider()
            dehumSection
            Divider()

            Text("Declick and Dehum by Nick Shaforostov — MIT\nShellacFilters v\(TDShellacFiltersVersion)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .help("The upstream release these filters were built from. They ship compiled "
                    + "into TangoDisplay, so they update with the app.")
        }
        .padding(12)
        .frame(width: 340)
    }

    // MARK: - Declick

    private var declickSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: r.declickEnabled) {
                Text("Declick").font(.headline)
            }
            .help("Detects clicks as spikes in an autoregressive model's prediction residual "
                + "and reconstructs what the waveform should have been. Adds about 18 ms of "
                + "latency while it is engaged.")

            VStack(alignment: .leading, spacing: 8) {
                row("Sensitivity", r.declickSensitivity, 0...1, "%.2f",
                    help: "How readily a sample is called a click. The default puts the "
                        + "trigger at 3.9 sigma above the local noise estimate; on 78 rpm "
                        + "tango transfers that takes impulsive events from roughly 71 per "
                        + "second down to 14. Raise it towards 0.8 to catch more, at the "
                        + "cost of flagging music as damage.")

                row("Extent", r.declickExtent, 0...1, "%.2f",
                    help: "How far each detection spreads outwards into the tail of the "
                        + "click. Higher repairs more of the decay; too high starts "
                        + "replacing good audio either side of it.")

                advancedToggle("Advanced", isOpen: $showDeclickAdvanced)

                if showDeclickAdvanced {
                    VStack(alignment: .leading, spacing: 8) {
                        row("Max repair", r.declickMaxLengthMs, 0.2...20, "%.1f ms",
                            help: "The longest single stretch that may be reconstructed. "
                                + "Damage longer than this is left alone rather than "
                                + "guessed at.")

                        row("Repair depth", r.declickDepth, 0...1, "%.2f",
                            help: "How much of the estimated click is subtracted. 0 is the "
                                + "setting measured to add the least error of its own, "
                                + "against real clicks injected into a clean master at "
                                + "known positions. Raising it removes more of each click "
                                + "but substitutes more guesswork.")

                        row("Passes", r.declickPasses, 1...3, "%.0f", step: 1,
                            help: "How many times the detector sweeps each block. A second "
                                + "pass catches clicks that the first pass's repairs "
                                + "uncover.")

                        row("Model order", r.declickOrder, 8...256, "%.0f", step: 8,
                            help: "Taps in the autoregressive model that predicts what the "
                                + "waveform should have been. The lever that pays most: "
                                + "against injected-click ground truth, 128 takes "
                                + "whole-file error from +0.60 to +1.31 dB and 256 to "
                                + "+2.55 dB. It also costs real CPU and adds latency, "
                                + "which is why the default stops at 64.")

                        row("Dry/Wet", r.declickDryWet, 0...1, "%.2f",
                            help: "Blend of the repaired signal against the original. "
                                + "0 passes the input through untouched — useful for A/B, "
                                + "though the filter still runs. To stop paying for it, "
                                + "switch Declick off.")
                    }
                    .padding(.leading, 10)
                }
            }
            .disabled(!settings.restoration.declickEnabled)
        }
    }

    // MARK: - Dehum

    private var dehumSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: r.dehumEnabled) {
                Text("Dehum").font(.headline)
            }
            .help("Finds continuous narrowband lines — mains hum, and the off-frequency "
                + "drones on speed-corrected disc transfers — and cancels them. Zero latency.")

            VStack(alignment: .leading, spacing: 8) {
                row("Sensitivity", r.dehumSensitivity, 0...1, "%.2f",
                    help: "How far a spectral peak must stand above its surroundings before "
                        + "it counts as a tone. The default maps to a 16 dB prominence "
                        + "threshold, which the reference hum clears on 87% of analysis "
                        + "hops while hum-free material manages at most 10%. Past about "
                        + "0.7, clean material starts qualifying.")

                row("Rumble", r.dehumRumbleHz, 0...200, "%.0f Hz", step: 1,
                    help: "High-pass corner for broadband turntable rumble — a separate "
                        + "defect that happens to share the band with hum. 0 turns it off. "
                        + "The 67 Hz default goes after rumble properly and takes the "
                        + "bottom octave of a double bass with it; wind it back towards 40 "
                        + "where the low end is worth keeping.")

                advancedToggle("Advanced", isOpen: $showDehumAdvanced)

                if showDehumAdvanced {
                    VStack(alignment: .leading, spacing: 8) {
                        row("Bandwidth", r.dehumBandwidth, 0.1...5, "%.2f Hz",
                            help: "Half width of each notch. 1 Hz costs nothing musically — "
                                + "a partial 5 Hz away loses 0.15 dB — and is wide enough "
                                + "to absorb the detector's own error before the frequency "
                                + "tracker converges on the line.")

                        row("Search to", r.dehumSearchTo, 40...500, "%.0f Hz", step: 5,
                            help: "Top of the range searched for hum automatically. Hum "
                                + "lives low; searching higher finds sustained musical "
                                + "notes instead — during calibration a bandoneón E4 at "
                                + "329 Hz was detected as hum and duly cancelled.")

                        row("Harmonics", r.dehumHarmonics, 1...8, "%.0f", step: 1,
                            help: "Multiples of each detected line to cancel as well. Mains "
                                + "buzz has them; the drones on speed-corrected disc "
                                + "transfers usually do not, and the extra notches land "
                                + "squarely in the musical register.")

                        row("Frequency", r.dehumFrequency, 0...500, "%.0f Hz", step: 1,
                            help: "0 detects the line automatically, which needs a few "
                                + "seconds of steady evidence before it engages — "
                                + "TangoDisplay shortens that by scanning the opening of "
                                + "the file before it plays. Set a frequency to pin the "
                                + "notch there instead, when you already know what you are "
                                + "removing.")

                        row("Dry/Wet", r.dehumDryWet, 0...1, "%.2f",
                            help: "Blend of the processed signal against the original. "
                                + "0 passes the input through untouched, while the detector "
                                + "keeps tracking, so switching back is instant.")
                    }
                    .padding(.leading, 10)
                }
            }
            .disabled(!settings.restoration.dehumEnabled)
        }
    }

    // MARK: - Shared controls

    /// Fixed-width label and readout with the slider taking the slack, so the track can
    /// never collapse and hide its knob.
    private func row(
        _ label: String,
        _ value: Binding<Float>,
        _ range: ClosedRange<Float>,
        _ format: String,
        step: Float? = nil,
        help: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 78, alignment: .leading)

            AppSlider(value: value, range: range, step: step)
                .frame(maxWidth: .infinity)

            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 54, alignment: .trailing)
        }
        .help(help)
    }

    private func advancedToggle(_ title: String, isOpen: Binding<Bool>) -> some View {
        Button {
            isOpen.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 11))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
