import SwiftUI
import TangoDisplayCore

struct CortinaView: View {
    let state: DisplayState
    let profile: AppearanceProfile
    let isLastTandaActive: Bool
    @ObservedObject var settings: AppSettings
    var sideImage: SidePanelImage? = nil

    private var isSplit: Bool { profile.displayLayout == .textLeftImageRight }
    private var textAlignment: TextAlignment { isSplit ? .leading : .center }
    private var stackAlignment: HorizontalAlignment { isSplit ? .leading : .center }

    var body: some View {
        if isSplit {
            HStack(spacing: 40) {
                textStack
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let side = sideImage {
                    Image(nsImage: side.image)
                        .resizable()
                        .scaledToFit()
                        .opacity(side.opacity)
                        .padding(.vertical, 60)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            textStack
                .padding(.horizontal, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var textStack: some View {
        VStack(alignment: stackAlignment, spacing: 32) {
            Spacer()

            // Cortina-track section: CORTINA label always shown; artist/title gated by toggle
            VStack(alignment: stackAlignment, spacing: 12) {
                ForEach(profile.cortinaTrackItemOrder, id: \.self) { entry in
                    if case .builtin(let item) = entry {
                    switch item {
                    case .cortinaLabel:
                        Text(settings.cortinaLabel)
                            .font(profile.cortinaLabelFont)
                            .tracking(12)
                            .foregroundColor(profile.cortinaLabelSwiftUIColor)
                            .multilineTextAlignment(textAlignment)
                    case .cortinaArtist:
                        if profile.showCortinaTrackDuringCortina,
                           profile.showCortinaTrackArtist,
                           let artist = state.currentTrack?.artist, !artist.isEmpty {
                            Text(settings.transform(artist, for: .artist))
                                .font(profile.cortinaArtistFont)
                                .foregroundColor(profile.cortinaArtistSwiftUIColor)
                                .multilineTextAlignment(textAlignment)
                                .lineLimit(2)
                                .minimumScaleFactor(0.5)
                        }
                    case .cortinaTitle:
                        if profile.showCortinaTrackDuringCortina,
                           profile.showCortinaTrackTitle,
                           let title = state.currentTrack?.title, !title.isEmpty {
                            Text(settings.transform(title, for: .title))
                                .font(profile.cortinaTitleFont)
                                .foregroundColor(profile.cortinaTitleSwiftUIColor)
                                .multilineTextAlignment(textAlignment)
                                .lineLimit(2)
                                .minimumScaleFactor(0.5)
                        }
                    default:
                        EmptyView()
                    }
                    }
                }
            }

            let perfCortinLines = settings.performanceTextLines.filter { $0.showDuringCortina }
            let showPerformanceComing = state.nextTrackIsPerformance && !perfCortinLines.isEmpty
            let showComingUp = profile.showNextTrackDuringCortina && state.nextTrack != nil && !showPerformanceComing
            let showLastTanda = isLastTandaActive && profile.showLastTandaLabel && !settings.lastTandaLabel.isEmpty
            if showPerformanceComing || showComingUp || showLastTanda {
                // Divider between cortina section and coming-up section
                Rectangle()
                    .fill(profile.genreSwiftUIColor.opacity(0.3))
                    .frame(width: 120, height: 1)
                    .padding(.vertical, 8)

                // Coming-up section
                VStack(alignment: stackAlignment, spacing: 12) {
                    if showPerformanceComing {
                        // Performance cortina: show nextUpLabel + DJ-configured lines
                        if !settings.nextUpLabel.isEmpty {
                            Text(settings.nextUpLabel)
                                .font(profile.nextUpLabelFont)
                                .tracking(4)
                                .foregroundColor(profile.nextUpLabelSwiftUIColor)
                        }
                        ForEach(perfCortinLines) { line in
                            let resolved = resolvePerformancePlaceholders(line.text, track: state.nextTrack)
                            if !resolved.isEmpty {
                                Text(resolved)
                                    .font(performanceLineFont(line))
                                    .foregroundColor(Color(hex: line.colorHex))
                                    .multilineTextAlignment(textAlignment)
                                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                            }
                        }
                    } else {
                        ForEach(profile.cortinaItemOrder, id: \.self) { entry in
                            switch entry {
                            case .custom(let id):
                                if showComingUp, let next = state.nextTrack,
                                   let line = profile.customTextLines.first(where: { $0.id == id }),
                                   line.showInCortina {
                                    let resolved = resolveCustomPlaceholders(line.text, track: next,
                                                                             profile: profile, settings: settings,
                                                                             override: state.nextTrackOverride)
                                    if !resolved.isEmpty {
                                        Text(resolved)
                                            .font(profile.font(name: line.fontName, size: line.fontSize,
                                                               bold: line.fontBold, italic: line.fontItalic))
                                            .foregroundColor(Color(hex: line.colorHex))
                                            .multilineTextAlignment(textAlignment)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.5)
                                    }
                                }
                            case .builtin(let item):
                                switch item {
                                case .nextUpLabel:
                                if showComingUp {
                                    Text(settings.nextUpLabel)
                                        .font(profile.nextUpLabelFont)
                                        .tracking(4)
                                        .foregroundColor(profile.nextUpLabelSwiftUIColor)
                                }
                            case .genre:
                                if showComingUp, let next = state.nextTrack,
                                   profile.showGenreCortina, !next.genre.isEmpty {
                                    Text(settings.displayLabel(for: next.genre))
                                        .font(profile.genreFont)
                                        .foregroundColor(profile.genreSwiftUIColor)
                                }
                            case .artist:
                                if showComingUp, let next = state.nextTrack, profile.showArtistCortina {
                                    // Override text is shown verbatim — the DJ typed exactly what they want.
                                    Text(state.nextTrackOverride?.artistValue
                                         ?? settings.transform(next.artist, for: .artist))
                                        .font(profile.artistFont)
                                        .foregroundColor(profile.artistSwiftUIColor)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.5)
                                        .multilineTextAlignment(textAlignment)
                                }
                            case .year:
                                if showComingUp, let next = state.nextTrack,
                                   profile.showYearCortina,
                                   state.nextTrackOverride?.yearValue != nil || next.year != nil {
                                    let displayYear = state.nextTrackOverride?.yearValue
                                        ?? settings.transform(String(next.year ?? 0), for: .year)
                                    if !displayYear.isEmpty {
                                        Text(displayYear)
                                            .font(profile.yearFont)
                                            .foregroundColor(profile.yearSwiftUIColor)
                                            .multilineTextAlignment(textAlignment)
                                    }
                                }
                            case .title:
                                if showComingUp, let next = state.nextTrack,
                                   profile.showTitleCortina, !next.title.isEmpty {
                                    Text(settings.transform(next.title, for: .title))
                                        .font(profile.titleFont)
                                        .foregroundColor(profile.titleSwiftUIColor)
                                        .multilineTextAlignment(textAlignment)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.5)
                                }
                            case .singer:
                                if showComingUp, let next = state.nextTrack,
                                   profile.showSingerCortina {
                                    let singer: String = state.nextTrackOverride?.singerValue ?? {
                                        guard let raw = profile.singerValue(from: next), !raw.isEmpty else { return "" }
                                        return settings.transform(raw, for: singerTrackInfoField(profile.singerSource))
                                    }()
                                    if !singer.isEmpty {
                                        Text(singer)
                                            .font(profile.singerFont)
                                            .foregroundColor(profile.singerSwiftUIColor)
                                            .multilineTextAlignment(textAlignment)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.5)
                                    }
                                }
                            case .lastTandaLabel:
                                if showLastTanda {
                                    Text(settings.lastTandaLabel.uppercased())
                                        .font(profile.lastTandaLabelFont)
                                        .foregroundColor(profile.lastTandaLabelSwiftUIColor)
                                        .multilineTextAlignment(textAlignment)
                                }
                            case .tdjName:
                                if settings.showTdjName,
                                   settings.tdjNamePosition == .centre,
                                   !settings.tdjName.isEmpty,
                                   settings.tdjNameVisibility != .idlePaused {
                                    Text(settings.tdjName)
                                        .font(profile.tdjNameFont)
                                        .foregroundColor(profile.tdjNameSwiftUIColor)
                                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                                        .multilineTextAlignment(textAlignment)
                                }
                                default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
            }

            Spacer()
        }
    }

    private func performanceLineFont(_ line: PerformanceTextLine) -> Font {
        if line.fontName == "System" || line.fontName.isEmpty {
            return .system(size: line.fontSize)
        }
        return .custom(line.fontName, size: line.fontSize)
    }
}
