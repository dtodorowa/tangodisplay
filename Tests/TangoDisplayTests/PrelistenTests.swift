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
        test("a selection missing from these rows counts as All instead of hiding everything") {
            let result = browse([["3 Vals"], ["De Angelis, Alfredo"]])
            try expectEqual(result.columns[1].selection, [])
            try expectEqual(result.rows.map(\.title), ["Loca"])
        }
    }

    suite("Prelisten column browser clicks") {
        func click(_ picked: Set<String?>, column: Int, showing selections: [Set<String>]) -> [Set<String>] {
            prelistenBrowseSelections(afterPicking: picked, inColumn: column, of: browse(selections).columns)
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
        test("a click keeps what the other columns show and forgets selections they hid") {
            let result = click(["D'Arienzo, Juan"], column: 1,
                               showing: [["3 Vals"], ["De Angelis, Alfredo"], ["Echagüe, Juan Carlos"]])
            try expectEqual(result, [["3 Vals"], ["D'Arienzo, Juan"], []])
        }
    }
}
