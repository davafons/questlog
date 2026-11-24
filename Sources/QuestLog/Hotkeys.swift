// Global hotkeys, configured in the options panel.
import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys through Carbon's RegisterEventHotKey (no Accessibility permission needed).
@MainActor
final class Hotkeys {
    static let shared = Hotkeys()
    struct Binding: Codable, Equatable { var keyCode: UInt32; var mods: UInt32; var label: String }
    nonisolated static let actions = ["toggleLog", "toggleTracker", "newQuest"]
    nonisolated static let defaults: [String: Binding] = [
        "toggleLog": Binding(keyCode: UInt32(kVK_ANSI_L), mods: UInt32(controlKey | optionKey), label: "⌃⌥L"),
        "toggleTracker": Binding(keyCode: UInt32(kVK_ANSI_T), mods: UInt32(controlKey | optionKey), label: "⌃⌥T"),
        "newQuest": Binding(keyCode: UInt32(kVK_ANSI_N), mods: UInt32(controlKey | optionKey), label: "⌃⌥N"),
    ]
    var onPress: ((String) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    /// Saved bindings; an action saved as nil (key present, empty data) is unbound.
    var bindings: [String: Binding?] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "hotkeys"),
                  let saved = try? JSONDecoder().decode([String: Binding?].self, from: data) else { return Self.defaults }
            var out: [String: Binding?] = Self.defaults
            for (k, v) in saved { out[k] = v }
            return out
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "hotkeys"); register() }
    }

    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let i = Int(id.id)
            if i < Hotkeys.actions.count { DispatchQueue.main.async { MainActor.assumeIsolated { Hotkeys.shared.onPress?(Hotkeys.actions[i]) } } }
            return noErr
        }, 1, &spec, nil, &handler)
        register()
    }

    func unregister() { refs.forEach { UnregisterEventHotKey($0) }; refs = [] }

    func register() {
        unregister()
        let all = bindings
        for (i, action) in Self.actions.enumerated() {
            guard let b = all[action] ?? nil else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5154_4C47), id: UInt32(i))  // "QTLG"
            let err = RegisterEventHotKey(b.keyCode, b.mods, id, GetApplicationEventTarget(), 0, &ref)
            if err == noErr, let ref { refs.append(ref) }
        }
    }
}

