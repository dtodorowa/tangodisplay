import AppKit
import os.log
import SwiftUI
import TangoDisplayCore
import UniformTypeIdentifiers

private let dropLog = OSLog(subsystem: "com.tangodisplay", category: "musicdrop")

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - AppKit Music.app drop handler
//
// SwiftUI's .onDrop only sees types bridged through NSItemProvider. Music.app puts
// com.apple.itunes.drag / com.apple.music.metadata directly on NSPasteboard without
// bridging them through NSItemProvider.
//
// Architecture: MusicAppDropView is installed as an intermediate parent between
// window.contentView and its existing subviews. AppKit drag routing walks UP the
// superview chain from the hit-tested view; so any drag over SwiftUI content
// reaches MusicAppDropView via its ancestor relationship. Non-Music.app drags
// return [] from draggingEntered and fall through to SwiftUI's own handlers.

private class MusicAppDropView: NSView {
    var onDrop: ([URL], MusicDragIDs) -> Void = { _, _ in }
    var onTargeted: (Bool) -> Void = { _ in }

    // Legacy Music.app drag types (pre-Sequoia / older purchased AAC):
    private static let pasteboardType     = NSPasteboard.PasteboardType("com.apple.itunes.drag")
    private static let musicMetadataType  = NSPasteboard.PasteboardType("com.apple.music.metadata")
    // Same plist under two newer names. Carries Location + Persistent ID for each dragged
    // track (but not the start/stop times — those still come from ITLibrary).
    private static let tvMetadataType     = NSPasteboard.PasteboardType("com.apple.tv.metadata")
    private static let itunMetadataType   = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x6974756E")
    // Music.app on Sequoia for iTunes-purchased AAC: file promise + Music identifier
    private static let musicJRFSType      = NSPasteboard.PasteboardType("com.apple.Music.JRFS")
    // Legacy file-promise pasteboard types (Music.app's actual mechanism on Sequoia).
    // NSFilePromiseReceiver does NOT match these — must use the older
    // namesOfPromisedFiles(droppedAtDestination:) API.
    private static let legacyPromiseURLType      = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
    private static let legacyPromiseContentsType = NSPasteboard.PasteboardType("NSPromiseContentsPboardType")
    // Plain file URLs from Finder, Swinsian, or AIFF-from-Music drags.
    private static let fileURLType               = NSPasteboard.PasteboardType.fileURL

    private let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            var types: [NSPasteboard.PasteboardType] = [
                Self.pasteboardType, Self.musicMetadataType, Self.musicJRFSType,
                Self.legacyPromiseURLType, Self.legacyPromiseContentsType,
                Self.fileURLType
            ]
            // Also include NSFilePromiseReceiver types so future Music.app versions
            // that adopt the modern API are still handled. We filter non-Music promise
            // drags in hasAcceptableDrag().
            types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes
                .map { NSPasteboard.PasteboardType($0) })
            registerForDraggedTypes(types)
            os_log("register types=%{public}@ frame=%{public}@ subviews=%d isContentView=%{public}@",
                   log: dropLog, type: .info,
                   String(describing: registeredDraggedTypes),
                   String(describing: frame),
                   subviews.count,
                   String(window?.contentView === self))
        } else {
            unregisterDraggedTypes()
        }
    }

    private func hasAcceptableDrag(_ sender: NSDraggingInfo) -> Bool {
        let types = sender.draggingPasteboard.types ?? []
        let match = types.contains(Self.pasteboardType)
            || types.contains(Self.musicMetadataType)
            || types.contains(Self.musicJRFSType)
            || types.contains(Self.legacyPromiseURLType)
            || types.contains(Self.fileURLType)
        if !match {
            os_log("reject: no acceptable type; types=%{public}@", log: dropLog, type: .info,
                   String(describing: types))
        }
        return match
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        os_log("draggingEntered types=%{public}@", log: dropLog, type: .info,
               String(describing: sender.draggingPasteboard.types ?? []))
        guard hasAcceptableDrag(sender) else { return [] }
        // Start the Music start/stop rescan now, off the main thread: this fires about a
        // second before the drop and is guaranteed to be after any edit the user just made
        // in Music. Coalesced inside the cache, so repeat hovers cost nothing.
        SetlistManager.warmMusicTrims()
        onTargeted(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasAcceptableDrag(sender) else { return [] }
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onTargeted(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onTargeted(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { hasAcceptableDrag(sender) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargeted(false)
        let pasteboard = sender.draggingPasteboard
        let types = pasteboard.types ?? []
        os_log("performDrag types=%{public}@", log: dropLog, type: .info,
               String(describing: types))
        let musicIDs = Self.musicDragIDs(pasteboard)

        // 1. Modern NSFilePromiseReceiver — for future Music.app versions.
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self],
                                                  options: nil) as? [NSFilePromiseReceiver],
           !promises.isEmpty
        {
            return acceptFilePromises(promises, musicIDs: musicIDs)
        }

        // 2. Legacy file-promise — Music.app on Sequoia for iTunes-purchased AAC.
        if types.contains(Self.legacyPromiseURLType)
            || types.contains(Self.legacyPromiseContentsType)
        {
            return acceptLegacyFilePromise(sender, musicIDs: musicIDs)
        }

        // 3. Legacy plist path — pre-Sequoia purchased AAC.
        if types.contains(Self.musicMetadataType) {
            let urls = resolveViaMusicMetadata(pasteboard)
            if !urls.isEmpty { onDrop(urls, musicIDs); return true }
        }

        // 4. Plain file URL — Finder, Swinsian, AIFF-from-Music drags.
        if types.contains(Self.fileURLType) {
            let pbURLs = pasteboard.readObjects(forClasses: [NSURL.self],
                                                 options: [.urlReadingFileURLsOnly: true]) as? [URL]
            if let pbURLs = pbURLs, !pbURLs.isEmpty {
                os_log("file-url path resolved %d url(s)", log: dropLog, type: .info, pbURLs.count)
                onDrop(pbURLs, musicIDs)
                return true
            }
        }

        // 5. AppleScript selection fallback — com.apple.itunes.drag only.
        // Synchronous and slow (Music.app library query) — kept as a last resort.
        if types.contains(Self.pasteboardType) {
            let urls = resolveViaMusicSelection()
            if !urls.isEmpty { onDrop(urls, musicIDs); return true }
        }

        os_log("performDrag resolved zero urls", log: dropLog, type: .error)
        return false
    }

    // Legacy file-promise path. Music.app on Sequoia advertises
    // com.apple.pasteboard.promised-file-url on the root pasteboard, but in
    // practice only a small subset of per-item NSPasteboardItems carry the
    // promise string — the rest carry just public.file-url. Read file-url
    // first per item and fall back to the promise string, so multi-track
    // drags (e.g. an entire 108-track playlist) aren't truncated to the
    // few items that happen to advertise the promise flavor.
    //
    // If none of the items resolve to an on-disk file, fall back to
    // namesOfPromisedFilesDropped to ask Music.app to materialise the files
    // in our app-support cache (the genuine cloud-only case).
    private func acceptLegacyFilePromise(_ sender: NSDraggingInfo, musicIDs: MusicDragIDs) -> Bool {
        let pb = sender.draggingPasteboard

        let items = pb.pasteboardItems ?? []
        // How many items advertise a file flavor at all — the count we expect to
        // resolve. Cloud-only tracks advertise a file-url/promise but have no
        // on-disk file, so they pass this test yet fail per-item resolution below.
        let advertisedCount = items.filter {
            $0.string(forType: .fileURL) != nil
                || $0.string(forType: Self.legacyPromiseURLType) != nil
        }.count

        var urls: [URL] = []
        for item in items {
            // Try public.file-url first, then the promise string. Per-item
            // fallback (not `??` on the strings) so a broken file-url doesn't
            // prevent us from trying the promise flavor on the same item —
            // protects the v3.21.4 iTunes-purchased-AAC drag case.
            let candidates = [
                item.string(forType: .fileURL),
                item.string(forType: Self.legacyPromiseURLType),
            ].compactMap { $0 }
            for str in candidates {
                guard let url = URL(string: str),
                      url.isFileURL,
                      FileManager.default.fileExists(atPath: url.path)
                else { continue }
                urls.append(url)
                break
            }
        }
        // Fast path only when every advertised item resolved to an on-disk file.
        // A partial resolve means the selection mixes downloaded and cloud-only
        // tracks — the unresolved ones would be silently dropped, so fall through
        // to materialise the whole selection instead of returning a truncated set.
        if !urls.isEmpty && urls.count >= advertisedCount {
            os_log("promise resolved %d url(s) from pasteboard string",
                   log: dropLog, type: .info, urls.count)
            onDrop(urls, musicIDs)
            return true
        }

        // Partial or zero local resolution — ask Music.app to materialise the
        // promised files (writes cached copies of every track, cloud-only included).
        // Blocking, but only hit when the drag isn't fully local on disk.
        os_log("promise partial: resolved %d of %d advertised — materialising",
               log: dropLog, type: .info, urls.count, advertisedCount)
        let destDir = Self.filePromiseDestination()
        let names = sender.namesOfPromisedFilesDropped(atDestination: destDir) ?? []
        let writtenURLs = names.map { destDir.appendingPathComponent($0) }
        os_log("promise materialised %d file(s) at %{public}@",
               log: dropLog, type: .info, names.count, destDir.path)
        if !writtenURLs.isEmpty {
            onDrop(writtenURLs, musicIDs)
            return true
        }
        // Materialise yielded nothing — fall back to whatever local URLs resolved.
        guard !urls.isEmpty else { return false }
        onDrop(urls, musicIDs)
        return true
    }

    // Accept one or more NSFilePromiseReceiver promises, writing the files to a
    // persistent cache directory inside Application Support. Calls onDrop once all
    // promises have either resolved or failed. Returns true synchronously so the
    // drag UI completes immediately; the resulting URLs land asynchronously.
    private func acceptFilePromises(_ promises: [NSFilePromiseReceiver], musicIDs: MusicDragIDs) -> Bool {
        let destDir = Self.filePromiseDestination()
        os_log("accepting %d file promise(s) to %{public}@",
               log: dropLog, type: .info, promises.count, destDir.path)
        let lock = NSLock()
        var receivedURLs: [URL] = []
        let group = DispatchGroup()
        for promise in promises {
            group.enter()
            promise.receivePromisedFiles(atDestination: destDir,
                                          options: [:],
                                          operationQueue: promiseQueue) { url, error in
                if let error = error {
                    os_log("file promise error: %{public}@", log: dropLog, type: .error,
                           String(describing: error))
                } else {
                    os_log("received promised file: %{public}@", log: dropLog, type: .info, url.path)
                    lock.lock(); receivedURLs.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            if receivedURLs.isEmpty {
                os_log("file promises yielded zero urls", log: dropLog, type: .error)
            } else {
                self.onDrop(receivedURLs, musicIDs)
            }
        }
        return true
    }

    private static func filePromiseDestination() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("TangoDisplay/MusicAppDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Music.app puts com.apple.music.metadata on the drag pasteboard for post-2022
    // purchased AAC tracks. Two known plist structures (varies by Music.app version):
    //   Newer: {"Tracks": {"12345": {"Location": "…"}}, "Playlists": […]}
    //   Older: {"12345": {"Location": "…"}, "Playlist Items": […]}
    // Location is either a "~/…" tilde path or a "file://…" URL (Embrace handles both).
    // Falls back to reading public.file-url directly if the plist yields nothing.
    // Music's persistent IDs for the dragged tracks, straight off the pasteboard — free and
    // instant. Only the IDs: the plist has no Start/Stop Time (verified against a track with
    // start = 90s), so the times still come from the ITLibrary scan warmed in draggingEntered.
    static func musicDragIDs(_ pasteboard: NSPasteboard) -> MusicDragIDs {
        for item in pasteboard.pasteboardItems ?? [] {
            for type in [tvMetadataType, itunMetadataType, musicMetadataType] {
                guard let plist = item.propertyList(forType: type) as? [String: Any] else { continue }
                let ids = MusicDragIDs(musicMetadataPlist: plist)
                if !ids.isEmpty {
                    os_log("music drag ids: %d track(s) from %{public}@",
                           log: dropLog, type: .info, ids.count, type.rawValue)
                    return ids
                }
            }
        }
        // Root-pasteboard fallback: the flavors are sometimes only advertised there.
        for type in [tvMetadataType, itunMetadataType, musicMetadataType] {
            guard let data = pasteboard.data(forType: type),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = plist as? [String: Any] else { continue }
            let ids = MusicDragIDs(musicMetadataPlist: dict)
            if !ids.isEmpty {
                os_log("music drag ids: %d track(s) from root %{public}@",
                       log: dropLog, type: .info, ids.count, type.rawValue)
                return ids
            }
        }
        os_log("music drag ids: none on pasteboard", log: dropLog, type: .info)
        return MusicDragIDs()
    }

    private func resolveViaMusicMetadata(_ pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        for item in pasteboard.pasteboardItems ?? [] {
            guard let plist = item.propertyList(forType: Self.musicMetadataType) as? [String: Any]
            else {
                os_log("plist cast failed for pasteboard item", log: dropLog, type: .error)
                continue
            }
            // Use the "Tracks" sub-dict if present (newer format), otherwise the root
            let trackSource = (plist["Tracks"] as? [String: Any]) ?? plist
            os_log("plist keys=%{public}@ trackSource keys=%{public}@",
                   log: dropLog, type: .info,
                   String(describing: Array(plist.keys)),
                   String(describing: Array(trackSource.keys)))
            for (_, value) in trackSource {
                guard let track = value as? [String: Any],
                      var location = track["Location"] as? String,
                      !location.isEmpty else { continue }
                let raw = location
                if location.hasPrefix("file:") {
                    location = URL(string: location)?.path ?? location
                }
                let path = NSString(string: location).expandingTildeInPath
                let url = URL(fileURLWithPath: path)
                let exists = FileManager.default.fileExists(atPath: url.path)
                os_log("track loc=%{public}@ → url=%{public}@ exists=%{public}@",
                       log: dropLog, type: .info, raw, url.path, String(exists))
                if url.isFileURL { urls.append(url) }
            }
        }
        os_log("resolveViaMusicMetadata produced %d urls", log: dropLog, type: .info, urls.count)
        if !urls.isEmpty { return urls }

        // Fallback: Music.app may also offer a direct public.file-url on the same item
        for item in pasteboard.pasteboardItems ?? [] {
            if let str = item.string(forType: .fileURL),
               let url = URL(string: str) {
                urls.append(url.standardized)
            }
        }
        os_log("fallback file-url produced %d urls", log: dropLog, type: .info, urls.count)
        return urls
    }

    // WARNING: synchronous Apple event on the drop path. Music will not answer one while it
    // is finishing a drag out of itself — measured at a flat 24.7s timeout, freezing the UI.
    // Kept only because this is strategy 5 of 5: by the time we get here the alternative is
    // the drag failing outright. Never add an Apple event to any earlier strategy.
    private func resolveViaMusicSelection() -> [URL] {
        let source = """
        tell application "Music"
            set paths to {}
            repeat with t in selection
                try
                    set end of paths to POSIX path of (location of t as alias)
                end try
            end repeat
            return paths
        end tell
        """
        let script = NSAppleScript(source: source)
        var errorInfo: NSDictionary?
        guard let descriptor = script?.executeAndReturnError(&errorInfo) else { return [] }
        var urls: [URL] = []
        if descriptor.numberOfItems > 0 {
            for i in 1...descriptor.numberOfItems {
                if let path = descriptor.atIndex(i)?.stringValue {
                    urls.append(URL(fileURLWithPath: path))
                }
            }
        } else if let path = descriptor.stringValue, !path.isEmpty {
            urls.append(URL(fileURLWithPath: path))
        }
        return urls
    }
}

// Replaces the NSWindow's contentView with MusicAppDropView, re-parenting the
// original contentView (typically SwiftUI's NSHostingView) underneath. Owning
// contentView outright — rather than wrapping its subviews — survives any
// SwiftUI rebuild that re-asserts the hosting hierarchy and guarantees the
// drop view is always in AppKit's drag routing path.
//
// Type registration on MusicAppDropView is intentionally limited to
// com.apple.music.metadata and com.apple.itunes.drag, so AppKit's drag walk-up
// only stops here for Music.app drags. Drags carrying public.file-url (Finder,
// Swinsian, AIFF from Music) flow past us to SwiftUI's .onDrop handler as today.
private struct MusicAppWindowDropInstaller: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: ([URL], MusicDragIDs) -> Void

    func makeNSView(context: Context) -> InstallerSentinel { InstallerSentinel() }

    func updateNSView(_ nsView: InstallerSentinel, context: Context) {
        nsView.update(isTargetedBinding: $isTargeted, onDrop: onDrop)
    }

    class InstallerSentinel: NSView {
        private weak var dropView: MusicAppDropView?
        private var pendingBinding: Binding<Bool>?
        private var pendingDrop: (([URL], MusicDragIDs) -> Void)?
        private var contentViewObserver: NSKeyValueObservation?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }
        required init?(coder: NSCoder) { fatalError() }

        deinit {
            contentViewObserver?.invalidate()
        }

        func update(isTargetedBinding: Binding<Bool>, onDrop: @escaping ([URL], MusicDragIDs) -> Void) {
            pendingBinding = isTargetedBinding
            pendingDrop    = onDrop
            if let dv = dropView {
                configure(dv, binding: isTargetedBinding, onDrop: onDrop)
            } else if window != nil {
                install()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, dropView == nil else { return }
            install()
        }

        private func install() {
            guard let window = self.window,
                  let binding = pendingBinding,
                  let drop = pendingDrop else { return }

            // Already installed?
            if let dv = window.contentView as? MusicAppDropView {
                configure(dv, binding: binding, onDrop: drop)
                dropView = dv
                observeContentView(on: window)
                return
            }

            let oldContent = window.contentView
            let dv = MusicAppDropView(frame: oldContent?.frame ?? window.contentLayoutRect)
            dv.autoresizingMask = [.width, .height]
            window.contentView = dv
            if let oldContent = oldContent {
                oldContent.translatesAutoresizingMaskIntoConstraints = true
                oldContent.frame = dv.bounds
                oldContent.autoresizingMask = [.width, .height]
                dv.addSubview(oldContent)
            }
            os_log("replaced contentView; previousContent=%{public}@ newFrame=%{public}@",
                   log: dropLog, type: .info,
                   String(describing: oldContent.map { type(of: $0) } ?? NSObject.self),
                   String(describing: dv.frame))
            configure(dv, binding: binding, onDrop: drop)
            dropView = dv
            observeContentView(on: window)
        }

        private func observeContentView(on window: NSWindow) {
            contentViewObserver?.invalidate()
            contentViewObserver = window.observe(\.contentView, options: [.new]) { [weak self] win, _ in
                guard let self = self else { return }
                if !(win.contentView is MusicAppDropView) {
                    os_log("contentView reset detected — re-installing", log: dropLog, type: .error)
                    self.dropView = nil
                    self.install()
                }
            }
        }

        private func configure(_ dv: MusicAppDropView,
                                binding: Binding<Bool>,
                                onDrop: @escaping ([URL], MusicDragIDs) -> Void) {
            dv.onTargeted = { t in DispatchQueue.main.async { binding.wrappedValue = t } }
            dv.onDrop = onDrop
        }
    }
}

private func setlistFormatDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}

struct SetlistView: View {
    @ObservedObject var setlist: SetlistManager
    let player: LocalPlayerSource
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var reportStore: SetlistReportStore
    @EnvironmentObject var configStore: PluginConfigurationStore
    @Environment(\.openWindow) private var openWindow
    @State private var isDragTargeted = false
    @State private var activeEntryID: UUID? = nil
    @State private var isPlayerActive: Bool = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showClearConfirmation = false
    @State private var pendingDeleteIDs: Set<UUID>? = nil
    @State private var showExportDialog = false
    @State private var exportPlaylistName = ""
    @State private var showExportError = false
    @State private var exportErrorMessage = ""
    @State private var showSaveReportDialog = false
    @State private var saveReportName = ""
    @State private var showSaveReportError = false
    @State private var saveReportErrorMessage = ""
    @State private var showEQPopover = false
    @State private var showBalancePopover = false
    @State private var showAutoGapPopover = false
    @State private var showReplayGainPopover = false
    @State private var showRestorationPopover = false
    @State private var showPluginChainPopover = false
    @State private var scrollTrigger: UUID? = nil
    @State private var showLastTandaWarning = false
    @State private var pendingRepeatID: UUID?
    @State private var editingUpcoming: SetlistEntry?
    @State private var pasteMonitor: Any? = nil
    @State private var hogConflictWarning = false
    @State private var hogDeviceStolenAlertShown = false
    @State private var engineStalledAlertShown = false
    @State private var dropFeedback: String? = nil

    // Seed the @State mirrors from the player so the very first body render
    // after this view is (re-)created already reflects the live playing track.
    // Without this, returning to the Setlist tab while a track is past its
    // mark-as-played threshold renders one frame with activeEntryID=nil and
    // isPlayerActive=false — Hide Played then filters the playing row out,
    // and the row that re-appears after .onAppear briefly shows as "played".
    init(setlist: SetlistManager, player: LocalPlayerSource) {
        self._setlist = ObservedObject(wrappedValue: setlist)
        self.player = player
        self._activeEntryID = State(initialValue: player.currentEntryID)
        self._isPlayerActive = State(initialValue: player.isActivePlaying)
        self._hogConflictWarning = State(initialValue: player.hogModeConflict)
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerControlsView(player: player, onScrollToCurrentTrack: {
                scrollTrigger = activeEntryID
            })
            .environmentObject(appState)

            Divider()

            if hogConflictWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text("Another app has exclusive access to the audio output. Playback may fail — go to Player Settings to release it.")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Retry") {
                        player.retryOutputDevice()
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.borderless)
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                Divider()
            }

            let visibleEntries = settings.hidePlayed
                ? setlist.entries.filter { $0.state != .played || $0.id == activeEntryID }
                : setlist.entries
            let hiddenCount = setlist.entries.count - visibleEntries.count
            if settings.hidePlayed && hiddenCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 11))
                    Text("^[\(hiddenCount) played track](inflect: true) hidden")
                        .font(.system(size: 11))
                    Spacer()
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                Divider()
            }
            if visibleEntries.isEmpty {
                emptyDropZone
            } else {
                ScrollViewReader { proxy in
                    trackList
                        .onChange(of: scrollTrigger) { id in
                            guard let id else { return }
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                            scrollTrigger = nil
                        }
                }
            }

            if !setlist.entries.isEmpty {
                Divider()
                StatusBarView(player: player, setlist: setlist, selectedIDs: selectedIDs)
            }
        }
        .onAppear {
            activeEntryID = player.currentEntryID
            isPlayerActive = player.isActivePlaying
            hogConflictWarning = player.hogModeConflict
            guard pasteMonitor == nil else { return }
            pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "v",
                      !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
                pasteFromClipboard()
                return nil
            }
        }
        .onDisappear {
            if let m = pasteMonitor { NSEvent.removeMonitor(m); pasteMonitor = nil }
        }
        .background(
            MusicAppWindowDropInstaller(isTargeted: $isDragTargeted) { urls, musicIDs in
                handleIncomingURLs(urls, anchorID: nil, musicIDs: musicIDs)
            }
        )
        .onReceive(player.$currentEntryID) { activeEntryID = $0 }
        .onReceive(player.$isActivePlaying) { isPlayerActive = $0 }
        .onReceive(player.$hogModeConflict) { hogConflictWarning = $0 }
        .onReceive(player.$hogDeviceStolenAlert) { if $0 { hogDeviceStolenAlertShown = true } }
        .alert("Playback Interrupted", isPresented: $hogDeviceStolenAlertShown) {
            Button("Retry") { player.retryOutputDevice() }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Another app has taken exclusive access of the audio output device, so playback was paused. Release the exclusive access in that app, then tap Retry.")
        }
        .onReceive(player.$engineStalled) { if $0 { engineStalledAlertShown = true } }
        .alert("Audio Device Unavailable", isPresented: $engineStalledAlertShown) {
            Button("Retry") { player.retryOutputDevice() }
            Button("OK", role: .cancel) {}
        } message: {
            Text("The audio output device did not come back, so playback was stopped. Check the device is connected and powered on, then tap Retry.")
        }
        .alert("Save Setlist Report", isPresented: $showSaveReportDialog) {
            TextField("Setlist name", text: $saveReportName)
            Button("Save") {
                let trimmed = saveReportName.trimmingCharacters(in: .whitespaces)
                let name = trimmed.isEmpty ? Self.defaultExportName() : trimmed
                saveSetlistReport(name: name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this setlist export. It will appear in the Reports tab.")
        }
        .alert("Save Failed", isPresented: $showSaveReportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveReportErrorMessage)
        }
        .toolbar {
            if settings.decibelMeterEnabled {
                ToolbarItem(placement: .automatic) {
                    DecibelToolbarLabel(
                        monitor: appState.microphoneMonitor,
                        low:  settings.decibelMeterLowThreshold,
                        high: settings.decibelMeterHighThreshold
                    )
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Export to Apple Music") {
                        exportPlaylistName = Self.defaultExportName()
                        showExportDialog = true
                    }
                    Button("Export to M3U8…") {
                        exportM3U8()
                    }
                    Divider()
                    Button("Save Setlist Report…") {
                        saveReportName = Self.defaultExportName()
                        showSaveReportDialog = true
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(setlist.entries.isEmpty)
                .help("Export setlist to Apple Music, M3U8, or save a report")
            }
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 2) {
                    Button { showEQPopover.toggle() } label: {
                        Label("Equaliser", systemImage: "slider.horizontal.3")
                    }
                    .disabled(!isPlayerActive)
                    .popover(isPresented: $showEQPopover) {
                        EQView().environmentObject(settings)
                    }
                    .help("Equaliser")
                    Button { showBalancePopover.toggle() } label: {
                        Label("Balance", systemImage: "dial.medium")
                    }
                    .disabled(!isPlayerActive)
                    .popover(isPresented: $showBalancePopover) {
                        BalanceView().environmentObject(settings)
                    }
                    .help("Stereo balance")
                    Button { showAutoGapPopover.toggle() } label: {
                        Label("Auto-gap", systemImage: "timer")
                    }
                    .disabled(!settings.autoGapEnabled)
                    .popover(isPresented: $showAutoGapPopover) {
                        AutoGapPopoverView().environmentObject(settings)
                    }
                    .help("Auto-gap between tracks")
                    Button { showReplayGainPopover.toggle() } label: {
                        Label("ReplayGain", systemImage: "waveform")
                    }
                    .popover(isPresented: $showReplayGainPopover) {
                        ReplayGainPopoverView(player: player)
                            .environmentObject(settings)
                    }
                    .help("ReplayGain normalisation")
                    // Never disabled, like ReplayGain: this is set-level configuration you
                    // set up before starting, not a live-only control like EQ or Balance.
                    // State has to be readable without opening the popover, hence the tint
                    // plus a dot — a toolbar button style can drop the tint, but an overlay
                    // always draws.
                    Button { showRestorationPopover.toggle() } label: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(settings.restoration.enabled ? Color.accentColor : Color.secondary)
                            .overlay(alignment: .topTrailing) {
                                if settings.restoration.enabled {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 5, height: 5)
                                        .offset(x: 3, y: -2)
                                }
                            }
                            .accessibilityLabel(settings.restoration.enabled
                                                ? "Restoration on" : "Restoration off")
                    }
                    .popover(isPresented: $showRestorationPopover) {
                        RestorationPopoverView().environmentObject(settings)
                    }
                    .help(settings.restoration.enabled
                          ? "Shellac restoration — on (declick and dehum)"
                          : "Shellac restoration — off")
                    if !settings.audioUnitPluginChain.isEmpty {
                        Button { showPluginChainPopover.toggle() } label: {
                            Label("Plugins", systemImage: "puzzlepiece.fill")
                        }
                        .popover(isPresented: $showPluginChainPopover) {
                            PluginChainPopoverView(player: player)
                                .environmentObject(settings)
                        }
                        .help("Audio Unit plugin chain")
                    }
                    Button { openWindow(id: "waveform") } label: {
                        Label("Waveform", systemImage: "waveform.path")
                    }
                    .disabled(player.currentEntryID == nil)
                    .help("View waveform for current track")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    settings.hidePlayed.toggle()
                    let target = activeEntryID
                        ?? setlist.entries.first(where: { $0.state != .played })?.id
                    scrollTrigger = target
                } label: {
                    Label("Hide Played", systemImage: settings.hidePlayed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .disabled(setlist.entries.isEmpty)
                .help(settings.hidePlayed ? "Show played tracks" : "Hide played tracks")
            }
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) { showClearConfirmation = true } label: {
                    Label("Clear Setlist", systemImage: "trash")
                }
                .disabled(setlist.entries.isEmpty)
                .help("Clear all tracks from setlist")
            }
        }
        .confirmationDialog(
            "Clear Setlist?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { setlist.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if isPlayerActive {
                Text("Playback will stop and all tracks will be removed.")
            } else {
                Text("All tracks will be removed.")
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: Binding(
                get: { pendingDeleteIDs != nil },
                set: { if !$0 { pendingDeleteIDs = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let ids = pendingDeleteIDs {
                    setlist.remove(ids: ids)
                    selectedIDs.subtract(ids)
                    pendingDeleteIDs = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteIDs = nil }
        }
        .alert("Export to Apple Music", isPresented: $showExportDialog) {
            TextField("Playlist name", text: $exportPlaylistName)
            Button("Export") {
                let trimmed = exportPlaylistName.trimmingCharacters(in: .whitespaces)
                let name = trimmed.isEmpty ? Self.defaultExportName() : trimmed
                let urls = setlist.entries.map(\.fileURL)
                createAppleMusicPlaylist(name: name, fileURLs: urls) { result in
                    if case .failure(let error) = result {
                        exportErrorMessage = error.localizedDescription
                        showExportError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
        .alert("Last Tanda Not Configured", isPresented: $showLastTandaWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Set the Last Tanda label text in Appearance Settings before marking a Last Tanda.")
        }
        .alert("Track Set to Stop after Playing",
               isPresented: Binding(get: { pendingRepeatID != nil },
                                    set: { if !$0 { pendingRepeatID = nil } })) {
            Button("Repeat Instead") {
                if let id = pendingRepeatID { setlist.setRepeat(true, for: id) }
                pendingRepeatID = nil
            }
            Button("Cancel", role: .cancel) { pendingRepeatID = nil }
        } message: {
            Text("This track is marked Stop after Playing. Remove that and repeat it instead?")
        }
        .sheet(item: $editingUpcoming) { entry in
            UpcomingInfoEditor(entry: entry)
        }
    }

    // MARK: - Empty state

    private var emptyDropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundColor(isDragTargeted ? ControlTheme.accent : .secondary)
            Text("Drag tracks here, or copy in your music app and press ⌘V")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDragTargeted ? ControlTheme.accent.opacity(0.08) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
        // No SwiftUI .onDrop: SwiftUI's NSHostingView registration for the drop
        // type intercepts Music.app's promise-based drag before AppKit's walk-up
        // reaches MusicAppDropView. The window-level MusicAppDropView handles
        // public.file-url, Music.app drags, and visual targeting in this state.
    }

    // MARK: - Drop handling

    private func handleIncomingURLs(_ urls: [URL], anchorID: UUID?,
                                    musicIDs: MusicDragIDs = MusicDragIDs()) {
        // Reject files that no longer exist on disk (e.g. a Music track whose
        // underlying file is missing — shown with a warning triangle in Music).
        // Otherwise they enter the setlist and get silently skipped at playback.
        let valid = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        let missingCount = urls.count - valid.count
        if missingCount > 0 { showMissingFileAlert(missingCount) }
        // Import Music's per-track start/stop into trim markers only when the built-in
        // player is active — trim only affects playback there, matching the manual editor gate.
        let importMusicTimes = appState.localPlayer != nil

        guard !valid.isEmpty else { return }

        guard settings.duplicateTrackProtection else {
            setlist.insertURLs(valid, before: anchorID, importMusicTimes: importMusicTimes,
                               musicIDs: musicIDs)
            return
        }

        let existingURLs = Set(setlist.entries.map(\.fileURL))
        guard valid.contains(where: { existingURLs.contains($0) }) else {
            setlist.insertURLs(valid, before: anchorID, importMusicTimes: importMusicTimes,
                               musicIDs: musicIDs)
            return
        }

        let shouldAddDuplicates: Bool
        switch setlist.duplicateSessionDecision {
        case .alwaysAdd:
            shouldAddDuplicates = true
        case .neverAdd:
            shouldAddDuplicates = false
        case nil:
            let dupURLs = valid.filter { existingURLs.contains($0) }
            let matchedPlayed = setlist.entries.contains {
                $0.state == .played && dupURLs.contains($0.fileURL)
            }
            let (shouldAdd, remember) = promptForDuplicates(count: dupURLs.count, alreadyPlayed: matchedPlayed)
            if remember { setlist.setDuplicateSessionDecision(shouldAdd ? .alwaysAdd : .neverAdd) }
            shouldAddDuplicates = shouldAdd
        }

        let toInsert = shouldAddDuplicates ? valid : valid.filter { !existingURLs.contains($0) }
        if !toInsert.isEmpty {
            setlist.insertURLs(toInsert, before: anchorID, importMusicTimes: importMusicTimes,
                               musicIDs: musicIDs)
        }

        let skipped = valid.count - toInsert.count
        if skipped > 0 {
            showDropFeedback("Added \(toInsert.count) — \(skipped) already in set")
        }
    }

    private func showMissingFileAlert(_ n: Int) {
        let alert = NSAlert()
        alert.messageText = n == 1 ? "Track Not Added" : "Tracks Not Added"
        alert.informativeText = n == 1
            ? "1 dragged track was skipped because its file could not be found."
            : "\(n) dragged tracks were skipped because their files could not be found."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // Brief auto-dismissing note in the bottom drop-hint slot, so silently
    // filtered duplicates aren't misread as a failed drag.
    private func showDropFeedback(_ message: String) {
        withAnimation { dropFeedback = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation { dropFeedback = nil }
        }
    }

    private func promptForDuplicates(count: Int, alreadyPlayed: Bool) -> (shouldAdd: Bool, remember: Bool) {
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Track Already in Setlist" : "Tracks Already in Setlist"
        if count == 1 {
            alert.informativeText = alreadyPlayed
                ? "This track has already been played in this set. Add anyway?"
                : "This track already exists in this set. Add anyway?"
        } else {
            alert.informativeText = alreadyPlayed
                ? "\(count) tracks have already been played in this set. Add anyway?"
                : "\(count) tracks are already in this set. Add anyway?"
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Don't Add")

        let checkbox = NSButton(checkboxWithTitle: "Remember for this session", target: nil, action: nil)
        checkbox.sizeToFit()
        alert.accessoryView = checkbox

        let result = alert.runModal()
        return (
            shouldAdd: result == .alertFirstButtonReturn,
            remember: checkbox.state == .on
        )
    }

    // MARK: - Track list

    private var nextToPlayID: UUID? {
        guard !isPlayerActive else { return nil }
        if let id = activeEntryID { return id }
        guard !setlist.entries.contains(where: { $0.state == .playing || $0.state == .paused })
        else { return nil }
        return setlist.entries.first(where: { $0.state == .queued })?.id
    }

    @ViewBuilder
    private func rowView(for entry: SetlistEntry, wouldSkipAutoGap: Bool) -> some View {
        let detector = settings.makeDetector()
        SetlistRowView(
            entry: entry,
            isStopAfter: entry.id == setlist.stopAfterEntryID
                      || (entry.isPerformance && settings.stopAfterEachPerformanceTrack),
            isActivelyPlaying: activeEntryID == entry.id && isPlayerActive,
            isNextToPlay: entry.id == nextToPlayID,
            showYear: settings.showYear,
            showTime: settings.showTime,
            showComments: settings.showComments,
            showAlbumArtist: settings.showAlbumArtist,
            showGrouping: settings.showGrouping,
            wouldSkipAutoGap: wouldSkipAutoGap,
            autoFadeCortinasEnabled: settings.autoFadeCortinasEnabled,
            isLastTanda: entry.isLastTanda,
            configurationName: entry.pluginConfigurationID.flatMap { configStore.configuration(id: $0)?.name },
            genreColorsEnabled: settings.genreColorsEnabled,
            genreColorRules: settings.genreColorRules,
            genreColorTitleEnabled: settings.genreColorTitleEnabled,
            isCortina: detector.isCortina(genre: entry.track.genre),
            player: activeEntryID == entry.id && isPlayerActive ? player : nil
        )
        .tag(entry.id)
        .moveDisabled(entry.state == .playing)
        // NSViewRepresentable overlay handles double-click without adding any
        // SwiftUI gesture recognizer — keeping NSTableView's primary click
        // handler free to process single/multi-selection.
        .overlay(DoubleClickOverlay { player.jumpTo(entry) })
        .contextMenu {
            let targets: Set<UUID> = selectedIDs.contains(entry.id)
                ? selectedIDs : [entry.id]
            rowContextMenu(entry: entry, targets: targets)
        }
    }

    private var trackList: some View {
        let firstID = setlist.entries.first?.id
        let nonePlayedYet = !setlist.entries.contains(where: { $0.state == .played })
        let entries = settings.hidePlayed
            ? setlist.entries.filter { $0.state != .played || $0.id == activeEntryID }
            : setlist.entries
        return List(selection: $selectedIDs) {
            ForEach(entries) { entry in
                let autoGapIgnored = settings.autoGapEnabled &&
                    entry.autoGapIgnored(isFirstTrack: nonePlayedYet && entry.id == firstID,
                                         ignoreFirstTrack: settings.autoGapIgnoreFirstTrack)
                rowView(for: entry, wouldSkipAutoGap: autoGapIgnored)
            }
            .onMove { source, dest in
                // The ForEach iterates `entries` (filtered when Hide Played is on),
                // so SwiftUI's offsets are into the filtered array. Map back to
                // master-array offsets via stable UUIDs before mutating.
                let sourceIDs = source.compactMap { entries[safe: $0]?.id }
                let masterSource = IndexSet(sourceIDs.compactMap { id in
                    setlist.entries.firstIndex(where: { $0.id == id })
                })
                let masterDest: Int
                if dest < entries.count {
                    let destID = entries[dest].id
                    masterDest = setlist.entries.firstIndex(where: { $0.id == destID }) ?? setlist.entries.count
                } else {
                    masterDest = setlist.entries.count
                }
                setlist.move(from: masterSource, to: masterDest)
            }
            .onDelete { offsets in
                let ids = Set(offsets.compactMap { entries[safe: $0]?.id })
                pendingDeleteIDs = ids
            }
            .onInsert(of: [.fileURL]) { offset, providers in
                // Convert the integer offset to a stable UUID anchor immediately,
                // before any async work — the list may mutate during URL/metadata loading.
                // Index the filtered `entries` (what the ForEach actually rendered),
                // not `setlist.entries`, so the anchor is correct when Hide Played is on.
                let anchorID: UUID? = offset < entries.count
                    ? entries[offset].id
                    : nil
                Task {
                    let urls = await loadURLs(from: providers)
                    handleIncomingURLs(urls, anchorID: anchorID)
                }
            }
        }
        .listStyle(.plain)
        .overlay(alignment: .bottom) {
            if let dropFeedback {
                Text(dropFeedback)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                    .transition(.opacity)
            } else {
                dropHint
            }
        }
    }

    private var deleteConfirmationTitle: String {
        let count = pendingDeleteIDs?.count ?? 0
        return count == 1 ? "Delete Track?" : "Delete \(count) Tracks?"
    }

    @ViewBuilder
    private func rowContextMenu(entry: SetlistEntry, targets: Set<UUID>) -> some View {
        let allPlayed = targets.allSatisfy { id in
            setlist.entries.first(where: { $0.id == id })?.state == .played
        }
        if allPlayed {
            Button("Mark as Not Played") { setlist.markUnplayed(ids: targets) }
        } else {
            Button("Mark as Played") {
                setlist.markPlayed(ids: targets)
                selectedIDs.subtract(targets)
            }
        }
        if targets.count == 1, let id = targets.first,
           let e = setlist.entries.first(where: { $0.id == id }) {
            Divider()
            if e.state != .played || e.id == player.currentEntryID {
                Button {
                    if setlist.stopAfterEntryID == id {
                        setlist.stopAfterEntryID = nil
                    } else {
                        setlist.stopAfterEntryID = id
                        setlist.setRepeat(false, for: id)   // stop-after supersedes repeat
                    }
                } label: {
                    Text(setlist.stopAfterEntryID == id ? "Resume after Playing" : "Stop after Playing")
                }
            }
            if e.state == .queued || e.state == .paused {
                let nonePlayed = !setlist.entries.contains { $0.state == .played }
                let eff = settings.autoGapEnabled &&
                    e.autoGapIgnored(isFirstTrack: nonePlayed && e.id == setlist.entries.first?.id,
                                     ignoreFirstTrack: settings.autoGapIgnoreFirstTrack)
                Button(eff ? "Resume Auto-gap" : "Ignore Auto-gap before this Track") {
                    setlist.setAutoGapOverride(id: id, ignore: !eff)
                }
            }
        }
        let detector = settings.makeDetector()
        // Shellac restoration: single track, built-in player only (only it has the graph).
        // An override outranks the master switch, so a lone shellac transfer can be
        // repaired in an otherwise unrestored set — and vice versa.
        if targets.count == 1, let id = targets.first,
           let e = setlist.entries.first(where: { $0.id == id }),
           appState.localPlayer != nil {
            Divider()
            let byDefault = settings.restoration.appliesByDefault(
                isCortina: detector.isCortina(genre: e.track.genre))
            let applied = e.restorationApplied(globalDefault: byDefault)
            Button(applied ? "Skip Restoration for this Track" : "Restore this Track") {
                setlist.setRestorationOverride(id: id, skip: applied)
            }
            if e.restorationOverride != nil {
                Button("Use Default Restoration") {
                    setlist.setRestorationOverride(id: id, skip: nil)
                }
            }
        }
        if settings.autoFadeCortinasEnabled && appState.fadeMode == .none {
            let autoFadeTargets = targets.filter { id in
                guard let e = setlist.entries.first(where: { $0.id == id }) else { return false }
                return (e.state != .played || e.id == player.currentEntryID) && detector.isCortina(genre: e.track.genre)
            }
            let skippable = autoFadeTargets.filter { id in
                !(setlist.entries.first(where: { $0.id == id })?.ignoresAutoFade ?? false)
            }
            if !skippable.isEmpty {
                Divider()
                Button("Skip Auto-fade") {
                    for id in skippable { appState.toggleIgnoresAutoFadeForEntry(id: id) }
                }
            }
        }
        // Last Tanda: single cortina entry not yet fully played
        if targets.count == 1, let id = targets.first,
           let e = setlist.entries.first(where: { $0.id == id }),
           detector.isCortina(genre: e.track.genre),
           e.state != .played || e.id == player.currentEntryID {
            Divider()
            Button(e.isLastTanda ? "Remove Last Tanda" : "Mark as Last Tanda") {
                if !e.isLastTanda &&
                   settings.lastTandaLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                    showLastTandaWarning = true
                } else {
                    appState.setLastTanda(id: id, value: !e.isLastTanda)
                }
            }
            Button(e.repeatTrack ? "Stop Repeating" : "Repeat Track") {
                if !e.repeatTrack && setlist.stopAfterEntryID == id {
                    pendingRepeatID = id
                } else {
                    setlist.setRepeat(!e.repeatTrack, for: id)
                }
            }
            Divider()
            Button("Edit Upcoming Info…") { editingUpcoming = e }
            if e.upcomingOverride != nil {
                Button("Clear Upcoming Info") {
                    setlist.setUpcomingOverride(nil, for: id)
                    appState.applyUpcomingOverride(nil, forCortinaEntry: id)
                }
            }
        }
        // Track start & end time: single track, built-in player only (only it can enforce the trim)
        if targets.count == 1, let id = targets.first,
           let e = setlist.entries.first(where: { $0.id == id }),
           appState.localPlayer != nil {
            Divider()
            Button("Track Start & End Time…") {
                appState.trimEditorEntryID = id
                openWindow(id: "trackTiming")
            }
            if e.trimStartSeconds != nil || e.trimEndSeconds != nil {
                Button("Clear Start & End Time") { setlist.clearTrim(for: id) }
            }
        }
        // Performance: available for any non-fully-played track(s)
        let performanceTargets = targets.filter { id in
            guard let e = setlist.entries.first(where: { $0.id == id }) else { return false }
            return e.state != .played || e.id == player.currentEntryID
        }
        if !performanceTargets.isEmpty {
            let areAllPerformance = performanceTargets.allSatisfy { id in
                setlist.entries.first(where: { $0.id == id })?.isPerformance ?? false
            }
            Divider()
            Button(areAllPerformance ? "Remove Performance Mark" : "Mark as Performance") {
                setlist.setPerformance(!areAllPerformance, for: performanceTargets)
            }
        }
        if !configStore.configurations.isEmpty {
            Divider()
            Menu("Apply Configuration") {
                Button("None") {
                    setlist.setPluginConfiguration(nil, for: targets)
                }
                Divider()
                ForEach(configStore.configurations) { config in
                    Button(config.name) {
                        setlist.setPluginConfiguration(config.id, for: targets)
                    }
                }
            }
        }
        Divider()
        let singleEntry = targets.count == 1 ? setlist.entries.first(where: { targets.contains($0.id) }) : nil
        let hasTag = singleEntry.map { $0.tagColor != TagColor.none } ?? targets.contains(where: { id in
            setlist.entries.first(where: { $0.id == id })?.tagColor != TagColor.none
        })
        if hasTag {
            Button("Clear Tag Colour") { setlist.setTagColor(.none, for: targets) }
        }
        ForEach(TagColor.allCases.filter { $0 != .none }, id: \.self) { colour in
            Button {
                setlist.setTagColor(colour, for: targets)
            } label: {
                Label {
                    Text(colour.displayName)
                } icon: {
                    Image(nsImage: colour.menuCircleImage)
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { pendingDeleteIDs = targets }
    }

    private func exportM3U8() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(Self.defaultExportName()).m3u8"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = ["#EXTM3U"]
        for entry in setlist.entries {
            let secs = Int(entry.duration ?? -1)
            lines.append("#EXTINF:\(secs),\(entry.track.artist) - \(entry.track.title)")
            lines.append(entry.fileURL.path)
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func saveSetlistReport(name: String) {
        let entries = setlist.entries.map { e in
            SetlistReportEntry(
                title: e.track.title,
                artist: e.track.artist,
                genre: settings.displayLabel(for: e.track.genre),
                year: e.track.year,
                albumArtist: e.track.albumArtist,
                duration: e.duration,
                isPlayed: e.state != .queued,
                isLastTanda: e.isLastTanda,
                isPerformance: e.isPerformance
            )
        }
        let report = SetlistReport(id: UUID(), name: name, exportDate: Date(), entries: entries)
        do {
            try reportStore.save(report)
        } catch {
            saveReportErrorMessage = error.localizedDescription
            showSaveReportError = true
        }
    }

    private static func defaultExportName() -> String {
        let f = DateFormatter()
        f.dateFormat = "ddMMyy HH:mm"
        return "Tango Display SetList \(f.string(from: Date()))"
    }

    private func pasteFromClipboard() {
        // ⌘C in Music puts the same metadata plist on the general pasteboard as a drag does,
        // so pasting from Music imports start/stop too. Warm the scan for the same reason
        // draggingEntered does.
        let musicIDs = MusicAppDropView.musicDragIDs(.general)
        if !musicIDs.isEmpty { SetlistManager.warmMusicTrims() }

        // Standard path: works for Finder, Music.app, etc.
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            handleIncomingURLs(urls, anchorID: nil, musicIDs: musicIDs)
            return
        }

        // foobar2000 (macOS) writes public.file-url as a bare POSIX path string
        // rather than a file:// URL, so readObjects yields nothing. Read per-item
        // and construct the URL directly from the path or file:// string.
        var perItemURLs: [URL] = []
        for item in NSPasteboard.general.pasteboardItems ?? [] {
            if let str = item.string(forType: .fileURL), !str.isEmpty {
                let url: URL
                if str.hasPrefix("file://") {
                    // percent-encode in case the app left spaces unencoded
                    url = URL(string: str) ?? URL(fileURLWithPath: String(str.dropFirst(7)))
                } else {
                    url = URL(fileURLWithPath: str)
                }
                if url.isFileURL { perItemURLs.append(url) }
            }
        }
        if !perItemURLs.isEmpty {
            handleIncomingURLs(perItemURLs, anchorID: nil)
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await resolveFileURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private func resolveFileURL(from provider: NSItemProvider) async -> URL? {
        // Standard path: works for Desktop, external volumes, most Finder drags.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        continuation.resume(returning: url)
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: url)
                    } else if let nsURL = item as? NSURL {
                        continuation.resume(returning: nsURL as URL)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let url, url.isFileURL { return url }
        }

        // Fallback: Apple Music purchases after ~July 2022 stored in Media.localized
        // are offered by Finder as public.audio rather than public.file-url on Sequoia.
        // openInPlace:true returns the original on-disk URL for non-sandboxed apps.
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(for: UTType.audio,
                                                openInPlace: true) { url, _, _ in
                    continuation.resume(returning: url)
                }
            }
            if let url, url.isFileURL { return url }
        }

        return nil
    }

    private var dropHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Drop tracks to add")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 8)
    }
}

// MARK: - Status bar (isolated observer — re-renders every 0.5 s without affecting SetlistView)

private struct StatusBarView: View {
    @ObservedObject var player: LocalPlayerSource
    @ObservedObject var setlist: SetlistManager
    var selectedIDs: Set<UUID>
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) var openWindow

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.autoGapEnabled ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(settings.autoGapEnabled
                        ? "Auto-gap: \(settings.autoGapDuration, specifier: "%.1f")s"
                        : "Auto-gap: off")
                }
                .font(.system(size: 11))
                .foregroundColor(settings.autoGapEnabled ? .primary : .secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.autoFadeCortinasEnabled ? Color.orange : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text("Auto-fade: \(settings.autoFadeCortinasEnabled ? "on" : "off")")
                }
                .font(.system(size: 11))
                .foregroundColor(settings.autoFadeCortinasEnabled ? .primary : .secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                if selectedIDs.count >= 2 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("\(selectedIDs.count) selected")
                        Text("·")
                        Text(formatDuration(selectionDuration))
                            .monospacedDigit()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                }

                Button {
                    openWindow(id: "set-timings")
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(formatDuration(setlist.totalPlaylistDuration))
                            Text("·")
                            Text("\(unplayedCount) remaining")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Text("Next cortina:")
                            Text(setlistFormatDuration(timeUntilNextCortina))
                                .monospacedDigit()
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Text("Ends at:")
                            Text(formattedEndTime)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var unplayedCount: Int {
        setlist.entries.filter { $0.state != .played }.count
    }

    private var selectionDuration: TimeInterval {
        setlist.entries
            .filter { selectedIDs.contains($0.id) }
            .compactMap { $0.duration }
            .reduce(0, +)
    }

    private var timeUntilNextCortina: TimeInterval {
        let detector = settings.makeDetector()
        let entries = setlist.entries

        let startIdx: Int
        var remaining: TimeInterval

        if let id = player.currentEntryID,
           let idx = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries[idx]
            if detector.isCortina(genre: entry.track.genre) { return 0 }
            startIdx = idx
            remaining = max(0, (entry.duration ?? 0) - player.elapsed)
        } else if let idx = entries.firstIndex(where: { $0.state != .played }) {
            let entry = entries[idx]
            if detector.isCortina(genre: entry.track.genre) { return 0 }
            startIdx = idx
            remaining = entry.duration ?? 0
        } else {
            return 0
        }

        for entry in entries[(startIdx + 1)...] {
            guard entry.state != .played else { continue }
            if detector.isCortina(genre: entry.track.genre) { return remaining }
            remaining += entry.duration ?? 0
        }
        return 0
    }

    private func effectiveDuration(for entry: SetlistEntry, detector: CortinaDetector) -> TimeInterval {
        let duration = entry.duration ?? 0
        guard settings.autoFadeCortinasEnabled,
              !entry.ignoresAutoFade,
              detector.isCortina(genre: entry.track.genre) else {
            return duration
        }
        let fade = settings.builtInFadeDuration
        let play = settings.cortinaPlayTime
        let delay: Double
        if duration > play + fade { delay = play }
        else if duration > fade   { delay = duration - fade }
        else                      { delay = 0 }
        return min(duration, delay + fade + 1.0)
    }

    private var setEndTime: Date? {
        guard appState.currentPlayerState != .stopped else { return nil }
        var remaining: TimeInterval = 0
        let stopAfterID = setlist.stopAfterEntryID
        let detector = settings.makeDetector()
        for entry in setlist.entries {
            switch entry.state {
            case .playing:
                remaining += max(0, effectiveDuration(for: entry, detector: detector) - player.elapsed)
            case .paused, .queued:
                remaining += effectiveDuration(for: entry, detector: detector)
            case .played:
                if entry.id == player.currentEntryID {
                    remaining += max(0, effectiveDuration(for: entry, detector: detector) - player.elapsed)
                }
            }
            if let stopID = stopAfterID, entry.id == stopID { break }
        }
        return Date().addingTimeInterval(remaining)
    }

    private var formattedEndTime: String {
        guard let end = setEndTime else { return "play to calculate" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: end)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        setlistFormatDuration(seconds)
    }
}

// MARK: - Double-click overlay

// Uses NSClickGestureRecognizer with delaysPrimaryMouseButtonEvents = false so
// NSTableView receives primary clicks unobstructed (enabling mouse selection),
// while still detecting double-clicks to jump to a track.
private struct DoubleClickOverlay: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let gr = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.fired)
        )
        gr.numberOfClicksRequired = 2
        gr.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(gr)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fired() { action() }
    }
}

// MARK: - Tag colour

extension TagColor {
    var swiftUIColor: Color? {
        switch self {
        case .none:   return nil
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return Color(red: 0.95, green: 0.80, blue: 0.0)
        case .green:  return .green
        case .blue:   return .blue
        case .purple: return .purple
        }
    }

    var menuCircleImage: NSImage {
        let nsColor: NSColor
        switch self {
        case .none:   nsColor = .clear
        case .red:    nsColor = .systemRed
        case .orange: nsColor = .systemOrange
        case .yellow: nsColor = NSColor(red: 0.95, green: 0.80, blue: 0.0, alpha: 1)
        case .green:  nsColor = .systemGreen
        case .blue:   nsColor = .systemBlue
        case .purple: nsColor = .systemPurple
        }
        let size = CGFloat(13)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    var displayName: String { rawValue.capitalized }
}

// MARK: - Row

struct SetlistRowView: View {
    let entry: SetlistEntry
    let isStopAfter: Bool
    var isActivelyPlaying: Bool = false
    var isNextToPlay: Bool = false
    var showYear: Bool = true
    var showTime: Bool = true
    var showComments: Bool = false
    var showAlbumArtist: Bool = false
    var showGrouping: Bool = false
    var wouldSkipAutoGap: Bool = false
    var autoFadeCortinasEnabled: Bool = false
    var isLastTanda: Bool = false
    var configurationName: String? = nil
    var genreColorsEnabled: Bool = false
    var genreColorRules: [GenreColorRule] = []
    var genreColorTitleEnabled: Bool = false
    var isCortina: Bool = false
    var player: LocalPlayerSource? = nil

    private var isCurrent: Bool { entry.state == .playing || entry.state == .paused || isActivelyPlaying }
    private var isCurrentPlaying: Bool { entry.state == .playing || isActivelyPlaying }
    private var isBoldBright: Bool {
        guard entry.state == .queued, !isNextToPlay, !isCurrent else { return false }
        return !genreColorsEnabled || isCortina
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(entry.tagColor.swiftUIColor ?? Color.clear)
                .frame(width: 3)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                stateIndicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.track.title)
                        .font(.system(size: 13))
                        .fontWeight(isBoldBright ? .semibold : (entry.state == .queued ? .medium : .regular))
                        .lineLimit(1)
                        .foregroundColor(genreColorTitleEnabled ? genreTagColor : (entry.state == .played && !isActivelyPlaying ? .secondary : .primary))
                    Text(entry.track.artist + (showYear ? (entry.track.year.map { " · \($0)" } ?? "") : ""))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    let extraParts = [
                        showComments ? entry.track.comment : nil,
                        showAlbumArtist ? entry.track.albumArtist : nil,
                        showGrouping ? entry.track.grouping : nil
                    ].compactMap { $0 }.filter { !$0.isEmpty }
                    if !extraParts.isEmpty {
                        Text(extraParts.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if showTime, let dur = entry.duration {
                    Text(setlistFormatDuration(dur))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if !entry.track.genre.isEmpty {
                    Text(entry.track.genre)
                        .font(.system(size: 10))
                        .foregroundColor(genreTagColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(genreTagColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                if entry.isPerformance {
                    Text("PERFORMANCE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }

                if isStopAfter {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                if entry.repeatTrack {
                    Image(systemName: "repeat")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                }
                if entry.autoGapApplied {
                    Image(systemName: "wave.3.left.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                } else if wouldSkipAutoGap {
                    Image(systemName: "wave.3.left.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if autoFadeCortinasEnabled && entry.ignoresAutoFade {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                if isLastTanda {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                if entry.upcomingOverride != nil {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                        .help("Upcoming info edited")
                }
                if let name = configurationName {
                    Text(name)
                        .font(.system(size: 9))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())
                }
                if entry.trimStartSeconds != nil || entry.trimEndSeconds != nil {
                    Label(trimBadgeText, systemImage: "timeline.selection")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
                // Only shown for an explicit per-track override — a track following the
                // global rule needs no badge, or every row would carry one.
                if let skip = entry.restorationOverride {
                    // "sparkles.slash" is not an SF Symbol — it renders blank. nosign is.
                    Image(systemName: skip ? "nosign" : "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(skip ? .secondary : .teal)
                        .help(skip ? "Restoration skipped for this track"
                                   : "Restoration applied to this track")
                }
            }
            .padding(.top, 3)
            .padding(.bottom, isCurrent && player != nil ? 2 : 3)

            if isCurrent, let player = player {
                RowProgressBarView(player: player, entry: entry)
                    .padding(.leading, 22)
                    .padding(.bottom, 5)
            }
        }
        }
        .contentShape(Rectangle())
        .listRowBackground(rowBackground)
    }

    private var trimBadgeText: String {
        func fmt(_ s: Double) -> String {
            let i = Int(max(0, s).rounded()); return String(format: "%d:%02d", i / 60, i % 60)
        }
        let start = entry.trimStartSeconds ?? 0
        let end = entry.trimEndSeconds ?? entry.duration ?? 0
        return "\(fmt(start))–\(fmt(end))"
    }

    private var genreTagColor: Color {
        if isNextToPlay { return .accentColor }
        if isCurrent && isCurrentPlaying { return .green }
        if isCurrent && entry.state == .paused { return .orange }
        if entry.state == .queued && genreColorsEnabled && !isCortina {
            if let rule = genreColorRules.first(where: {
                entry.track.genre.localizedCaseInsensitiveContains($0.keyword)
            }) {
                return Color(hex: rule.colorHex)
            }
        }
        if isBoldBright { return .primary }
        return .secondary
    }

    private var rowBackground: Color {
        if isNextToPlay { return Color.accentColor.opacity(0.15) }
        guard isCurrent else { return .clear }
        return entry.state == .paused ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.15)
    }

    private var stateIndicator: some View {
        Group {
            switch entry.state {
            case .playing:
                Image(systemName: "waveform")
                    .foregroundColor(.green)
            case .paused:
                Image(systemName: "stop.fill")
                    .foregroundColor(.orange)
            case .played:
                Image(systemName: "checkmark")
                    .foregroundColor(isCurrentPlaying ? .green : Color.secondary.opacity(0.6))
            case .queued:
                if isNextToPlay {
                    Image(systemName: "play.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Color.clear
                }
            }
        }
        .font(.system(size: 11))
        .frame(width: 14)
    }
}

// MARK: - In-row progress bar

private struct RowProgressBarView: View {
    @ObservedObject var player: LocalPlayerSource
    @EnvironmentObject var appState: AppState
    let entry: SetlistEntry

    var body: some View {
        let barColor: Color = entry.state == .paused ? .orange : ControlTheme.accent
        VStack(spacing: 2) {
            GeometryReader { geo in
                let progress = player.duration > 0
                    ? player.elapsed / max(player.duration, 1)
                    : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * progress, height: 3)
                    let shouldShowPlayed = !appState.settings.markAsPlayedAfterCompletion
                        && player.duration > 0
                        && !player.isCurrentEntryMarkedAsPlayed
                    let playedFraction = min(1.0,
                        Double(appState.settings.markAsPlayedAfterSeconds) / player.duration)
                    Rectangle()
                        .fill(ControlTheme.accent.opacity(0.7))
                        .frame(width: 2, height: 8)
                        .position(x: playedFraction * geo.size.width, y: geo.size.height / 2)
                        .opacity(shouldShowPlayed ? 1 : 0)
                    let autoFadeDelay: Double = {
                        guard appState.settings.autoFadeCortinasEnabled,
                              appState.displayState.mode == .cortina,
                              player.duration > 0 else { return -1 }
                        if entry.ignoresAutoFade { return -1 }
                        let fade = appState.settings.builtInFadeDuration
                        let play = appState.settings.cortinaPlayTime
                        let dur = player.duration
                        if dur > play + fade { return play }
                        if dur > fade        { return dur - fade }
                        return -1
                    }()
                    Rectangle()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: 2, height: 8)
                        .position(x: (autoFadeDelay / player.duration) * geo.size.width,
                                  y: geo.size.height / 2)
                        .opacity(autoFadeDelay >= 0 ? 1 : 0)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 16)
            HStack {
                Text(formatTime(player.elapsed))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("-\(formatTime(max(0, player.duration - player.elapsed)))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct DecibelToolbarLabel: View {
    let monitor: MicrophoneMonitor
    let low: Int
    let high: Int
    @State private var displayLevel: Int = 0
    @State private var permissionDenied: Bool = false

    var body: some View {
        if !permissionDenied {
            let color: Color = displayLevel < low ? .blue : (displayLevel >= high ? .red : .green)
            Text("\(displayLevel) dB")
                .font(.system(size: 12, design: .monospaced).bold())
                .foregroundColor(color)
                .frame(minWidth: 52, alignment: .trailing)
                .onReceive(monitor.$level.throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)) {
                    displayLevel = $0
                }
                .onReceive(monitor.$permissionDenied) {
                    permissionDenied = $0
                }
        }
    }
}
