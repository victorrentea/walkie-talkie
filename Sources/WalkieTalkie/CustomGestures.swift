import AppKit

/// **Custom gestures** (2026-11-22) — the side-button gestures for a mouse that
/// has no Logi Options+ behind it. Victor: *"mai adaugă încă un meniu 'custom'
/// în gestures care, când e bifat, să deschidă un meniu în care să poți trece
/// echivalente pentru tastele care mie acum îmi vin din logi gestures … cmd
/// wheel click, sau opt-cmd-left click … mouse with 3 buttons + special keys
/// pressed"*, and why: *"eu nu voi folosi vreodată, dar vreau să ușurez viața
/// altora care nu au mouse Logi, fără a mi-o complica pe a mea"*.
///
/// So this is **only another way to make the same ten chords**. A trigger — a
/// mouse button with modifiers, or a key combination — is translated at the
/// tap's entrance into the ⌃⌥⌘F-key its Logi gesture sends
/// (`HotkeyTap.customGestureTakes` → `dispatchChord`, the trackpad's own door),
/// so every branch, guard and re-fire clock is the side button's. Nothing here
/// knows what a gesture does.
///
/// **Off by default, and off it costs the tap one comparison** (`live`).

/// One row of the window: a Logi gesture, by the name the Gesture Guide gives it.
enum CustomGestureAction: String, CaseIterable {
    case forwardClick, forwardRight, forwardUp, forwardLeft, forwardDown, bindAndPrompt
    case backClick, backRight, backDown, backLeft, backUp

    /// The function key Options+ sends under ⌃⌥⌘ — `HotkeyTap`'s `VK_F3…F12`.
    /// A third copy of those numbers; `CustomGesturesTests` holds it to
    /// `HotkeyTap.gestureNames`, glyph included, so it cannot drift.
    var keyCode: CGKeyCode {
        switch self {
        case .forwardClick, .bindAndPrompt: return 0x62   // F7
        case .forwardRight: return 0x6D                   // F10
        case .forwardUp: return 0x64                      // F8
        case .forwardLeft: return 0x67                    // F11
        case .forwardDown: return 0x65                    // F9
        case .backClick: return 0x61                      // F6
        case .backRight: return 0x60                      // F5
        case .backDown: return 0x6F                       // F12
        case .backLeft: return 0x63                       // F3
        case .backUp: return 0x76                         // F4
        }
    }

    /// ⬅️ held + 🔼 is ⌃⌥⌘F7 with the left button down; no trigger can hold it,
    /// so the tap is told (`HotkeyTap.customForcesBind`).
    var holdsLeft: Bool { self == .bindAndPrompt }

    /// The glyphs the logs and the rules use.
    var glyph: String {
        switch self {
        case .forwardClick: return "🔼"
        case .forwardRight: return "🔼 →"
        case .forwardUp: return "🔼 ↑"
        case .forwardLeft: return "🔼 ←"
        case .forwardDown: return "🔼 ↓"
        case .bindAndPrompt: return "◀️ + 🔼"
        case .backClick: return "🔽"
        case .backRight: return "🔽 →"
        case .backDown: return "🔽 ↓"
        case .backLeft: return "🔽 ←"
        case .backUp: return "🔽 ↑"
        }
    }

    var title: String {
        switch self {
        case .forwardClick: return "Prompt at the caret"
        case .forwardRight: return "Prompt to the bound terminal"
        case .forwardUp: return "Prompt to a new Claude session"
        case .forwardLeft: return "Cancel — or ask ⚡"
        case .forwardDown: return "Kamikaze"
        case .bindAndPrompt: return "Bind and prompt"
        case .backClick: return "Dictate — or screenshot"
        case .backRight: return "Switch the model — or Google it"
        case .backDown: return "Type — or unbind"
        case .backLeft: return "Interrupt — or Codex voice"
        case .backUp: return "Record the screen"
        }
    }

    /// What it does, in one line.
    var detail: String {
        switch self {
        case .forwardClick: return "Start a prompt where you type; again ends any prompt."
        case .forwardRight: return "Start a prompt to the bound terminal; mid-sentence: terminal ⇄ caret."
        case .forwardUp: return "Your words open a new Claude Code session."
        case .forwardLeft: return "Dictating: throw the take away. At rest: a quick question."
        case .forwardDown: return "The agent closes its terminal when done. Over ⚡: Google it too."
        case .bindAndPrompt: return "Bind the terminal in front and open a prompt to it."
        case .backClick: return "Plain dictation, start / stop. In a prompt: one screenshot."
        case .backRight: return "In a prompt: the session's model. Over ⚡: Google it."
        case .backDown: return "In a prompt: a box to type into. At rest: unbind the terminal."
        case .backLeft: return "Bound prompt: 🛑 interrupt. At rest: talk to Codex."
        case .backUp: return "In a prompt: start or stop a screen recording."
        }
    }

    /// The gesture on the Logitech mouse, as the guide words it.
    var logi: String {
        switch self {
        case .forwardClick: return "Forward click"
        case .forwardRight: return "Hold Forward, swipe right"
        case .forwardUp: return "Hold Forward, swipe up"
        case .forwardLeft: return "Hold Forward, swipe left"
        case .forwardDown: return "Hold Forward, swipe down"
        case .bindAndPrompt: return "Hold Left, click Forward"
        case .backClick: return "Back click"
        case .backRight: return "Hold Back, swipe right"
        case .backDown: return "Hold Back, swipe down"
        case .backLeft: return "Hold Back, swipe left"
        case .backUp: return "Hold Back, swipe up"
        }
    }
}

/// What the hand does: a mouse button or a key, under modifiers.
struct CustomTrigger: Hashable {
    enum Input: Hashable {
        /// 0 left, 1 right, 2 the wheel pressed — `mouseEventButtonNumber`.
        case mouse(Int)
        case key(CGKeyCode)
    }

    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let shift = Modifiers(rawValue: 4)
        static let command = Modifiers(rawValue: 8)

        init(rawValue: Int) { self.rawValue = rawValue & 15 }

        init(_ flags: CGEventFlags) {
            var m: Modifiers = []
            if flags.contains(.maskControl) { m.insert(.control) }
            if flags.contains(.maskAlternate) { m.insert(.option) }
            if flags.contains(.maskShift) { m.insert(.shift) }
            if flags.contains(.maskCommand) { m.insert(.command) }
            self = m
        }

        init(_ flags: NSEvent.ModifierFlags) {
            var m: Modifiers = []
            if flags.contains(.control) { m.insert(.control) }
            if flags.contains(.option) { m.insert(.option) }
            if flags.contains(.shift) { m.insert(.shift) }
            if flags.contains(.command) { m.insert(.command) }
            self = m
        }

        /// macOS's own order: ⌃⌥⇧⌘.
        var symbols: String {
            (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        }
    }

    var input: Input
    var modifiers: Modifiers
    /// What the key is called on his layout, read when it was recorded. Not part
    /// of what the trigger *is*.
    var keyLabel: String = ""

    static func == (a: CustomTrigger, b: CustomTrigger) -> Bool {
        a.input == b.input && a.modifiers == b.modifiers
    }
    func hash(into h: inout Hasher) { h.combine(input); h.combine(modifiers) }

    /// `⌘ wheel click`, `⌥⌘ click`, `⌃⇧ right click`, `⌃⌥K`.
    var display: String {
        switch input {
        case .mouse(let button):
            let name = button == 0 ? "click" : button == 1 ? "right click" : button == 2 ? "wheel click" : "button \(button + 1)"
            return modifiers.isEmpty ? name : "\(modifiers.symbols) \(name)"
        case .key(let code):
            return modifiers.symbols + (keyLabel.isEmpty ? Self.keyName(code, characters: nil) : keyLabel)
        }
    }

    /// The form kept in the defaults: `mouse:2:8`, `key:40:9:K`.
    var stored: String {
        switch input {
        case .mouse(let button): return "mouse:\(button):\(modifiers.rawValue)"
        case .key(let code): return "key:\(code):\(modifiers.rawValue):\(keyLabel)"
        }
    }

    init(_ input: Input, _ modifiers: Modifiers, keyLabel: String = "") {
        self.input = input
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(stored: String) {
        let parts = stored.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, let code = Int(parts[1]), code >= 0, let mods = Int(parts[2]), (0...15).contains(mods)
        else { return nil }
        switch parts[0] {
        case "mouse":
            guard code <= 2, parts.count == 3 else { return nil }
            self.init(.mouse(code), Modifiers(rawValue: mods))
        case "key":
            guard code <= 0xFF else { return nil }
            self.init(.key(CGKeyCode(code)), Modifiers(rawValue: mods), keyLabel: parts.count == 4 ? parts[3] : "")
        default:
            return nil
        }
    }

    /// The recorder's reading of an event in the window. Nil for anything that
    /// is not a button or a key going down.
    init?(recording event: NSEvent) {
        let mods = Modifiers(event.modifierFlags)
        switch event.type {
        case .leftMouseDown: self.init(.mouse(0), mods)
        case .rightMouseDown: self.init(.mouse(1), mods)
        case .otherMouseDown:
            guard event.buttonNumber == 2 else { return nil }
            self.init(.mouse(2), mods)
        case .keyDown:
            self.init(.key(event.keyCode), mods,
                      keyLabel: Self.keyName(event.keyCode, characters: event.charactersIgnoringModifiers))
        default: return nil
        }
    }

    private static let namedKeys: [CGKeyCode: String] = [
        0x24: "Return", 0x30: "Tab", 0x31: "Space", 0x33: "Delete", 0x35: "Esc", 0x4C: "Enter", 0x75: "Fwd Delete",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]

    static func keyName(_ code: CGKeyCode, characters: String?) -> String {
        if let named = namedKeys[code] { return named }
        if let c = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty,
           c.unicodeScalars.allSatisfy({ $0.value > 0x20 && !(0xF700...0xF8FF).contains($0.value) }) {
            return c.uppercased()
        }
        return "key \(code)"
    }
}

/// Why a recorded trigger is not taken.
enum CustomTriggerRefusal: Equatable {
    /// A click with nothing held is a click.
    case bareClick
    /// A key with none of ⌘ ⌥ ⌃ is typing.
    case bareKey
    case taken(by: CustomGestureAction)
    /// One of this app's own keys (⌘⌃B, ⌘⌃X, ⌃P, the ⌃⌥⌘F-keys themselves).
    case reserved

    var message: String {
        switch self {
        case .bareClick: return "A plain click stays a click — hold ⌘, ⌥, ⌃ or ⇧ with it."
        case .bareKey: return "A key needs ⌘, ⌥ or ⌃ with it."
        case .taken(let other): return "Already the trigger for “\(other.title)” — clear that one first."
        case .reserved: return "That one is Walkie Talkie's own shortcut."
        }
    }
}

/// The bindings, the switch, and what the tap asks. One instance for the app
/// (`shared`); tests make their own.
final class CustomGestures {
    static let shared = CustomGestures(defaults: .standard)

    static let enabledKey = "customGesturesOn"
    static let bindingsKey = "customGestureBindings"

    private let defaults: UserDefaults?
    private let lock = NSLock()
    private var on = false
    private var bound: [CustomGestureAction: CustomTrigger] = [:]
    private var lookup: [CustomTrigger: CustomGestureAction] = [:]
    /// Presses the tap swallowed and whose release it therefore owes.
    private var held: Set<CustomTrigger.Input> = []
    private var recordingNow = false

    /// `defaults: nil` keeps everything in memory.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        on = defaults?.bool(forKey: Self.enabledKey) ?? false
        let raw = defaults?.dictionary(forKey: Self.bindingsKey) as? [String: String] ?? [:]
        for (name, stored) in raw {
            guard let action = CustomGestureAction(rawValue: name), let trigger = CustomTrigger(stored: stored),
                  Self.refusal(of: trigger, for: action, in: bound) == nil else { continue }
            bound[action] = trigger
        }
        lookup = Self.index(bound)
    }

    private static func index(_ b: [CustomGestureAction: CustomTrigger]) -> [CustomTrigger: CustomGestureAction] {
        Dictionary(b.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - The switch and the bindings (main thread)

    /// Unticked, the bindings are kept and nothing is translated.
    var enabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return on }
        set {
            lock.lock(); on = newValue; lock.unlock()
            defaults?.set(newValue, forKey: Self.enabledKey)
        }
    }

    var bindings: [CustomGestureAction: CustomTrigger] {
        lock.lock(); defer { lock.unlock() }; return bound
    }

    /// The recorder is listening: the tap translates nothing, so a trigger
    /// already bound can be pressed again without firing its gesture.
    var recording: Bool {
        get { lock.lock(); defer { lock.unlock() }; return recordingNow }
        set { lock.lock(); recordingNow = newValue; lock.unlock() }
    }

    /// Bind (or, with nil, clear) a row. Returns why not, and then changes nothing.
    @discardableResult
    func set(_ trigger: CustomTrigger?, for action: CustomGestureAction) -> CustomTriggerRefusal? {
        lock.lock()
        if let trigger {
            if let no = Self.refusal(of: trigger, for: action, in: bound) { lock.unlock(); return no }
            bound[action] = trigger
        } else {
            bound[action] = nil
        }
        lookup = Self.index(bound)
        let raw = Dictionary(uniqueKeysWithValues: bound.map { ($0.key.rawValue, $0.value.stored) })
        lock.unlock()
        defaults?.set(raw, forKey: Self.bindingsKey)
        return nil
    }

    private static let reservedKeys: Set<CustomTrigger> = {
        var all: Set<CustomTrigger> = [
            CustomTrigger(.key(0x0B), [.control, .command]),   // ⌘⌃B bind
            CustomTrigger(.key(0x07), [.control, .command]),   // ⌘⌃X the local model
            CustomTrigger(.key(0x23), [.control]),             // ⌃P the shutter
        ]
        for action in CustomGestureAction.allCases {
            all.insert(CustomTrigger(.key(action.keyCode), [.control, .option, .command]))
        }
        return all
    }()

    /// The recorder's judgment, pure: a bare click, a bare key, one of the app's
    /// own keys, or a trigger another row already has.
    static func refusal(of trigger: CustomTrigger, for action: CustomGestureAction,
                        in bindings: [CustomGestureAction: CustomTrigger]) -> CustomTriggerRefusal? {
        switch trigger.input {
        case .mouse:
            if trigger.modifiers.isEmpty { return .bareClick }
        case .key:
            if trigger.modifiers.isDisjoint(with: [.control, .option, .command]) { return .bareKey }
            if reservedKeys.contains(trigger) { return .reserved }
        }
        if let other = bindings.first(where: { $0.key != action && $0.value == trigger })?.key {
            return .taken(by: other)
        }
        return nil
    }

    // MARK: - The tap's side (tap thread)

    enum TapInput: Equatable {
        case down(CustomTrigger.Input, CustomTrigger.Modifiers, autorepeat: Bool)
        case up(CustomTrigger.Input)
    }

    enum Verdict: Equatable {
        case pass
        /// Taken, nothing to run: the release of a taken press, a key's autorepeat.
        case swallow
        /// Taken, and it is this gesture.
        case fire(CustomGestureAction)
    }

    /// Whether the tap has anything to ask at all: switched on, or a release
    /// still owed from before it was switched off.
    var live: Bool {
        lock.lock(); defer { lock.unlock() }
        return on || !held.isEmpty
    }

    /// A button or a key, going down or up; nil for every other event.
    static func tapInput(_ type: CGEventType, _ event: CGEvent) -> TapInput? {
        func mouse() -> CustomTrigger.Input? {
            let n = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            return n <= 2 ? .mouse(n) : nil
        }
        switch type {
        case .leftMouseDown: return .down(.mouse(0), .init(event.flags), autorepeat: false)
        case .leftMouseUp: return .up(.mouse(0))
        case .rightMouseDown: return .down(.mouse(1), .init(event.flags), autorepeat: false)
        case .rightMouseUp: return .up(.mouse(1))
        case .otherMouseDown: return mouse().map { .down($0, .init(event.flags), autorepeat: false) }
        case .otherMouseUp: return mouse().map { .up($0) }
        case .keyDown:
            return .down(.key(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))), .init(event.flags),
                         autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp: return .up(.key(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))))
        default: return nil
        }
    }

    /// **The release matches the press**: a release is taken exactly when the
    /// last press of that button was (`area-crop.md` — neither a passed press
    /// with a swallowed release nor the reverse may happen). `frozen` (the main
    /// thread hung) and `busy` (a crop under the wheel, the trackpad chord)
    /// match nothing new; a release owed is still taken.
    func feed(_ input: TapInput, frozen: Bool = false, busy: Bool = false) -> Verdict {
        lock.lock(); defer { lock.unlock() }
        switch input {
        case .up(let what):
            return held.remove(what) != nil ? .swallow : .pass
        case .down(let what, let modifiers, let autorepeat):
            if autorepeat { return held.contains(what) ? .swallow : .pass }
            guard on, !recordingNow, !frozen, !busy, let action = lookup[CustomTrigger(what, modifiers)] else {
                held.remove(what)
                return .pass
            }
            held.insert(what)
            return .fire(action)
        }
    }
}
