import Foundation
import TangoDisplayCore

func runPrelistenTests() {
    func playlist(_ id: String, _ name: String, parent: String? = nil,
                  folder: Bool = false) -> PrelistenPlaylistSummary {
        PrelistenPlaylistSummary(id: id, parentID: parent, name: name, isFolder: folder, isSmart: false)
    }

    suite("Prelisten playlist tree") {
        test("playlists nest under their folder") {
            let tree = buildPrelistenPlaylistTree([
                playlist("F", "Milongas", folder: true),
                playlist("A", "Canaro tanda", parent: "F"),
            ])
            try expectEqual(tree.map(\.id), ["F"])
            try expectEqual(tree[0].children?.map(\.id), ["A"])
        }
        test("folders first, then names in Finder order") {
            let tree = buildPrelistenPlaylistTree([
                playlist("p10", "Tanda 10"),
                playlist("p2", "Tanda 2"),
                playlist("f", "Zzz", folder: true),
            ])
            try expectEqual(tree.map(\.id), ["f", "p2", "p10"])
        }
        test("playlist whose folder is missing stays at the top level") {
            let tree = buildPrelistenPlaylistTree([playlist("A", "Orphan", parent: "gone")])
            try expectEqual(tree.map(\.id), ["A"])
        }
        test("a playlist can't act as a folder") {
            let tree = buildPrelistenPlaylistTree([
                playlist("A", "List"),
                playlist("B", "Child", parent: "A"),
            ])
            try expectEqual(Set(tree.map(\.id)), ["A", "B"])
            try expect(tree.allSatisfy { $0.children == nil })
        }
        test("empty folders get an empty children array, playlists get none") {
            let tree = buildPrelistenPlaylistTree([
                playlist("F", "Empty", folder: true),
                playlist("A", "List"),
            ])
            try expectEqual(tree[0].children?.count, 0)
            try expectNil(tree[1].children)
        }
    }

    suite("Prelisten queue navigation") {
        test("next walks by position, so a repeated track is its own stop") {
            try expectEqual(prelistenNextIndex(after: 1, count: 4), 2)
            try expectNil(prelistenNextIndex(after: 3, count: 4))
        }
        test("previous restarts once the track has played a few seconds") {
            try expectEqual(prelistenPreviousAction(current: 2, elapsed: 5), .restart)
        }
        test("previous goes back a track near the start") {
            try expectEqual(prelistenPreviousAction(current: 2, elapsed: 1), .play(1))
        }
        test("previous on the first track restarts it") {
            try expectEqual(prelistenPreviousAction(current: 0, elapsed: 0), .restart)
        }
    }

    suite("Prelisten filter and time") {
        test("empty filter matches everything") {
            try expect(prelistenRowMatches("  ", fields: ["Poema"]))
        }
        test("every word must match, ignoring case and accents") {
            let fields = ["Peña Mulata", "Francisco Canaro", "Tango", "1937"]
            try expect(prelistenRowMatches("pena canaro", fields: fields))
            try expect(!prelistenRowMatches("pena biagi", fields: fields))
        }
        test("time formatting") {
            try expectEqual(formatPrelistenTime(0), "0:00")
            try expectEqual(formatPrelistenTime(65.9), "1:05")
            try expectEqual(formatPrelistenTime(3725), "1:02:05")
            try expectEqual(formatPrelistenTime(.nan), "0:00")
        }
    }

    struct Row: Equatable {
        let title: String, genre: String, artist: String, comment: String
    }
    let rows = [
        Row(title: "Pregonera", genre: "Tango", artist: "De Angelis, Alfredo", comment: "Dante, Carlos"),
        Row(title: "Paciencia", genre: "Tango", artist: "D'Arienzo, Juan", comment: "Echagüe, Juan Carlos"),
        Row(title: "La bruja", genre: "Tango", artist: "D'Arienzo, Juan", comment: " Mauré, Héctor "),
        Row(title: "Pensalo bien", genre: "Tango", artist: "D'Arienzo, Juan", comment: "Echagüe, Juan Carlos"),
        Row(title: "Loca", genre: "3 Vals", artist: "D'Arienzo, Juan", comment: ""),
        Row(title: "Paciencia", genre: "Tango", artist: "D'Arienzo, Juan", comment: "Echagüe, Juan Carlos"),
    ]
    let fields: [(Row) -> String] = [{ $0.genre }, { $0.artist }, { $0.comment }]
    func browse(_ selections: [Set<String>]) -> PrelistenBrowseResult<Row> {
        prelistenBrowse(rows, by: fields, selections: selections)
    }

    suite("Prelisten column browser") {
        test("nothing selected lists each column's values in Finder order and keeps every row") {
            let result = browse([])
            try expectEqual(result.columns.map(\.values), [
                ["3 Vals", "Tango"],
                ["D'Arienzo, Juan", "De Angelis, Alfredo"],
                ["Dante, Carlos", "Echagüe, Juan Carlos", "Mauré, Héctor"],
            ])
            try expectEqual(result.rows, rows)
            try expect(result.columns.allSatisfy { $0.selection.isEmpty })
        }
        test("a blank value isn't listed, but its row still shows under All") {
            let result = browse([])
            try expect(!result.columns[2].values.contains(""))
            try expect(result.rows.contains { $0.title == "Loca" })
        }
        test("picking a value narrows the columns to its right and the rows") {
            let result = browse([[], ["D'Arienzo, Juan"]])
            try expectEqual(result.columns[0].values, ["3 Vals", "Tango"])
            try expectEqual(result.columns[2].values, ["Echagüe, Juan Carlos", "Mauré, Héctor"])
            try expectEqual(result.rows.map(\.title), ["Paciencia", "La bruja", "Pensalo bien", "Loca", "Paciencia"])
        }
        test("filtering by singer keeps a repeated track as two rows") {
            let result = browse([[], [], ["Echagüe, Juan Carlos"]])
            try expectEqual(result.rows.map(\.title), ["Paciencia", "Pensalo bien", "Paciencia"])
        }
        test("several values in one column match any of them") {
            let result = browse([[], [], ["Dante, Carlos", "Mauré, Héctor"]])
            try expectEqual(result.rows.map(\.title), ["Pregonera", "La bruja"])
        }
        test("surrounding spaces don't make a separate value") {
            let result = browse([[], [], ["Mauré, Héctor"]])
            try expectEqual(result.rows.map(\.title), ["La bruja"])
        }
        test("a pick with no rows left stays listed and picked, so an empty list has a visible reason") {
            let result = browse([["3 Vals"], ["De Angelis, Alfredo"]])
            try expectEqual(result.columns[1].values, ["D'Arienzo, Juan", "De Angelis, Alfredo"])
            try expectEqual(result.columns[1].selection, ["De Angelis, Alfredo"])
            try expectEqual(result.columns[1].unmatched, ["De Angelis, Alfredo"])
            try expectEqual(result.rows, [])
        }
        test("a pick that has rows isn't unmatched") {
            try expectEqual(browse([[], ["D'Arienzo, Juan"]]).columns[1].unmatched, [])
        }
    }

    suite("Prelisten column browser clicks") {
        func click(_ picked: Set<String?>, column: Int, showing selections: [Set<String>]) -> [Set<String>] {
            prelistenBrowseSelections(afterPicking: picked, inColumn: column, selections: selections,
                                      rows: rows, by: fields)
        }
        test("clicking a value while All shows selects just that value") {
            try expectEqual(click(["Tango"], column: 0, showing: []), [["Tango"], [], []])
            try expectEqual(click([nil, "Tango"], column: 0, showing: []), [["Tango"], [], []])
        }
        test("clicking All clears the column, with or without ⌘") {
            try expectEqual(click([nil], column: 0, showing: [["Tango"]]), [[], [], []])
            try expectEqual(click([nil, "Tango"], column: 0, showing: [["Tango"]]), [[], [], []])
        }
        test("⌘-click adds a value, and deselecting the last one goes back to All") {
            try expectEqual(click(["Tango", "3 Vals"], column: 0, showing: [["Tango"]]),
                            [["Tango", "3 Vals"], [], []])
            try expectEqual(click([], column: 0, showing: [["Tango"]]), [[], [], []])
        }
        test("a click drops picks to its right that the new pick leaves without rows") {
            let result = click(["De Angelis, Alfredo"], column: 1,
                               showing: [["Tango"], ["D'Arienzo, Juan"], ["Echagüe, Juan Carlos"]])
            try expectEqual(result, [["Tango"], ["De Angelis, Alfredo"], []])
        }
        test("a click keeps picks to its right that still have rows") {
            let result = click(["D'Arienzo, Juan", "De Angelis, Alfredo"], column: 1,
                               showing: [["Tango"], ["D'Arienzo, Juan"], ["Echagüe, Juan Carlos"]])
            try expectEqual(result, [["Tango"], ["D'Arienzo, Juan", "De Angelis, Alfredo"], ["Echagüe, Juan Carlos"]])
        }
        test("a click never drops picks to its left") {
            try expectEqual(click(["Dante, Carlos"], column: 2, showing: [["3 Vals"]]),
                            [["3 Vals"], [], ["Dante, Carlos"]])
        }
    }

    suite("Prelisten list search") {
        let singers = browse([[], [], ["Dante, Carlos"]]).columns[2]
        test("a blank search shows every value") {
            try expectEqual(prelistenBrowseListValues(singers, search: " "), singers.values)
        }
        test("search ignores case and accents") {
            try expectEqual(prelistenBrowseListValues(browse([]).columns[2], search: "echague"),
                            ["Echagüe, Juan Carlos"])
        }
        test("picked values stay in the list while searching") {
            try expectEqual(prelistenBrowseListValues(singers, search: "maure"), ["Dante, Carlos", "Mauré, Héctor"])
        }
    }

    suite("Prelisten year range") {
        func years(_ from: Int?, _ to: Int?) -> PrelistenYearRange { PrelistenYearRange(from: from, to: to) }
        test("a blank field sets no range and lets every row through, with or without a year") {
            try expectEqual(prelistenYearRange(" "), years(nil, nil))
            try expect(prelistenYearRange("").contains(nil))
            try expect(prelistenYearRange("").contains(1937))
        }
        test("two-digit years mean 19xx, so 35-38 is 1935 to 1938") {
            try expectEqual(prelistenYearRange("35-38"), years(1935, 1938))
        }
        test("four-digit years, spaces and en dashes work too") {
            try expectEqual(prelistenYearRange("1935 – 1945"), years(1935, 1945))
            try expectEqual(prelistenYearRange("35-2005"), years(1935, 2005))
        }
        test("one year means just that year") {
            try expectEqual(prelistenYearRange("40"), years(1940, 1940))
        }
        test("either end can be left open") {
            try expectEqual(prelistenYearRange("40-"), years(1940, nil))
            try expectEqual(prelistenYearRange("-45"), years(nil, 1945))
            try expect(prelistenYearRange("40-").contains(1950))
            try expect(!prelistenYearRange("40-").contains(1939))
        }
        test("bounds are inclusive, and typed backwards still work") {
            let range = prelistenYearRange("45-35")
            try expect(range.contains(1935))
            try expect(range.contains(1945))
            try expect(!range.contains(1946))
        }
        test("a row without a year drops out once a range is set") {
            try expect(!prelistenYearRange("35-45").contains(nil))
        }
        test("half-typed or unreadable years set no bound, so typing doesn't empty the list") {
            try expectEqual(prelistenYearRange("194"), years(nil, nil))
            try expectEqual(prelistenYearRange("1935-194"), years(1935, nil))
            try expectEqual(prelistenYearRange("abc"), years(nil, nil))
            try expectEqual(prelistenYearRange("35-38-40"), years(nil, nil))
        }
    }

    suite("Prelisten column browser lists") {
        let standard: [PrelistenBrowseField] = [.genre, .artist, .album, .comment]
        test("stored lists read back in order, skipping unknown and repeated names") {
            try expectEqual(prelistenBrowseFields(stored: "comment,artist,bogus,artist"), [.comment, .artist])
        }
        test("nothing usable stored falls back to Genres, Artists, Albums, Comments") {
            try expectEqual(prelistenBrowseFields(stored: ""), standard)
            try expectEqual(prelistenBrowseFields(stored: "bogus"), standard)
        }
        test("showing a list puts it back in its usual place") {
            try expectEqual(prelistenTogglingBrowseField(.composer, in: standard),
                            [.genre, .artist, .composer, .album, .comment])
            try expectEqual(prelistenTogglingBrowseField(.artist, in: [.album, .genre]), [.album, .genre, .artist])
            try expectEqual(prelistenTogglingBrowseField(.genre, in: [.album]), [.genre, .album])
        }
        test("hiding a list removes it, but the last one stays") {
            try expectEqual(prelistenTogglingBrowseField(.album, in: standard), [.genre, .artist, .comment])
            try expectEqual(prelistenTogglingBrowseField(.genre, in: [.genre]), [.genre])
        }
        test("moving a list stops at either end") {
            try expectEqual(prelistenMovingBrowseField(.album, by: -1, in: standard),
                            [.genre, .album, .artist, .comment])
            try expectEqual(prelistenMovingBrowseField(.genre, by: -1, in: standard), standard)
            try expectEqual(prelistenMovingBrowseField(.comment, by: 1, in: standard), standard)
        }
    }
}
