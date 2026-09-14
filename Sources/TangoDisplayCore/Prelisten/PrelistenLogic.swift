import Foundation

// Pure logic behind the Prelisten window: nesting Music playlists, walking a queue by
// position, filtering rows. Kept free of iTunesLibrary so the test runner can cover it.

/// One Music playlist or folder as read from the library, before nesting.
public struct PrelistenPlaylistSummary: Equatable {
    public let id: String
    public let parentID: String?
    public let name: String
    public let isFolder: Bool
    public let isSmart: Bool

    public init(id: String, parentID: String?, name: String, isFolder: Bool, isSmart: Bool) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.isFolder = isFolder
        self.isSmart = isSmart
    }
}

public struct PrelistenPlaylistNode: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let isFolder: Bool
    public let isSmart: Bool
    /// nil for playlists so OutlineGroup draws no disclosure triangle; [] for an empty folder.
    public let children: [PrelistenPlaylistNode]?
}

/// Nests playlists under their folders, folders first and names in Finder order, the way
/// Music's sidebar shows them. A playlist whose folder isn't in the list stays at the top
/// level rather than disappearing.
public func buildPrelistenPlaylistTree(_ summaries: [PrelistenPlaylistSummary]) -> [PrelistenPlaylistNode] {
    let folderIDs = Set(summaries.lazy.filter(\.isFolder).map(\.id))
    var childrenByFolder: [String: [PrelistenPlaylistSummary]] = [:]
    var roots: [PrelistenPlaylistSummary] = []
    for summary in summaries {
        if let parent = summary.parentID, parent != summary.id, folderIDs.contains(parent) {
            childrenByFolder[parent, default: []].append(summary)
        } else {
            roots.append(summary)
        }
    }

    func sorted(_ list: [PrelistenPlaylistSummary]) -> [PrelistenPlaylistSummary] {
        list.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    func node(for summary: PrelistenPlaylistSummary) -> PrelistenPlaylistNode {
        PrelistenPlaylistNode(
            id: summary.id, name: summary.name, isFolder: summary.isFolder, isSmart: summary.isSmart,
            children: summary.isFolder ? sorted(childrenByFolder[summary.id] ?? []).map(node(for:)) : nil)
    }

    return sorted(roots).map(node(for:))
}

// MARK: - Queue navigation

/// Next stop in the queue, or nil at the end. Positions, never track identity: Music.app
/// resolves "what's next" by track, which is why a song listed twice makes it jump.
public func prelistenNextIndex(after current: Int, count: Int) -> Int? {
    let next = current + 1
    return next < count ? next : nil
}

public enum PrelistenPreviousAction: Equatable {
    case restart
    case play(Int)
}

/// Like Music: Previous restarts the track once it has played a few seconds, and goes back
/// a track only near the start.
public func prelistenPreviousAction(current: Int, elapsed: Double,
                                    restartAfter threshold: Double = 3) -> PrelistenPreviousAction {
    if elapsed > threshold || current == 0 { return .restart }
    return .play(current - 1)
}

// MARK: - Filtering and display

/// Every word of the query has to appear in one of the fields, ignoring case and accents,
/// so "pena canaro" finds "Peña Mulata" by Francisco Canaro.
public func prelistenRowMatches(_ query: String, fields: [String]) -> Bool {
    let words = query.split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return true }
    let haystack = fields.joined(separator: " ")
    return words.allSatisfy {
        haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

public struct PrelistenYearRange: Equatable {
    public let from: Int?
    public let to: Int?

    public init(from: Int?, to: Int?) {
        self.from = from
        self.to = to
    }

    public var isUnbounded: Bool { from == nil && to == nil }

    /// Inclusive, and bounds typed the wrong way round still work. A row without a year drops
    /// out once a bound is set, since it can't be shown to be in range.
    public func contains(_ year: Int?) -> Bool {
        if isUnbounded { return true }
        guard let year else { return false }
        var low = from ?? .min, high = to ?? .max
        if low > high { swap(&low, &high) }
        return (low...high).contains(year)
    }
}

/// Reads the Years field: "35-38", "1935–1945", "40" for one year, "40-" or "-45" for an open
/// end. Two digits mean 19xx, where most tango recordings are; later years need four digits.
/// A half-typed year like "194" sets no bound, so the list doesn't empty while typing.
public func prelistenYearRange(_ text: String) -> PrelistenYearRange {
    func year(_ part: Substring) -> Int? {
        let digits = part.trimmingCharacters(in: .whitespaces)
        guard digits.allSatisfy(\.isASCII), let value = Int(digits) else { return nil }
        switch digits.count {
        case 2: return 1900 + value
        case 4: return value
        default: return nil
        }
    }
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        .flatMap { $0.split(separator: "–", omittingEmptySubsequences: false) }
    switch parts.count {
    case 1: return PrelistenYearRange(from: year(parts[0]), to: year(parts[0]))
    case 2: return PrelistenYearRange(from: year(parts[0]), to: year(parts[1]))
    default: return PrelistenYearRange(from: nil, to: nil)
    }
}

// MARK: - Column browser

/// A list the column browser can show. Raw values are what gets stored.
public enum PrelistenBrowseField: String, CaseIterable {
    case genre, artist, composer, album, grouping, comment

    public static let standard: [PrelistenBrowseField] = [.genre, .artist, .album, .comment]
}

/// Reads the stored comma-separated lists. Unknown and repeated names are skipped, and
/// nothing usable gives the standard lists, so the browser always has something to right-click.
public func prelistenBrowseFields(stored: String) -> [PrelistenBrowseField] {
    var seen = Set<PrelistenBrowseField>()
    let fields = stored.split(separator: ",")
        .compactMap { PrelistenBrowseField(rawValue: String($0)) }
        .filter { seen.insert($0).inserted }
    return fields.isEmpty ? PrelistenBrowseField.standard : fields
}

/// Hides a shown list or shows a hidden one. A list being shown goes after the last shown
/// list that comes before it in `allCases`, so it lands in its usual place even after moves.
/// The last list stays: with none left there'd be nothing to right-click to get one back.
public func prelistenTogglingBrowseField(_ field: PrelistenBrowseField,
                                         in fields: [PrelistenBrowseField]) -> [PrelistenBrowseField] {
    var result = fields
    if let index = fields.firstIndex(of: field) {
        if fields.count > 1 { result.remove(at: index) }
        return result
    }
    let earlier = PrelistenBrowseField.allCases.prefix { $0 != field }
    let position = fields.lastIndex { earlier.contains($0) }.map { $0 + 1 } ?? 0
    result.insert(field, at: position)
    return result
}

public func prelistenMovingBrowseField(_ field: PrelistenBrowseField, by offset: Int,
                                       in fields: [PrelistenBrowseField]) -> [PrelistenBrowseField] {
    guard let index = fields.firstIndex(of: field) else { return fields }
    var result = fields
    result.remove(at: index)
    result.insert(field, at: min(max(index + offset, 0), result.count))
    return result
}

public struct PrelistenBrowseColumn: Equatable {
    /// Distinct non-blank values among the rows the columns to the left leave, plus picked
    /// values that have none, in Finder order.
    public let values: [String]
    /// Empty means All.
    public let selection: Set<String>
    /// Picked values no row has anymore.
    public let unmatched: Set<String>
}

public struct PrelistenBrowseResult<Row> {
    public let columns: [PrelistenBrowseColumn]
    public let rows: [Row]
}

/// Music's column browser: each column lists what the columns to its left leave, and the rows
/// are what all of them leave. A pick keeps filtering when no row has its value anymore, for
/// example after typing in the filter field, and stays listed. The empty result then has a
/// visible cause, where falling back to All would quietly show other singers.
public func prelistenBrowse<Row>(_ rows: [Row], by fields: [(Row) -> String],
                                 selections: [Set<String>]) -> PrelistenBrowseResult<Row> {
    var remaining = rows
    var columns: [PrelistenBrowseColumn] = []
    for (index, field) in fields.enumerated() {
        let distinct = browseValues(remaining, field)
        let selection = index < selections.count ? selections[index] : []
        columns.append(PrelistenBrowseColumn(
            values: distinct.union(selection).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            selection: selection,
            unmatched: selection.subtracting(distinct)))
        if !selection.isEmpty {
            remaining = remaining.filter { selection.contains(browseValue($0, field)) }
        }
    }
    return PrelistenBrowseResult(columns: columns, rows: remaining)
}

/// Applies a click in one column's list. `picked` is that list's new selection, nil standing
/// for its All row. All and values exclude each other: picking All clears the column, picking
/// a value while All shows replaces it. Picks to the right that the new pick leaves without
/// rows are dropped, so switching orchestra doesn't keep the last one's singer picked.
/// Pass the rows before any text or year filter, so only the columns decide what's dropped.
public func prelistenBrowseSelections<Row>(afterPicking picked: Set<String?>, inColumn index: Int,
                                           selections: [Set<String>], rows: [Row],
                                           by fields: [(Row) -> String]) -> [Set<String>] {
    var result = fields.indices.map { $0 < selections.count ? selections[$0] : [] }
    guard result.indices.contains(index) else { return result }
    result[index] = picked.contains(nil) && !result[index].isEmpty ? [] : Set(picked.compactMap { $0 })
    var remaining = rows
    for (column, field) in fields.enumerated() {
        if column > index {
            result[column].formIntersection(browseValues(remaining, field))
        }
        let selection = result[column]
        if !selection.isEmpty {
            remaining = remaining.filter { selection.contains(browseValue($0, field)) }
        }
    }
    return result
}

/// What one list shows while its search field has text: values matching every word, ignoring
/// case and accents, plus picked values, so a pick that's filtering the rows never hides.
public func prelistenBrowseListValues(_ column: PrelistenBrowseColumn, search: String) -> [String] {
    column.values.filter { column.selection.contains($0) || prelistenRowMatches(search, fields: [$0]) }
}

private func browseValue<Row>(_ row: Row, _ field: (Row) -> String) -> String {
    field(row).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func browseValues<Row>(_ rows: [Row], _ field: (Row) -> String) -> Set<String> {
    var values = Set<String>()
    for row in rows {
        let value = browseValue(row, field)
        if !value.isEmpty { values.insert(value) }
    }
    return values
}

public func formatPrelistenTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}
