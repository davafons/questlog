// Quest Log: menu bar app with the quest log window, the objective tracker over the desktop, and a quest window
// that pops up for new offered quests. Data lives in ~/.questlog and is shared with the `quest` command.
import AppKit
import QuestCore
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Hosting view that takes the first click, so the tracker works without activating the app first.
final class ClickHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var status: NSStatusItem!
    var tracker: FloatingPanel!
    var logWindow: NSWindow?
    var offerPanel: FloatingPanel?
    var showingOffer: String?
    var pendingOffer: String?
    var answered = Set<String>()
    var trackerHeight: CGFloat = 120
    var hovering = false
    let prefs = Prefs.shared
    let defaults = UserDefaults.standard
    let model = AppModel.shared

    var offerOrigin: NSPoint? {
        get { defaults.object(forKey: "offerX") == nil ? nil : NSPoint(x: defaults.double(forKey: "offerX"), y: defaults.double(forKey: "offerY")) }
        set {
            if let p = newValue { defaults.set(Double(p.x), forKey: "offerX"); defaults.set(Double(p.y), forKey: "offerY") }
            else { defaults.removeObject(forKey: "offerX"); defaults.removeObject(forKey: "offerY") }
        }
    }
    /// Top-left corner of the tracker in screen coordinates; nil means the default spot on the right edge.
    var savedTopLeft: NSPoint? {
        get { defaults.object(forKey: "trackerX") == nil ? nil : NSPoint(x: defaults.double(forKey: "trackerX"), y: defaults.double(forKey: "trackerTop")) }
        set {
            if let p = newValue { defaults.set(Double(p.x), forKey: "trackerX"); defaults.set(Double(p.y), forKey: "trackerTop") }
            else { defaults.removeObject(forKey: "trackerX"); defaults.removeObject(forKey: "trackerTop") }
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        _ = Theme.shared
        buildStatusItem()
        buildTracker()
        Hotkeys.shared.onPress = { [weak self] action in self?.runHotkey(action) }
        Hotkeys.shared.install()
        prefs.onChange = { [weak self] in self?.applyPrefs() }
        model.onOffer = { [weak self] ref in
            self?.pendingOffer = ref
            if ref == nil { self?.hideOffer() } else { self?.showNextOffer() }
        }
        model.reload(force: true)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.placeTracker() }
        }
        // Development: --open shows the log, --panel options|new|edit opens a panel in it.
        let args = CommandLine.arguments
        if args.contains("--open") { openLog(ref: nil) }
        if let i = args.firstIndex(of: "--panel"), i + 1 < args.count {
            openLog(ref: nil, newQuest: args[i + 1] == "new")
            if args[i + 1] == "options" { LogState.shared.optionsOpen = true }
            if args[i + 1] == "edit", let p = model.current, let q = LogState.shared.quest(in: p) { EditorDraft.start(p, q) }
        }
    }

    // questlog://open/<slug>/<quest> (or questlog://open) opens the quest log, e.g. from `quest open`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "questlog" {
            let ref = url.absoluteString.replacingOccurrences(of: "questlog://open", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            openLog(ref: ref.isEmpty ? nil : (ref.removingPercentEncoding ?? ref))
        }
    }

    func applyPrefs() {
        tracker.ignoresMouseEvents = prefs.clickThrough
        fade()
        setTrackerVisible(!prefs.trackerHidden)
        rebuildMenu()
    }

    // MARK: Tracker

    func buildTracker() {
        tracker = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: trackerHeight),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        tracker.level = .floating
        tracker.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        tracker.isOpaque = false
        tracker.backgroundColor = .clear
        tracker.hasShadow = false
        tracker.hidesOnDeactivate = false
        tracker.isReleasedWhenClosed = false
        let view = TrackerView { [weak self] h in
            guard let self, abs(h - self.trackerHeight) > 0.5 else { return }
            self.trackerHeight = h
            self.placeTracker()
        }
        .onHover { [weak self] inside in self?.hovering = inside; self?.fade() }
        let host = ClickHost(rootView: view)
        host.sizingOptions = []
        tracker.contentView = host
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: tracker, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let frame = self.tracker?.frame else { return }
                self.savedTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
            }
        }
        tracker.ignoresMouseEvents = prefs.clickThrough
        tracker.alphaValue = prefs.idleAlpha
        placeTracker()
        if !prefs.trackerHidden { tracker.orderFrontRegardless() }
    }

    func placeTracker() {
        guard let tracker, let screen = tracker.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame, width: CGFloat = 330
        let height = min(trackerHeight, area.height - 40)
        var topLeft = savedTopLeft ?? NSPoint(x: area.maxX - width - 8, y: area.maxY - 60)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(topLeft) }) {
            topLeft = NSPoint(x: area.maxX - width - 8, y: area.maxY - 60)
        }
        tracker.setFrame(NSRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height), display: true)
    }

    func fade() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = hovering ? 0.12 : 0.6
            tracker.animator().alphaValue = hovering ? 1 : prefs.idleAlpha
        }
    }

    func setTrackerVisible(_ visible: Bool) {
        if visible && !prefs.trackerHidden && !(logWindow?.isVisible ?? false) { placeTracker(); tracker.orderFrontRegardless() }
        else { tracker.orderOut(nil) }
    }

    // MARK: Hotkeys

    func runHotkey(_ action: String) {
        switch action {
        case "toggleLog":
            if let w = logWindow, w.isVisible, w.occlusionState.contains(.visible) { w.performClose(nil) } else { openLog(ref: nil) }
        case "toggleTracker": toggleTracker()
        case "newQuest": openLog(ref: nil, newQuest: true)
        default: break
        }
    }

    // MARK: Quest log window

    @objc func openLogFromMenu() { openLog(ref: nil) }

    func openLog(ref: String?, newQuest: Bool = false) {
        if logWindow == nil {
            // A titled window with the title bar hidden: only the frame art shows, but window managers such as
            // AeroSpace still treat it as a normal, tileable window.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690 * 1.3, height: 448 * 1.3),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Quest Log"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(b)?.isHidden = true }
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.delegate = self
            window.contentMinSize = NSSize(width: 420, height: 280)
            let host = NSHostingView(rootView: LogView(close: { [weak window] in window?.performClose(nil) },
                                                       minimize: { [weak window] in window?.miniaturize(nil) }))
            host.sizingOptions = []
            window.contentView = host
            window.setFrameAutosaveName("QuestLogWindow6")
            if !window.setFrameUsingName("QuestLogWindow6") { window.center() }
            logWindow = window
        }
        let ui = LogState.shared
        if let ref { ui.select(ref) }
        if newQuest, let p = model.current { EditorDraft.start(p, nil) }
        if !(logWindow?.isVisible ?? false) { Sound.shared.play("open") }
        NSApp.activate(ignoringOtherApps: true)
        logWindow?.makeKeyAndOrderFront(nil)
        setTrackerVisible(false)
        rebuildMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.logWindow?.invalidateShadow() }
    }

    func windowDidResize(_ notification: Notification) {
        if (notification.object as? NSWindow) === logWindow { logWindow?.invalidateShadow() }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === logWindow else { return }
        Sound.shared.play("close")
        DispatchQueue.main.async { self.setTrackerVisible(true); self.rebuildMenu() }
    }

    // MARK: New quest window

    func showNextOffer() {
        guard showingOffer == nil, let ref = pendingOffer, !answered.contains(ref) else { return }
        if offerPanel == nil {
            let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 384, height: 411),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
                MainActor.assumeIsolated {
                    guard let panel = self.offerPanel, panel.isVisible else { return }
                    self.offerOrigin = panel.frame.origin
                }
            }
            offerPanel = panel
        }
        guard let panel = offerPanel, let screen = NSScreen.main else { return }
        let host = ClickHost(rootView: OfferView(ref: ref) { [weak self] in
            self?.answered.insert(ref)
            self?.hideOffer()
            self?.showNextOffer()
        })
        host.sizingOptions = []
        panel.contentView = host
        let area = screen.visibleFrame
        var origin = offerOrigin ?? NSPoint(x: area.minX + 60, y: area.midY - 205)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSPoint(x: origin.x + 20, y: origin.y + 20)) }) {
            origin = NSPoint(x: area.minX + 60, y: area.midY - 205)
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: 384, height: 411)), display: true)
        showingOffer = ref
        Sound.shared.play("offer")
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hideOffer() {
        offerPanel?.orderOut(nil)
        showingOffer = nil
    }

    // MARK: Menu bar

    func buildStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "scroll", accessibilityDescription: "Quest Log")
        image?.isTemplate = true
        status.button?.image = image
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(item("Open Quest Log", #selector(openLogFromMenu), "l"))
        menu.addItem(.separator())
        menu.addItem(item(prefs.trackerHidden ? "Show Tracker" : "Hide Tracker", #selector(toggleTracker), "t"))
        menu.addItem(item("Click Through Tracker", #selector(toggleClickThrough), "", on: prefs.clickThrough))
        menu.addItem(item("Mute Sounds", #selector(toggleMute), "", on: prefs.muted))
        menu.addItem(item("Reset Window Positions", #selector(resetPosition), ""))
        menu.addItem(.separator())
        menu.addItem(item("Open Theme Folder", #selector(openTheme), ""))
        menu.addItem(item("Reload Theme", #selector(reloadTheme), "r"))
        menu.addItem(.separator())
        menu.addItem(item("Quit Quest Log", #selector(quit), "q"))
        status.menu = menu
    }

    func item(_ title: String, _ action: Selector, _ key: String, on: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.state = on ? .on : .off
        return i
    }

    @objc func toggleTracker() { prefs.trackerHidden.toggle() }
    @objc func toggleClickThrough() { prefs.clickThrough.toggle() }
    @objc func toggleMute() { prefs.muted.toggle() }
    @objc func resetPosition() { savedTopLeft = nil; offerOrigin = nil; placeTracker() }
    @objc func openTheme() { NSWorkspace.shared.open(model.store.home.appendingPathComponent("theme")) }
    @objc func reloadTheme() { Theme.shared.reload() }
    @objc func quit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
