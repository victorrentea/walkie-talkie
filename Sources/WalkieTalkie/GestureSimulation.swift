import Foundation

/// **The gesture machine's unit test**, behind `POST /test/gesture-machine/simulate`.
///
/// It is a route and not an XCTest target for `WisprStateSimulation`'s reason:
/// the package is one `executableTarget` with a `main.swift` in it, which an
/// XCTest bundle cannot import without the top-level code fighting it. What it
/// buys is the thing the old imperative gesture code could least do — assert
/// that 🔼 → with nothing bound **warns and leaves the microphone open**, in a
/// millisecond, with no Wispr, no microphone and nothing on screen.
///
/// A fresh machine over the **checked-in diagram**, a fake clock and a fake
/// world. Touches nothing in the running relay.
enum GestureMachineSimulation {

    /// Records what it was asked to do instead of doing it. The guards are
    /// settable mid-script (`{"set": {"bound": true}}`), which is how a bind
    /// arriving mid-sentence is expressed without a terminal.
    private final class FakeWorld: GestureWorld {
        var bound = false
        // Bound implies deliverable, exactly as AppDelegate's own expression does;
        // letting a script set them apart would let it assert against a world that
        // cannot exist.
        var deliverable = false
        var called: [String] = []
        var warnings: [String] = []
        var notes: [String] = []
        /// The chip after each transition, so an assertion can be written about
        /// which tooltip was showing when.
        var chipLog: [(atMs: Int, rows: [String])] = []
        var clockMs = 0

        func openDictation()     { called.append("openDictation") }
        func stopDictation()     { called.append("stopDictation") }
        func cancelDictation()   { called.append("cancelDictation") }
        func aimAtCaret()        { called.append("aimAtCaret"); deliverable = true }
        func aimAtBound()        { called.append("aimAtBound"); deliverable = bound }
        func aimAtSpawn()        { called.append("aimAtSpawn"); deliverable = true }
        func aimWhereAimed()     { called.append("aimWhereAimed") }
        func bindFrontmost()     { called.append("bindFrontmost"); bound = true; deliverable = true }
        func unbind()            { called.append("unbind"); bound = false }
        func captureScreenshot() { called.append("captureScreenshot") }
        func postReturn()        { called.append("postReturn") }
        func postHandsFreeChord() { called.append("postHandsFreeChord") }
        func deliver()           { called.append("deliver") }
        func holdForBind()       { called.append("holdForBind") }
        func deliverHeld()       { called.append("deliverHeld") }
        func dropHeld()          { called.append("dropHeld") }
        func pauseMusic()        { called.append("pauseMusic") }
        func resumeMusic()       { called.append("resumeMusic") }
        func warn(_ english: String) { called.append("warn"); warnings.append(english) }
        func note(_ line: String)    { notes.append(line) }
        func reconcile(state: String, chip: [String]) {
            if chipLog.last?.rows != chip { chipLog.append((clockMs, chip)) }
        }
    }

    /// `steps` is a list of `{"fire": "<trigger>", "atMs": N}` and
    /// `{"set": {"bound": true}, "atMs": N}`. `from` overrides the diagram's
    /// initial state so a path can be entered in the middle.
    static func run(_ body: [String: Any]) -> [String: Any] {
        guard let loaded = GestureDiagramFile.loadDiagram() else {
            return ["ok": false, "error": "gestures.puml could not be found or parsed"]
        }
        // **A simulation may not run on the fallback.** The last-known-good copy
        // exists so a typo at four in the afternoon costs a warning rather than
        // the afternoon — but a *test* that quietly asserts against yesterday's
        // diagram is worse than one that fails. It cost twenty minutes the day
        // this was written: a duplicated line made the checked-in file
        // unparseable, the fallback loaded, and the answer complained about five
        // action names that had already been deleted.
        if let problem = loaded.problem {
            return ["ok": false, "error": problem, "origin": loaded.origin]
        }
        let world = FakeWorld()
        if let w = body["world"] as? [String: Any] {
            world.bound = (w["bound"] as? Bool) ?? false
            world.deliverable = (w["deliverable"] as? Bool) ?? world.bound
        }
        let machine: GestureMachine
        do {
            machine = try GestureMachine(diagram: loaded.diagram, world: world,
                                         origin: loaded.origin,
                                         now: { CFAbsoluteTime(world.clockMs) / 1000 })
        } catch {
            return ["ok": false, "error": "\(error)"]
        }
        if let from = body["from"] as? String {
            guard loaded.diagram.states[from] != nil else {
                return ["ok": false, "error": "no state named \(from)"]
            }
            machine.enterForSimulation(from)
        }

        var transitions: [[String: Any]] = []
        var unknown: [String] = []
        machine.onStep = { s in
            transitions.append([
                "atMs": world.clockMs,
                "from": s.from, "to": s.to, "trigger": s.trigger,
                "actions": s.actions, "internal": s.isInternal,
            ])
        }
        for raw in (body["steps"] as? [[String: Any]]) ?? [] {
            if let at = raw["atMs"] as? Int { world.clockMs = at }
            if let set = raw["set"] as? [String: Any] {
                if let b = set["bound"] as? Bool { world.bound = b; if b { world.deliverable = true } }
                if let d = set["deliverable"] as? Bool { world.deliverable = d }
                continue
            }
            guard let trigger = raw["fire"] as? String else { continue }
            if !loaded.diagram.triggerNames.contains(trigger) { unknown.append(trigger) }
            machine.fire(trigger)
        }
        return [
            "ok": true,
            "final": machine.state,
            "chip": machine.chip,
            "origin": loaded.origin,
            "transitions": transitions,
            "chipAt": world.chipLog.map { ["atMs": $0.atMs, "rows": $0.rows] },
            "actions": world.called,
            "warnings": world.warnings,
            // A gesture that reached no transition at all. Before this machine,
            // *why did nothing happen* had no answer anywhere in the app.
            "refused": machine.refused,
            // A trigger the diagram has never heard of — usually a typo in the
            // script rather than in the diagram, which is why it is not an error.
            "unknownTriggers": unknown,
        ]
    }
}

extension GestureMachine {
    /// **Simulation only.** Jumping into the middle of a path without running the
    /// entry actions that got there is exactly what a real machine must never do,
    /// which is why this is named for its one caller rather than being a setter.
    func enterForSimulation(_ name: String) { setStateForSimulation(name) }
}
