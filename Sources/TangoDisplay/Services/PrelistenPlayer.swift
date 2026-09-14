import AVFoundation
import AudioToolbox
import Combine
import CoreAudio
import Foundation
import TangoDisplayCore

/// Elapsed time is published apart from the player so the track table doesn't re-render
/// on every tick.
final class PrelistenClock: ObservableObject {
    @Published var elapsed: Double = 0
}

/// Plays prelisten tracks on its own engine and output device, independent of the setlist
/// player, so cueing on headphones never touches what the room hears.
///
/// The queue is a snapshot of the rows playback started from and is walked by position, so
/// a track that appears twice in a playlist is simply two stops.
final class PrelistenPlayer: ObservableObject {
    @Published private(set) var queue: [PrelistenRow] = []
    /// Playlist the queue came from, so the table only marks the playing row in that playlist.
    @Published private(set) var queueSourceID: String?
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var isChangingDevice = false
    @Published var errorMessage: String?

    let clock = PrelistenClock()

    var current: PrelistenRow? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    /// Music's start/stop times when set, else the whole track, in file seconds.
    var playRange: ClosedRange<Double> {
        guard let current else { return 0...0 }
        let lower = current.trimStart ?? 0
        return lower...max(lower, current.trimEnd ?? fileDuration ?? current.duration)
    }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var connectedFormat: AVAudioFormat?
    private var fileDuration: Double? {
        file.map { Double($0.length) / $0.processingFormat.sampleRate }
    }
    /// File position where the scheduled segment starts; the node's clock restarts at zero
    /// on every schedule.
    private var segmentStart: Double = 0
    /// Bumped before every node stop, so a replaced segment's completion handler is ignored.
    private var generation = 0
    private let settings: AppSettings
    private let trackFiles: PrelistenTrackFiles
    private let deviceQueue = DispatchQueue(label: "com.tangodisplay.prelisten-device", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, trackFiles: PrelistenTrackFiles) {
        self.settings = settings
        self.trackFiles = trackFiles
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: nil)

        settings.$prelistenVolume
            .sink { [weak self] volume in self?.node.volume = volume }
            .store(in: &cancellables)
        settings.$prelistenOutputDeviceUID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uid in self?.applyOutputDevice(uid) }
            .store(in: &cancellables)
        Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isPlaying else { return }
                self.clock.elapsed = self.position()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(engineConfigurationChanged),
            name: .AVAudioEngineConfigurationChange, object: engine)
    }

    // MARK: - Transport

    func play(_ rows: [PrelistenRow], startingAt index: Int, sourceID: String?) {
        queue = rows
        queueSourceID = sourceID
        start(at: index)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if file != nil {
            resume()
        } else if let currentIndex {
            start(at: currentIndex)
        }
    }

    func next() {
        guard let currentIndex,
              let next = prelistenNextIndex(after: currentIndex, count: queue.count) else { return }
        start(at: next)
    }

    func previous() {
        guard let currentIndex else { return }
        switch prelistenPreviousAction(current: currentIndex, elapsed: position() - playRange.lowerBound) {
        case .restart:         seek(to: playRange.lowerBound)
        case .play(let index): start(at: index)
        }
    }

    func seek(to seconds: Double) {
        guard file != nil else { return }
        if isPlaying {
            schedule(from: seconds)
            node.play()
        } else {
            clock.elapsed = min(max(seconds, playRange.lowerBound), playRange.upperBound)
        }
    }

    private func start(at index: Int) {
        guard queue.indices.contains(index) else { return }
        stopNode()
        currentIndex = index
        let row = queue[index]
        // The queue is a snapshot, possibly taken before this row's location was looked up.
        guard let url = row.fileURL ?? (row.isLocalFile ? trackFiles.location(forPersistentID: row.persistentID) : nil) else {
            file = nil
            isPlaying = false
            errorMessage = "“\(row.title)” isn't downloaded to this Mac, so it can't play here."
            return
        }
        do {
            let newFile = try AVAudioFile(forReading: url)
            if connectedFormat != newFile.processingFormat {
                // Reconnecting upstream of the mixer is allowed while the engine runs.
                engine.disconnectNodeOutput(node)
                engine.connect(node, to: engine.mainMixerNode, format: newFile.processingFormat)
                connectedFormat = newFile.processingFormat
            }
            file = newFile
            if !engine.isRunning { try engine.start() }
            errorMessage = nil
            schedule(from: row.trimStart ?? 0)
            node.play()
            isPlaying = true
        } catch {
            file = nil
            isPlaying = false
            errorMessage = "Couldn't play “\(row.title)”: \(error.localizedDescription)"
        }
    }

    private func pause() {
        clock.elapsed = position()
        stopNode()
        isPlaying = false
    }

    private func resume() {
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            errorMessage = "Couldn't start the prelisten output: \(error.localizedDescription)"
            return
        }
        errorMessage = nil
        schedule(from: clock.elapsed)
        node.play()
        isPlaying = true
    }

    private func stopNode() {
        generation += 1
        node.stop()
    }

    private func schedule(from seconds: Double) {
        guard let file else { return }
        stopNode()
        let range = playRange
        // A track that already finished resumes from its start instead of scheduling nothing.
        let from = seconds < range.upperBound - 0.05 ? max(range.lowerBound, seconds) : range.lowerBound
        let rate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(from * rate)
        let endFrame = min(file.length, AVAudioFramePosition(range.upperBound * rate))
        guard endFrame > startFrame else { return }
        segmentStart = from
        clock.elapsed = from
        let gen = generation
        node.scheduleSegment(file, startingFrame: startFrame,
                             frameCount: AVAudioFrameCount(endFrame - startFrame),
                             at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.segmentFinished(generation: gen) }
        }
    }

    private func segmentFinished(generation gen: Int) {
        guard gen == generation else { return }
        if settings.prelistenAutoAdvance, let currentIndex,
           let next = prelistenNextIndex(after: currentIndex, count: queue.count) {
            start(at: next)
        } else {
            stopNode()
            isPlaying = false
            clock.elapsed = playRange.lowerBound
        }
    }

    private func position() -> Double {
        guard isPlaying, let time = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: time) else { return clock.elapsed }
        return min(playRange.upperBound, segmentStart + Double(playerTime.sampleTime) / playerTime.sampleRate)
    }

    // MARK: - Output device

    private func applyOutputDevice(_ uid: String) {
        let wasPlaying = isPlaying
        if wasPlaying { pause() }
        isChangingDevice = true
        let unit = engine.outputNode.audioUnit
        deviceQueue.async { [weak self] in
            guard let self else { return }
            // CoreAudio device switches can block, so they stay off the main thread.
            if self.engine.isRunning { self.engine.stop() }
            let routed = unit.map { AudioDeviceManager.route($0, toUID: uid) } ?? false
            DispatchQueue.main.async {
                self.isChangingDevice = false
                if !routed {
                    self.errorMessage = "The prelisten output isn't connected. Pick another output."
                } else if wasPlaying {
                    self.resume()
                }
            }
        }
    }

    @objc private func engineConfigurationChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            // Our own device switch posts this too; it's handled there.
            guard let self, !self.isChangingDevice else { return }
            // Usually headphones being unplugged. Pause rather than carry on, because macOS
            // may have moved the default output to the room speakers.
            let wasPlaying = self.isPlaying
            if wasPlaying { self.pause() }
            self.applyOutputDevice(self.settings.prelistenOutputDeviceUID)
            if wasPlaying {
                self.errorMessage = "Audio output changed, so prelisten paused. Press play to continue."
            }
        }
    }
}

extension AudioDeviceManager {
    /// Points an engine's output unit at a device; an empty UID means the system default.
    /// Returns false when a specific device was asked for and isn't connected.
    static func route(_ unit: AudioUnit, toUID uid: String) -> Bool {
        var deviceID = AudioDeviceID(0)
        if uid.isEmpty {
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        } else if let found = audioDeviceID(forUID: uid) {
            deviceID = found
        } else {
            return false
        }
        return AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                    &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr
    }
}
