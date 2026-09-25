import AppKit
import SwiftUI
import TangoDisplayCore
import os.log

// MARK: - Wrapper VC: hosts the AU's native view + a preset bar at the bottom.
//
// Modeled on Embrace's EditSystemEffectController (iccir/Embrace): the AU
// view is a direct subview of our content view (no NSScrollView, no clip
// view, no nested wrapper), and the window resizes in response to
// NSViewFrameDidChangeNotification on the AU view, keeping the titlebar
// fixed by adjusting origin.y.
//
// Note: plugin-driven resize only works for plugins loaded *in-process*.
// Plugins now default to out-of-process hosting (for crash isolation); only
// those on AudioUnitPluginManager.inProcessAllowlist (e.g. MJUC) load
// in-process and can drive window resize this way. When a V2 AU is loaded via
// the out-of-process bridge, its view comes back wrapped in NSRemoteView and
// frame changes from the plugin process don't surface to the host — so the
// frame-observer path below is a no-op for OOP plugins (they resize, if at
// all, via the preferredContentSize observer instead).

final class PluginWindowViewController: NSViewController {
    private let pluginVC: NSViewController
    private let player: LocalPlayerSource
    private let slotId: UUID
    private let barHeight: CGFloat = 44
    private var sizeObservation: NSKeyValueObservation?
    private var barView: NSView!
    private var inFrameCallback = false
    /// Descendant views we've already attached `frameDidChange` observers
    /// to. Some plugins resize an inner peer NSView rather than the root,
    /// so we observe the full tree and rescan on every frame change.
    private var observedViews = Set<ObjectIdentifier>()

    private static let log = OSLog(subsystem: "com.tangodisplay", category: "PluginWindow")

    init(pluginVC: NSViewController, player: LocalPlayerSource, slotId: UUID) {
        self.pluginVC = pluginVC
        self.player = player
        self.slotId = slotId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(pluginVC)
        let effectView = pluginVC.view
        let natural = effectView.frame.size
        // Not just > 0: a remote plugin view reports 1x1 until the hosting
        // service connects, and a window built to that size is unusable.
        let naturalW = natural.width  >= 80 ? natural.width  : 600
        let naturalH = natural.height >= 40 ? natural.height : 400

        let contentSize = NSSize(width: naturalW, height: naturalH + barHeight)
        view.setFrameSize(contentSize)

        // Match Embrace's setFrame sequence: zero autoresize mask while we
        // place the view, then restore so the plugin can autoresize with
        // future window resizes if it supports them.
        let originalMask = effectView.autoresizingMask
        effectView.autoresizingMask = []
        effectView.frame = NSRect(x: 0, y: barHeight, width: naturalW, height: naturalH)
        effectView.autoresizingMask = originalMask
        view.addSubview(effectView)

        // Preset bar pinned to the bottom; stretches horizontally with the window.
        let barVC = NSHostingController(rootView: PluginWindowPresetBar(
            player: player,
            slotId: slotId
        ))
        addChild(barVC)
        let bar = barVC.view
        bar.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: barHeight)
        bar.autoresizingMask = [.width, .maxYMargin]
        view.addSubview(bar)
        self.barView = bar

        // V3 AUs publish via preferredContentSize.
        sizeObservation = pluginVC.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.adoptPreferredContentSize() }
        }

        // V2 AUs (JUCE plugins) post frame changes when their editor
        // resizes. Observe the whole subview tree so we don't miss
        // resizes that originate on an inner peer NSView.
        installFrameObservers(on: effectView)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else { return }
        // If the plugin's view doesn't support being resized, take the
        // resize grip off the window (Embrace's pattern). JUCE plugins
        // typically have no autoresize mask set.
        let mask = pluginVC.view.autoresizingMask
        if !mask.contains(.width) && !mask.contains(.height) {
            window.styleMask.remove(.resizable)
        }
        snapWindowToPluginFrame()
    }

    @objc private func pluginFrameDidChange(_ note: Notification) {
        // A child view may have just been resized; re-walk so any newly
        // added descendants pick up observers too.
        installFrameObservers(on: pluginVC.view)
        snapWindowToPluginFrame()
    }

    /// Recursively attach `frameDidChange` and `boundsDidChange` observers
    /// to `view` and every descendant. Idempotent via `observedViews`.
    private func installFrameObservers(on view: NSView) {
        let id = ObjectIdentifier(view)
        if observedViews.insert(id).inserted {
            view.postsFrameChangedNotifications = true
            view.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pluginFrameDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: view
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pluginFrameDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: view
            )
        }
        for sub in view.subviews {
            installFrameObservers(on: sub)
        }
    }

    /// Recursive bounding box of every descendant view (frame) translated
    /// into the root view's coord space. Catches a subview that grew past
    /// the root's bounds.
    private func contentExtent(of root: NSView) -> NSRect {
        var box = root.bounds
        for sub in root.subviews {
            let subBox = contentExtent(of: sub)
            box = box.union(sub.convert(subBox, to: root))
        }
        return box
    }

    private func adoptPreferredContentSize() {
        let size = pluginVC.preferredContentSize
        // Floors, not just > 0: a view mid-layout can publish a few points and
        // leave the window a sliver with no visible grip to drag it back.
        guard size.width >= 80, size.height >= 40 else { return }
        // Treat preferredContentSize as a frame request: write it into the
        // plugin's NSView so the rest of the pipeline (frameDidChange)
        // handles the window resize via the same code path.
        if abs(pluginVC.view.frame.width  - size.width)  > 0.5 ||
           abs(pluginVC.view.frame.height - size.height) > 0.5 {
            pluginVC.view.setFrameSize(size)
        }
    }

    /// Resize the host window to match the plugin's current frame (plus
    /// the preset bar). Modeled on Embrace's `_resizeWindowWithOldSize:newSize:`.
    private func snapWindowToPluginFrame() {
        guard !inFrameCallback,
              let window = view.window,
              !window.inLiveResize else { return }

        let root = pluginVC.view.frame.size
        let extent = contentExtent(of: pluginVC.view).size
        let target = NSSize(
            width:  max(root.width,  extent.width),
            height: max(root.height, extent.height)
        )
        // Same floors as adoptPreferredContentSize: a hosted SwiftUI view reports
        // a near-zero frame mid-layout, and following it collapses the window to a
        // sliver the user can't even grab to resize.
        guard target.width >= 80, target.height >= 40 else { return }

        let content = window.contentRect(forFrameRect: window.frame).size
        let currentPluginH = max(0, content.height - barHeight)
        let deltaW = target.width  - content.width
        let deltaH = target.height - currentPluginH
        if abs(deltaW) < 0.5 && abs(deltaH) < 0.5 { return }

        inFrameCallback = true
        defer { inFrameCallback = false }

        let effectView = pluginVC.view
        let oldMask = effectView.autoresizingMask
        effectView.autoresizingMask = []

        var frame = window.frame
        frame.size.width  += deltaW
        frame.size.height += deltaH
        // Keep window top fixed: growing height pushes origin.y down by
        // the same amount (NSWindow uses bottom-left origin).
        frame.origin.y    -= deltaH
        window.setFrame(frame, display: true, animate: false)

        effectView.frame = NSRect(x: 0,
                                  y: barHeight,
                                  width: target.width,
                                  height: target.height)
        effectView.autoresizingMask = oldMask

        #if DEBUG
        let newContent = window.contentRect(forFrameRect: window.frame).size
        os_log(.debug, log: Self.log,
               "resize plugin=%{public}@ window=%{public}@",
               NSStringFromSize(target),
               NSStringFromSize(newContent))
        #endif
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Preset bar rendered inside the plugin window

private struct PluginWindowPresetBar: View {
    @ObservedObject var player: LocalPlayerSource
    let slotId: UUID
    @State private var showSaveAlert = false
    @State private var presetName = ""

    private var presets: [AudioUnitPreset] {
        player.slotPresets[slotId] ?? []
    }

    private var activePresetLabel: String {
        guard let id = player.slotActivePresetIDs[slotId],
              let p = presets.first(where: { $0.id == id }) else { return "None" }
        return p.name
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Text("Preset:")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                if !presets.isEmpty {
                    let factoryPresets = presets.filter(\.isFactory)
                    let userPresets = presets.filter(\.isUser)
                    Menu {
                        if !factoryPresets.isEmpty {
                            Section("Factory") {
                                ForEach(factoryPresets) { p in
                                    Button(p.name) { player.applyPreset(p, toSlot: slotId) }
                                }
                            }
                        }
                        if !userPresets.isEmpty {
                            Section("Saved") {
                                ForEach(userPresets) { p in
                                    Button(p.name) { player.applyPreset(p, toSlot: slotId) }
                                }
                            }
                            Divider()
                            ForEach(userPresets) { p in
                                Button("Delete \"\(p.name)\"", role: .destructive) {
                                    try? player.deletePreset(p, fromSlot: slotId)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(activePresetLabel)
                                .font(.system(size: 12))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(minWidth: 120)
                }

                Spacer()

                Button("Save as Preset…") {
                    presetName = ""
                    showSaveAlert = true
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
        .background(.regularMaterial)
        .alert("Save as Preset", isPresented: $showSaveAlert) {
            TextField("Preset name", text: $presetName)
            Button("Save") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                try? player.saveCurrentAsPreset(named: name, forSlot: slotId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the current plugin settings.")
        }
    }
}
