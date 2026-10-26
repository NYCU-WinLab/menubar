import AppKit
import Carbon.HIToolbox

/// What a global shortcut can do.
enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
    case togglePause, skip, volumeUp, volumeDown, openDoor, openPortal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .togglePause: "暫停／繼續"
        case .skip: "下一首"
        case .volumeUp: "音量加大"
        case .volumeDown: "音量減小"
        case .openDoor: "開門"
        case .openPortal: "開啟 portal"
        }
    }

    /// Shortcuts set on first launch. The door has none, so it never opens
    /// by accident.
    var defaultShortcut: Shortcut? {
        let mods = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .togglePause: return Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: mods)
        case .skip: return Shortcut(keyCode: UInt32(kVK_RightArrow), modifiers: mods)
        case .volumeUp: return Shortcut(keyCode: UInt32(kVK_UpArrow), modifiers: mods)
        case .volumeDown: return Shortcut(keyCode: UInt32(kVK_DownArrow), modifiers: mods)
        case .openDoor, .openPortal: return nil
        }
    }
}

/// A key plus Carbon modifier flags.
struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// From a key press; nil without ⌘, ⌥ or ⌃ (a bare key would steal typing).
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = mods
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(Int(keyCode))
    }

    static func keyName(_ code: Int) -> String {
        let named: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = named[code] { return name }
        // The character this key types on the current layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return "#\(code)" }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return "#\(code)" }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}

/// System-wide shortcuts through Carbon's RegisterEventHotKey, which needs no
/// accessibility permission.
@MainActor
final class Hotkeys {
    static let shared = Hotkeys()
    private static let storeKey = "shortcuts"
    private static let signature: OSType = 0x574C_4142 // "WLAB"

    var handler: ((HotkeyAction) -> Void)?
    /// Actions whose shortcut another app already holds.
    private(set) var conflicts: Set<HotkeyAction> = []
    private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    private var installed = false

    private init() {}

    var shortcuts: [HotkeyAction: Shortcut] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.storeKey),
                  let saved = try? JSONDecoder().decode([String: Shortcut?].self, from: data)
            else {
                return Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.compactMap { a in a.defaultShortcut.map { (a, $0) } })
            }
            var out: [HotkeyAction: Shortcut] = [:]
            for action in HotkeyAction.allCases {
                // A key never saved (an action added later) takes its default.
                if let entry = saved[action.rawValue] {
                    if let s = entry { out[action] = s }
                } else if let d = action.defaultShortcut {
                    out[action] = d
                }
            }
            return out
        }
        set {
            var saved: [String: Shortcut?] = [:]
            for action in HotkeyAction.allCases { saved[action.rawValue] = newValue[action] }
            UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.storeKey)
            registerAll()
        }
    }

    func set(_ shortcut: Shortcut?, for action: HotkeyAction) {
        var all = shortcuts
        // One shortcut, one action.
        if let shortcut { for (a, s) in all where s == shortcut { all[a] = nil } }
        all[action] = shortcut
        shortcuts = all
    }

    func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            let index = Int(id.id)
            // Carbon calls this on the main thread.
            MainActor.assumeIsolated { Hotkeys.shared.fire(index) }
            return noErr
        }, 1, &spec, nil, nil)
        registerAll()
    }

    /// Stops listening while the recorder waits for keys, so pressing an
    /// existing shortcut records it instead of running it.
    func suspend() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs = [:]
    }

    func registerAll() {
        suspend()
        conflicts = []
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let s = shortcuts[action] else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                s.keyCode, s.modifiers, EventHotKeyID(signature: Self.signature, id: UInt32(index)),
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref { refs[action] = ref } else { conflicts.insert(action) }
        }
    }

    private func fire(_ index: Int) {
        guard HotkeyAction.allCases.indices.contains(index) else { return }
        handler?(HotkeyAction.allCases[index])
    }
}
