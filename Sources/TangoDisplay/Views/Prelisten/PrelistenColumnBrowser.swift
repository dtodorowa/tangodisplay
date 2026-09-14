import SwiftUI
import TangoDisplayCore

extension PrelistenBrowseField {
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

/// One list of the column browser: a search field, an All row, then the list's values.
struct PrelistenBrowseColumnList<MenuItems: View>: View {
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

/// Keeps the track table's column layout in UserDefaults. A view of its own because the
/// customization type only exists from macOS 14, so the pane can't hold it as a property.
@available(macOS 14.0, *)
struct PrelistenTrackColumnsStorage<Content: View>: View {
    @AppStorage(PrelistenDefaults.trackColumns) private var customization = TableColumnCustomization<PrelistenRow>()
    @ViewBuilder let content: (Binding<TableColumnCustomization<PrelistenRow>>) -> Content

    var body: some View {
        content($customization)
    }
}
