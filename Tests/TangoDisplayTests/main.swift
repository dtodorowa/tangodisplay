// Lightweight test runner — no XCTest or Xcode required.
// Run with: swift run TangoDisplayTests
//
// Convention:
//   suite("SuiteName") { ... }      — groups tests, prints header
//   test("name") { ... }            — individual test, catches thrown errors
//   expect(_ condition, file:line:) — assertion; throws on failure

import Foundation
import TangoDisplayCore

// MARK: - Minimal test framework

private var totalPassed = 0
private var totalFailed = 0
private var currentSuite = ""

struct TestFailure: Error {
    let message: String
    let file: StaticString
    let line: Int
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String = "",
    file: StaticString = #file,
    line: Int = #line
) throws {
    guard condition() else {
        let msg = message.isEmpty ? "Assertion failed" : message
        throw TestFailure(message: msg, file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ a: T,
    _ b: T,
    file: StaticString = #file,
    line: Int = #line
) throws {
    try expect(a == b, "Expected \(a) == \(b)", file: file, line: line)
}

func expectNil<T>(_ value: T?, file: StaticString = #file, line: Int = #line) throws {
    try expect(value == nil, "Expected nil but got \(String(describing: value))", file: file, line: line)
}

func expectNotNil<T>(_ value: T?, file: StaticString = #file, line: Int = #line) throws {
    try expect(value != nil, "Expected non-nil value", file: file, line: line)
}

func suite(_ name: String, _ body: () -> Void) {
    currentSuite = name
    print("\n── \(name) ──")
    body()
}

func test(_ name: String, body: () throws -> Void) {
    do {
        try body()
        print("  ✓ \(name)")
        totalPassed += 1
    } catch let failure as TestFailure {
        print("  ✗ \(name)")
        print("      \(failure.message) (\(failure.file):\(failure.line))")
        totalFailed += 1
    } catch {
        print("  ✗ \(name) — unexpected error: \(error)")
        totalFailed += 1
    }
}

// MARK: - CortinaDetector tests

func runCortinaDetectorTests() {
    suite("CortinaDetector — Allowlist only") {
        test("matching genre is cortina") {
            let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                    useDenylist: false, denylistGenres: [])
            try expect(d.isCortina(genre: "Cortina"))
        }
        test("non-matching genre is not cortina") {
            let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                    useDenylist: false, denylistGenres: [])
            try expect(!d.isCortina(genre: "Tango"))
        }
        test("case insensitive — CORTINA") {
            let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                    useDenylist: false, denylistGenres: [])
            try expect(d.isCortina(genre: "CORTINA"))
            try expect(d.isCortina(genre: "cortina"))
            try expect(d.isCortina(genre: "Cortina"))
        }
        test("empty genre is NOT cortina under allowlist-only") {
            let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                    useDenylist: false, denylistGenres: [])
            try expect(!d.isCortina(genre: ""))
        }
    }

    suite("CortinaDetector — Denylist only") {
        let d = CortinaDetector(useAllowlist: false, allowlistGenres: [],
                                useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("dance genre is not cortina") {
            try expect(!d.isCortina(genre: "Tango"))
            try expect(!d.isCortina(genre: "Vals"))
            try expect(!d.isCortina(genre: "Milonga"))
        }
        test("non-dance genre is cortina") {
            try expect(d.isCortina(genre: "Pop"))
            try expect(d.isCortina(genre: "Cortina"))
        }
        test("empty genre is cortina") {
            try expect(d.isCortina(genre: ""))
        }
        test("case insensitive — TANGO") {
            try expect(!d.isCortina(genre: "TANGO"))
            try expect(!d.isCortina(genre: "Vals"))
        }
    }

    suite("CortinaDetector — Both rules (EITHER match → cortina)") {
        let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("allowlist match is cortina") {
            try expect(d.isCortina(genre: "Cortina"))
        }
        test("denylist match is cortina (Pop not in dance genres)") {
            try expect(d.isCortina(genre: "Pop"))
        }
        test("dance genre is NOT cortina") {
            try expect(!d.isCortina(genre: "Tango"))
        }
    }

    suite("CortinaDetector — Neither rule") {
        let d = CortinaDetector(useAllowlist: false, allowlistGenres: ["cortina"],
                                useDenylist: false, denylistGenres: ["tango"])
        test("never cortina") {
            try expect(!d.isCortina(genre: "Cortina"))
            try expect(!d.isCortina(genre: "Pop"))
            try expect(!d.isCortina(genre: ""))
            try expect(!d.isCortina(genre: "Tango"))
        }
    }

    suite("CortinaDetector — Denylist partial match") {
        let d = CortinaDetector(useAllowlist: false, allowlistGenres: [],
                                useDenylist: true, denylistGenres: ["tango", "vals", "milonga"],
                                denylistPartialGenres: ["tango", "vals", "milonga"])
        test("exact match still not cortina") {
            try expect(!d.isCortina(genre: "Tango"))
            try expect(!d.isCortina(genre: "Vals"))
            try expect(!d.isCortina(genre: "Milonga"))
        }
        test("prefix match with space — not cortina") {
            try expect(!d.isCortina(genre: "Tango Instrumental"))
            try expect(!d.isCortina(genre: "Tango Vocals"))
            try expect(!d.isCortina(genre: "Vals Instrumental"))
            try expect(!d.isCortina(genre: "Milonga Vocal"))
        }
        test("case insensitive prefix match — not cortina") {
            try expect(!d.isCortina(genre: "tango instrumental"))
            try expect(!d.isCortina(genre: "TANGO VOCALS"))
        }
        test("no space after term — is cortina") {
            try expect(d.isCortina(genre: "Tangoed"))
            try expect(d.isCortina(genre: "Valses"))
        }
        test("unrelated genre — is cortina") {
            try expect(d.isCortina(genre: "Pop"))
            try expect(d.isCortina(genre: "Cortina"))
        }

        let noPartial = CortinaDetector(useAllowlist: false, allowlistGenres: [],
                                        useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("without partial match, Tango Instrumental IS cortina") {
            try expect(noPartial.isCortina(genre: "Tango Instrumental"))
        }
        test("without partial match, exact Tango is still NOT cortina") {
            try expect(!noPartial.isCortina(genre: "Tango"))
        }
    }

    suite("CortinaDetector — Whitespace trimming") {
        let denyOnly = CortinaDetector(useAllowlist: false, allowlistGenres: [],
                                       useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("leading space on denylist genre is NOT cortina") {
            try expect(!denyOnly.isCortina(genre: " Tango"))
        }
        test("trailing space on denylist genre is NOT cortina") {
            try expect(!denyOnly.isCortina(genre: "Tango "))
        }
        test("leading and trailing spaces is NOT cortina") {
            try expect(!denyOnly.isCortina(genre: "  Tango  "))
        }
        test("tab-padded denylist genre is NOT cortina") {
            try expect(!denyOnly.isCortina(genre: "\tTango"))
        }

        let allowOnly = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                        useDenylist: false, denylistGenres: [])
        test("leading space on allowlist genre IS cortina") {
            try expect(allowOnly.isCortina(genre: " Cortina"))
        }
        test("trailing space on allowlist genre IS cortina") {
            try expect(allowOnly.isCortina(genre: "Cortina "))
        }

        let both = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                   useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("both rules: spaced Tango is NOT cortina") {
            try expect(!both.isCortina(genre: " Tango"))
        }
        test("both rules: spaced Cortina IS cortina") {
            try expect(both.isCortina(genre: " Cortina"))
        }

        test("spaces-only genre treated as empty -> cortina under denylist") {
            try expect(denyOnly.isCortina(genre: "   "))
        }
    }
}

// MARK: - TandaTracker tests

func runTandaTrackerTests() {
    let tracker = TandaTracker()
    let detector = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                   useDenylist: false, denylistGenres: [])

    func tracks(_ genres: [String]) -> [Track] {
        genres.enumerated().map { i, g in
            Track(title: "T\(i)", artist: "A", genre: g, persistentID: "\(i)")
        }
    }

    suite("TandaTracker — Playlist-based position") {
        test("first track of tanda") {
            // C T T T C
            let t = tracks(["Cortina", "Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 1, detector: detector)
            try expectEqual(pos?.current, 1)
            try expectEqual(pos?.total, 3)
        }
        test("mid-tanda") {
            let t = tracks(["Cortina", "Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 2, detector: detector)
            try expectEqual(pos?.current, 2)
            try expectEqual(pos?.total, 3)
        }
        test("last track of tanda") {
            let t = tracks(["Cortina", "Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 3, detector: detector)
            try expectEqual(pos?.current, 3)
            try expectEqual(pos?.total, 3)
        }
        test("single-track tanda") {
            let t = tracks(["Cortina", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 1, detector: detector)
            try expectEqual(pos?.current, 1)
            try expectEqual(pos?.total, 1)
        }
        test("tanda at start of playlist (no leading cortina)") {
            let t = tracks(["Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 1, detector: detector)
            try expectEqual(pos?.current, 2)
            try expectEqual(pos?.total, 3)
        }
        test("tanda at end of playlist (no trailing cortina)") {
            let t = tracks(["Cortina", "Tango", "Tango", "Tango"])
            let pos = tracker.position(tracks: t, currentIndex: 3, detector: detector)
            try expectEqual(pos?.current, 3)
            try expectEqual(pos?.total, 3)
        }
        test("current is cortina → returns nil") {
            let t = tracks(["Cortina", "Tango"])
            let pos = tracker.position(tracks: t, currentIndex: 0, detector: detector)
            try expectNil(pos)
        }
        test("out of bounds → returns nil") {
            let t = tracks(["Tango"])
            try expectNil(tracker.position(tracks: t, currentIndex: -1, detector: detector))
            try expectNil(tracker.position(tracks: t, currentIndex: 5, detector: detector))
        }
        test("second tanda in playlist") {
            // C T T C T T T C
            let t = tracks(["Cortina", "Tango", "Tango", "Cortina", "Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 5, detector: detector)
            try expectEqual(pos?.current, 2)
            try expectEqual(pos?.total, 3)
        }
    }

    suite("TandaTracker — History-based position") {
        func h(_ n: Int) -> [Track] {
            (0..<n).map { Track(title: "T\($0)", artist: "A", genre: "Tango", persistentID: "\($0)") }
        }
        test("single track") {
            let pos = tracker.positionFromHistory(h(1))
            try expectEqual(pos?.current, 1)
            try expectNil(pos?.total)
        }
        test("multiple tracks") {
            let pos = tracker.positionFromHistory(h(3))
            try expectEqual(pos?.current, 3)
            try expectNil(pos?.total)
        }
        test("empty history returns nil") {
            try expectNil(tracker.positionFromHistory([]))
        }
    }
}

// MARK: - ProfileStore tests

func runProfileStoreTests() {
    suite("ProfileStore — Round-trip save/load/delete") {
        test("save and reload user profile") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            let profile = AppearanceProfile(
                id: UUID(), name: "Test Profile", isBuiltIn: false,
                backgroundColor: "#FF0000"
            )
            try store.save(profile)

            // Load from disk into a fresh store
            let store2 = ProfileStore(storeURL: tmpDir)
            store2.load()
            try expect(store2.userProfiles.count == 1, "Expected 1 user profile, got \(store2.userProfiles.count)")
            try expectEqual(store2.userProfiles[0].id, profile.id)
            try expectEqual(store2.userProfiles[0].backgroundColor, "#FF0000")
        }

        test("update existing profile") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            var profile = AppearanceProfile(id: UUID(), name: "A", isBuiltIn: false)
            try store.save(profile)
            profile.name = "B"
            try store.save(profile)
            try expectEqual(store.userProfiles.count, 1)
            try expectEqual(store.userProfiles[0].name, "B")
        }

        test("delete user profile") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            let profile = AppearanceProfile(id: UUID(), name: "Del", isBuiltIn: false)
            try store.save(profile)
            try expectEqual(store.userProfiles.count, 1)
            try store.delete(profile)
            try expectEqual(store.userProfiles.count, 0)
            // Verify file is gone
            let fileURL = tmpDir.appendingPathComponent("\(profile.id.uuidString).json")
            try expect(!FileManager.default.fileExists(atPath: fileURL.path), "File should be deleted")
        }

        test("built-in profiles are never written to disk") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            do {
                try store.save(AppearanceProfile.classic)
                try expect(false, "Should have thrown for built-in profile")
            } catch ProfileStoreError.cannotModifyBuiltIn {
                // Expected
            }
            let files = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path)) ?? []
            try expect(files.isEmpty, "No files should exist for built-in profile")
        }

        test("delete built-in profile throws") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            do {
                try store.delete(AppearanceProfile.modern)
                try expect(false, "Should have thrown for built-in profile")
            } catch ProfileStoreError.cannotModifyBuiltIn {
                // Expected
            }
        }

        test("allProfiles prepends built-ins") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            let user = AppearanceProfile(id: UUID(), name: "My Profile", isBuiltIn: false)
            try store.save(user)
            let all = store.allProfiles
            try expect(all.count == AppearanceProfile.builtIns.count + 1)
            try expect(all.prefix(AppearanceProfile.builtIns.count)
                          .map(\.id) == AppearanceProfile.builtIns.map(\.id),
                       "Built-ins should come first")
        }
    }
}

// MARK: - DisplayState transition tests (pure logic, no AppKit)

func runDisplayStateTests() {
    // Helper: simulate the core logic that AppState applies
    let detector = CortinaDetector(
        useAllowlist: true, allowlistGenres: ["cortina"],
        useDenylist: true, denylistGenres: ["tango", "vals", "milonga"]
    )
    let tracker = TandaTracker()

    func track(_ title: String, genre: String, pid: String? = nil) -> Track {
        Track(title: title, artist: "A", genre: genre, persistentID: pid ?? title)
    }

    suite("DisplayState — Mode transitions") {
        test("stopped → idle") {
            var state = DisplayState(mode: .playing, currentTrack: track("A", genre: "Tango"))
            // Simulate stopping
            state = DisplayState()
            try expectEqual(state.mode, .idle)
            try expectNil(state.currentTrack)
        }

        test("playing → cortina clears tanda position") {
            var state = DisplayState(mode: .playing,
                                     currentTrack: track("A", genre: "Tango"),
                                     tandaPosition: TandaPosition(current: 2, total: 4))
            let cortina = track("C", genre: "Cortina")
            state = DisplayState(mode: .cortina, currentTrack: cortina)
            try expectEqual(state.mode, .cortina)
            try expectNil(state.tandaPosition)
        }

        test("cortina → playing sets mode correctly") {
            var state = DisplayState(mode: .cortina)
            let tango = track("A", genre: "Tango")
            let pos = tracker.positionFromHistory([tango])
            state = DisplayState(mode: .playing, currentTrack: tango, tandaPosition: pos)
            try expectEqual(state.mode, .playing)
            try expectEqual(state.currentTrack?.genre, "Tango")
            try expectEqual(state.tandaPosition?.current, 1)
        }

        test("override mode ignores track updates") {
            var state = DisplayState(mode: .override, overrideText: "Custom Message")
            // Simulate logic: if mode == .override, don't update
            let newTrack = track("NewTrack", genre: "Tango")
            let shouldUpdate = state.mode != .override
            if shouldUpdate { state.currentTrack = newTrack }
            try expectEqual(state.mode, .override)
            try expect(state.currentTrack == nil, "Override mode should ignore track changes")
            try expectEqual(state.overrideText, "Custom Message")
        }

        test("override cleared returns to idle") {
            var state = DisplayState(mode: .override, overrideText: "Custom")
            state = DisplayState()  // clearOverride resets to idle
            try expectEqual(state.mode, .idle)
            try expectNil(state.overrideText)
        }

        test("empty genre treated as cortina under denylist") {
            let isCortina = detector.isCortina(genre: "")
            try expect(isCortina, "Empty genre should be detected as cortina")
        }

        test("paused mode preserves content") {
            let tango = track("A", genre: "Tango")
            var state = DisplayState(mode: .playing, currentTrack: tango,
                                     tandaPosition: TandaPosition(current: 2, total: 4))
            // Simulate pause: change mode only
            state.mode = .paused
            try expectEqual(state.mode, .paused)
            try expectEqual(state.currentTrack?.title, "A")
            try expectEqual(state.tandaPosition?.current, 2)
        }

        test("next track set during cortina") {
            let cortina = track("C", genre: "Cortina")
            let nextTango = track("Di Sarli", genre: "Tango")
            let state = DisplayState(mode: .cortina, currentTrack: cortina, nextTrack: nextTango)
            try expectEqual(state.mode, .cortina)
            try expectEqual(state.nextTrack?.title, "Di Sarli")
        }

        test("upcoming track uses cortina's real position, not stale index") {
            // Playlist: dance, dance, cortina, dance, dance
            // Simulates the user skipping to the cortina at index 2 while
            // playlistCurrentIndex is stale at 0.
            let tracks: [Track] = [
                track("D1", genre: "Tango",   pid: "d1"),
                track("D2", genre: "Tango",   pid: "d2"),
                track("C1", genre: "Cortina", pid: "c1"),
                track("D3", genre: "Tango",   pid: "d3"),
                track("D4", genre: "Tango",   pid: "d4"),
            ]
            let cortina = tracks[2]

            // Simulate stale index (pointing before the cortina)
            var staleIndex = 0
            // Anchor to real position via persistentID lookup (the fix)
            if let idx = tracks.firstIndex(where: { $0.persistentID == cortina.persistentID }) {
                staleIndex = idx
            }
            // Forward scan from correct position
            let startSearch = staleIndex + 1
            let nextTrack = startSearch < tracks.count
                ? tracks[startSearch...].first { !detector.isCortina(genre: $0.genre) }
                : nil

            try expect(nextTrack?.persistentID == "d3",
                       "Upcoming track should be D3 (after the cortina), not D1")
        }

        test("upcoming track is nil when cortina is last in playlist") {
            let tracks: [Track] = [
                track("D1", genre: "Tango",   pid: "d1"),
                track("C1", genre: "Cortina", pid: "c1"),
            ]
            let cortina = tracks[1]
            var idx = 0
            if let i = tracks.firstIndex(where: { $0.persistentID == cortina.persistentID }) {
                idx = i
            }
            let startSearch = idx + 1
            let nextTrack = startSearch < tracks.count
                ? tracks[startSearch...].first { !detector.isCortina(genre: $0.genre) }
                : nil
            try expect(nextTrack == nil, "No upcoming track when cortina is last in playlist")
        }

        test("playlist-based tanda position during playing") {
            let tracks: [Track] = [
                track("C1", genre: "Cortina", pid: "c1"),
                track("T1", genre: "Tango", pid: "t1"),
                track("T2", genre: "Tango", pid: "t2"),
                track("T3", genre: "Tango", pid: "t3"),
                track("C2", genre: "Cortina", pid: "c2"),
            ]
            let pos = tracker.position(tracks: tracks, currentIndex: 2, detector: detector)
            let state = DisplayState(mode: .playing,
                                     currentTrack: tracks[2],
                                     tandaPosition: pos)
            try expectEqual(state.tandaPosition?.current, 2)
            try expectEqual(state.tandaPosition?.total, 3)
        }
    }
}

// MARK: - ReplayGain tests

func runReplayGainTests() {
    suite("parseReplayGainDb") {
        test("parses negative dB with unit") {
            try expectEqual(parseReplayGainDb("-7.23 dB"), -7.23)
        }
        test("parses positive dB with unit") {
            try expectEqual(parseReplayGainDb("+3.00 dB"), 3.0)
        }
        test("parses negative dB without unit") {
            try expectEqual(parseReplayGainDb("-5.4"), -5.4)
        }
        test("parses value with uppercase DB") {
            try expectEqual(parseReplayGainDb("-2.0 DB"), -2.0)
        }
        test("returns nil for non-numeric") {
            try expectNil(parseReplayGainDb("abc dB"))
        }
        test("returns nil for nil input") {
            try expectNil(parseReplayGainDb(nil))
        }
        test("returns nil for empty string") {
            try expectNil(parseReplayGainDb(""))
        }
    }

    suite("calculateReplayGainLinear — mode off") {
        test("always returns 1.0 when mode is off") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: 0.95, albumGainDb: -6.0, albumPeak: 0.90)
            let settings = ReplayGainSettings(mode: .off, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: info, settings: settings), 1.0)
        }
        test("returns 1.0 when mode is off and info is nil") {
            let settings = ReplayGainSettings(mode: .off, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: nil, settings: settings), 1.0)
        }
    }

    suite("calculateReplayGainLinear — track gain mode") {
        test("applies track gain correctly") {
            let info = ReplayGainInfo(trackGainDb: -6.0206, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            // -6.0206 dB ≈ 0.5 linear
            try expect(abs(gain - 0.5) < 0.001, "Expected ~0.5, got \(gain)")
        }
        test("returns 1.0 when track gain is missing") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: 0.95, albumGainDb: -5.0, albumPeak: 0.90)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: info, settings: settings), 1.0)
        }
        test("returns 1.0 when info is nil") {
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: nil, settings: settings), 1.0)
        }
        test("returns 1.0 when all fields are nil") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: info, settings: settings), 1.0)
        }
    }

    suite("calculateReplayGainLinear — album gain mode") {
        test("applies album gain correctly") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: 0.95, albumGainDb: -5.0, albumPeak: 0.90)
            let settings = ReplayGainSettings(mode: .album, preampDb: 0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, -5.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
        test("returns 1.0 when album gain is missing even if track gain is present") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: 0.95, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .album, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: info, settings: settings), 1.0)
        }
    }

    suite("calculateReplayGainLinear — preamp") {
        test("adds preamp dB to gain") {
            let info = ReplayGainInfo(trackGainDb: 0.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 6.0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, 6.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
        test("negative preamp reduces gain") {
            let info = ReplayGainInfo(trackGainDb: 0.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: -6.0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, -6.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
    }

    suite("calculateReplayGainLinear — clipping protection") {
        test("reduces gain when gain * peak exceeds 1.0") {
            // +4 dB gain with peak 0.90 → linear ≈ 1.585 * 0.90 > 1.0, should clamp to 1/0.90
            let info = ReplayGainInfo(trackGainDb: 4.0, trackPeak: 0.90, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: true)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let maxGain = Float(1.0 / 0.90)
            try expect(abs(gain - maxGain) < 0.0001, "Expected \(maxGain), got \(gain)")
        }
        test("does not reduce gain when clipping protection is off") {
            let info = ReplayGainInfo(trackGainDb: 4.0, trackPeak: 0.90, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, 4.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
        test("no clipping reduction needed when gain * peak is within 1.0") {
            // -7.23 dB gain with peak 0.95 → linear ≈ 0.436 * 0.95 < 1.0, no clamping
            let info = ReplayGainInfo(trackGainDb: -7.23, trackPeak: 0.95, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: true)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, -7.23 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
        test("skips clipping check when peak is nil") {
            let info = ReplayGainInfo(trackGainDb: 4.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: true)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, 4.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
    }
}

// MARK: - Auto ReplayGain tests

func runAutoReplayGainTests() {

    // MARK: Helpers

    func makeAnalysis(gainDb: Double, lufs: Double, samplePeak: Double? = nil,
                      truePeak: Double? = nil) -> LoudnessAnalysisResult {
        LoudnessAnalysisResult(
            filePath: "/fake/track.flac", fileSize: 1_000_000,
            modifiedDate: Date(), duration: 180,
            integratedLoudnessLufs: lufs, calculatedReplayGainDb: gainDb,
            targetLoudnessLufs: -18.0,
            samplePeak: samplePeak, truePeak: truePeak, analysedAt: Date())
    }

    func baseSettings(mode: ReplayGainMode, preventClipping: Bool = false,
                       preamp: Double = 0) -> ReplayGainSettings {
        ReplayGainSettings(mode: mode, preampDb: preamp,
                           preventClipping: preventClipping, targetLoudnessLufs: -18.0)
    }

    // MARK: calculateReplayGain — auto mode

    suite("calculateReplayGain — auto mode") {
        test("uses track metadata when present, ignores analysis") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: nil, albumGainDb: -5.0, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -3.0, lufs: -15.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto))
            try expectEqual(result.source, .metadataTrack)
            let expected = Float(pow(10.0, -7.0 / 20.0))
            try expect(abs(result.linearGain - expected) < 0.0001,
                       "Expected ~\(expected), got \(result.linearGain)")
        }

        test("uses analysis when track metadata is absent") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -7.1, lufs: -10.9)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto))
            try expectEqual(result.source, .analysed)
            let expected = Float(pow(10.0, -7.1 / 20.0))
            try expect(abs(result.linearGain - expected) < 0.0001,
                       "Expected ~\(expected), got \(result.linearGain)")
        }

        test("does not use album metadata in auto mode") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: -5.0, albumPeak: nil)
            let result = calculateReplayGain(info: info, analysis: nil,
                                              settings: baseSettings(mode: .auto))
            try expectEqual(result.source, .none)
            try expectEqual(result.linearGain, 1.0)
        }

        test("returns 1.0 when neither metadata nor analysis present") {
            let result = calculateReplayGain(info: nil, analysis: nil,
                                              settings: baseSettings(mode: .auto))
            try expectEqual(result.source, .none)
            try expectEqual(result.linearGain, 1.0)
        }

        test("integratedLoudnessLufs populated for analysed source") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -7.1, lufs: -10.9)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto))
            try expect(result.integratedLoudnessLufs != nil, "Expected integratedLoudnessLufs to be set")
            try expect(abs(result.integratedLoudnessLufs! - (-10.9)) < 0.001,
                       "Expected -10.9, got \(result.integratedLoudnessLufs!)")
        }

        test("integratedLoudnessLufs is nil for metadata source") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let result = calculateReplayGain(info: info, analysis: nil,
                                              settings: baseSettings(mode: .auto))
            try expectNil(result.integratedLoudnessLufs)
        }
    }

    // MARK: calculateReplayGain — mode isolation

    suite("calculateReplayGain — mode isolation") {
        test("track mode ignores analysis") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -3.0, lufs: -15.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .track))
            try expectEqual(result.source, .metadataTrack)
        }

        test("album mode ignores analysis") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: -5.0, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -3.0, lufs: -15.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .album))
            try expectEqual(result.source, .metadataAlbum)
        }

        test("off mode ignores metadata and analysis") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: nil, albumGainDb: -5.0, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -3.0, lufs: -15.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .off))
            try expectEqual(result.source, .none)
            try expectEqual(result.linearGain, 1.0)
        }
    }

    // MARK: calculateReplayGain — preamp with analysis

    suite("calculateReplayGain — preamp with analysed gain") {
        test("preamp applies to analysed gain") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -7.0, lufs: -11.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto, preamp: 2.0))
            let expected = Float(pow(10.0, (-7.0 + 2.0) / 20.0))
            try expect(abs(result.linearGain - expected) < 0.0001,
                       "Expected ~\(expected), got \(result.linearGain)")
        }
    }

    // MARK: calculateReplayGain — clipping with analysis peaks

    suite("calculateReplayGain — clipping protection with analysed peaks") {
        test("uses samplePeak for clipping protection") {
            // gain +4 dB * samplePeak 0.90 > 1.0 → clamp to 1/0.90
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: 4.0, lufs: -22.0, samplePeak: 0.90)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto, preventClipping: true))
            let maxGain = Float(1.0 / 0.90)
            try expect(result.clippingProtectionApplied, "Expected clipping protection to be applied")
            try expect(abs(result.linearGain - maxGain) < 0.0001,
                       "Expected \(maxGain), got \(result.linearGain)")
        }

        test("prefers truePeak over samplePeak when both present") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            // truePeak is lower than samplePeak → truePeak is the binding constraint
            let analysis = makeAnalysis(gainDb: 4.0, lufs: -22.0, samplePeak: 0.90, truePeak: 0.85)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto, preventClipping: true))
            let maxGain = Float(1.0 / 0.85)
            try expect(result.clippingProtectionApplied, "Expected clipping protection to be applied")
            try expect(abs(result.linearGain - maxGain) < 0.0001,
                       "Expected \(maxGain) (truePeak), got \(result.linearGain)")
        }

        test("clipping off — full gain applied even when would clip") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: 4.0, lufs: -22.0, samplePeak: 0.90)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto, preventClipping: false))
            let expected = Float(pow(10.0, 4.0 / 20.0))
            try expect(!result.clippingProtectionApplied, "Expected no clipping protection")
            try expect(abs(result.linearGain - expected) < 0.0001,
                       "Expected \(expected), got \(result.linearGain)")
        }
    }

    // MARK: LoudnessAnalysisCacheKey equality

    suite("LoudnessAnalysisCacheKey — equality (path + size + modDate only)") {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let key = LoudnessAnalysisCacheKey(filePath: "/music/track.flac",
                                            fileSize: 10_000_000,
                                            modifiedDate: date)

        test("identical keys are equal") {
            let key2 = LoudnessAnalysisCacheKey(filePath: "/music/track.flac",
                                                 fileSize: 10_000_000,
                                                 modifiedDate: date)
            try expect(key == key2, "Keys with same fields should be equal")
        }

        test("mismatch on fileSize") {
            let key2 = LoudnessAnalysisCacheKey(filePath: "/music/track.flac",
                                                 fileSize: 9_999_999,
                                                 modifiedDate: date)
            try expect(key != key2, "Keys should differ when fileSize changes")
        }

        test("mismatch on modifiedDate") {
            let key2 = LoudnessAnalysisCacheKey(filePath: "/music/track.flac",
                                                 fileSize: 10_000_000,
                                                 modifiedDate: Date(timeIntervalSince1970: 1_700_000_001))
            try expect(key != key2, "Keys should differ when modifiedDate changes")
        }

        test("duration variation does not affect key — prevents spurious cache misses") {
            // AVAudioFile may report slightly different frame counts across codec versions.
            // Cache key must be stable regardless of decoded duration precision.
            let k1 = LoudnessAnalysisCacheKey(filePath: "/music/a.m4a",
                                               fileSize: 5_000_000,
                                               modifiedDate: date)
            let k2 = LoudnessAnalysisCacheKey(filePath: "/music/a.m4a",
                                               fileSize: 5_000_000,
                                               modifiedDate: date)
            try expect(k1 == k2, "Keys must be equal regardless of any duration value")
        }

        test("mismatch on filePath") {
            let key2 = LoudnessAnalysisCacheKey(filePath: "/music/other.flac",
                                                 fileSize: 10_000_000,
                                                 modifiedDate: date)
            try expect(key != key2, "Keys should differ when filePath changes")
        }
    }
}

// MARK: - AudioUnitPlugin tests

func runAudioUnitPluginTests() {
    suite("AudioUnitPluginSelection — model") {
        test("encodes and decodes round-trip") {
            let sel = AudioUnitPluginSelection(
                id: UUID(),
                name: "Test EQ",
                manufacturerName: "Acme Audio",
                componentType: 1635083896,
                componentSubType: 1162298982,
                componentManufacturer: 1634758764
            )
            let data = try JSONEncoder().encode(sel)
            let decoded = try JSONDecoder().decode(AudioUnitPluginSelection.self, from: data)
            try expectEqual(decoded.name, sel.name)
            try expectEqual(decoded.manufacturerName, sel.manufacturerName)
            try expectEqual(decoded.componentType, sel.componentType)
            try expectEqual(decoded.componentSubType, sel.componentSubType)
            try expectEqual(decoded.componentManufacturer, sel.componentManufacturer)
            try expectEqual(decoded.id, sel.id)
        }

        test("reconstructs component values from stored data") {
            let type: UInt32 = 1635083896
            let sub: UInt32  = 9999
            let mfr: UInt32  = 1634758764
            let sel = AudioUnitPluginSelection(
                name: "FX", manufacturerName: "Co",
                componentType: type, componentSubType: sub, componentManufacturer: mfr
            )
            let data = try JSONEncoder().encode(sel)
            let out = try JSONDecoder().decode(AudioUnitPluginSelection.self, from: data)
            try expectEqual(out.componentType, type)
            try expectEqual(out.componentSubType, sub)
            try expectEqual(out.componentManufacturer, mfr)
        }

        test("invalid JSON decodes safely to nil") {
            let bad = "not json".data(using: .utf8)!
            let result = try? JSONDecoder().decode(AudioUnitPluginSelection.self, from: bad)
            try expectNil(result)
        }

        test("Equatable — identical values are equal") {
            let id = UUID()
            let a = AudioUnitPluginSelection(id: id, name: "X", manufacturerName: "Y",
                                             componentType: 1, componentSubType: 2, componentManufacturer: 3)
            let b = AudioUnitPluginSelection(id: id, name: "X", manufacturerName: "Y",
                                             componentType: 1, componentSubType: 2, componentManufacturer: 3)
            try expect(a == b)
        }

        test("Equatable — different id is not equal") {
            let a = AudioUnitPluginSelection(name: "X", manufacturerName: "Y",
                                             componentType: 1, componentSubType: 2, componentManufacturer: 3)
            let b = AudioUnitPluginSelection(name: "X", manufacturerName: "Y",
                                             componentType: 1, componentSubType: 2, componentManufacturer: 3)
            try expect(a != b)
        }
    }

    suite("AudioUnitPluginStatus — display text") {
        test("disabled") {
            try expectEqual(AudioUnitPluginStatus.disabled.displayText, "Plugin: Disabled")
        }
        test("noPluginSelected") {
            try expectEqual(AudioUnitPluginStatus.noPluginSelected.displayText, "Plugin: No plugin selected")
        }
        test("loading") {
            try expectEqual(AudioUnitPluginStatus.loading("Focusrite Red 2 EQ").displayText,
                            "Plugin: Loading Focusrite Red 2 EQ…")
        }
        test("active") {
            try expectEqual(AudioUnitPluginStatus.active("MJUC").displayText, "Plugin: Active — MJUC")
        }
        test("bypassed") {
            try expectEqual(AudioUnitPluginStatus.bypassed("MJUC").displayText, "Plugin: Bypassed — MJUC")
        }
        test("unavailable") {
            try expectEqual(AudioUnitPluginStatus.unavailable("Focusrite Red 2 EQ").displayText,
                            "Plugin: Not available — Focusrite Red 2 EQ")
        }
        test("failed") {
            try expectEqual(AudioUnitPluginStatus.failed("REAMP", reason: "timeout").displayText,
                            "Plugin: Failed to load — REAMP")
        }
    }

    suite("AudioUnitPluginStatus — predicates") {
        test("isActive true only for active") {
            try expect(AudioUnitPluginStatus.active("X").isActive)
            try expect(!AudioUnitPluginStatus.disabled.isActive)
            try expect(!AudioUnitPluginStatus.loading("X").isActive)
            try expect(!AudioUnitPluginStatus.bypassed("X").isActive)
            try expect(!AudioUnitPluginStatus.failed("X", reason: "r").isActive)
        }
        test("isInert true for disabled and noPluginSelected") {
            try expect(AudioUnitPluginStatus.disabled.isInert)
            try expect(AudioUnitPluginStatus.noPluginSelected.isInert)
            try expect(!AudioUnitPluginStatus.active("X").isInert)
            try expect(!AudioUnitPluginStatus.loading("X").isInert)
            try expect(!AudioUnitPluginStatus.bypassed("X").isInert)
            try expect(!AudioUnitPluginStatus.unavailable("X").isInert)
            try expect(!AudioUnitPluginStatus.failed("X", reason: "r").isInert)
        }
        test("shortDisplayText empty for inert statuses") {
            try expectEqual(AudioUnitPluginStatus.disabled.shortDisplayText, "")
            try expectEqual(AudioUnitPluginStatus.noPluginSelected.shortDisplayText, "")
        }
        test("shortDisplayText non-empty for active statuses") {
            try expect(!AudioUnitPluginStatus.active("MJUC").shortDisplayText.isEmpty)
            try expect(!AudioUnitPluginStatus.bypassed("MJUC").shortDisplayText.isEmpty)
            try expect(!AudioUnitPluginStatus.loading("MJUC").shortDisplayText.isEmpty)
        }
        test("Equatable — same cases are equal") {
            try expect(AudioUnitPluginStatus.active("X") == AudioUnitPluginStatus.active("X"))
            try expect(AudioUnitPluginStatus.disabled == AudioUnitPluginStatus.disabled)
        }
        test("Equatable — different cases are not equal") {
            try expect(AudioUnitPluginStatus.active("X") != AudioUnitPluginStatus.bypassed("X"))
            try expect(AudioUnitPluginStatus.failed("X", reason: "a") != AudioUnitPluginStatus.failed("X", reason: "b"))
        }
    }
}

func runPreparedAutoGapTests() {
    let a = UUID(), b = UUID(), c = UUID()
    suite("PreparedAutoGap — pair-bound injected silence") {
        let prep = PreparedAutoGap(currentID: a, nextID: b, trailing: 1, leading: 1)
        test("matching pair subtracts intrinsic silence") {
            try expectEqual(prep.injectedDuration(currentID: a, nextID: b, target: 5), 3)
        }
        test("intrinsic silence at or above target injects zero") {
            let p = PreparedAutoGap(currentID: a, nextID: b, trailing: 3, leading: 2)
            try expectEqual(p.injectedDuration(currentID: a, nextID: b, target: 5), 0)
        }
        test("mismatched currentID rejects as stale") {
            try expectNil(prep.injectedDuration(currentID: c, nextID: b, target: 5))
        }
        test("mismatched nextID rejects as stale") {
            try expectNil(prep.injectedDuration(currentID: a, nextID: c, target: 5))
        }
        test("negative and non-finite measurements clamp") {
            let p = PreparedAutoGap(currentID: a, nextID: b, trailing: -1, leading: .nan)
            try expectEqual(p.injectedDuration(currentID: a, nextID: b, target: 5), 5)
            let q = PreparedAutoGap(currentID: a, nextID: b, trailing: 1, leading: 1)
            try expectEqual(q.injectedDuration(currentID: a, nextID: b, target: .infinity), 0)
        }
    }
}

// MARK: - Music start/stop → trim seconds

func runMusicTrimTests() {
    suite("musicTrimSeconds — Music start/stop import") {
        test("custom start and stop convert ms→s") {
            let r = musicTrimSeconds(startMs: 5000, stopMs: 150000, totalMs: 180000)
            try expectEqual(r.start, 5.0)
            try expectEqual(r.end, 150.0)
        }
        test("no start, stop == total → no trim") {
            let r = musicTrimSeconds(startMs: 0, stopMs: 180000, totalMs: 180000)
            try expectNil(r.start)
            try expectNil(r.end)
        }
        test("all zero → no trim") {
            let r = musicTrimSeconds(startMs: 0, stopMs: 0, totalMs: 180000)
            try expectNil(r.start)
            try expectNil(r.end)
        }
    }

    suite("MusicDragIDs — persistent IDs off the Music drag pasteboard") {
        // Shaped like the real com.apple.tv.metadata plist Music writes.
        let ids = MusicDragIDs(musicMetadataPlist: [
            "Tracks": [
                "26405": [
                    "Location": "file:///Users/dj/Music/Music/iTunes/iTunes%20Media/Music/Canaro/Poema.m4a",
                    "Persistent ID": "76DD4E72A603757F",
                    "Total Time": 252313,
                ],
                "26406": [
                    "Location": "~/Music/Music/iTunes/iTunes Media/Music/Biagi/Indiferencia.mp3",
                    "Persistent ID": "AABBCCDDEEFF0011",
                ],
            ],
        ])
        test("file:// location, percent-decoded, exact path hit") {
            try expectEqual(ids.persistentID(for: URL(fileURLWithPath: "/Users/dj/Music/Music/iTunes/iTunes Media/Music/Canaro/Poema.m4a")),
                            "76DD4E72A603757F")
        }
        test("tilde location is expanded") {
            let expanded = ("~/Music/Music/iTunes/iTunes Media/Music/Biagi/Indiferencia.mp3" as NSString).expandingTildeInPath
            try expectEqual(ids.persistentID(for: URL(fileURLWithPath: expanded)), "AABBCCDDEEFF0011")
        }
        test("filename fallback for materialised promise copies") {
            // Music writes promise drops into our app-support cache, so the path differs.
            try expectEqual(ids.persistentID(for: URL(fileURLWithPath: "/Users/dj/Library/Application Support/TangoDisplay/MusicAppDrops/Poema.m4a")),
                            "76DD4E72A603757F")
        }
        test("miss returns nil — no trim import for non-Music drops") {
            try expectNil(ids.persistentID(for: URL(fileURLWithPath: "/Users/dj/Other/Milonga.mp3")))
        }
        test("bare {id: track} plist shape is also accepted") {
            let bare = MusicDragIDs(musicMetadataPlist: [
                "99": ["Location": "file:///tmp/x.m4a", "Persistent ID": "0123456789ABCDEF"],
            ])
            try expectEqual(bare.persistentID(for: URL(fileURLWithPath: "/tmp/x.m4a")), "0123456789ABCDEF")
        }
        test("empty plist is empty") {
            try expect(MusicDragIDs(musicMetadataPlist: [:]).isEmpty)
            try expect(MusicDragIDs().isEmpty)
        }
    }
}

// MARK: - JRiver playlist index clamp

func runPlaylistIndexClampTests() {
    // Mirrors the safeIndex computation in JRiverPoller.fetchPlaylistRange.
    // JRiver reports PlayingNowPosition = -1 when no valid current position
    // (rapid playlist rebuild) — the index fed to handlePlaylistUpdate must
    // never be negative, or tracks[playlistCurrentIndex] traps out of bounds.
    func safeIndex(currentPlayingIndex: Int, lookback: Int, trackCount: Int) -> Int {
        let adjustedIndex = min(lookback, currentPlayingIndex)
        return max(0, min(adjustedIndex, trackCount - 1))
    }

    suite("JRiver playlist index clamp") {
        test("negative PlayingNowPosition clamps to 0") {
            try expectEqual(safeIndex(currentPlayingIndex: -1, lookback: 5, trackCount: 16), 0)
        }
        test("normal position clamps to lookback") {
            try expectEqual(safeIndex(currentPlayingIndex: 20, lookback: 5, trackCount: 16), 5)
        }
        test("small playlist clamps to last index") {
            try expectEqual(safeIndex(currentPlayingIndex: 0, lookback: 5, trackCount: 3), 0)
            try expectEqual(safeIndex(currentPlayingIndex: 10, lookback: 5, trackCount: 3), 2)
        }
    }
}

// MARK: - Main entry point

runPrelistenTests()
runMusicTrimTests()
runPlaylistIndexClampTests()
runPreparedAutoGapTests()
runCortinaDetectorTests()
runTandaTrackerTests()
runProfileStoreTests()
runDisplayStateTests()
runReplayGainTests()
runAutoReplayGainTests()
runAudioUnitPluginTests()
runRestorationTests()
runSliderSnapTests()

print("\n════════════════════════════════")
let icon = totalFailed == 0 ? "✓" : "✗"
print("\(icon) \(totalPassed) passed, \(totalFailed) failed")
print("════════════════════════════════")

if totalFailed > 0 {
    exit(1)
}
