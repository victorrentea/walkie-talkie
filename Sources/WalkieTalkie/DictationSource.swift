import Foundation

/// **Where the words come from** — the one interface the rest of the relay is
/// allowed to know about a recogniser.
///
/// Until 2026-09-12 there were two dictation paths in this app and they did not
/// look alike from the outside. The relay's own microphone went through
/// `startLocalRecording` / `stopLocalRecording`, produced a transcript and a
/// WAV, and everything downstream — the corpus, the held prompt, the caret
/// paste — hung off it. Wispr Flow went through `wisprDictationChanged` and
/// produced *a boolean*: the ring knew a microphone was open and nothing else
/// did, because Wispr pasted its own text into whatever had focus.
///
/// Victor's decision (2026-09-12) is that **Wispr Flow is the microphone for
/// everything**, bound relay included. That is only buildable once the two
/// paths are the same shape: the destination logic, the settle, the halo and the
/// corpus must not be able to tell which recogniser they are serving, or every
/// one of them grows a second branch that only one of the two ever exercises —
/// which is exactly how the Wispr path spent a month with no transcript in it.
///
/// So: one protocol, two implementations, and `AppDelegate` holds a
/// `DictationSource` and never names either of them.
///
/// | | `WisprFlowSource` | `LocalWhisperSource` |
/// |---|---|---|
/// | start | posts Wispr's own hands-free chord | opens `MicRecorder` |
/// | begins | when CoreAudio says its input is running | synchronously, inside `start()` |
/// | level | a second `MicRecorder` alongside Wispr's | the recording's own meter |
/// | transcript | Wispr's delivery, intercepted (`wrapWispr`) | `LocalWhisper` over the WAV |
/// | audio | the meter's WAV, kept for the corpus | the recording itself |
///
/// ## Every callback lands on the main queue
///
/// What they drive is AppKit — the chip, the halo, a window frame — and the two
/// sources produce their edges on three different threads between them
/// (CoreAudio's listener queue, a transcription callback, the event tap). One
/// rule at the boundary is cheaper than a hop at every call site, and the
/// asymmetry was a real crash once already (`onTestDictationStart`, 2026-09-08).
protocol DictationSource: AnyObject {

    /// For the log and the menu. Never parsed.
    var name: String { get }

    /// Is a dictation open right now? True from `didBegin` to `didStopListening`.
    var isRecording: Bool { get }

    /// Whether `start()` would work this instant. The local model answers *are
    /// the weights loaded*; Wispr answers *is it running*.
    var isReady: Bool { get }

    /// **Whichever microphone is actually hearing him**, for the halo's swell.
    /// A source that cannot hear (there is no such one today) returns the
    /// recorder at rest rather than nil — the halo reads this at 20 Hz on the
    /// main thread and an optional there buys nothing.
    var meter: MicRecorder { get }

    /// Bring whatever is slow up now, before a gesture is waiting on it.
    func prepare()

    /// Open a dictation. Returns the reason it could not, or nil.
    ///
    /// **Not the same instant as `didBegin`.** The local source begins inside
    /// this call; Wispr's begins when its microphone opens, which is Electron
    /// waking up later. Nothing may assume the two are the same moment.
    @discardableResult
    func start() -> String?

    /// End it and deliver. `didStopListening` follows, then `didTranscribe` or
    /// `didEnd`.
    func stop()

    /// End it and throw it away. `didEnd(.cancelled)` follows; no transcript.
    func cancel()

    /// **The gesture that asks for a dictation was seen, before the microphone
    /// is open.** Only Wispr has a gap here worth drawing — the ring goes up on
    /// the keystroke and is taken back if no microphone follows — but the event
    /// is on the protocol because *speculation* is a property of a source whose
    /// recorder lives in another process, not a fact about Wispr Flow.
    var didMaybeBegin: ((String) -> Void)? { get set }

    /// The microphone is open.
    var didBegin: (() -> Void)? { get set }

    /// The microphone closed and the words are in flight. **This is where the
    /// destination is latched** — the recipient is whoever the relay is pointed
    /// at when the microphone closes, and for a source with a round trip in it
    /// the close and the transcript are seconds apart.
    var didStopListening: (() -> Void)? { get set }

    /// The words.
    var didTranscribe: ((DictationResult) -> Void)? { get set }

    /// The session is over, whichever way it ended. Always exactly once per
    /// `didBegin`, and after `didTranscribe` when there was one.
    var didEnd: ((DictationEnd) -> Void)? { get set }
}

/// What a source hands back when the words arrive.
struct DictationResult {
    /// What was said.
    let text: String
    /// What the recogniser thought it was, when it says. Whisper answers;
    /// Wispr's pasteboard delivery carries no language.
    let language: String?
    /// **The audio, for `VoiceCorpus`** — the one thing in `~/.walkie-talkie`
    /// that cannot be regenerated. Nil when the source kept none, and the
    /// corpus entry is then skipped rather than faked.
    ///
    /// The caller owns it and deletes it: the corpus reads the bytes on the
    /// calling thread precisely so the staged file can go immediately after.
    let audio: URL?
    /// How long the microphone was open, for the corpus manifest.
    let duration: TimeInterval
    /// Stamped into `corpus.jsonl`, so a sample recorded under one recogniser
    /// stays distinguishable from one recorded under another forever.
    let engine: String
    /// A note to hang under the transcript on the prompt panel — a confidence
    /// floor, a loop ceiling. Generic because *the recogniser is unsure* is not
    /// a Whisper-specific idea, even though Whisper is the only one measuring
    /// it today.
    let warning: String?
    /// Whether the relay still has to put these words somewhere.
    let delivery: DictationDelivery
}

/// **Who inserts the text.**
///
/// A source whose recogniser lives in another process may have already typed
/// the sentence into whatever had focus by the time the relay hears about it.
/// That is not a Wispr quirk to be branched on — it is a property of the
/// delivery, and the one thing the router needs to know before it routes.
enum DictationDelivery {
    /// The relay delivers: the bound agent, or the caret.
    case route
    /// Somebody else already put it on screen. File it, do not deliver it.
    case alreadyInserted
    /// Somebody else put it **where the focus was**, and this is the text they
    /// put there (2026-09-12: Wispr Flow's Accessibility insertion, read back
    /// from its `History` row). At the caret that *is* the delivery; at a
    /// terminal the words still have to travel, and the copy at the caret is
    /// a stray that cannot be taken back.
    case insertedElsewhere
}

/// How a dictation finished.
enum DictationEnd {
    /// A transcript came back — `didTranscribe` has already fired.
    case delivered
    /// Nothing to deliver, and why. Shown to Victor when there is something to
    /// say; the empty string is *nothing worth a banner* — a misfire, a chord
    /// Wispr ignored, a click released inside the minimum duration.
    case silent(String)
    /// He threw it away, and here is the audio if the source kept any: a
    /// cancelled dictation is held for five minutes so *Recover Cancelled
    /// Dictation* has something to re-read.
    case cancelled(audio: URL?, duration: TimeInterval)
}
