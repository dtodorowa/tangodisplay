import AppKit
import SwiftUI
import TangoDisplayCore

struct AppearanceArtworkTab: View {
    @Binding var working: AppearanceProfile
    let bgThumbnail: NSImage?
    let onPickImage: () -> Void
    let onClearImage: () -> Void
    let cortinaImageThumbnail: NSImage?
    let onPickCortinaImage: () -> Void
    let onClearCortinaImage: () -> Void
    let artistBgThumbnails: [UUID: NSImage]
    let onPickArtistImage: (ArtistBackground) -> Void
    let onClearArtistImage: (ArtistBackground) -> Void
    let onAddArtistBackground: () -> Void
    let onRemoveArtistBackground: (ArtistBackground) -> Void
    let genreBgThumbnails: [UUID: NSImage]
    let onPickGenreImage: (GenreBackground) -> Void
    let onClearGenreImage: (GenreBackground) -> Void
    let cortinaRowLabel: String

    @FocusState private var focusedEntryId: UUID?
    @State private var prevArtistCount: Int = 0

    private var orderedGenreBackgrounds: [GenreBackground] {
        let dance = working.genreBackgrounds.filter { !$0.isCortinaEntry }
        let cortina = working.genreBackgrounds.filter { $0.isCortinaEntry }
        return dance + cortina
    }

    private var anyGenreImageSet: Bool {
        working.genreBackgrounds.contains { $0.imageFilename != nil }
    }

    var body: some View {
        Form {
            Section {
                Picker("Layout", selection: $working.displayLayout) {
                    ForEach(DisplayLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                if working.displayLayout == .textLeftImageRight {
                    HStack(spacing: 12) {
                        Group {
                            if let thumb = cortinaImageThumbnail {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipped()
                                    .cornerRadius(4)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "pause.rectangle")
                                            .foregroundColor(.secondary)
                                    )
                            }
                        }
                        Text("Cortina Image")
                        Spacer()
                        Button(working.cortinaImageFilename == nil ? "Pick Image…" : "Change Image…") {
                            onPickCortinaImage()
                        }
                        .buttonStyle(.bordered)
                        if working.cortinaImageFilename != nil {
                            Button("Clear") { onClearCortinaImage() }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                        }
                    }
                    if working.cortinaImageFilename != nil {
                        HStack {
                            Text("Opacity")
                            Slider(value: $working.cortinaImageOpacity, in: 0...1)
                            Text(String(format: "%.0f%%", working.cortinaImageOpacity * 100))
                                .monospacedDigit()
                                .frame(width: 44)
                        }
                    }
                }
            } header: {
                Text("Layout")
                    .foregroundColor(ControlTheme.accent)
            } footer: {
                if working.displayLayout == .textLeftImageRight {
                    Label {
                        Text("Text is left-aligned. The right half shows the matching Artist Background image, or the album artwork when no artist matches. During cortinas it shows the Cortina Image when one is set, otherwise the next tanda's artist. Artist image scale and position sliders do not apply in this layout.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
            }

            Section {
                Picker("Style", selection: $working.transitionStyle) {
                    ForEach(TransitionStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                HStack {
                    Text("Duration")
                    Slider(value: $working.transitionDuration, in: 0...2, step: 0.1)
                    Text(String(format: "%.1fs", working.transitionDuration))
                        .monospacedDigit()
                        .frame(width: 36)
                }
            } header: {
                Text("Transition")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                Toggle("Show artwork on dance tracks", isOn: $working.showArtworkDance)
                if working.showArtworkDance || working.showArtworkCortina {
                    HStack {
                        Text("Opacity")
                        Slider(value: $working.albumArtworkOpacity, in: 0...1)
                        Text(String(format: "%.0f%%", working.albumArtworkOpacity * 100))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    HStack {
                        Text("Edge Fade")
                        Slider(value: $working.albumArtworkEdgeFade, in: 0...1)
                        Text(String(format: "%.0f%%", working.albumArtworkEdgeFade * 100))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    HStack {
                        Text("Scale")
                        Slider(value: $working.albumArtworkScale, in: 0.1...5.0)
                        Text(String(format: "%.2f×", working.albumArtworkScale))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    HStack {
                        Text("Horizontal Position")
                        Slider(value: $working.albumArtworkOffsetX, in: -2000...2000)
                        Text(String(format: "%+.0f", working.albumArtworkOffsetX))
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                    HStack {
                        Text("Vertical Position")
                        Slider(value: $working.albumArtworkOffsetY, in: -2000...2000)
                        Text(String(format: "%+.0f", working.albumArtworkOffsetY))
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                }
            } header: {
                Text("Album Artwork")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                HStack(spacing: 12) {
                    Group {
                        if let thumb = bgThumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipped()
                                .cornerRadius(4)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    Spacer()
                    Button(working.backgroundImageFilename == nil ? "Pick Image…" : "Change Image…") {
                        onPickImage()
                    }
                    .buttonStyle(.bordered)
                    if working.backgroundImageFilename != nil {
                        Button("Clear") { onClearImage() }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                    }
                }

                if working.backgroundImageFilename != nil {
                    HStack {
                        Text("Opacity")
                        Slider(value: $working.backgroundImageOpacity, in: 0...1)
                        Text(String(format: "%.0f%%", working.backgroundImageOpacity * 100))
                            .monospacedDigit()
                            .frame(width: 36)
                    }
                    HStack {
                        Text("Scale")
                        Slider(value: $working.backgroundImageScale, in: 0.1...5.0)
                        Text(String(format: "%.2f×", working.backgroundImageScale))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    HStack {
                        Text("Horizontal Position")
                        Slider(value: $working.backgroundImageOffsetX, in: -2000...2000)
                        Text(String(format: "%+.0f", working.backgroundImageOffsetX))
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                    HStack {
                        Text("Vertical Position")
                        Slider(value: $working.backgroundImageOffsetY, in: -2000...2000)
                        Text(String(format: "%+.0f", working.backgroundImageOffsetY))
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                }
            } header: {
                Text("Background Image")
                    .foregroundColor(ControlTheme.accent)
            } footer: {
                Label {
                    Text("Background images are best checked in Live because external display resolution can vary.")
                } icon: {
                    Image(systemName: "info.circle")
                }
            }

            Section {
                Toggle("Enable artist backgrounds", isOn: $working.artistBackgroundsEnabled)

                if working.artistBackgroundsEnabled {
                    ForEach($working.artistBackgrounds) { $entry in
                        artistEntryRow(entry: $entry)
                    }

                    Button("Add Artist…") {
                        onAddArtistBackground()
                    }
                    .buttonStyle(.bordered)

                    if working.artistBackgrounds.contains(where: { $0.imageFilename != nil }) {
                        HStack {
                            Text("Opacity")
                            Slider(value: $working.artistBackgroundOpacity, in: 0...1)
                            Text(String(format: "%.0f%%", working.artistBackgroundOpacity * 100))
                                .monospacedDigit()
                                .frame(width: 36)
                        }
                        HStack {
                            Text("Scale")
                            Slider(value: $working.artistBackgroundScale, in: 0.1...5.0)
                            Text(String(format: "%.2f×", working.artistBackgroundScale))
                                .monospacedDigit()
                                .frame(width: 44)
                        }
                        HStack {
                            Text("Horizontal Position")
                            Slider(value: $working.artistBackgroundOffsetX, in: -2000...2000)
                            Text(String(format: "%+.0f", working.artistBackgroundOffsetX))
                                .monospacedDigit()
                                .frame(width: 48)
                        }
                        HStack {
                            Text("Vertical Position")
                            Slider(value: $working.artistBackgroundOffsetY, in: -2000...2000)
                            Text(String(format: "%+.0f", working.artistBackgroundOffsetY))
                                .monospacedDigit()
                                .frame(width: 48)
                        }
                    }
                }
            } header: {
                Text("Artist Backgrounds")
                    .foregroundColor(ControlTheme.accent)
            } footer: {
                if working.artistBackgroundsEnabled {
                    Label {
                        Text("Artist Backgrounds override genre, profile, and colour backgrounds when the current track artist matches. Priority: artist → genre → profile → background colour.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
            }

            Section {
                Toggle("Enable genre backgrounds", isOn: $working.genreBackgroundsEnabled)

                if working.genreBackgroundsEnabled {
                    if orderedGenreBackgrounds.isEmpty {
                        Label {
                            Text("No genres configured. Add entries under Cortina Rules to create per-genre background slots.")
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .font(.callout)
                        .foregroundColor(.secondary)
                    } else {
                        ForEach(orderedGenreBackgrounds) { entry in
                            genreEntryRow(entry: entry)
                        }
                    }

                    if anyGenreImageSet {
                        HStack {
                            Text("Opacity")
                            Slider(value: $working.genreBackgroundOpacity, in: 0...1)
                            Text(String(format: "%.0f%%", working.genreBackgroundOpacity * 100))
                                .monospacedDigit()
                                .frame(width: 36)
                        }
                        HStack {
                            Text("Scale")
                            Slider(value: $working.genreBackgroundScale, in: 0.1...5.0)
                            Text(String(format: "%.2f×", working.genreBackgroundScale))
                                .monospacedDigit()
                                .frame(width: 44)
                        }
                        HStack {
                            Text("Horizontal Position")
                            Slider(value: $working.genreBackgroundOffsetX, in: -2000...2000)
                            Text(String(format: "%+.0f", working.genreBackgroundOffsetX))
                                .monospacedDigit()
                                .frame(width: 48)
                        }
                        HStack {
                            Text("Vertical Position")
                            Slider(value: $working.genreBackgroundOffsetY, in: -2000...2000)
                            Text(String(format: "%+.0f", working.genreBackgroundOffsetY))
                                .monospacedDigit()
                                .frame(width: 48)
                        }
                    }
                }
            } header: {
                Text("Genre Backgrounds")
                    .foregroundColor(ControlTheme.accent)
            } footer: {
                if working.genreBackgroundsEnabled {
                    Label {
                        Text("Genre Backgrounds override the profile background image when the current track's genre matches a Cortina-Rules entry. Configure entries under Cortina Rules. Priority: artist → genre → profile → background colour.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            prevArtistCount = working.artistBackgrounds.count
        }
        .onChange(of: working.artistBackgrounds.count) { newCount in
            if newCount > prevArtistCount, let lastId = working.artistBackgrounds.last?.id {
                focusedEntryId = lastId
            }
            prevArtistCount = newCount
        }
    }

    @ViewBuilder
    private func artistEntryRow(entry: Binding<ArtistBackground>) -> some View {
        let e = entry.wrappedValue
        let isIncomplete = e.artistName.trimmingCharacters(in: .whitespaces).isEmpty || e.imageFilename == nil
        HStack(spacing: 10) {
            Group {
                if let thumb = artistBgThumbnails[e.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.crop.rectangle")
                                .foregroundColor(.secondary)
                        )
                }
            }

            Text("Name")
                .foregroundColor(.secondary)
                .fixedSize()

            TextField("", text: entry.artistName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            e.artistName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.red.opacity(0.7)
                                : Color(NSColor.separatorColor).opacity(0.5),
                            lineWidth: 1
                        )
                )
                .focused($focusedEntryId, equals: e.id)

            Button(e.imageFilename == nil ? "Pick Image…" : "Change Image…") {
                onPickArtistImage(e)
            }
            .buttonStyle(.bordered)

            if e.imageFilename != nil {
                Button("Clear") { onClearArtistImage(e) }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
            }

            if isIncomplete {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .help("This entry needs both an artist name and a background image before saving.")
            }

            Button {
                onRemoveArtistBackground(e)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func genreEntryRow(entry: GenreBackground) -> some View {
        let label = entry.isCortinaEntry ? "\(cortinaRowLabel) (non-dance)" : entry.genreKey
        HStack(spacing: 10) {
            Group {
                if let thumb = genreBgThumbnails[entry.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: entry.isCortinaEntry ? "pause.rectangle" : "music.note")
                                .foregroundColor(.secondary)
                        )
                }
            }

            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Button(entry.imageFilename == nil ? "Pick Image…" : "Change Image…") {
                onPickGenreImage(entry)
            }
            .buttonStyle(.bordered)

            if entry.imageFilename != nil {
                Button("Clear") { onClearGenreImage(entry) }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
            }
        }
    }
}
