import AppKit
import SwiftUI
import TangoDisplayCore

struct PresentationView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    var isPreview: Bool = false

    @State private var bgImage: NSImage? = nil
    @State private var artistBgImage: NSImage? = nil
    @State private var genreBgImage: NSImage? = nil
    @State private var performanceBgImage: NSImage? = nil

    private var activeProfile: AppearanceProfile { appState.activeProfile }

    private var shouldShowArtwork: Bool {
        switch appState.displayState.mode {
        case .playing: return activeProfile.showArtworkDance
        case .cortina: return activeProfile.showArtworkCortina
        default:       return false
        }
    }

    var body: some View {
        // Content layer: transitions between playing/idle/cortina views.
        // Background is applied behind it; track counter is overlaid on top.
        ZStack {
            // Album artwork layer — above background, below text.
            // Uses displayedArtworkTrackID as transition identity so it
            // transitions in/out with each track change (same timing as text).
            if shouldShowArtwork {
                TransitionContainer(
                    identity: appState.displayedArtworkTrackID,
                    style: activeProfile.transitionStyle,
                    duration: activeProfile.transitionDuration
                ) {
                    if let art = appState.currentArtwork {
                        Image(nsImage: art)
                            .resizable()
                            .scaledToFit()
                            .mask(edgeFadeMask(fade: activeProfile.albumArtworkEdgeFade))
                            .scaleEffect(activeProfile.albumArtworkScale)
                            .offset(x: activeProfile.albumArtworkOffsetX,
                                    y: activeProfile.albumArtworkOffsetY)
                            .opacity(activeProfile.albumArtworkOpacity)
                    }
                }
            }

            TransitionContainer(
                identity: appState.displayState,
                style: activeProfile.transitionStyle,
                duration: activeProfile.transitionDuration
            ) {
                contentView
            }

            // Window registration (real display only)
            if !isPreview {
                WindowAccessor { WindowManager.register($0) }
                    .allowsHitTesting(false)
            }
        }
        .background {
            // Rendered behind the content by SwiftUI's layout contract —
            // .background() can never cover its parent view.
            // Priority (performance mode): performance background → background colour.
            // Priority (normal mode): artist background → genre background → profile background → background colour.
            ZStack {
                activeProfile.backgroundSwiftUIColor
                    .ignoresSafeArea()

                let showPerformanceBg = appState.displayState.mode == .performance
                    || (appState.displayState.mode == .cortina
                        && appState.displayState.nextTrackIsPerformance
                        && settings.performanceBackgroundDuringCortina)
                if showPerformanceBg {
                    if let img = performanceBgImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .clipped()
                            .ignoresSafeArea()
                    }
                } else if let img = artistBgImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(activeProfile.artistBackgroundScale)
                        .offset(x: activeProfile.artistBackgroundOffsetX,
                                y: activeProfile.artistBackgroundOffsetY)
                        .opacity(activeProfile.artistBackgroundOpacity)
                        .clipped()
                        .ignoresSafeArea()
                } else if let img = genreBgImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(activeProfile.genreBackgroundScale)
                        .offset(x: activeProfile.genreBackgroundOffsetX,
                                y: activeProfile.genreBackgroundOffsetY)
                        .opacity(activeProfile.genreBackgroundOpacity)
                        .clipped()
                        .ignoresSafeArea()
                } else if let img = bgImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(activeProfile.backgroundImageScale)
                        .offset(x: activeProfile.backgroundImageOffsetX,
                                y: activeProfile.backgroundImageOffsetY)
                        .opacity(activeProfile.backgroundImageOpacity)
                        .clipped()
                        .ignoresSafeArea()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading)     { cornerItems(for: .topLeft) }
        .overlay(alignment: .topTrailing)    { cornerItems(for: .topRight) }
        .overlay(alignment: .bottomLeading)  { cornerItems(for: .bottomLeft) }
        .overlay(alignment: .bottomTrailing) { cornerItems(for: .bottomRight) }
        .overlay(alignment: .center) {
            let mode = appState.displayState.mode
            if tdjNameVisible(in: mode),
               settings.tdjNamePosition == .centre,
               mode != .playing {
                Text(settings.tdjName)
                    .font(activeProfile.tdjNameFont)
                    .foregroundColor(activeProfile.tdjNameSwiftUIColor)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            reloadBgImage()
            reloadArtistBgImage()
            reloadGenreBgImage()
            reloadPerformanceBgImage()
        }
        .onChange(of: activeProfile) { _ in
            reloadBgImage()
            reloadArtistBgImage()
            reloadGenreBgImage()
        }
        .onChange(of: appState.displayState.mode) { _ in
            reloadArtistBgImage()
            reloadGenreBgImage()
        }
        .onChange(of: appState.displayState.currentTrack?.artist ?? "") { _ in
            reloadArtistBgImage()
        }
        .onChange(of: appState.displayState.currentTrack?.genre ?? "") { _ in
            reloadGenreBgImage()
        }
        .onChange(of: settings.performanceBackgroundImageFilename) { _ in
            reloadPerformanceBgImage()
        }
    }

    private func reloadPerformanceBgImage() {
        guard let filename = settings.performanceBackgroundImageFilename else {
            performanceBgImage = nil
            return
        }
        let url = appState.profileStore.imageURL(for: filename)
        performanceBgImage = NSImage(contentsOf: url)
    }

    private func reloadBgImage() {
        guard let filename = activeProfile.backgroundImageFilename else {
            bgImage = nil
            return
        }
        let url = appState.profileStore.imageURL(for: filename)
        bgImage = NSImage(contentsOf: url)
    }

    private func reloadArtistBgImage() {
        guard appState.displayState.mode == .playing else {
            artistBgImage = nil
            return
        }
        let artist = appState.displayState.currentTrack?.artist ?? ""
        guard let match = activeProfile.matchingArtistBackground(for: artist),
              let filename = match.imageFilename else {
            artistBgImage = nil
            return
        }
        artistBgImage = NSImage(contentsOf: appState.profileStore.imageURL(for: filename))
    }

    private func reloadGenreBgImage() {
        // Active for both .playing (dance-genre matches) and .cortina (cortina-sentinel match).
        // The detector itself decides which entry applies based on the current track's genre.
        let mode = appState.displayState.mode
        guard mode == .playing || mode == .cortina else {
            genreBgImage = nil
            return
        }
        let genre = appState.displayState.currentTrack?.genre ?? ""
        let detector = settings.makeDetector()
        guard let match = activeProfile.matchingGenreBackground(for: genre, using: detector),
              let filename = match.imageFilename else {
            genreBgImage = nil
            return
        }
        genreBgImage = NSImage(contentsOf: appState.profileStore.imageURL(for: filename))
    }

    private func tdjNameVisible(in mode: DisplayMode) -> Bool {
        guard settings.showTdjName && !settings.tdjName.isEmpty else { return false }
        switch settings.tdjNameVisibility {
        case .playing:    return mode == .playing || mode == .cortina
        case .idlePaused: return mode == .idle || mode == .paused
        case .always:     return true
        }
    }

    @ViewBuilder
    private func cornerItems(for corner: TrackCounterPosition) -> some View {
        let mode = appState.displayState.mode
        let showTdj = tdjNameVisible(in: mode) && settings.tdjNamePosition == corner
        let showCounter = settings.showTrackCounter
            && settings.trackCounterPosition == corner
            && mode == .playing
        if showTdj || showCounter {
            VStack(spacing: 12) {
                if showTdj {
                    Text(settings.tdjName)
                        .font(activeProfile.tdjNameFont)
                        .foregroundColor(activeProfile.tdjNameSwiftUIColor)
                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                }
                if showCounter, let pos = appState.displayState.tandaPosition {
                    Text(pos.label)
                        .font(activeProfile.trackCounterFont)
                        .foregroundColor(activeProfile.trackCounterSwiftUIColor)
                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                }
            }
            .padding(24)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch appState.displayState.mode {
        case .playing:
            PlayingView(
                state: appState.displayState,
                profile: activeProfile,
                isLastTandaActive: appState.isLastTandaActive,
                settings: appState.settings
            )
        case .cortina:
            CortinaView(
                state: appState.displayState,
                profile: activeProfile,
                isLastTandaActive: appState.isLastTandaActive,
                settings: appState.settings
            )
        case .idle, .paused:
            IdleView(
                mode: appState.displayState.mode,
                settings: appState.settings,
                profile: activeProfile
            )
        case .override:
            overrideView
        case .performance:
            PerformanceView(
                currentTrack: appState.displayState.currentTrack,
                settings: appState.settings
            )
        }
    }

    private func edgeFadeMask(fade: Double) -> some View {
        GeometryReader { geo in
            // Reach the *corner* of the (square) artwork, not just the
            // inscribed circle — otherwise the square's corners fall outside
            // the gradient and disappear instantly at any non-zero fade.
            let r = sqrt(geo.size.width * geo.size.width
                       + geo.size.height * geo.size.height) * 0.5
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: .white,             location: 0.0),
                    .init(color: .white,             location: max(0.0, 1.0 - fade)),
                    .init(color: .white.opacity(0),  location: 1.0)
                ]),
                center: .center,
                startRadius: 0,
                endRadius: r
            )
        }
    }

    private var overrideView: some View {
        Text(appState.displayState.overrideText ?? "")
            .font(activeProfile.overrideTextFont)
            .foregroundColor(activeProfile.overrideTextSwiftUIColor)
            .multilineTextAlignment(.center)
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
