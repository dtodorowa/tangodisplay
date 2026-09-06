import AVFoundation
import AppKit
import Foundation
import TangoDisplayCore
import TangoDisplayObjC

// The one runnable check behind the vendored C++: it proves the ShellacFilters cores
// compiled, linked, and produce correct numbers on this architecture. That matters
// because the SSE2 path (x86_64) and the scalar path (arm64) are different code, and
// Install.sh builds both slices.
func runRestorationTests() {
    suite("Shellac restoration cores") {
        test("declick repairs injected clicks, dehum notches a pinned line") {
            let result = TDRestorationSelfTest()
            try expect(result & 1 == 0, "declick did not repair the injected clicks")
            try expect(result & 2 == 0, "dehum did not attenuate the 50 Hz line")
        }

        test("both units register and can be found by description") {
            try expect(TDRestorationRegister(), "AudioComponent registration did not take")
        }

        // The registration path is the part that has no fallback: a locally registered
        // subclass is visible to AudioComponentFindNext but is not guaranteed to reach
        // AVAudioUnitComponentManager, so this renders one through a real AVAudioEngine
        // exactly as LocalPlayerSource wires it — instantiate by description, attach,
        // connect, pull audio out the other end.
        test("declick renders inside an AVAudioEngine graph") {
            try expect(TDRestorationRegister())

            var acd = AudioComponentDescription()
            acd.componentType = kAudioUnitType_Effect
            acd.componentSubType = TDDeclickSubType
            acd.componentManufacturer = TDRestorationManufacturer

            let rate = 44100.0
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let frames: AVAudioFrameCount = 8192

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let unit = AVAudioUnitEffect(audioComponentDescription: acd)

            engine.attach(player)
            engine.attach(unit)
            engine.connect(player, to: unit, format: format)
            engine.connect(unit, to: engine.mainMixerNode, format: format)

            let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            input.frameLength = frames
            for c in 0..<Int(format.channelCount) {
                let ch = input.floatChannelData![c]
                for i in 0..<Int(frames) {
                    ch[i] = Float(0.5 * sin(2.0 * .pi * 220.0 * Double(i) / rate))
                }
            }

            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            try engine.start()
            player.scheduleBuffer(input, at: nil, options: [])
            player.play()

            let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                          frameCapacity: engine.manualRenderingMaximumFrameCount)!
            var rendered: AVAudioFrameCount = 0
            var sumSquares = 0.0

            while rendered < frames {
                let want = min(engine.manualRenderingMaximumFrameCount, frames - rendered)
                let status = try engine.renderOffline(want, to: output)
                try expect(status == .success, "renderOffline returned \(status.rawValue)")

                // Skip the declick pipeline's 784-sample fill; past that it must be audio.
                if rendered >= 1024 {
                    let ch = output.floatChannelData![0]
                    for i in 0..<Int(output.frameLength) {
                        try expect(ch[i].isFinite, "non-finite sample from the declick unit")
                        sumSquares += Double(ch[i]) * Double(ch[i])
                    }
                }
                rendered += output.frameLength
            }

            engine.stop()
            engine.disableManualRenderingMode()

            // A 0.5 sine is 0.354 RMS. Well inside that means the unit passed audio
            // rather than silence, and well outside it means it mangled the signal.
            let rms = sqrt(sumSquares / Double(frames - 1024))
            try expect(rms > 0.25 && rms < 0.45, "declick output RMS was \(rms), expected ~0.354")
        }

        // LocalPlayerSource leaves both units connected for the life of a track and
        // expresses engagement as bypass, so that toggling restoration mid-track costs an
        // atomic store instead of an engine restart. That only holds if AVAudioEngine keeps
        // calling our render block when the unit is bypassed: if it short-circuited the node
        // instead, the pipeline's latency would vanish and reappear on every toggle — a
        // discontinuity, which is exactly the gap this arrangement exists to remove.
        test("a bypassed declick still delays, so engaging it stays sample-aligned") {
            try expect(TDRestorationRegister())

            var acd = AudioComponentDescription()
            acd.componentType = kAudioUnitType_Effect
            acd.componentSubType = TDDeclickSubType
            acd.componentManufacturer = TDRestorationManufacturer

            let rate = 44100.0
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let frames: AVAudioFrameCount = 4096

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let unit = AVAudioUnitEffect(audioComponentDescription: acd)

            engine.attach(player)
            engine.attach(unit)
            engine.connect(player, to: unit, format: format)
            engine.connect(unit, to: engine.mainMixerNode, format: format)
            unit.auAudioUnit.shouldBypassEffect = true

            let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            input.frameLength = frames
            for c in 0..<Int(format.channelCount) {
                let ch = input.floatChannelData![c]
                for i in 0..<Int(frames) {
                    ch[i] = Float(0.5 * sin(2.0 * .pi * 220.0 * Double(i) / rate))
                }
            }

            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            try engine.start()
            player.scheduleBuffer(input, at: nil, options: [])
            player.play()

            let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                          frameCapacity: engine.manualRenderingMaximumFrameCount)!
            var collected = [Float]()
            while collected.count < Int(frames) {
                let want = min(engine.manualRenderingMaximumFrameCount,
                               frames - AVAudioFrameCount(collected.count))
                let status = try engine.renderOffline(want, to: output)
                try expect(status == .success, "renderOffline returned \(status.rawValue)")
                let ch = output.floatChannelData![0]
                for i in 0..<Int(output.frameLength) { collected.append(ch[i]) }
            }

            engine.stop()
            engine.disableManualRenderingMode()

            // cfg.latency is 880 samples at the shipped defaults (order 64, 4 ms max repair,
            // 44.1 kHz); 800 leaves room without depending on the exact figure. Those frames
            // are the primed silence still working its way out of the pipeline.
            let head = collected.prefix(800).map { abs($0) }.max() ?? 0
            try expect(head < 1e-4,
                       "bypassed declick passed audio straight through (peak \(head) in the "
                       + "first 800 frames) — the node was short-circuited, not bypassed")

            // Past the fill it must still be the dry signal, not silence.
            let tail = collected.dropFirst(1024)
            let rms = sqrt(tail.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(tail.count))
            try expect(rms > 0.25 && rms < 0.45,
                       "bypassed declick output RMS was \(rms), expected the dry ~0.354")
        }
    }

    // A bad SF Symbol name renders as nothing at all — no crash, no warning, just an
    // invisible badge. "sparkles.slash" shipped once and did exactly that.
    suite("Restoration UI symbols") {
        test("every symbol name the restoration UI uses resolves") {
            for name in ["sparkles", "nosign", "chevron.down", "chevron.right"] {
                try expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                           "SF Symbol '\(name)' does not exist")
            }
        }
    }

    suite("RestorationSettings") {
        test("defaults match the cores' own defaults and start disabled") {
            let d = RestorationSettings.defaults
            try expect(!d.enabled, "restoration must be off for existing users")
            try expect(d.skipOnCortinas, "cortinas are skipped by default")
            try expectEqual(d.declickSensitivity, 0.6)
            try expectEqual(d.declickPasses, 2)
            try expectEqual(d.declickOrder, 64)
            try expectEqual(d.dehumSensitivity, 0.5)
            try expectEqual(d.dehumSearchTo, 100)
            try expectEqual(d.dehumHarmonics, 1)
            try expectEqual(d.dehumRumbleHz, 67)
        }

        test("round-trips through JSON, and an older blob keeps its defaults") {
            var s = RestorationSettings.defaults
            s.enabled = true
            s.dehumRumbleHz = 40

            let data = try JSONEncoder().encode(s)
            let back = try JSONDecoder().decode(RestorationSettings.self, from: data)
            try expectEqual(back, s)

            // A blob written before a field existed must decode, not throw
            let partial = Data(#"{"enabled":true}"#.utf8)
            let old = try JSONDecoder().decode(RestorationSettings.self, from: partial)
            try expect(old.enabled)
            try expectEqual(old.declickOrder, RestorationSettings.defaults.declickOrder)
        }
    }
}
