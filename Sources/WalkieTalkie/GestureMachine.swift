import Foundation

/// **What the mouse means right now**, executed from `docs/gestures.puml`.
///
/// ## Two machines, one seam
///
/// `WisprState` answers *where is the recogniser in its own round trip* — five
/// phases joined from four witnesses that disagree with each other, with the
/// measured lags to prove it. This one answers *what does a gesture do*. They
/// compose by event and neither re-derives the other: `WisprState` reaching
/// `listening` is what fires `@micOpened` in here, and this machine never polls
/// CoreAudio, never reads a `History` row and never names a recogniser.
///
/// Keeping them apart is the whole of Victor's scope for this change. Collapsing
/// them would produce two opinions about whether a microphone is open, which is
/// exactly the failure of 2026-09-13 with an extra layer on top.
///
/// ## It owns nothing
///
/// No timers, no AppKit, no I/O, injectable clock — the same discipline
/// `WisprState` is written under, and for the same payoff:
/// `POST /test/gesture-machine/simulate` runs a scripted day through a fresh
/// machine with a fake world in under a millisecond.
///
/// **Main thread only**, like every `DictationSource` callback. `HotkeyTap`
/// dispatches globally, so `fire` is reached through a hop.
final class GestureMachine {

    // MARK: - What happened, for the log and for an assertion

    struct Step {
        let at: CFAbsoluteTime
        let from: String
        let to: String
        let trigger: String
        let actions: [String]
        let isInternal: Bool
        /// How many triggers were waiting behind this one. Non-zero is a
        /// re-entrant burst — see `fire`.
        let queued: Int
    }

    private(set) var state: String
    private(set) var since: CFAbsoluteTime
    private(set) var steps: [Step] = []
    /// Triggers that reached no transition at all. The answer to *why did
    /// nothing happen*, which before this machine had no answer anywhere.
    private(set) var refused: [String] = []

    let diagram: GestureDiagram.Parsed
    /// Where the text came from, for `GET /test/state` — a diagram loaded from
    /// the repo during a `swift build` run is a different claim to one loaded
    /// from the installed bundle.
    let origin: String

    private let world: GestureWorld
    private let actions: [String: (GestureWorld) -> Void]
    private let guards: [String: (GestureWorld) -> Bool]
    private let now: () -> CFAbsoluteTime

    /// Every transition, for `relay.log` and for the shadow harness.
    var onStep: ((Step) -> Void)?

    // MARK: - Building one

    /// **Every name is resolved here, eagerly, before the machine is usable.**
    /// A diagram is accepted whole or not at all: a partial one would answer some
    /// gestures and silently drop others, which is worse than answering none.
    init(diagram: GestureDiagram.Parsed,
         world: GestureWorld,
         origin: String,
         actions: [String: (GestureWorld) -> Void] = GestureActions.actions(),
         guards: [String: (GestureWorld) -> Bool] = GestureActions.guards(),
         now: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent) throws {
        let missingActions = diagram.actionNames.subtracting(actions.keys).sorted()
        let missingGuards = diagram.guardNames.subtracting(guards.keys).sorted()
        guard missingActions.isEmpty, missingGuards.isEmpty else {
            throw Unresolved(actions: missingActions, guards: missingGuards)
        }
        self.diagram = diagram
        self.world = world
        self.origin = origin
        self.actions = actions
        self.guards = guards
        self.now = now
        self.state = diagram.initial
        self.since = now()
    }

    /// Names the diagram uses that nothing answers. Carries both lists rather
    /// than the first one found, because a rename usually breaks several at once
    /// and finding them one build at a time is the slow way.
    struct Unresolved: Error, CustomStringConvertible {
        let actions: [String]
        let guards: [String]
        var description: String {
            var parts: [String] = []
            if !actions.isEmpty { parts.append("actions \(actions.joined(separator: ", "))") }
            if !guards.isEmpty { parts.append("guards \(guards.joined(separator: ", "))") }
            return "gestures.puml names \(parts.joined(separator: " and ")) that nothing implements"
        }
    }

    // MARK: - Firing

    private var pending: [String] = []
    private var draining = false

    /// **A trigger from the mouse, the keyboard, or the world.**
    ///
    /// Queued rather than recursed. `stopDictation` reaches `source.stop()`,
    /// which for the local recogniser can raise `didStopListening`
    /// **synchronously** and fire `@micConfirmedShut` back in here while the
    /// first transition's action list is still running. `WisprState` has no such
    /// problem because nothing calls back into it; this machine is wired to the
    /// things it commands, so it needs the queue. The depth rides in `Step` so a
    /// re-entrant burst is visible in the log rather than merely survived.
    func fire(_ trigger: String) {
        pending.append(trigger)
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while !pending.isEmpty {
            let next = pending.removeFirst()
            step(next, queued: pending.count)
        }
        world.reconcile(state: state, chip: chip)
    }

    /// The chip rows for the state now current — the diagram's own strings.
    var chip: [String] { diagram.chipRows(in: state) }

    /// Is the machine in this state, or inside it. `isIn("Listening")` is true
    /// in all three of its substates, which is what replaced the four-clause
    /// `atCaret` expression this refactor was written to delete.
    func isIn(_ name: String) -> Bool { diagram.chain(of: state).contains(name) }

    private func step(_ trigger: String, queued: Int) {
        for candidate in GestureDiagram.candidates(in: diagram, state: state, trigger: trigger) {
            if let name = candidate.guardName {
                // Resolved at init, so this cannot be nil — but a crash beside a
                // man mid-sentence is not the way to say so.
                guard let test = guards[name] else {
                    Log.error("🖱️ guard \(name) vanished between load and fire")
                    continue
                }
                let passed = candidate.guardNegated ? !test(world) : test(world)
                if !passed { continue }
            }
            take(candidate, queued: queued)
            return
        }
        refused.append(trigger)
        // Bounded like `steps`: this app runs from login and a gesture that means
        // nothing in the state it was made in is an ordinary thing to do.
        if refused.count > 50 { refused.removeFirst(refused.count - 50) }
        Log.info("🖱️ \(trigger) in \(state) — the diagram answers it with nothing")
    }

    /// Exit actions, then the transition's own, then entry — UML's order, with
    /// the state changing between the second and the third so an entry action
    /// sees where it has arrived.
    private func take(_ t: GestureDiagram.Transition, queued: Int) {
        let from = state
        var ran: [String] = []
        if let to = t.to {
            let crossing = GestureDiagram.crossing(in: diagram, from: from, to: to)
            ran += perform(crossing.exit)
            ran += perform(t.actions)
            state = to
            since = now()
            ran += perform(crossing.entry)
        } else {
            ran += perform(t.actions)
        }
        let step = Step(at: now(), from: from, to: t.to ?? from, trigger: t.trigger,
                        actions: ran, isInternal: t.isInternal, queued: queued)
        steps.append(step)
        // Bounded, because the app runs from login all day and this is a log.
        if steps.count > 200 { steps.removeFirst(steps.count - 200) }
        let arrow = t.isInternal ? "↻" : "→"
        let detail = ran.isEmpty ? "" : " / \(ran.joined(separator: ", "))"
        let behind = queued > 0 ? "  (\(queued) queued)" : ""
        Log.info("🖱️ \(from) \(arrow) \(t.to ?? from) : \(t.trigger)\(detail)\(behind)")
        onStep?(step)
    }

    /// **Simulation only** — see `GestureMachine.enterForSimulation`.
    func setStateForSimulation(_ name: String) { state = name; since = now() }

    @discardableResult
    private func perform(_ names: [String]) -> [String] {
        for name in names { actions[name]?(world) }
        return names
    }

    // MARK: - What `GET /test/state` answers

    func snapshot() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [
            "state": state,
            "chip": chip,
            "sinceMs": Int((now() - since) * 1000),
            "diagram": [
                "origin": origin,
                "states": diagram.order,
                "transitions": diagram.transitions.count,
            ],
            // `Array(…)`, not the slice: `JSONSerialization` refuses an
            // `ArraySlice` and `GET /test/state` would throw on a gesture that
            // had been refused — which is exactly the run somebody is reading the
            // state to understand.
            "refused": Array(refused.suffix(20)),
            "steps": Array(steps.suffix(20)).map { s in
                [
                    "at": iso.string(from: Date(timeIntervalSinceReferenceDate: s.at)),
                    "from": s.from, "to": s.to, "trigger": s.trigger,
                    "actions": s.actions, "internal": s.isInternal, "queued": s.queued,
                ] as [String: Any]
            },
        ]
    }
}

// MARK: - Finding the diagram

/// **Where `gestures.puml` lives**, and what happens when it will not load.
///
/// The resolution order is `Transcriber.helperPath`'s, copied deliberately
/// rather than reinvented — including the `relativeTo: currentDirectoryPath`
/// standardisation, whose absence was a real bug there (`arguments[0]` is
/// routinely relative, so the walk produced a path relative to nothing and the
/// helper "did not exist" in a checkout that plainly had it).
///
/// The third leg is not optional: `docs/shoot-overlay-states.sh` runs
/// `./.build/debug/WalkieTalkie`, which has no `Contents/Resources` at all.
enum GestureDiagramFile {

    /// The copy of the last diagram that loaded. Not a second source of truth —
    /// it is never hand-edited and never wins silently; a run on it says so in
    /// `GET /test/state.gestureMachine.diagram.origin`. It exists because a typo
    /// at four in the afternoon should cost a warning, not the afternoon.
    static var lastGood: URL { Outbox.home.appendingPathComponent("gestures.last-good.puml") }

    static func candidates() -> [URL] {
        var out: [URL] = []
        if let override = ProcessInfo.processInfo.environment["WT_GESTURES_PUML"] {
            out.append(URL(fileURLWithPath: override))
        }
        if let res = Bundle.main.resourcePath {
            out.append(URL(fileURLWithPath: res).appendingPathComponent("gestures.puml"))
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0],
                      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<4 {
            out.append(dir.appendingPathComponent("docs/gestures.puml"))
            dir = dir.deletingLastPathComponent()
        }
        return out
    }

    /// The text, and where it came from. `nil` when there is nothing anywhere —
    /// which is Safe Mode, and is said out loud by the caller.
    static func read() -> (text: String, origin: String)? {
        for url in candidates() {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return (text, url.path)
            }
        }
        if let text = try? String(contentsOf: lastGood, encoding: .utf8) {
            return (text, "last-good")
        }
        return nil
    }

    static func rememberGood(_ text: String) {
        try? text.write(to: lastGood, atomically: true, encoding: .utf8)
    }

    /// Parse what is on disk, falling back to the last diagram that worked.
    ///
    /// Whole or not at all, in both directions: a file that parses becomes the
    /// last-known-good, and a file that does not is refused entirely rather than
    /// merged with anything.
    static func loadDiagram() -> (diagram: GestureDiagram.Parsed, origin: String, problem: String?)? {
        guard let (text, origin) = read() else { return nil }
        do {
            let parsed = try GestureDiagram.parse(text)
            if origin != "last-good" { rememberGood(text) }
            return (parsed, origin, nil)
        } catch {
            let why = "\(error)"
            Log.error("🖱️ \(why)")
            guard origin != "last-good",
                  let fallback = try? String(contentsOf: lastGood, encoding: .utf8),
                  let parsed = try? GestureDiagram.parse(fallback) else { return nil }
            return (parsed, "last-good", why)
        }
    }
}
