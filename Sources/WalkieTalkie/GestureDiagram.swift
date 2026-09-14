import Foundation

/// **The PlantUML state diagram, parsed.** `docs/gestures.puml` is the program;
/// this file is the only thing that reads it.
///
/// ## Why a parser and not a Swift table
///
/// Until this landed, what a mouse gesture meant was the emergent behaviour of
/// about twenty booleans spread across `AppDelegate`, `HotkeyTap` and
/// `WisprFlowSource` — `listening`, `speculative`, `settling`, `settlingAtCaret`,
/// `pasteMode`, `latchedAtCaret`, `spawnPending`, `awaitingBind` — with the
/// answer to *what does 🔼 → do while unbound* living in a four-clause boolean
/// expression nobody had read since the day it was written. Every rule in
/// `.claude/rules/dictation-source.md` that cost a night is a missing guard on
/// one of those implicit states.
///
/// So the vocabulary is written down **once**, in a file that is also a picture,
/// and executed from there. A second copy — generated Swift, a hand-kept table —
/// is the drift this exists to remove, which is why there is no codegen step and
/// no baked-in fallback table.
///
/// ## It owns nothing, and it is pure
///
/// Text in, table out or errors out. No Foundation beyond `String`, no AppKit, no
/// I/O, no clock. That is what lets `POST /test/gesture-machine/simulate` run a
/// scripted day through a machine in under a millisecond, and what lets
/// `evals/test_gesture_diagram.py` reason about the same file from Python.
///
/// ## The grammar, and why each rule is there
///
/// The whole of it is in `docs/gestures.puml`'s own header, so a person editing
/// the diagram reads the rules in the file they are editing. Repeated here only
/// where the *reason* belongs with the code:
///
/// - **The trigger is the last whitespace-separated token of the trigger
///   clause.** `🔼 →` in front is a glyph for the reader. Without this the
///   diagram would have to choose between being readable and being parseable.
/// - **`A --> A` is a parse error.** A UML self-transition re-runs exit and
///   entry, which here would resume the music and drop the ring for a gesture
///   meant to change nothing. Refusing the syntax makes the 🔼 → refusal
///   (*"dictarea nu se termină"*) unwriteable wrong: it has to be an internal
///   transition, and an internal transition cannot run `exit`.
/// - **Guards and actions are names.** A guard with an expression in it is logic
///   nobody can test; a guard that is a name is a registry entry with a doc
///   comment and a simulate-route assertion behind it.
/// - **One level of nesting.** A hand-written statechart stops being readable at
///   depth two, and readability is the entire justification for this file.
enum GestureDiagram {

    // MARK: - What a parsed diagram is

    /// One arrow, or one line inside a state box. `to == nil` is an **internal**
    /// transition: it runs its actions and neither `exit` nor `entry`.
    struct Transition: Equatable {
        let from: String
        /// `nil` for an internal transition — see the type's own note.
        let to: String?
        /// The bare gesture name (`forward-click`) or an event (`@wordsLanded`).
        let trigger: String
        let guardName: String?
        /// `[!bound]`. The only operator the grammar has.
        let guardNegated: Bool
        let actions: [String]
        /// 1-based, for an error a person can go and look at.
        let line: Int

        var isInternal: Bool { to == nil }
    }

    struct State {
        let name: String
        /// The composite this sits inside, if any. One level only.
        let parent: String?
        let stereotype: String?
        /// The tooltip beside the pointer, in file order. **This is the chip** —
        /// the strings are not duplicated in `RelayWindow`.
        var chip: [String] = []
        var entry: [String] = []
        var exit: [String] = []
        var line: Int
    }

    struct Parsed {
        let initial: String
        /// Declaration order, so errors and `/test/state` read like the file.
        let order: [String]
        let states: [String: State]
        /// Every transition, internal and external, in file order.
        let transitions: [Transition]

        var actionNames: Set<String> {
            var names = Set<String>()
            for s in states.values { names.formUnion(s.entry); names.formUnion(s.exit) }
            for t in transitions { names.formUnion(t.actions) }
            return names
        }
        var guardNames: Set<String> {
            Set(transitions.compactMap(\.guardName))
        }
        var triggerNames: Set<String> {
            Set(transitions.map(\.trigger))
        }
        /// The chain from the outermost ancestor down to `name`, inclusive.
        func chain(of name: String) -> [String] {
            var chain: [String] = []
            var cursor: String? = name
            while let c = cursor, let s = states[c] { chain.insert(c, at: 0); cursor = s.parent }
            return chain
        }
        /// Ancestors outermost-first then the leaf's own rows — general, though
        /// today only leaves carry a chip.
        func chipRows(in name: String) -> [String] {
            chain(of: name).flatMap { states[$0]?.chip ?? [] }.filter { !$0.isEmpty }
        }
    }

    /// A refusal a person can act on: what, and which line of which file.
    struct ParseError: Error, CustomStringConvertible {
        let line: Int
        let message: String
        var description: String { "gestures.puml:\(line): \(message)" }
    }

    // MARK: - Parsing

    // Lines that are decoration. Everything the renderer needs and the machine
    // does not: if PlantUML grows another one, it lands here rather than in a
    // parse error, because a diagram that will not load is a mouse that does
    // nothing.
    private static let ignoredPrefixes = [
        "@startuml", "@enduml", "skinparam", "hide", "show", "title", "legend",
        "end legend", "scale", "left to right", "top to bottom", "!", "caption",
        "header", "footer", "note ", "end note",
    ]

    static func parse(_ text: String) throws -> Parsed {
        var states: [String: State] = [:]
        var order: [String] = []
        var transitions: [Transition] = []
        var initial: String?
        // The composite currently open. One element deep by the grammar; kept as
        // a stack so a second `{` can be refused by name rather than by counting.
        var openComposites: [String] = []
        // `skinparam state { … }` and friends are multi-line decoration. Their
        // bodies look like nothing else in the grammar, so they are skipped by
        // depth rather than by trying to recognise each property.
        var decorationDepth = 0

        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = index + 1
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("'") { continue }
            if decorationDepth > 0 {
                if s.hasSuffix("{") { decorationDepth += 1 }
                else if s == "}" || s.hasPrefix("}") { decorationDepth -= 1 }
                continue
            }
            let lower = s.lowercased()
            if ignoredPrefixes.contains(where: { lower.hasPrefix($0) }) {
                if s.hasSuffix("{") { decorationDepth = 1 }
                continue
            }

            if s == "}" {
                guard !openComposites.isEmpty else {
                    throw ParseError(line: line, message: "a closing brace with no state open")
                }
                openComposites.removeLast()
                continue
            }

            // ── the initial state ──────────────────────────────────────────
            if s.hasPrefix("[*]") {
                guard let arrow = s.range(of: "-->") ?? s.range(of: "->") else {
                    throw ParseError(line: line, message: "[*] must be followed by an arrow")
                }
                let target = s[arrow.upperBound...]
                    .split(separator: ":").first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                guard !target.isEmpty else {
                    throw ParseError(line: line, message: "[*] points at nothing")
                }
                guard initial == nil else {
                    throw ParseError(line: line, message: "a second initial state — there may be only one")
                }
                initial = target
                continue
            }

            // ── a state declaration ────────────────────────────────────────
            if s.hasPrefix("state ") {
                var body = String(s.dropFirst("state ".count)).trimmingCharacters(in: .whitespaces)
                let opensComposite = body.hasSuffix("{")
                if opensComposite { body = String(body.dropLast()).trimmingCharacters(in: .whitespaces) }
                var stereotype: String?
                if let open = body.range(of: "<<"), let close = body.range(of: ">>") {
                    stereotype = String(body[open.upperBound..<close.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    body = (String(body[body.startIndex..<open.lowerBound])
                            + String(body[close.upperBound...]))
                        .trimmingCharacters(in: .whitespaces)
                }
                let name = body.split(separator: " ").first.map(String.init) ?? body
                guard !name.isEmpty else {
                    throw ParseError(line: line, message: "a state with no name")
                }
                // Re-declaring is how PlantUML lets you open a composite and add
                // to it; the stereotype and parent of the first declaration win.
                if states[name] == nil {
                    guard openComposites.count <= 1 else {
                        throw ParseError(line: line,
                                         message: "\(name) would be two levels deep — the grammar allows one")
                    }
                    states[name] = State(name: name, parent: openComposites.last,
                                         stereotype: stereotype, line: line)
                    order.append(name)
                }
                if opensComposite {
                    guard decorationDepth == 0 else {
            throw ParseError(line: 0, message: "a skinparam block was never closed")
        }
        guard openComposites.isEmpty else {
                        throw ParseError(line: line,
                                         message: "\(name) opens a second level of nesting — the grammar allows one")
                    }
                    openComposites.append(name)
                }
                continue
            }

            // ── a transition ───────────────────────────────────────────────
            if let arrow = s.range(of: "-->") ?? s.range(of: "->") {
                let from = String(s[s.startIndex..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rest = String(s[arrow.upperBound...])
                let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                let to = parts[0].trimmingCharacters(in: .whitespaces)
                guard !from.isEmpty, !to.isEmpty else {
                    throw ParseError(line: line, message: "an arrow with no state at one end")
                }
                guard from != to else {
                    throw ParseError(line: line, message:
                        "`\(from) --> \(from)` is refused: a self-transition re-runs exit and entry. "
                        + "Write it as an internal transition — `\(from) : <trigger> / <actions>`")
                }
                guard parts.count == 2 else {
                    throw ParseError(line: line, message: "a transition with no trigger")
                }
                transitions.append(try transition(from: from, to: to,
                                                  label: String(parts[1]), line: line))
                continue
            }

            // ── a description line: `Name : …` ─────────────────────────────
            if let colon = s.firstIndex(of: ":") {
                let name = String(s[s.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let rawBody = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                guard states[name] != nil else {
                    throw ParseError(line: line, message: "`\(name)` has no `state \(name)` declaration")
                }
                // Collapse runs of whitespace before the keyword tests. `exit  /`
                // — aligned under `entry /` in the diagram, which is how a person
                // writes it — did not match `exit /` and fell through to being
                // parsed as a *transition* whose trigger was the word `exit`. It
                // raised no error and cost `resumeMusic`: the music stayed paused
                // after every sentence. Silence is the failure mode this grammar
                // can least afford, which is why the reserved words below are
                // refused as triggers rather than merely handled here.
                let body = rawBody.split(separator: " ", omittingEmptySubsequences: true)
                    .joined(separator: " ")
                if body.hasPrefix("chip ") {
                    let quoted = String(body.dropFirst("chip ".count)).trimmingCharacters(in: .whitespaces)
                    guard quoted.hasPrefix("\""), quoted.hasSuffix("\""), quoted.count >= 2 else {
                        throw ParseError(line: line, message: "a chip row must be in double quotes")
                    }
                    states[name]?.chip.append(String(quoted.dropFirst().dropLast()))
                } else if body.hasPrefix("entry /") {
                    states[name]?.entry.append(contentsOf:
                        actionList(String(body.dropFirst("entry /".count))))
                } else if body.hasPrefix("exit /") {
                    states[name]?.exit.append(contentsOf:
                        actionList(String(body.dropFirst("exit /".count))))
                } else if body.hasPrefix("mic ") || body.hasPrefix("note ") {
                    // A declared invariant or a reader's note — rendered, not executed.
                    continue
                } else {
                    transitions.append(try transition(from: name, to: nil, label: body, line: line))
                }
                continue
            }

            throw ParseError(line: line, message: "cannot read `\(s)`")
        }

        guard decorationDepth == 0 else {
            throw ParseError(line: 0, message: "a skinparam block was never closed")
        }
        guard openComposites.isEmpty else {
            throw ParseError(line: 0, message: "\(openComposites.joined(separator: ", ")) was never closed")
        }
        guard let start = initial else {
            throw ParseError(line: 0, message: "no initial state — the diagram needs one `[*] --> …`")
        }
        let parsed = Parsed(initial: start, order: order, states: states, transitions: transitions)
        try check(parsed)
        return parsed
    }

    /// `trigger [guard] / action, action` — the one label grammar, shared by an
    /// arrow's label and a state's internal line so the two cannot drift.
    private static func transition(from: String, to: String?,
                                   label: String, line: Int) throws -> Transition {
        var head = label.trimmingCharacters(in: .whitespaces)
        var actions: [String] = []
        if let slash = head.firstIndex(of: "/") {
            actions = actionList(String(head[head.index(after: slash)...]))
            head = String(head[head.startIndex..<slash]).trimmingCharacters(in: .whitespaces)
        }
        var guardName: String?
        var negated = false
        if let open = head.firstIndex(of: "["), let close = head.firstIndex(of: "]"), open < close {
            var g = String(head[head.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            if g.hasPrefix("!") { negated = true; g = String(g.dropFirst()).trimmingCharacters(in: .whitespaces) }
            guard !g.isEmpty else { throw ParseError(line: line, message: "an empty guard") }
            guard !g.contains("&"), !g.contains("|"), !g.contains("=") else {
                throw ParseError(line: line, message:
                    "`\(g)` is an expression; a guard must be a name the registry can resolve")
            }
            guardName = g
            head = String(head[head.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        }
        // The trigger is the LAST token: everything before it is the glyph the
        // reader sees on the arrow (`🔼 →`), checked against HotkeyTap's own
        // table by evals/test_gesture_glyphs.py rather than here.
        guard let trigger = head.split(separator: " ").last.map(String.init), !trigger.isEmpty else {
            throw ParseError(line: line, message: "a transition with no trigger")
        }
        // A description line whose keyword was mistyped or oddly spaced used to
        // arrive here and be accepted as a transition named `exit`. It cost a
        // real action silently; now it is a refusal with the line number on it.
        guard !["entry", "exit", "chip", "mic", "note"].contains(trigger) else {
            throw ParseError(line: line, message:
                "`\(trigger)` is a reserved word, not a trigger — write `\(trigger) / …` "
                + "with a single space, or `\(trigger) \"…\"` for a chip row")
        }
        return Transition(from: from, to: to, trigger: trigger,
                          guardName: guardName, guardNegated: negated,
                          actions: actions, line: line)
    }

    private static func actionList(_ s: String) -> [String] {
        s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - What the parser refuses

    private static func check(_ d: Parsed) throws {
        guard d.states[d.initial] != nil else {
            throw ParseError(line: 0, message: "the initial state `\(d.initial)` is never declared")
        }
        for t in d.transitions {
            guard d.states[t.from] != nil else {
                throw ParseError(line: t.line, message: "`\(t.from)` is never declared")
            }
            if let to = t.to, d.states[to] == nil {
                throw ParseError(line: t.line, message: "`\(to)` is never declared")
            }
        }
        // At most one unguarded transition per (state, trigger), and it must come
        // last — otherwise a guarded one written after it could never be reached,
        // and reading order would stop being evaluation order.
        var seenUnguarded: [String: Int] = [:]
        for t in d.transitions {
            let key = "\(t.from)\u{1}\(t.trigger)"
            if let at = seenUnguarded[key] {
                throw ParseError(line: t.line, message:
                    "`\(t.trigger)` on `\(t.from)` is unreachable — line \(at) already answers it "
                    + "with no guard. The unguarded one must be written last.")
            }
            if t.guardName == nil { seenUnguarded[key] = t.line }
        }
        // A composite may not be entered directly: entering it would have to pick
        // a substate, and picking one silently is how a diagram starts lying.
        let composites = Set(d.states.values.compactMap(\.parent))
        for t in d.transitions {
            if let to = t.to, composites.contains(to) {
                throw ParseError(line: t.line, message:
                    "`\(to)` is a composite; point the arrow at the substate it should enter")
            }
        }
        if composites.contains(d.initial) {
            throw ParseError(line: 0, message: "the initial state may not be a composite")
        }
    }

    // MARK: - Resolution, which is the semantics

    /// **A substate's own transitions outrank its parent's** (plain UML), and
    /// within one state file order decides. That precedence is what lets the
    /// endings be written once on the composite while `AtCaret` keeps first
    /// refusal on a gesture it answers differently.
    ///
    /// Returns every candidate for `(state, trigger)`, innermost first, so the
    /// caller evaluates guards in order and takes the first that passes. Guards
    /// are evaluated by the caller because only it knows the world.
    static func candidates(in d: Parsed, state: String, trigger: String) -> [Transition] {
        var out: [Transition] = []
        for name in d.chain(of: state).reversed() {
            out.append(contentsOf: d.transitions.filter { $0.from == name && $0.trigger == trigger })
        }
        return out
    }

    /// The exit actions, then the entry actions, for moving between two states —
    /// everything below the lowest common ancestor is left and re-entered, and
    /// the ancestor itself is not. This is what makes `Listening`'s
    /// `pauseMusic` / `resumeMusic` a declaration instead of something
    /// `syncBorrowedGestures` has to remember.
    static func crossing(in d: Parsed, from: String, to: String) -> (exit: [String], entry: [String]) {
        let fromChain = d.chain(of: from), toChain = d.chain(of: to)
        var shared = 0
        while shared < min(fromChain.count, toChain.count),
              fromChain[shared] == toChain[shared] { shared += 1 }
        let leaving = fromChain.dropFirst(shared).reversed()
        let entering = toChain.dropFirst(shared)
        return (leaving.flatMap { d.states[$0]?.exit ?? [] },
                entering.flatMap { d.states[$0]?.entry ?? [] })
    }
}
