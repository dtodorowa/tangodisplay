import SwiftUI
import TangoDisplayCore

/// Edits the "Coming Up" details shown during one cortina. Used when the next
/// tanda is mixed and the first track's metadata would misdescribe it.
/// Blank field = fall back to the real track metadata.
struct UpcomingInfoEditor: View {
    let entry: SetlistEntry
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var artist: String = ""
    @State private var singer: String = ""
    @State private var year: String = ""

    private var profile: AppearanceProfile { appState.activeProfile }

    /// First non-cortina entry after this cortina — what the display would show unedited.
    private var nextTrack: Track? {
        let detector = settings.makeDetector()
        let entries = appState.setlist.entries
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return nil }
        return entries[(i + 1)...].first { !detector.isCortina(genre: $0.track.genre) }?.track
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Upcoming Info")
                .font(.headline)

            Text("Shown during this cortina instead of the next track's own details. Leave a field blank to use the real details.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Artist")
                    TextField(nextTrack?.artist ?? "Artist", text: $artist)
                        .textFieldStyle(.roundedBorder)
                }
                if profile.showSingerCortina {
                    GridRow {
                        Text("Singer")
                        TextField(singerPlaceholder, text: $singer)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                GridRow {
                    Text("Year")
                    TextField(nextTrack?.year.map(String.init) ?? "Year", text: $year)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Clear All") {
                    artist = ""; singer = ""; year = ""
                    save()
                }
                .buttonStyle(.bordered)
                .disabled(artist.isEmpty && singer.isEmpty && year.isEmpty)

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            artist = entry.upcomingOverride?.artist ?? ""
            singer = entry.upcomingOverride?.singer ?? ""
            year   = entry.upcomingOverride?.year ?? ""
        }
    }

    private var singerPlaceholder: String {
        if let t = nextTrack, let raw = profile.singerValue(from: t), !raw.isEmpty { return raw }
        return profile.singerSource.displayName
    }

    private func save() {
        let o = UpcomingOverride(artist: artist, singer: singer, year: year)
        let value = o.isEmpty ? nil : o
        appState.setlist.setUpcomingOverride(value, for: entry.id)
        appState.applyUpcomingOverride(value, forCortinaEntry: entry.id)
        dismiss()
    }
}
