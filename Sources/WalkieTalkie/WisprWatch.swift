import CoreAudio
import Foundation

/// **Is Wispr Flow listening right now?** — the one question this app has to ask
/// of the dictation tool it did not replace.
///
/// ## Why the ring has to know about another app at all
///
/// `CaretHalo` stopped being the caret's warning on 2026-09-11 and became the
/// **microphone's beacon**: it is up whenever something is hearing him, and it
/// breathes on his own voice. That reading is only honest if it covers *every*
/// way he dictates, and Replace Wispr — this app's own caret mode — is off far
/// more often than it is on. With the tick down, Wispr Flow is what he talks
/// into, everywhere: *"dacă aceasta nu este activată, atunci Wispr trebuie
/// folosit în tot, în orice context în care dictez, fie că este terminal, câte
/// terminale noi, fie că este binduit … că este la cursor, peste tot"*
/// (2026-09-11). A beacon that goes dark for the commonest dictation of the day
/// is a beacon that cannot be trusted on the rare one.
///
/// So there is no gate here — not on `pasteMode`, not on a binding, not on the
/// Replace Wispr tick. The rule in `.claude/rules/replace-wispr-and-halo.md` is
/// *do not gate the ring*, and Wispr's microphone is simply a second way for the
/// same answer to be yes.
///
/// ## This is **not** the Wispr Flow database coming back
///
/// Until 2026-08-29 this app read Wispr Flow's `flow.sqlite`, transcribed the WAV
/// blob it found there and swallowed Wispr's own paste; all of it went whole and
/// the rule says **never reintroduce the Wispr Flow database path**. That rule is
/// about a *recogniser* — about this app taking words out of another app's store
/// and pretending they are its own.
///
/// Nothing here reads a word, a file, or a transcript. It asks CoreAudio one
/// boolean about a process id: *is its input running*. It is the same fact the
/// orange dot in the menu bar is drawn from, and it would be just as true of any
/// other app that opened the microphone — Wispr Flow is named only because it is
/// the one that means *Victor is dictating*.
///
/// ## The signal, and the two that were rejected
///
/// **`kAudioProcessPropertyIsRunningInput` on the Wispr Flow process objects.**
/// macOS files every audio client as an `AudioObject` under
/// `kAudioHardwarePropertyProcessObjectList`, each carrying a pid, a bundle id
/// and that flag. Wispr Flow is Electron and spreads over several of them
/// (`com.electron.wispr-flow`, `.helper`, `.accessibility-mac-app`), which is why
/// the match is a **prefix** and the verdict is an OR over all of them: which
/// helper holds the device is Wispr's business and changes between its versions.
///
/// - **Not the device's `kAudioDevicePropertyDeviceIsRunningSomewhere`.** It
///   answers *is anybody using the input*, and on this Mac the answer is
///   permanently yes: measured 2026-09-11, `ai.krisp.krispMac` and
///   `com.rogueamoeba.audiohijack` both sit at `runningInput = 1` all day with
///   nothing being dictated. A flag that is always true is not a signal.
/// - **Not the chord this app already types.** `HotkeyTap.postWisprHandsFree`
///   posts `fn ⌃ Space` — Wispr's hands-free toggle — every time the forward
///   button is clicked outside Replace Wispr, so the relay does know about *one*
///   of the ways a Wispr dictation starts. It is still the wrong thing to draw a
///   ring from: it says *a chord went out*, not *the microphone opened*. It is a
///   **toggle**, so the relay's idea of the state drifts the first time Wispr
///   misses one or Victor ends the dictation from Wispr's own window; and it
///   knows nothing at all about a dictation he started with the keyboard chord
///   himself. The device is the only thing that cannot be wrong about this.
///
/// ## Listeners, not a poll
///
/// Two kinds of listener block, because there are two ways the answer changes.
/// The per-process one fires on the flag itself; the one on the system object's
/// process list fires when a client appears or goes away, and re-subscribes.
/// That second one matters at launch: an Electron helper is only filed as an
/// audio object once it first touches audio, so the process that will hold the
/// microphone this afternoon may not exist when this starts.
///
/// **Everything runs on one serial queue** and the verdict is reported on the
/// main one, because what it drives is AppKit: a panel, a mouse monitor and an
/// `AVAudioEngine`.
final class WisprWatch {

    /// Every bundle id Wispr Flow's processes carry starts with this. A prefix
    /// rather than a list: the Electron helpers are named per role and per
    /// version, and a list would go stale silently — the failure would be the
    /// ring simply never coming up, which looks exactly like the feature not
    /// being built.
    private static let bundlePrefix = "com.electron.wispr-flow"

    /// Called on the main queue on every **change**, never on a repeat.
    var onChange: ((Bool) -> Void)?

    /// The last verdict, for anyone who needs to ask rather than be told.
    private(set) var isDictating = false

    /// **When the edge was read off CoreAudio**, stamped on the watcher's own
    /// queue immediately before the hop to main. The ring's job is to be up the
    /// instant the microphone opens, and "instant" is only a claim until
    /// something measures it — `AppDelegate` subtracts this from the moment the
    /// panel is on screen and writes the milliseconds into the log.
    private(set) var edgeAt: CFAbsoluteTime = 0

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.wispr-watch")
    /// The process objects we hold an `IsRunningInput` listener on, and the block
    /// each was registered with — `AudioObjectRemovePropertyListenerBlock` matches
    /// on the block, so it has to be the same one.
    private var watched: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var listListener: AudioObjectPropertyListenerBlock?
    private var started = false

    private static var listAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunningInput,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self, !self.started else { return }
            self.started = true
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.queue.async { self?.resubscribe() }
            }
            self.listListener = block
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &Self.listAddress, self.queue, block)
            if status != noErr {
                // Not fatal and not silent: without it the ring still lights for
                // every Wispr process that already existed at launch, which is
                // most of them — it is the helper that appears later that would
                // go unseen.
                Log.error("wispr watch: cannot follow the audio process list (OSStatus \(status))")
            }
            self.resubscribe()
        }
    }

    // MARK: - Subscription

    /// Re-reads the process list and makes `watched` match the Wispr Flow
    /// processes in it, then re-reads the verdict.
    private func resubscribe() {
        let wanted = Set(Self.processObjects().filter {
            Self.bundleID(of: $0)?.hasPrefix(Self.bundlePrefix) == true
        })

        for (object, block) in watched where !wanted.contains(object) {
            AudioObjectRemovePropertyListenerBlock(object, &Self.runningAddress, queue, block)
            watched.removeValue(forKey: object)
        }
        for object in wanted where watched[object] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.queue.async { self?.publish() }
            }
            let status = AudioObjectAddPropertyListenerBlock(object, &Self.runningAddress, queue, block)
            if status == noErr { watched[object] = block }
        }
        publish()
    }

    /// The OR over every watched process, reported on the main queue and only on
    /// an edge.
    private func publish() {
        let now = watched.keys.contains { Self.isRunningInput($0) }
        let at = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async { [weak self] in
            self?.edgeAt = at
            guard let self, now != self.isDictating else { return }
            self.isDictating = now
            Log.info("wispr flow \(now ? "opened the microphone" : "closed the microphone")")
            self.onChange?(now)
        }
    }

    // MARK: - CoreAudio

    private static func processObjects() -> [AudioObjectID] {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &listAddress, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &listAddress, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// **`takeRetainedValue`, not unretained** — `kAudioProcessPropertyBundleID`
    /// hands back a `CFString` the caller owns. Reading it through a plain
    /// `inout CFString?` compiles with a warning and leaks it on every scan.
    private static func bundleID(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let cf = value?.takeRetainedValue() else { return nil }
        return cf as String
    }

    private static func isRunningInput(_ object: AudioObjectID) -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &runningAddress, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }
}
