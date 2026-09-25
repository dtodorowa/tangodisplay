import Foundation
import TangoDisplayCore

func runUpcomingOverrideTests() {
    // Mirrors the fallback expression used by CortinaView / resolveCustomPlaceholders:
    // a blank override field falls through to the real metadata.
    func shown(_ o: UpcomingOverride?, real: String) -> String { o?.artistValue ?? real }

    suite("UpcomingOverride — blank means fall back") {
        test("nil override shows real metadata") {
            try expectEqual(shown(nil, real: "Di Sarli"), "Di Sarli")
        }
        test("empty field shows real metadata") {
            try expectEqual(shown(UpcomingOverride(artist: ""), real: "Di Sarli"), "Di Sarli")
        }
        test("whitespace-only field shows real metadata") {
            try expectEqual(shown(UpcomingOverride(artist: "   "), real: "Di Sarli"), "Di Sarli")
        }
        test("filled field replaces real metadata") {
            try expectEqual(shown(UpcomingOverride(artist: "Mixed Tanda"), real: "Di Sarli"), "Mixed Tanda")
        }
        test("value is trimmed") {
            try expectEqual(shown(UpcomingOverride(artist: "  Mixed  "), real: "Di Sarli"), "Mixed")
        }
        test("fields are independent — artist set, singer and year fall back") {
            let o = UpcomingOverride(artist: "Mixed Tanda")
            try expectEqual(o.artistValue, "Mixed Tanda")
            try expectNil(o.singerValue)
            try expectNil(o.yearValue)
        }
    }

    suite("UpcomingOverride — isEmpty (drives clear-down to nil)") {
        test("all nil is empty") {
            try expect(UpcomingOverride().isEmpty)
        }
        test("all blank is empty") {
            try expect(UpcomingOverride(artist: "", singer: "  ", year: "").isEmpty)
        }
        test("any filled field is not empty") {
            try expect(!UpcomingOverride(year: "1941-43").isEmpty)
            try expect(!UpcomingOverride(singer: "various").isEmpty)
        }
    }

    suite("UpcomingOverride — persistence") {
        test("free-text year survives a JSON round-trip") {
            let o = UpcomingOverride(artist: "Mixed Tanda", singer: "Various", year: "1935-52")
            let decoded = try JSONDecoder().decode(
                UpcomingOverride.self, from: try JSONEncoder().encode(o))
            try expectEqual(decoded, o)
            try expectEqual(decoded.yearValue, "1935-52")
        }
        test("decodes from a partial object — older/sparser JSON") {
            let data = #"{"artist":"Mixed Tanda"}"#.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(UpcomingOverride.self, from: data)
            try expectEqual(decoded.artistValue, "Mixed Tanda")
            try expectNil(decoded.singerValue)
        }
    }
}
