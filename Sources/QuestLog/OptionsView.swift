// The gear panel: hotkeys, sound and tracker settings. Also shown in the menu bar menu.
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Preferences saved in UserDefaults, observable by the options panel; the app delegate applies changes.
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard
    var onChange: (() -> Void)?

    @Published var volume: Int { didSet { d.set(volume, forKey: "volume"); onChange?() } }
    @Published var muted: Bool { didSet { d.set(muted, forKey: "muted"); onChange?() } }
    @Published var trackerHidden: Bool { didSet { d.set(trackerHidden, forKey: "trackerHidden"); onChange?() } }
    @Published var clickThrough: Bool { didSet { d.set(clickThrough, forKey: "clickThrough"); onChange?() } }
    @Published var idleAlpha: Double { didSet { d.set(idleAlpha, forKey: "idleAlpha"); onChange?() } }
    @Published var hotkeys: [String: Hotkeys.Binding?] = Hotkeys.shared.bindings

    init() {
        volume = d.object(forKey: "volume") == nil ? 25 : d.integer(forKey: "volume")
        muted = d.bool(forKey: "muted")
        trackerHidden = d.bool(forKey: "trackerHidden")
        clickThrough = d.bool(forKey: "clickThrough")
        idleAlpha = d.object(forKey: "idleAlpha") == nil ? 0.4 : d.double(forKey: "idleAlpha")
    }

    func setHotkey(_ action: String, _ b: Hotkeys.Binding?) {
        var all = Hotkeys.shared.bindings
        all[action] = .some(b)
        Hotkeys.shared.bindings = all
        hotkeys = Hotkeys.shared.bindings
        onChange?()
    }

    func resetHotkeys() {
        Hotkeys.shared.reset()
        hotkeys = Hotkeys.shared.bindings
        onChange?()
    }
}

extension Hotkeys {
    func reset() {
        UserDefaults.standard.removeObject(forKey: "hotkeys")
        register()
        Prefs.shared.hotkeys = bindings
    }

    /// Carbon modifier mask and a label like ⌃⌥L for a key press.
    static func binding(for e: NSEvent) -> Binding? {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods = 0, label = ""
        if f.contains(.control) { mods |= controlKey; label += "⌃" }
        if f.contains(.option) { mods |= optionKey; label += "⌥" }
        if f.contains(.shift) { mods |= shiftKey; label += "⇧" }
        if f.contains(.command) { mods |= cmdKey; label += "⌘" }
        // A global hotkey needs ⌃, ⌥ or ⌘, or it would swallow plain typing.
        guard mods & (controlKey | optionKey | cmdKey) != 0 else { return nil }
        let names: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
                                    kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
                                    kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        let key = names[Int(e.keyCode)] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
        return Binding(keyCode: UInt32(e.keyCode), mods: UInt32(mods), label: label + key)
    }
}

struct OptionsView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var theme = Theme.shared
    let z: CGFloat
    @State private var recording: String?
    @State private var monitor: Any?

    static let names = ["toggleLog": "Open or close the quest log", "toggleTracker": "Show or hide the tracker", "newQuest": "New quest"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6 * z) {
                section("Key Bindings")
                ForEach(Hotkeys.actions, id: \.self) { action in
                    HStack {
                        label(Self.names[action] ?? action)
                        Spacer()
                        keyButton(action)
                    }
                }
                hint(recording == nil ? "Click a binding, then press the new keys. Delete clears it, Esc cancels." : "Press the new keys…")

                section("Sound")
                HStack {
                    label("Volume")
                    Slider(value: Binding(get: { Double(prefs.volume) }, set: { prefs.volume = Int($0) }), in: 0...100) { editing in
                        if !editing { Sound.shared.play("objective") }
                    }
                    .frame(width: 180 * z)
                    Text("\(prefs.volume)%").font(theme.ui(11 * z)).foregroundStyle(Color.parchText).monospacedDigit().frame(width: 36 * z, alignment: .trailing)
                }
                check("Mute sounds", prefs.muted) { prefs.muted.toggle() }

                section("Tracker")
                check("Show the tracker when the log is closed", !prefs.trackerHidden) { prefs.trackerHidden.toggle() }
                check("Clicks go through the tracker", prefs.clickThrough) { prefs.clickThrough.toggle() }
                HStack {
                    label("Opacity when idle")
                    Slider(value: $prefs.idleAlpha, in: 0.1...1).frame(width: 180 * z)
                    Text("\(Int((prefs.idleAlpha * 100).rounded()))%").font(theme.ui(11 * z)).foregroundStyle(Color.parchText).monospacedDigit().frame(width: 36 * z, alignment: .trailing)
                }

                section("Theme")
                hint(theme.themed ? "Using the art extracted from your World of Warcraft install." :
                        "Using the built-in look. To use the game's art, run scripts/extract-wow-theme.py (see the README).")
                HStack(spacing: 8 * z) {
                    RedButton(title: "Theme Folder", width: 100, height: 19, z: z) {
                        NSWorkspace.shared.open(AppModel.shared.store.home.appendingPathComponent("theme"))
                    }
                    RedButton(title: "Reload Theme", width: 100, height: 19, z: z) { Theme.shared.reload() }
                }
            }
            .padding(14 * z)
        }
        .scrollIndicators(.never)
        .background(Color(hex: 0x0B0A08, alpha: 0.96))
        .overlay(Rectangle().strokeBorder(Color(hex: 0x4A443A), lineWidth: max(1, z)))
        .controlSize(.small)
        .tint(Color(hex: 0xC8A43A))
        .onDisappear(perform: stopRecording)
    }

    func section(_ t: String) -> some View {
        Text(t).font(theme.ui(13 * z)).foregroundStyle(Color.gold).outlined().padding(.top, 6 * z)
    }

    func label(_ t: String) -> some View { Text(t).font(theme.ui(12 * z)).foregroundStyle(Color(hex: 0xE8E0C8)).outlined() }

    func hint(_ t: String) -> some View { Text(t).font(theme.ui(10.5 * z)).foregroundStyle(Color(hex: 0x9B927F)) }

    func check(_ t: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6 * z) { CheckBox(on: on, z: z); label(t) }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func keyButton(_ action: String) -> some View {
        let on = recording == action
        let text = on ? "…" : ((prefs.hotkeys[action] ?? nil)?.label ?? "Not bound")
        return Button { on ? stopRecording() : startRecording(action) } label: {
            Text(text).font(theme.ui(11.5 * z)).foregroundStyle(on ? .white : Color.gold)
                .frame(width: 110 * z, height: 19 * z)
                .background(Color(hex: on ? 0x3A2A10 : 0x141210))
                .overlay(Rectangle().strokeBorder(on ? Color.gold : Color(hex: 0x5A5246), lineWidth: max(1, z)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func startRecording(_ action: String) {
        stopRecording()
        recording = action
        // Turn the hotkeys off while recording, so pressing one doesn't trigger it.
        Hotkeys.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            switch Int(e.keyCode) {
            case kVK_Escape: stopRecording()
            case kVK_Delete, kVK_ForwardDelete: prefs.setHotkey(action, nil); stopRecording()
            default:
                guard let b = Hotkeys.binding(for: e) else { NSSound.beep(); return nil }
                // One key can only do one thing.
                for (other, ob) in prefs.hotkeys where other != action && ob?.keyCode == b.keyCode && ob?.mods == b.mods { prefs.setHotkey(other, nil) }
                prefs.setHotkey(action, b)
                stopRecording()
            }
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil { Hotkeys.shared.register() }
        recording = nil
    }
}
