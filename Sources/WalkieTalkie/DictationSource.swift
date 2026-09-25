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

    /// **Where the recogniser is in its own round trip** — see `DictationPhase`.
    ///
    /// Added 2026-09-13, and the thing it buys is the difference between *the
    /// words are late* and *the words are lost*. `isRecording` answers only the
    /// middle of the five phases, so everything either side of the microphone —
    /// the warm-up a cold Electron costs, the seconds Wispr spends formatting —
    /// reached the relay as the same undivided "not recording", and a ring or a
    /// settle written against that has no way to wait for one and give up on the
    /// other. Nothing downstream may ask *which recogniser*; this is how it asks
    /// *how far along*.
    var phase: DictationPhase { get }

    /// **Does a sound played into the recogniser's ear reach its transcript?**
    ///
    /// The one question `ShotMarker` has to ask a source, and it is asked this
    /// way round rather than as *are you Wispr* on purpose: nothing downstream
    /// may name an implementation. Wispr hears a Loopback device this app can
    /// speak into, so it answers yes; the local model opens the physical
    /// microphone itself and would need the marker spliced into its own buffer
    /// instead, which is a different mechanism and not built.
    var acceptsAudioMarkers: Bool { get }

    /// **Put the marker for `index` of `kind` where this recogniser will hear
    /// it** — a picture he just took, or a highlight he just made.
    ///
    /// The mechanism is the source's, because the two are not the same move and
    /// only one of them works per source: Wispr hears a Loopback device, so its
    /// marker is *played* into it and is **summed** with his voice; the local
    /// model transcribes a file this app writes, so its marker is **spliced into
    /// that file** between two of his buffers, which is the same idea without
    /// the collision. Called from the shutter and from the selection watcher,
    /// off the main thread.
    func mark(_ kind: ShotMarker.Kind, index: Int)

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

    /// **Where in the audio this recogniser will transcribe did that moment
    /// fall** — nil when the source does not own the recording (2026-09-19).
    ///
    /// The one question a timestamp marker needs answered, and the one that
    /// divides the three sources cleanly: this app's own `MicRecorder` writes
    /// the file that `ElevenLabsSource` and `LocalWhisperSource` hand to a
    /// recogniser, so a shutter press can be placed on the same ruler the
    /// returned word timestamps are measured on. Wispr Flow records in another
    /// process and answers nil — there is no ruler to share.
    ///
    /// Nil is not a failure and is never reported as one: a source that cannot
    /// place a marker simply does not reserve one, and every picture, highlight
    /// and pick is still listed under the words by its offset exactly as before.
    /// → `ShotMarker.place`, `MicRecorder.offset(of:)`
    func audioOffset(of moment: Date) -> TimeInterval?

    /// **Whether this source streams the words while he is still talking**
    /// (2026-09-25, `☁️ ElevenLabs + Live`). The chip opens its `💬` row for the
    /// whole sentence when it does, so the row is there from the first frame
    /// rather than popping in under the pointer with the first word.
    var streamsLive: Bool { get }

    /// **The words heard so far, as the live recogniser has them right now** —
    /// the whole sentence, not a delta; a later call may revise the tail of an
    /// earlier one. A caption only: what is *delivered* still arrives through
    /// `didTranscribe`, from the recording.
    var didHearLive: ((String) -> Void)? { get set }
}

/// **One token of a transcript, with the moment it was said** (2026-09-19).
///
/// The shape ElevenLabs Scribe returns in `words[]`, kept source-agnostic
/// because it is not Scribe's idea: a recogniser that owns timings can say where
/// each word sat in the audio, and that is what lets this app put a screenshot
/// reference *between two of them* without a marker ever having been heard.
///
/// **`spacing` is a token too, and that is the useful part.** The whitespace
/// between two words arrives as its own entry with its own span, so an insertion
/// aimed at one lands on a gap he really left rather than inside a word — which
/// is precisely the damage the spliced marker did (`pus sub un-` / `Strat`).
struct TimedWord {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    /// `type` was `spacing` rather than `word`. Not an enum: the only question
    /// anything here asks is *is this a gap*, and `audio_event` — the third
    /// value, off in this app — is a word for every purpose below.
    let isSpacing: Bool
}

/// What a source hands back when the words arrive.
struct DictationResult {
    /// What was said.
    /// `var` since 2026-09-14, so `AppDelegate.deliver` can rewrite the spoken
    /// shot markers out of it **before** the corpus is filed: the relay's own
    /// recording never heard them (it is on the physical microphone, Wispr is on
    /// the Loopback device), so a corpus pair carrying `Screenshot one.` against
    /// audio that does not is a poisoned sample. → `ShotMarker`
    var text: String

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
    /// **Which of the recogniser's delivery routes produced this text** —
    /// `wispr-cmdv`, `wispr-history`, `wispr-notes`, `pasteboard`,
    /// `local-whisper` (2026-09-13).
    ///
    /// `wispr-notes` is the Scratchpad: Wispr dictating into its own note rather
    /// than into whatever has the caret, which is the one delivery of Wispr's
    /// that inserts nothing anywhere and never moves the focus. Read by
    /// `WisprNotes`; not wired to a gesture yet.
    ///
    /// It is recorded and never branched on, which is why it is a string and not
    /// an enum: the router's question is `delivery` above, and this one is only
    /// ever read back from `outbox.jsonl` and `GET /test/state`. It exists
    /// because the `🗣️ wispr transcript via …` line in `relay.log` was the only
    /// place the answer lived, and a log line is not something a test can assert
    /// against — on 2026-09-13 two failures turned on precisely which route
    /// delivered, and by then the log was the only witness.
    let via: String
    /// **Which process these words were meant for**, when the recogniser's own
    /// machinery may have taken the focus since (2026-09-14). Nil — the ordinary
    /// case — means *whatever has the caret*, which is what every delivery in
    /// this app meant until a recogniser started opening windows of its own.
    ///
    /// It is source-agnostic and deliberately a **pid** rather than anything
    /// Wispr-shaped: the fact being recorded is *the caret was here when he
    /// asked*, and the only thing that can act on it is a paste addressed with
    /// `postToPid`. Measured 2026-09-13: Wispr's Scratchpad window takes the key
    /// focus without its application becoming frontmost, so a ⌘V posted at the
    /// session lands in **its** note and not in his document — and the delivery
    /// had to wait for that window to close before it could fire, which cost
    /// 0.5–3.3 s of a round trip that was ready at 400 ms.
    var focusPid: pid_t?
    /// **Is the marker in the audio as well as in the words?**
    ///
    /// True only where the source *spliced* rather than played — the local model,
    /// whose WAV is the thing it transcribed. It decides one thing and it is the
    /// corpus's: a pair is only worth keeping if its transcript says what its
    /// audio contains, and the two mechanisms fail that test in opposite
    /// directions. Wispr's audio has no marker and its text does, so the corpus
    /// gets the **cleaned** text; the local model's audio has one, so the corpus
    /// gets the **raw** text. → `ShotMarker`, `AppDelegate.deliver`
    var markersInAudio: Bool = false

    /// **What to call the recogniser in front of Victor** — the local model's
    /// weights by name, `Wispr Flow` for Wispr. Written by the source, because
    /// only the source knows, and read by exactly one thing: the envelope's
    /// `[this text dictated and transcribed in RO or EN by …]`. Distinct from
    /// `engine`, which is the stable id the corpus files rows under and must
    /// never become a display string.
    var engineLabel: String = ""

    /// **The transcript with a clock on it**, when the recogniser gave one
    /// (2026-09-19).
    ///
    /// Read by exactly one thing — `AppDelegate.resolvingMarkers`, to put a
    /// screenshot reference at the word he pressed the shutter at. Nil is the
    /// ordinary case for a source that returns prose and nothing else, and it
    /// costs only the fallback everything had before: the frames stay listed
    /// under the sentence by their offsets. → `ShotMarker.place`
    var words: [TimedWord]? = nil
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
    /// **The sentence was said, was recorded, and the recogniser could not be
    /// reached** (2026-09-18, with `ElevenLabsSource`).
    ///
    /// It is neither of the two above and must not be filed as either. `.silent`
    /// throws the audio away, which is right for *nothing was heard* and wrong
    /// for *the network was down* — the words exist and the WAV is the only copy
    /// of them. `.cancelled` keeps the audio but says he asked for this, so it
    /// passes in silence; a failure he is not told about is a paragraph that
    /// simply never arrives, which is the one outcome he cannot notice and
    /// correct.
    ///
    /// So: both halves. The `why` is shown, and the audio goes into the same
    /// five-minute staging area a cancelled one does, so *Recover Cancelled
    /// Dictation* re-reads it through whichever engine is live by then — which
    /// after a network failure is very likely the local one.
    ///
    /// No source but a networked one can raise this today, and the case is
    /// written for *the recogniser could not be reached* rather than for
    /// ElevenLabs: it is a property of transcribing off this Mac, not of a
    /// vendor.
    case failed(why: String, audio: URL?, duration: TimeInterval)
}

extension DictationSource {
    /// **No, unless a source says otherwise.** A marker that reaches nobody is
    /// a word bitten out of his sentence for nothing, so silence is the safe
    /// answer for any recogniser added later.
    var acceptsAudioMarkers: Bool { false }

    /// A source that cannot place a marker is never asked to — `reserveMarker`
    /// checks `acceptsAudioMarkers` first — so this is the honest no-op rather
    /// than a fallback anybody relies on.
    func mark(_ kind: ShotMarker.Kind, index: Int) {}

    /// **No, for a source that does not own the recording.** The safe answer for
    /// any recogniser added later, and the true one for Wispr Flow.
    func audioOffset(of moment: Date) -> TimeInterval? { nil }

    var streamsLive: Bool { false }

    /// Nobody to call: a source that does not stream has no live words.
    var didHearLive: ((String) -> Void)? {
        get { nil }
        set {}
    }
}
