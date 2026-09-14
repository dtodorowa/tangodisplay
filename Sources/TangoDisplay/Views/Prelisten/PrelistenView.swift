import AppKit
import SwiftUI
import TangoDisplayCore

enum PrelistenDefaults {
    static let docked = "prelistenDocked"
    static let dockEdge = "prelistenDockEdge"
    static let dockFraction = "prelistenDockFraction"
    static let columnBrowser = "prelistenColumnBrowser"
    static let browseFields = "prelistenBrowseFields"
    static let trackColumns = "prelistenTrackColumns"
}

enum PrelistenDockEdge: String {
    case leading, trailing, bottom
}

extension NSPasteboard.PasteboardType {
    /// Marks rows dragged out of Prelisten. The setlist's window-wide drop catch-all skips
    /// them; otherwise letting go anywhere over the docked pane would add the tracks.
    static let prelistenRow = NSPasteboard.PasteboardType("com.tangodisplay.prelisten-row")
    /// Music-shaped track plist put on the clipboard by ⌘C, read by the setlist's paste so
    /// start/stop times come along. Our own type rather than Music's, so pasting into Music
    /// never sees half a Music plist.
    static let prelistenMetadata = NSPasteboard.PasteboardType("com.tangodisplay.prelisten-metadata")
}

// MARK: - Pane

/// Music playlists on the left (or in a menu when narrow), the playing track and the
/// selected playlist on the right. Used both docked in the main window and as its own window.
struct PrelistenPane: View {
    enum Presentation { case window, docked }

    let presentation: Presentation
    @ObservedObject var library: MusicLibraryBrowser
    @ObservedObject var player: PrelistenPlayer
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PrelistenDefaults.docked) private var docked = false
    @AppStorage(PrelistenDefaults.dockEdge) private var dockEdge: PrelistenDockEdge = .leading
    @State private var selectedRowIDs = Set<PrelistenRow.ID>()
    @State private var filter = ""
    @State private var yearFrom = ""
    @State private var yearTo = ""
    /// Keyed by list rather than position, so a pick survives moving its list.
    @State private var browseSelections: [PrelistenBrowseField: Set<String>] = [:]
    @AppStorage(PrelistenDefaults.columnBrowser) private var showColumnBrowser = true
    @AppStorage(PrelistenDefaults.browseFields) private var storedBrowseFields = ""
    @AppStorage(PrelistenDefaults.trackColumns) private var trackColumnsData = Data()
    @FocusState private var tableFocused: Bool
    @State private var copyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if presentation == .docked {
                dockHeader
                Divider()
            }
            GeometryReader { geo in
                if geo.size.width >= 640 {
                    HStack(spacing: 0) {
                        playlistSidebar
                            .frame(width: min(260, max(180, geo.size.width * 0.25)))
                        Divider()
                        detail(compact: false, height: geo.size.height)
                    }
                } else {
                    detail(compact: true, height: geo.size.height)
                }
            }
        }
        .toolbar {
            if presentation == .window {
                ToolbarItem {
                    Button {
                        let ownWindow = NSApp.keyWindow
                        docked = true
                        WindowManager.showControlWindow()
                        ownWindow?.close()
                    } label: {
                        Label("Dock in Main Window", systemImage: "rectangle.righthalf.inset.filled")
                    }
                    .help("Show Prelisten inside the main window instead")
                }
            }
        }
        .onAppear {
            library.loadIfNeeded()
            // Same approach as the setlist's ⌘V: a SwiftUI Table has no dependable copy hook.
            guard copyMonitor == nil else { return }
            copyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard tableFocused,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "c",
                      !(NSApp.keyWindow?.firstResponder is NSText),
                      copyToPasteboard(selectedRowIDs, from: visibleRows) else { return event }
                return nil
            }
        }
        .onDisappear {
            if let monitor = copyMonitor {
                NSEvent.removeMonitor(monitor)
                copyMonitor = nil
            }
        }
        .onChange(of: library.selectedPlaylistID) { _ in
            selectedRowIDs.removeAll()
            // A singer picked in one playlist would otherwise quietly narrow the next.
            browseSelections = [:]
        }
    }

    private var setlistIsPlaying: Bool {
        appState.currentPlayerState == .playing || appState.currentPlayerState == .pauseArmed
    }

    private var dockHeader: some View {
        HStack(spacing: 10) {
            Label("Prelisten", systemImage: "headphones")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Picker("Position", selection: $dockEdge) {
                Image(systemName: "rectangle.lefthalf.inset.filled")
                    .help("Dock on the left")
                    .tag(PrelistenDockEdge.leading)
                Image(systemName: "rectangle.righthalf.inset.filled")
                    .help("Dock on the right")
                    .tag(PrelistenDockEdge.trailing)
                Image(systemName: "rectangle.bottomhalf.inset.filled")
                    .help("Dock at the bottom")
                    .tag(PrelistenDockEdge.bottom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 108)
            Button {
                docked = false
                openWindow(id: "prelisten")
            } label: {
                Image(systemName: "macwindow.on.rectangle")
            }
            .help("Open Prelisten in its own window")
            Button {
                docked = false
            } label: {
                Image(systemName: "xmark")
            }
            .help("Hide Prelisten (⌘⇧L)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: Playlists

    private var playlistSidebar: some View {
        List(selection: $library.selectedPlaylistID) {
            OutlineGroup(library.playlists, children: \.children) { node in
                Label(node.name, systemImage: node.icon)
                    .tag(node.id)
            }
        }
        .listStyle(.sidebar)
    }

    private var playlistMenu: some View {
        Menu {
            PrelistenPlaylistMenuItems(nodes: library.playlists) { library.selectedPlaylistID = $0 }
        } label: {
            Label(library.selectedPlaylistName ?? "Choose a playlist", systemImage: "music.note.list")
        }
        .disabled(library.playlists.isEmpty)
    }

    // MARK: Tracks

    private func detail(compact: Bool, height: CGFloat) -> some View {
        let browse = browseResult
        return VStack(spacing: 0) {
            PrelistenTransportBar(player: player, clock: player.clock,
                                  devices: appState.availableAudioOutputDevices,
                                  setlistIsPlaying: setlistIsPlaying)
            Divider()
            browseBar(compact: compact, rows: browse.rows)
            Divider()
            if showColumnBrowser && library.selectedPlaylistID != nil {
                // A search field and about five values per list; less when a docked pane is short.
                columnBrowser(browse.columns)
                    .frame(height: min(180, max(90, height * 0.4)))
                Divider()
            }
            trackTable(browse.rows)
        }
    }

    private func browseBar(compact: Bool, rows: [PrelistenRow]) -> some View {
        HStack(spacing: 8) {
            if compact {
                playlistMenu
                    .frame(maxWidth: 220)
            }
            TextField("Filter tracks", text: $filter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            yearRange
            Toggle(isOn: $showColumnBrowser) {
                Image(systemName: "rectangle.split.3x1")
            }
            .toggleStyle(.button)
            .help(showColumnBrowser ? "Hide Column Browser" : "Show Column Browser")
            Spacer(minLength: 0)
            Button {
                addToSetlist(selectedRowIDs, from: rows)
            } label: {
                Label("Add to Setlist", systemImage: "text.badge.plus")
            }
            .disabled(urls(for: selectedRowIDs, in: rows).isEmpty)
            .help("Append the selected tracks to the setlist")
            Button {
                library.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(library.status == .loading)
            .help("Read playlists from Music again")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var yearRange: some View {
        HStack(spacing: 4) {
            TextField("From", text: $yearFrom)
                .frame(width: 50)
            Text("–")
                .foregroundColor(.secondary)
            TextField("To", text: $yearTo)
                .frame(width: 50)
        }
        .textFieldStyle(.roundedBorder)
        .help("Only tracks from these years. Leave a side empty to leave it open.")
    }

    private var browseFields: [PrelistenBrowseField] { prelistenBrowseFields(stored: storedBrowseFields) }

    private var visibleRows: [PrelistenRow] { browseResult.rows }

    /// Text and years narrow the rows, then the lists are built from what's left, the way
    /// Music's search narrows its column browser. Picks stay strict, so a picked singer the
    /// filter hides leaves the list empty instead of showing other singers.
    private var browseResult: PrelistenBrowseResult<PrelistenRow> {
        let from = Int(yearFrom.trimmingCharacters(in: .whitespaces))
        let to = Int(yearTo.trimmingCharacters(in: .whitespaces))
        let matching = filter.isEmpty && from == nil && to == nil ? library.rows : library.rows.filter { row in
            prelistenYearInRange(row.year, from: from, to: to)
                && prelistenRowMatches(filter, fields: [row.title, row.artist, row.album, row.composer,
                                                        row.genre, row.year.map(String.init) ?? "",
                                                        row.grouping ?? "", row.comment ?? ""])
        }
        // A hidden browser doesn't filter: nothing on screen would explain the missing rows.
        let fields = showColumnBrowser ? browseFields : []
        return prelistenBrowse(matching, by: browseValues(fields),
                               selections: fields.map { browseSelections[$0] ?? [] })
    }

    private func browseValues(_ fields: [PrelistenBrowseField]) -> [(PrelistenRow) -> String] {
        fields.map { field in { field.value(of: $0) } }
    }

    private func columnBrowser(_ columns: [PrelistenBrowseColumn]) -> some View {
        let fields = browseFields
        return HStack(spacing: 0) {
            ForEach(fields, id: \.self) { field in
                let index = fields.firstIndex(of: field) ?? 0
                if index > 0 { Divider() }
                if index < columns.count {
                    let count = columns[index].values.count - columns[index].unmatched.count
                    PrelistenBrowseColumnList(
                        title: field.title,
                        allLabel: "All (\(count) \(count == 1 ? field.singular : field.title))",
                        column: columns[index],
                        pick: { pickBrowseValues($0, inColumn: index, of: fields) },
                        menu: { browseListMenu(for: field, in: fields) })
                    // A new playlist starts with empty list searches, as it does with no picks.
                    .id(library.selectedPlaylistID)
                }
            }
        }
    }

    private func pickBrowseValues(_ picked: Set<String?>, inColumn index: Int, of fields: [PrelistenBrowseField]) {
        let updated = prelistenBrowseSelections(
            afterPicking: picked, inColumn: index, selections: fields.map { browseSelections[$0] ?? [] },
            rows: library.rows, by: browseValues(fields))
        for (field, selection) in zip(fields, updated) {
            browseSelections[field] = selection
        }
    }

    @ViewBuilder
    private func browseListMenu(for field: PrelistenBrowseField, in fields: [PrelistenBrowseField]) -> some View {
        ForEach(PrelistenBrowseField.allCases, id: \.self) { candidate in
            Toggle(candidate.title, isOn: Binding(
                get: { fields.contains(candidate) },
                set: { _ in setBrowseFields(prelistenTogglingBrowseField(candidate, in: fields)) }))
            .disabled(fields == [candidate])
        }
        Divider()
        Button("Move \(field.title) Left") {
            setBrowseFields(prelistenMovingBrowseField(field, by: -1, in: fields))
        }
        .disabled(fields.first == field)
        Button("Move \(field.title) Right") {
            setBrowseFields(prelistenMovingBrowseField(field, by: 1, in: fields))
        }
        .disabled(fields.last == field)
        Divider()
        Button("Hide Column Browser") { showColumnBrowser = false }
    }

    private func setBrowseFields(_ fields: [PrelistenBrowseField]) {
        storedBrowseFields = fields.map(\.rawValue).joined(separator: ",")
        // A list taken away mustn't keep filtering from off screen.
        browseSelections = browseSelections.filter { fields.contains($0.key) }
    }

    private func trackTable(_ rows: [PrelistenRow]) -> some View {
        Group {
            if #available(macOS 14.0, *) {
                // Right-clicking the header hides and shows columns; dragging one reorders.
                Table(of: PrelistenRow.self, selection: $selectedRowIDs, columnCustomization: trackColumns) {
                    customizableColumns
                } rows: {
                    ForEach(rows) { row in
                        TableRow(row)
                            .itemProvider { dragProvider(for: row) }
                    }
                }
            } else {
                Table(of: PrelistenRow.self, selection: $selectedRowIDs) {
                    TableColumn("#") { row in indexCell(row) }
                        .width(34)
                    TableColumn("Title") { row in titleCell(row) }
                    TableColumn("Artist") { row in textCell(row.artist, for: row) }
                    TableColumn("Album") { row in textCell(row.album, for: row) }
                    TableColumn("Genre") { row in textCell(row.genre, for: row) }
                        .width(min: 60, ideal: 90)
                    TableColumn("Year") { row in textCell(row.year.map(String.init) ?? "", for: row) }
                        .width(44)
                    TableColumn("Time") { row in timeCell(row) }
                        .width(52)
                    TableColumn("Comments") { row in textCell(row.comment ?? "", for: row) }
                } rows: {
                    ForEach(rows) { row in
                        TableRow(row)
                            .itemProvider { dragProvider(for: row) }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: PrelistenRow.ID.self) { ids in
            Button("Play") { play(ids, in: rows) }
                .disabled(ids.isEmpty)
            Button("Add to Setlist") { addToSetlist(ids, from: rows) }
                .disabled(urls(for: ids, in: rows).isEmpty)
            Button("Copy") { copyToPasteboard(ids, from: rows) }
                .disabled(urls(for: ids, in: rows).isEmpty)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(urls(for: ids, in: rows))
            }
            .disabled(urls(for: ids, in: rows).isEmpty)
        } primaryAction: { ids in
            play(ids, in: rows)
        }
        .focused($tableFocused)
        .overlay { tableNotice }
    }

    @ViewBuilder
    private var tableNotice: some View {
        if case .failed(let message) = library.status {
            libraryMessage("Can't read the Music library", detail: message)
        } else if library.playlists.isEmpty {
            if library.status == .ready {
                libraryMessage("No playlists found",
                               detail: "If Music has playlists, allow TangoDisplay in System Settings › Privacy & Security › Media & Apple Music, then try again.")
            } else {
                ProgressView("Reading playlists…")
            }
        } else if library.selectedPlaylistID == nil {
            Text("Choose a playlist")
                .foregroundColor(.secondary)
        } else if library.isLoadingRows && library.rows.isEmpty {
            ProgressView()
        }
    }

    private func libraryMessage(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { library.refresh() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: 360)
    }

    @available(macOS 14.0, *)
    @TableColumnBuilder<PrelistenRow, Never>
    private var customizableColumns: some TableColumnContent<PrelistenRow, Never> {
        TableColumn("#") { row in indexCell(row) }
            .width(34)
            .customizationID("index")
        TableColumn("Title") { row in titleCell(row) }
            .customizationID("title")
        TableColumn("Artist") { row in textCell(row.artist, for: row) }
            .customizationID("artist")
        TableColumn("Album") { row in textCell(row.album, for: row) }
            .customizationID("album")
        TableColumn("Composer") { row in textCell(row.composer, for: row) }
            .customizationID("composer")
            .defaultVisibility(.hidden)
        TableColumn("Genre") { row in textCell(row.genre, for: row) }
            .width(min: 60, ideal: 90)
            .customizationID("genre")
        TableColumn("Grouping") { row in textCell(row.grouping ?? "", for: row) }
            .customizationID("grouping")
            .defaultVisibility(.hidden)
        TableColumn("Year") { row in textCell(row.year.map(String.init) ?? "", for: row) }
            .width(44)
            .customizationID("year")
        TableColumn("Time") { row in timeCell(row) }
            .width(52)
            .customizationID("time")
        // A column builder takes ten columns at most.
        Group {
            TableColumn("Comments") { row in textCell(row.comment ?? "", for: row) }
                .customizationID("comments")
            TableColumn("Plays") { row in textCell(row.plays > 0 ? String(row.plays) : "", for: row) }
                .width(44)
                .customizationID("plays")
                .defaultVisibility(.hidden)
            TableColumn("Date Added") { row in
                textCell(row.dateAdded?.formatted(date: .numeric, time: .omitted) ?? "", for: row)
            }
            .customizationID("dateAdded")
            .defaultVisibility(.hidden)
        }
    }

    /// Saved as JSON: the customization type only exists from macOS 14, so it can't be a
    /// stored property here.
    @available(macOS 14.0, *)
    private var trackColumns: Binding<TableColumnCustomization<PrelistenRow>> {
        Binding(
            get: {
                (try? JSONDecoder().decode(TableColumnCustomization<PrelistenRow>.self, from: trackColumnsData))
                    ?? TableColumnCustomization()
            },
            set: { trackColumnsData = (try? JSONEncoder().encode($0)) ?? Data() })
    }

    private func titleCell(_ row: PrelistenRow) -> some View {
        Text(row.title)
            .fontWeight(isNowPlaying(row) ? .semibold : .regular)
            .foregroundColor(rowColor(row))
    }

    private func textCell(_ text: String, for row: PrelistenRow) -> some View {
        Text(text).foregroundColor(rowColor(row))
    }

    private func timeCell(_ row: PrelistenRow) -> some View {
        Text(formatPrelistenTime(row.playDuration))
            .monospacedDigit()
            .foregroundColor(rowColor(row))
    }

    @ViewBuilder
    private func indexCell(_ row: PrelistenRow) -> some View {
        if isNowPlaying(row) {
            Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                .foregroundColor(ControlTheme.accent)
        } else {
            Text(String(row.id + 1))
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
    }

    private func isNowPlaying(_ row: PrelistenRow) -> Bool {
        player.queueSourceID == library.selectedPlaylistID && player.current?.id == row.id
    }

    private func rowColor(_ row: PrelistenRow) -> Color {
        row.fileURL == nil ? .secondary : .primary
    }

    // MARK: Actions

    private func dragProvider(for row: PrelistenRow) -> NSItemProvider? {
        guard let url = row.fileURL else { return nil }
        let provider = NSItemProvider(object: url as NSURL)
        provider.registerDataRepresentation(forTypeIdentifier: NSPasteboard.PasteboardType.prelistenRow.rawValue,
                                            visibility: .all) { completion in
            completion(Data(), nil)
            return nil
        }
        return provider
    }

    private func play(_ ids: Set<PrelistenRow.ID>, in rows: [PrelistenRow]) {
        guard let first = ids.min(), let index = rows.firstIndex(where: { $0.id == first }) else { return }
        player.play(rows, startingAt: index, sourceID: library.selectedPlaylistID)
    }

    private func urls(for ids: Set<PrelistenRow.ID>, in rows: [PrelistenRow]) -> [URL] {
        rows.filter { ids.contains($0.id) }.compactMap(\.fileURL)
    }

    private func addToSetlist(_ ids: Set<PrelistenRow.ID>, from rows: [PrelistenRow]) {
        let picked = rows.filter { ids.contains($0.id) && $0.fileURL != nil }
        guard !picked.isEmpty else { return }
        SetlistManager.warmMusicTrims()
        appState.setlist.insertURLs(picked.compactMap(\.fileURL), before: nil, importMusicTimes: true,
                                    musicIDs: MusicDragIDs(musicMetadataPlist: musicMetadata(for: picked)))
    }

    /// Puts the selected tracks on the clipboard: files for the setlist's ⌘V (and Finder),
    /// "Title — Artist" text for notes or messages. Returns false when nothing was copyable.
    @discardableResult
    private func copyToPasteboard(_ ids: Set<PrelistenRow.ID>, from rows: [PrelistenRow]) -> Bool {
        let items: [NSPasteboardItem] = rows.filter { ids.contains($0.id) }.compactMap { row in
            guard let url = row.fileURL else { return nil }
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            item.setString(row.artist.isEmpty ? row.title : "\(row.title) — \(row.artist)", forType: .string)
            return item
        }
        guard let first = items.first else { return false }
        first.setPropertyList(musicMetadata(for: rows.filter { ids.contains($0.id) }),
                              forType: .prelistenMetadata)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects(items)
    }

    /// Shaped like Music's drag and copy plist, so the setlist imports start/stop times the
    /// same way it does for tracks coming from Music.
    private func musicMetadata(for rows: [PrelistenRow]) -> [String: Any] {
        var tracks: [String: Any] = [:]
        for row in rows {
            guard let url = row.fileURL else { continue }
            tracks[String(row.id)] = ["Location": url.absoluteString, "Persistent ID": row.persistentID]
        }
        return ["Tracks": tracks]
    }
}

private extension PrelistenBrowseField {
    var title: String {
        switch self {
        case .genre: return "Genres"
        case .artist: return "Artists"
        case .composer: return "Composers"
        case .album: return "Albums"
        case .grouping: return "Groupings"
        case .comment: return "Comments"
        }
    }

    var singular: String { String(title.dropLast()) }

    func value(of row: PrelistenRow) -> String {
        switch self {
        case .genre: return row.genre
        case .artist: return row.artist
        case .composer: return row.composer
        case .album: return row.album
        case .grouping: return row.grouping ?? ""
        case .comment: return row.comment ?? ""
        }
    }
}

private extension PrelistenPlaylistNode {
    var icon: String {
        isFolder ? "folder" : isSmart ? "gearshape" : "music.note.list"
    }
}

private struct PrelistenPlaylistMenuItems: View {
    let nodes: [PrelistenPlaylistNode]
    let select: (String) -> Void

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                // AnyView breaks the recursive opaque return type.
                Menu(node.name) {
                    AnyView(PrelistenPlaylistMenuItems(nodes: children, select: select))
                }
            } else {
                Button(node.name) { select(node.id) }
            }
        }
    }
}

/// One list of the column browser: a search field, an All row, then the list's values.
private struct PrelistenBrowseColumnList<MenuItems: View>: View {
    let title: String
    let allLabel: String
    let column: PrelistenBrowseColumn
    let pick: (Set<String?>) -> Void
    @ViewBuilder let menu: () -> MenuItems
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .contextMenu(menuItems: menu)
            // Kept out of the context menu so the field's own Cut/Copy/Paste menu still works.
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            Divider()
            List(selection: Binding(
                get: { column.selection.isEmpty ? [nil] : Set(column.selection.map { Optional($0) }) },
                set: pick
            )) {
                Text(allLabel)
                    .tag(String?.none)
                ForEach(prelistenBrowseListValues(column, search: search), id: \.self) { value in
                    Text(value)
                        .lineLimit(1)
                        .foregroundColor(column.unmatched.contains(value) ? .secondary : .primary)
                        .help(value)
                        .tag(Optional(value))
                }
            }
            .listStyle(.plain)
            .contextMenu(menuItems: menu)
        }
    }
}

// MARK: - Transport bar

private struct PrelistenTransportBar: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var player: PrelistenPlayer
    @ObservedObject var clock: PrelistenClock
    let devices: [AudioOutputDevice]
    let setlistIsPlaying: Bool
    @State private var scrubPosition: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // One row when there's room; controls wrap under the track when docked narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    transportButtons
                    nowPlaying
                    outputControls
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        transportButtons
                        nowPlaying
                    }
                    HStack {
                        Spacer(minLength: 0)
                        outputControls
                    }
                }
            }
            scrubber
            notices
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var transportButtons: some View {
        HStack(spacing: 10) {
            Button(action: player.previous) {
                Image(systemName: "backward.fill")
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .help("Previous (⌘←)")
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .frame(width: 26)
            }
            .help(player.isPlaying ? "Pause" : "Play")
            Button(action: player.next) {
                Image(systemName: "forward.fill")
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .help("Next (⌘→)")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 15))
        .disabled(player.current == nil)
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(player.current?.title ?? "Nothing playing")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(nowPlayingDetail)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 140, idealWidth: 240, maxWidth: .infinity, alignment: .leading)
    }

    private var nowPlayingDetail: String {
        guard let row = player.current else { return "Double-click a track to prelisten" }
        return [row.artist, row.year.map(String.init), row.genre]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var outputControls: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $settings.prelistenAutoAdvance) {
                Image(systemName: "arrow.forward.to.line")
            }
            .toggleStyle(.button)
            .help(settings.prelistenAutoAdvance ? "Continues to the next track" : "Stops after each track")
            HStack(spacing: 4) {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.secondary)
                Slider(value: $settings.prelistenVolume, in: 0...1)
                    .frame(width: 80)
            }
            Picker(selection: $settings.prelistenOutputDeviceUID) {
                Text("System Default").tag("")
                ForEach(devices) { device in
                    Text(device.name).tag(device.id)
                }
                if !settings.prelistenOutputDeviceUID.isEmpty,
                   !devices.contains(where: { $0.id == settings.prelistenOutputDeviceUID }) {
                    Text("Disconnected device").tag(settings.prelistenOutputDeviceUID)
                }
            } label: {
                Image(systemName: "headphones")
            }
            .pickerStyle(.menu)
            .frame(width: 170)
            .disabled(player.isChangingDevice)
            .help("Prelisten output")
        }
    }

    private var scrubber: some View {
        let range = player.playRange
        let hasRange = range.upperBound > range.lowerBound
        let position = min(max(scrubPosition ?? clock.elapsed, range.lowerBound), range.upperBound)
        return HStack(spacing: 8) {
            Text(formatPrelistenTime(position - range.lowerBound))
                .frame(width: 44, alignment: .trailing)
            Slider(value: Binding(get: { position }, set: { scrubPosition = $0 }),
                   in: hasRange ? range : 0...1) { editing in
                if !editing, let target = scrubPosition {
                    player.seek(to: target)
                    scrubPosition = nil
                }
            }
            .disabled(!hasRange)
            Text("-" + formatPrelistenTime(range.upperBound - position))
                .frame(width: 44, alignment: .leading)
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var notices: some View {
        if let message = player.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
        }
        if setlistIsPlaying, settings.selectedPlayer == .builtIn,
           settings.prelistenOutputDeviceUID == settings.builtInOutputDeviceUID {
            Label("Prelisten is on the same output as the setlist, so the room will hear it.",
                  systemImage: "speaker.wave.2.fill")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }
}

// MARK: - Docking in the main window

/// Wraps the main window's detail area and docks Prelisten on its left, right, or bottom
/// edge. The content keeps its slot when the pane is shown or hidden, so it keeps its state.
struct PrelistenDockContainer<Content: View>: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(PrelistenDefaults.docked) private var docked = false
    @AppStorage(PrelistenDefaults.dockEdge) private var edge: PrelistenDockEdge = .leading
    @AppStorage(PrelistenDefaults.dockFraction) private var fraction: Double = 0.45
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let sideBySide = edge != .bottom
            let total = sideBySide ? geo.size.width : geo.size.height
            let paneSize = clampedPaneSize(total: total, sideBySide: sideBySide)
            if sideBySide {
                HStack(spacing: 0) {
                    if docked && edge == .leading {
                        pane
                            .frame(width: paneSize)
                        PrelistenDockDivider(resizesWidth: true) { dx, _ in
                            resize(to: paneSize + dx, total: total)
                        }
                        .frame(width: 6)
                    }
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if docked && edge == .trailing {
                        PrelistenDockDivider(resizesWidth: true) { dx, _ in
                            resize(to: paneSize - dx, total: total)
                        }
                        .frame(width: 6)
                        pane
                            .frame(width: paneSize)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if docked {
                        // Window coordinates grow upward, so dragging up grows the pane.
                        PrelistenDockDivider(resizesWidth: false) { _, dy in
                            resize(to: paneSize + dy, total: total)
                        }
                        .frame(height: 6)
                        pane
                            .frame(height: paneSize)
                    }
                }
            }
        }
    }

    private var pane: some View {
        PrelistenPane(presentation: .docked, library: appState.musicLibrary, player: appState.prelistenPlayer)
    }

    private func clampedPaneSize(total: CGFloat, sideBySide: Bool) -> CGFloat {
        let minPane: CGFloat = sideBySide ? 340 : 220
        let minContent: CGFloat = sideBySide ? 360 : 200
        return max(minPane, min(total - minContent, CGFloat(fraction) * total))
    }

    private func resize(to size: CGFloat, total: CGFloat) {
        guard total > 0 else { return }
        fraction = Double(min(max(size / total, 0.15), 0.85))
    }
}

private struct PrelistenDockDivider: NSViewRepresentable {
    let resizesWidth: Bool
    /// Deltas in window coordinates since the last drag event.
    let onDrag: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> DividerView {
        let view = DividerView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DividerView, context: Context) {
        view.onDrag = onDrag
        if view.resizesWidth != resizesWidth {
            view.resizesWidth = resizesWidth
            view.window?.invalidateCursorRects(for: view)
        }
    }

    final class DividerView: NSView {
        var resizesWidth = true
        var onDrag: (CGFloat, CGFloat) -> Void = { _, _ in }
        private var lastLocation: NSPoint = .zero

        override func draw(_ dirtyRect: NSRect) {
            NSColor.separatorColor.setFill()
            bounds.fill()
            let grip = resizesWidth
                ? CGRect(x: (bounds.width - 2) / 2, y: (bounds.height - 32) / 2, width: 2, height: 32)
                : CGRect(x: (bounds.width - 32) / 2, y: (bounds.height - 2) / 2, width: 32, height: 2)
            NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: grip, xRadius: 1, yRadius: 1).fill()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: resizesWidth ? .resizeLeftRight : .resizeUpDown)
        }

        override func mouseDown(with event: NSEvent) {
            lastLocation = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            let location = event.locationInWindow
            onDrag(location.x - lastLocation.x, location.y - lastLocation.y)
            lastLocation = location
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
    }
}

// MARK: - Menus

/// ⌘⇧L toggles the docked pane; the separate window stays one menu item away.
struct PrelistenCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PrelistenDefaults.docked) private var docked = false
    @AppStorage(PrelistenDefaults.dockEdge) private var edge: PrelistenDockEdge = .leading

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button(docked ? "Hide Prelisten Pane" : "Show Prelisten Pane") {
                docked.toggle()
                if docked { WindowManager.showControlWindow() }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Picker("Prelisten Position", selection: $edge) {
                Text("Left").tag(PrelistenDockEdge.leading)
                Text("Right").tag(PrelistenDockEdge.trailing)
                Text("Bottom").tag(PrelistenDockEdge.bottom)
            }
            Button("Prelisten Window") { openWindow(id: "prelisten") }
            Divider()
        }
    }
}

/// Menu bar item. MenuBarExtra content has to be a View to use AppStorage.
struct PrelistenMenuButton: View {
    @AppStorage(PrelistenDefaults.docked) private var docked = false

    var body: some View {
        Button("Show Prelisten") {
            docked = true
            WindowManager.showControlWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
