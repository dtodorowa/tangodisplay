import AppKit
import SwiftUI
import TangoDisplayCore

/// Image shown in the right-hand pane of the "Text Left, Image Right" layout.
struct SidePanelImage {
    let image: NSImage
    let opacity: Double
}

struct PlayingView: View {
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
        VStack(alignment: stackAlignment, spacing: 16) {
            Spacer()

            ForEach(profile.danceItemOrder, id: \.self) { entry in
                switch entry {
                case .custom(let id):
                    if let line = profile.customTextLines.first(where: { $0.id == id }), line.showInDance {
                        let resolved = resolveCustomPlaceholders(line.text, track: state.currentTrack,
                                                                 profile: profile, settings: settings)
                        if !resolved.isEmpty {
                            Text(resolved)
                                .font(profile.font(name: line.fontName, size: line.fontSize,
                                                   bold: line.fontBold, italic: line.fontItalic))
                                .foregroundColor(Color(hex: line.colorHex))
                                .multilineTextAlignment(textAlignment)
                                .lineLimit(Self.dynamicLineLimit(resolved))
                                .minimumScaleFactor(0.5)
                        }
                    }
                case .builtin(let item):
                    switch item {
                    case .genre:
                    if profile.showGenreDance, let genre = state.currentTrack?.genre, !genre.isEmpty {
                        Text(settings.displayLabel(for: genre).uppercased())
                            .font(profile.genreFont)
                            .foregroundColor(profile.genreSwiftUIColor)
                            .multilineTextAlignment(textAlignment)
                    }
                case .artist:
                    if profile.showArtistDance, let artist = state.currentTrack?.artist, !artist.isEmpty {
                        let displayArtist = settings.transform(artist, for: .artist)
                        Text(displayArtist)
                            .font(profile.artistFont)
                            .foregroundColor(profile.artistSwiftUIColor)
                            .multilineTextAlignment(textAlignment)
                            .lineLimit(Self.dynamicLineLimit(displayArtist))
                            .minimumScaleFactor(0.5)
                    }
                case .year:
                    if profile.showYearDance, let year = state.currentTrack?.year {
                        let displayYear = settings.transform(String(year), for: .year)
                        if !displayYear.isEmpty {
                            Text(displayYear)
                                .font(profile.yearFont)
                                .foregroundColor(profile.yearSwiftUIColor)
                                .multilineTextAlignment(textAlignment)
                        }
                    }
                case .title:
                    if profile.showTitleDance, let title = state.currentTrack?.title, !title.isEmpty {
                        let displayTitle = settings.transform(title, for: .title)
                        Text(displayTitle)
                            .font(profile.titleFont)
                            .foregroundColor(profile.titleSwiftUIColor)
                            .multilineTextAlignment(textAlignment)
                            .lineLimit(Self.dynamicLineLimit(displayTitle))
                            .minimumScaleFactor(0.5)
                    }
                case .singer:
                    if profile.showSingerDance,
                       let rawSinger = state.currentTrack.flatMap({ profile.singerValue(from: $0) }),
                       !rawSinger.isEmpty {
                        let singerField: TrackInfoField = {
                            switch profile.singerSource {
                            case .albumArtist: return .albumArtist
                            case .comments:    return .comments
                            case .grouping:    return .grouping
                            }
                        }()
                        let singer = settings.transform(rawSinger, for: singerField)
                        if !singer.isEmpty {
                            Text(singer)
                                .font(profile.singerFont)
                                .foregroundColor(profile.singerSwiftUIColor)
                                .multilineTextAlignment(textAlignment)
                                .lineLimit(Self.dynamicLineLimit(singer))
                                .minimumScaleFactor(0.5)
                        }
                    }
                case .lastTandaLabel:
                    if profile.showLastTandaLabel, isLastTandaActive, !settings.lastTandaLabel.isEmpty {
                        Text(settings.lastTandaLabel.uppercased())
                            .font(profile.lastTandaLabelFont)
                            .foregroundColor(profile.lastTandaLabelSwiftUIColor)
                            .multilineTextAlignment(textAlignment)
                    }
                case .trackCounter:
                    if settings.showTrackCounter,
                       settings.trackCounterPosition == .centre,
                       let pos = state.tandaPosition {
                        Text(pos.label)
                            .font(profile.trackCounterFont)
                            .foregroundColor(profile.trackCounterSwiftUIColor)
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
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
                    case .cortinaLabel, .cortinaArtist, .cortinaTitle, .nextUpLabel:
                        EmptyView()
                    }
                }
            }

            Spacer()
        }
    }

    static func dynamicLineLimit(_ s: String) -> Int {
        min(4, max(2, s.components(separatedBy: "\n").count))
    }
}
