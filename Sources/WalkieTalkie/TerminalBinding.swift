import AppKit
import ApplicationServices

/// The terminal a dictation is typed into, once Victor has pointed the relay at
/// one — and the machinery that puts the words there.
///
/// **Why this exists.** Without it, attaching a session costs a trip into the
/// terminal to type `/relay`, an agent turn to arm a watcher on `outbox.jsonl`,
/// and a label filter that has to match. That is three things to get right
/// before the first word, in a workflow whose entire premise is that Victor is
/// away from the keyboard. Bound, the same dictation is typed straight into the
/// session he was looking at when he pressed the key, and the outbox goes back
/// to being what it always was underneath: the log.
///
/// **The binding is a handle, never a window.** Windows get reordered, tabs get
/// dragged between them, Spaces move underneath all of it — a reference to the
/// front window at bind time is stale by the second dictation. Every case of
/// `Handle` is instead something the terminal itself can be asked to resolve:
/// a tty, a tmux pane id, a process id. Delivery re-finds the target every
/// time, and says so plainly when it cannot.
///
/// **Nothing here steals focus except the fallback that has no choice.**
/// `do script … in <tab>` writes into a Terminal.app tab that is behind other
/// windows, on another Space, or minimised, without activating anything —
/// verified against a raw-mode reader, which is the shape a TUI actually has.
/// tmux `send-keys` is the same story one level down. Only `.keystroke` has to
/// bring the app forward, and it puts the focus back afterwards.
final class TerminalBinding {

    /// How the bound terminal is addressed at delivery time.
    enum Handle: Equatable {
        /// A Terminal.app tab, found by the tty it is showing. The tty survives
        /// tab reordering, being dragged into another window, and everything
        /// else Victor might do to the window between binding and speaking —
        /// which a tab index or a window id does not.
        case terminalApp(tty: String)

        /// A tmux pane, by its `%id`. Bound in preference to the tty whenever
        /// the tty turns out to be running tmux, because a tty binding there is
        /// quietly wrong: tmux hands the input to whichever pane is *active*
        /// when it arrives, so splitting the window after binding sends the
        /// next sentence somewhere Victor never pointed at.
        case tmux(pane: String, tty: String)

        /// A terminal panel inside VS Code or IntelliJ, addressed **through the
        /// editor's own extension** (`IDEBridge`): the relay hands the line to a
        /// loopback listener and the extension calls `sendText` on that exact
        /// terminal. Like the first two, it does not touch the focus.
        ///
        /// This is what `.keystroke` should have been and could not be from
        /// outside a window. It is guarded, because the extension hands back the
        /// shell's pid and a tty follows from that.
        case ide(IDEBridge.Handle)

        /// The last resort: no scripting surface and no extension answering —
        /// addressed by process id and driven with a paste and a Return.
        ///
        /// **The line goes wherever the caret is**, which is the whole problem:
        /// measured on a bound IntelliJ, a delivery with the caret in the editor
        /// pasted into the source file and pressed Return, and one with the
        /// caret in a second terminal tab landed in the wrong terminal — both
        /// reported as `delivered`, because "⌘V was sent" is all this can see.
        case keystroke(pid: pid_t, app: String)
    }

    struct Target {
        let handle: Handle
        /// `petclinic@main` when a Claude Code was found on the bound tty and
        /// its working directory is a git repo — the same `folder@branch` the
        /// status line shows. Falls back to the app's own name.
        let label: String
        /// The address, spelled out: `ttys004`, `%3`, `IntelliJ IDEA`. Two
        /// sessions in one repo produce the same label and nothing else tells
        /// them apart.
        let address: String
        /// The **destination app**: `Terminal`, `Visual Code`, `IntelliJ IDEA`.
        ///
        /// It is what the overlay draws the icon of, and the icon is the half of
        /// the chip Victor reads without reading: three destinations that behave
        /// differently (a tty he can be refused at, an editor extension, a blind
        /// paste) and are otherwise told apart only by a folder name that is
        /// often the same in all three.
        let appName: String
        /// …and where to get that icon from. Kept as the bundle id rather than an
        /// `NSImage` because this type is built on a background queue, several
        /// subprocesses deep, and `NSWorkspace.icon` is a main-thread errand.
        let bundleID: String
        /// `petclinic@main` — the working directory of whatever is running on the
        /// bound tty, plus its git branch. **nil when there is no tty to ask**:
        /// a terminal panel inside VS Code or IntelliJ has none, and nothing
        /// outside those apps can even say which panel owns the caret, so there
        /// is no honest answer rather than a guessed one. The chip shows its
        /// folder row only when this is present.
        var folder: String?
        /// **What the terminal is currently calling itself** — the title the
        /// agent sets and keeps updating as it works (`✳ fixing the tax bug`),
        /// read from Terminal.app's `custom title` or tmux's `pane_title`.
        ///
        /// `folder@branch` says which *repo* the words are going to, and with
        /// two sessions open on the same branch that is not an answer. The title
        /// is the only thing that distinguishes them, and unlike everything else
        /// in the binding it moves — which is exactly why it is worth showing:
        /// a title that is still changing is a session that is still working.
        var title: String?
        /// Where that window sat on screen **at the instant of binding**, in
        /// Cocoa coordinates — the starting rectangle for the flight the overlay
        /// draws to say which window was captured.
        ///
        /// Deliberately not refreshed with the title: it is read once, used once,
        /// within a frame or two of the bind, and a window frame goes stale the
        /// moment Victor drags anything. Nothing downstream may treat it as the
        /// current position of the target.
        let sourceFrame: CGRect?
        let boundAt: Date

        /// Whether delivery to this target can be checked before it happens.
        /// `.keystroke` cannot — see `foregroundIsShell`.
        var isGuarded: Bool {
            switch handle {
            case .keystroke: return false
            // Guarded exactly when the extension could tell us which process
            // owns the panel. It normally can; if it could not, saying so is
            // better than implying a check that will not happen.
            case .ide(let h): return h.shellPID != nil
            case .terminalApp, .tmux: return true
            }
        }
    }

    /// What a delivery did, for the flash that reports it.
    enum Outcome {
        case delivered
        case noTarget
        /// The tab, pane or process is gone. The binding is dropped: a target
        /// that cannot be found again will not come back, and a stale one is
        /// worse than none — it makes every later dictation look delivered.
        case targetGone(String)
        /// The foreground process is a shell, so the words would have been
        /// **executed** rather than typed at an agent. Nothing is sent.
        case wouldRunAsShell(String)
        case failed(String)
    }

    private var current: Target?
    private let lock = NSLock()

    var target: Target? {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    // MARK: - Binding

    /// Bind the terminal Victor is looking at.
    ///
    /// The app is passed in rather than read here because this runs on the
    /// listener queue, several `osascript` and `ps` subprocesses deep, while
    /// "which app is in front" is a main-thread question whose answer has to be
    /// taken at the keypress — before any of that work has had a chance to move
    /// the focus.
    @discardableResult
    func bind(app: NSRunningApplication) -> Target? {
        let bundleID = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? bundleID

        let bound: Target?
        if bundleID == "com.apple.Terminal" {
            bound = bindTerminalApp(fallbackName: name, bundleID: bundleID)
        } else if let editor = IDEBridge.kind(bundleID: bundleID) {
            let window = Self.focusedWindow(pid: app.processIdentifier)
            // **Ask the editor.** Its extension knows which terminal is active,
            // can name it, and can hand back the shell's pid — three things
            // nothing outside the window has ever been able to answer.
            switch IDEBridge.bind(bundleID: bundleID) {
            case .noTerminal:
                // The extension answered and said there is no terminal in this
                // window. Nothing to type into, so nothing is bound — a paste
                // here would land in whatever the window *does* hold, which is a
                // source file. Refusing sends the same message the banner
                // already knows how to say: click into a terminal first.
                Log.error("⌘⌃D on \(name) — that window has no terminal open, not binding")
                bound = nil
            case .bound(let handle):
                bound = Target(handle: .ide(handle),
                               label: Self.display(name), address: "\(Self.display(name)) · \(handle.name)",
                               appName: Self.display(name), bundleID: bundleID,
                               // `folder@branch`, like every other target. It used
                               // to be the raw published path, which is why the row
                               // could read `/Users/victorrentea/workspace` — or,
                               // for a shell sitting at the root, just `/`.
                               folder: Self.folder(ofIDE: handle),
                               title: window.title,
                               sourceFrame: window.frame, boundAt: Date())
            case .noExtension:
                // Nobody answered at all: the extension is not installed, or the
                // window has not loaded it yet. Paste is what is left — it is
                // that or nothing — and it is announced as such.
                Log.error("no \(editor) extension answering — falling back to paste, which lands wherever the caret is")
                bound = Target(handle: .keystroke(pid: app.processIdentifier, app: name),
                               label: Self.display(name), address: Self.display(name),
                               appName: Self.display(name), bundleID: bundleID,
                               folder: nil, title: window.title,
                               sourceFrame: window.frame, boundAt: Date())
            }
        } else {
            // **Not a terminal, and no longer bound as if it were.** Every
            // non-Terminal app used to fall through to the paste path, so ⌘⌃D
            // pressed while looking at Chrome bound Chrome and typed the next
            // dictation into whatever field held the caret. Proven, with the
            // screen locked, by binding `loginwindow`. A refusal is the only
            // correct answer: there is no terminal here to deliver to.
            Log.error("⌘⌃D on \(name) — not a terminal, not binding")
            bound = nil
        }

        guard let bound = bound else { return nil }
        lock.lock(); current = bound; lock.unlock()
        let where_ = bound.sourceFrame.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height))" } ?? "frame unknown"
        Log.info("📍 bound to \(bound.label) (\(bound.address)) — window at \(where_)")
        return bound
    }

    /// Terminal.app: ask it for the tty of the tab in front, then find out what
    /// is actually running there.
    private func bindTerminalApp(fallbackName: String, bundleID: String) -> Target? {
        guard let front = Self.frontTerminalTab() else {
            Log.error("bind: Terminal.app would not name its front tab's tty")
            return nil
        }
        let tty = front.tty

        // tmux first: the tty is the *client's*, and everything typed at it goes
        // to whichever pane happens to be active. Pinning the pane at bind time
        // is the only way the binding means what Victor pointed at.
        // Both terminal cases live in a Terminal.app window, so the rectangle
        // the overlay flies from is found the same way for either.
        let frame = Self.terminalWindowFrame(tty: tty)

        if let pane = Self.tmuxPane(clientTTY: tty) {
            let folder = Self.tmuxPaneLabel(pane)
            return Target(handle: .tmux(pane: pane, tty: tty), label: folder ?? fallbackName,
                          address: pane, appName: Self.display(fallbackName), bundleID: bundleID,
                          folder: folder, title: Self.tmuxPaneTitle(pane),
                          sourceFrame: frame, boundAt: Date())
        }

        let short = (tty as NSString).lastPathComponent
        let folder = Self.sessionLabel(onTTY: tty)
        return Target(handle: .terminalApp(tty: tty), label: folder ?? fallbackName,
                      address: short, appName: Self.display(fallbackName), bundleID: bundleID,
                      folder: folder, title: front.title,
                      sourceFrame: frame, boundAt: Date())
    }

    /// Re-read the two parts of a binding that move under it: what the terminal
    /// calls itself, and **which directory it is in**.
    ///
    /// The directory used to be read once, at bind. That was true for as long as
    /// the chip showed `folder@branch` as a second line beside the agent's title —
    /// a caption on a binding. It is now the *only* line, so it has to be the
    /// current answer: Victor `cd`s between repos and switches branches inside one
    /// session all day, and a chip still naming the folder he bound in an hour ago
    /// says the words are going somewhere they are not.
    ///
    /// Returns the updated target only when something actually moved, so a caller
    /// can skip a relayout it does not need.
    func refreshBinding() -> Target? {
        guard let existing = target else { return nil }
        let fresh: String?
        switch existing.handle {
        case .terminalApp(let tty): fresh = Self.title(forTTY: tty)
        case .tmux(let pane, _): fresh = Self.tmuxPaneTitle(pane)
        // An IDE retitles its window as the open file changes, which is the same
        // kind of movement an agent's terminal title has — and this one costs an
        // AX read rather than a subprocess.
        case .keystroke(let pid, _): fresh = Self.focusedWindow(pid: pid).title
        // The window's own title, exactly as for a paste target: the panel has
        // no title of its own that means anything to Victor, and both IDEs put
        // the project first in the window title.
        case .ide: fresh = nil
        }
        let folder = currentFolder(for: existing)
        guard fresh != existing.title || folder != existing.folder else { return nil }

        lock.lock()
        // Another bind may have landed while the subprocesses above were running.
        guard current?.handle == existing.handle else { lock.unlock(); return nil }
        current?.title = fresh
        current?.folder = folder
        let updated = current
        lock.unlock()
        return updated
    }

    /// Where the bound session is **now**, by the same route the bind used.
    ///
    /// A target with no tty to ask (a blind-paste app) has no honest answer and
    /// keeps the `nil` it was born with, rather than being handed the folder of
    /// whatever happens to be running elsewhere.
    private func currentFolder(for target: Target) -> String? {
        switch target.handle {
        case .terminalApp(let tty):     return Self.sessionLabel(onTTY: tty)
        case .tmux(let pane, _):        return Self.tmuxPaneLabel(pane)
        case .ide(let handle):          return handle.shellPID.flatMap { Self.folderLabel(shellPID: $0) }
                                            ?? IDEBridge.currentDirectory(of: handle).map { Self.label(forDirectory: $0) }
        case .keystroke:                return nil
        }
    }

    func unbind() {
        lock.lock()
        let had = current
        current = nil
        lock.unlock()
        if let had = had { Log.info("📍 unbound from \(had.label) (\(had.address))") }
        // Let the editor drop its end too, so a window that is never bound again
        // is not holding a reference to a terminal for the rest of its life.
        if case .ide(let handle) = had?.handle { IDEBridge.release(handle) }
    }

    // MARK: - Delivery

    /// Type one dictation into the bound terminal and press Return.
    ///
    /// **The shell guard is the load-bearing part of this method.** If the
    /// foreground process on the target is a shell, the dictation is not typed
    /// at an agent — it is *run*. "Șterge tot ce e în folderul de build" said
    /// out loud becomes a real `rm` against a real directory. So the check runs
    /// on **every delivery**, not once at bind: Victor hits Escape, quits, or
    /// the session crashes, and the tab goes back to being a prompt with the
    /// binding still pointing at it. It fails **closed** — a target we cannot
    /// interrogate is treated as a shell.
    func deliver(_ text: String) -> Outcome {
        guard let target = target else { return .noTarget }
        let line = Self.singleLine(text)
        guard !line.isEmpty else { return .failed("nothing to send") }

        switch target.handle {
        case .terminalApp(let tty):
            let foreground = Self.foregroundCommand(onTTY: tty)
            Log.info("⌨️ \(target.address) foreground=\(foreground ?? "nothing") — \(line.count) chars")
            switch foreground {
            case .none:
                unbind()
                return .targetGone("\(target.address) is gone")
            case .some(let command) where Self.isShell(command):
                return .wouldRunAsShell(command)
            case .some:
                break
            }
            guard Self.writeToTerminalApp(line, tty: tty) else {
                unbind()
                return .targetGone("no Terminal.app tab on \(target.address)")
            }
            return .delivered

        case .tmux(let pane, _):
            switch Self.tmuxPaneCommand(pane) {
            case .none:
                unbind()
                return .targetGone("tmux pane \(pane) is gone")
            case .some(let command) where Self.isShell(command):
                return .wouldRunAsShell(command)
            case .some:
                break
            }
            guard Self.writeToTmux(line, pane: pane) else {
                return .failed("tmux send-keys failed")
            }
            return .delivered

        case .ide(let handle):
            // **The same guard the tty paths get**, and the reason the shell pid
            // was worth asking the extension for. A dictation typed at a prompt
            // is not a prompt, it is a command; IDE targets were the one place
            // that could never be checked, and now they can. Fails closed, like
            // the others: a panel we cannot interrogate counts as a shell.
            // **No pid means unguarded, not refused.** Fail-closed is right for
            // a tty target, where the alternative is running a sentence as a
            // command in a shell we *could* have identified. It is wrong here:
            // an IDE panel whose process we cannot name is exactly what every
            // IDE target was before this existed, and they delivered. Refusing
            // would trade a known, announced weakness for a feature that does
            // nothing. `isGuarded` is false in this case and the bind flash says
            // `— no shell guard`, which is where the fact belongs.
            guard let shell = handle.shellPID, let tty = Self.tty(ofPID: shell) else {
                guard IDEBridge.send(line, to: handle) else {
                    return .failed("\(handle.name) did not take the line")
                }
                return .delivered
            }
            switch Self.foregroundCommand(onTTY: tty) {
            case .none:
                unbind()
                return .targetGone("\(handle.name) is gone")
            case .some(let command) where Self.isShell(command):
                return .wouldRunAsShell(command)
            case .some:
                break
            }
            guard IDEBridge.send(line, to: handle) else {
                return .failed("\(handle.name) did not take the line")
            }
            return .delivered

        case .keystroke(let pid, let app):
            guard let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated else {
                unbind()
                return .targetGone("\(app) is gone")
            }
            // No guard is possible here and none is pretended: nothing outside
            // VS Code or IntelliJ can say which pane inside them owns the caret,
            // let alone what is running in it. The overlay marks these targets
            // differently for exactly that reason.
            return Self.paste(line, into: running) ? .delivered : .failed("paste into \(app) failed")
        }
    }

    // MARK: - Terminal.app

    /// The tty and title of the frontmost Terminal.app tab.
    ///
    /// Both in one round trip: they are read at the same instant for the same
    /// tab, and asking twice leaves room for the answer to be about two
    /// different tabs. The title comes from `custom title`, which is where
    /// Terminal.app files what a program sets with the OSC escape — i.e. exactly
    /// what an agent writes there while it works.
    private static func frontTerminalTab() -> (tty: String, title: String?)? {
        let script = """
        tell application "Terminal"
            if (count of windows) is 0 then return ""
            set t to selected tab of front window
            set theTitle to ""
            try
                set theTitle to custom title of t
            end try
            return (tty of t) & "\t" & theTitle
        end tell
        """
        guard let out = osascript(script) else { return nil }
        let parts = out.components(separatedBy: "\t")
        guard let tty = parts.first, tty.hasPrefix("/dev/") else { return nil }
        return (tty, clean(parts.count > 1 ? parts[1] : nil))
    }

    /// The title of whichever tab is showing this tty — the refresh counterpart
    /// of `frontTerminalTab`, which cannot be reused because by then the tab is
    /// very often not the one in front.
    private static func title(forTTY tty: String) -> String? {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t is "\(escape(tty))" then return custom title of t
                    end try
                end repeat
            end repeat
            return ""
        end tell
        """
        return clean(osascript(script))
    }

    // MARK: - Where the bound window is

    /// The frame of the Terminal.app window showing this tty.
    ///
    /// The **window**, not the tab: a tab has no geometry of its own, and the
    /// window is what Victor can actually recognise on screen — which is the
    /// whole job of the rectangle drawn from it.
    private static func terminalWindowFrame(tty: String) -> CGRect? {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        if tty of t is "\(escape(tty))" then
                            set b to bounds of w
                            return ((item 1 of b) as string) & " " & ((item 2 of b) as string) & ¬
                                   " " & ((item 3 of b) as string) & " " & ((item 4 of b) as string)
                        end if
                    end repeat
                end try
            end repeat
            return ""
        end tell
        """
        guard let out = osascript(script) else { return nil }
        let n = out.split(separator: " ").compactMap { Double($0) }
        guard n.count == 4 else { return nil }
        // AppleScript gives {left, top, right, bottom}.
        return cocoaRect(topLeft: CGPoint(x: n[0], y: n[1]),
                         size: CGSize(width: n[2] - n[0], height: n[3] - n[1]))
    }

    /// The focused window of an app with no scripting surface — VS Code,
    /// IntelliJ — read through Accessibility, which the relay already holds a
    /// grant for.
    ///
    /// **The title is the closest thing to a working directory these targets
    /// have.** A Terminal tab has a tty, and from a tty the foreground process's
    /// cwd and its git branch follow; a terminal panel inside an IDE has
    /// neither, and nothing outside the app can even say which of its panels
    /// owns the caret. Guessing — picking the app's most recent child shell —
    /// would put a confidently wrong repo on the chip, which is worse than a
    /// vaguer true one. The window title is what the app itself says it is
    /// showing, and for both IDEs that begins with the project.
    private static func focusedWindow(pid: pid_t) -> (frame: CGRect?, title: String?) {
        let ax = axFocusedWindow(pid: pid)
        guard ax.frame == nil else { return ax }
        // **The window server is the fallback, and VS Code is why.** Electron
        // builds its Accessibility tree lazily — it is simply not there until an
        // assistive client asks for it — so `kAXFocusedWindow` answers
        // `cannotComplete` (-25204, measured) for every VS Code window, while
        // IntelliJ answers it fine. The visible consequence was that binding a VS
        // Code terminal skipped the bind flight entirely: no source rectangle, no
        // frame, nothing to fly from, and the one gesture that says *that window
        // is now this chip* silently did not happen there.
        //
        // The documented way to wake that tree is to set `AXManualAccessibility`
        // on the application, and it is deliberately not used: VS Code answers it
        // by switching the editor into screen-reader mode, which changes how
        // Victor's editor renders. Asking the window server instead costs one call,
        // changes nothing about the app, and answers the only question the flight
        // has — where is that window.
        let server = windowServerWindow(pid: pid)
        return (server.frame, ax.title ?? server.title)
    }

    /// The frontmost on-screen window of a pid, as the window server has it.
    ///
    /// The list comes back front-to-back, so the first ordinary window (layer 0)
    /// belonging to that pid is the one in front. Panels, tooltips and the
    /// autocomplete popovers Electron scatters around sit on other layers and are
    /// skipped by that test alone.
    private static func windowServerWindow(pid: pid_t) -> (frame: CGRect?, title: String?) {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return (nil, nil) }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 1, h > 1 else { continue }
            return (cocoaRect(topLeft: CGPoint(x: x, y: y), size: CGSize(width: w, height: h)),
                    clean(info[kCGWindowName as String] as? String))
        }
        return (nil, nil)
    }

    private static func axFocusedWindow(pid: pid_t) -> (frame: CGRect?, title: String?) {
        let app = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return (nil, nil) }
        let element = unsafeBitCast(window, to: AXUIElement.self)

        var titleRef: CFTypeRef?
        let title = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success
            ? clean(titleRef as? String) : nil

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return (nil, title) }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size)
        else { return (nil, title) }
        return (cocoaRect(topLeft: origin, size: size), title)
    }

    /// **AppleScript and Accessibility both measure y downward from the top of
    /// the primary display; Cocoa measures it upward from that display's
    /// bottom.** They agree only on the primary screen, which is exactly why
    /// getting this wrong stays invisible until a second monitor is plugged in.
    private static func cocoaRect(topLeft: CGPoint, size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0,
              let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: topLeft.x,
                      y: primary.frame.maxY - topLeft.y - size.height,
                      width: size.width, height: size.height)
    }

    /// An empty or whitespace-only title is not a title, and it must not push a
    /// bare separator onto the chip.
    private static func clean(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// `do script … in <that tab>` — which, despite the name, types the string
    /// into the tab and presses Return rather than starting anything. That is
    /// exactly the gesture wanted here, and it reaches a tab that is not in
    /// front, not on this Space, and not in the active window.
    ///
    /// **The Return is a second `do script`, with an empty string.** `do script`
    /// writes the text and the `\r` in **one write** — measured with a raw-mode
    /// reader logging read boundaries: `109 b'…like]\r'`, one chunk — and a TUI
    /// in raw mode reads a chunk that ends in `\r` as a **paste**, keeping the
    /// return as a newline in its prompt instead of submitting. So the dictation
    /// sat there unsent, which is exactly what Victor reported for a terminal on
    /// 2026-08-26, and exactly the bug the IDE bridges were fixed for a few
    /// hours earlier. `do script ""` sends a bare `\r` in a read of its own,
    /// which is a keypress: `17 b'hello-from-split\r'` then `1 b'\r'`.
    ///
    /// It costs an empty line in the two cases the paste reading does not apply
    /// to — a TUI that submitted on the first chunk gets an empty submit, a
    /// shell gets an empty command — and both are nothing. The shell case is
    /// mostly unreachable anyway: the guard refuses to deliver at a prompt.
    private static func writeToTerminalApp(_ text: String, tty: String) -> Bool {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t is "\(escape(tty))" then
                            do script "\(escape(text))" in t
                            delay 0.12
                            do script "" in t
                            return "ok"
                        end if
                    end try
                end repeat
            end repeat
            return "gone"
        end tell
        """
        return osascript(script) == "ok"
    }

    // MARK: - tmux

    /// The pane a tmux client on this tty is looking at — or nil, which is the
    /// answer for every ordinary terminal tab.
    ///
    /// **`display-message -c` is asked only after the tty is known to be a
    /// client, because on its own it does not refuse.** Handed a tty attached to
    /// nothing it silently falls back to tmux's own current client and answers
    /// with *that* pane, so a plain Terminal tab binds to whichever pane some
    /// unrelated background session happens to have focused — which is exactly
    /// what happened the first time this ran on a Mac with a detached `claude-rc`
    /// session alive. A wrong pane is the worst possible failure here: it is
    /// indistinguishable from a correct bind until a sentence lands in somebody
    /// else's window.
    private static func tmuxPane(clientTTY tty: String) -> String? {
        guard let clients = tmux(["list-clients", "-F", "#{client_tty}"]) else { return nil }
        let attached = clients.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard attached.contains(tty) else { return nil }

        guard let out = tmux(["display-message", "-p", "-c", tty, "#{pane_id}"]),
              out.hasPrefix("%") else { return nil }
        return out
    }

    private static func tmuxPaneCommand(_ pane: String) -> String? {
        guard let out = tmux(["display-message", "-p", "-t", pane, "#{pane_current_command}"]),
              !out.isEmpty else { return nil }
        return out
    }

    /// tmux's own record of what the pane called itself — the same OSC title,
    /// caught one layer down.
    private static func tmuxPaneTitle(_ pane: String) -> String? {
        clean(tmux(["display-message", "-p", "-t", pane, "#{pane_title}"]))
    }

    private static func tmuxPaneLabel(_ pane: String) -> String? {
        guard let dir = tmux(["display-message", "-p", "-t", pane, "#{pane_current_path}"]),
              !dir.isEmpty else { return nil }
        return label(forDirectory: dir)
    }

    /// `-l` sends the text **literally**, so a dictation containing the word
    /// "Enter" or a `;` cannot turn into a key name or a command separator.
    /// The Return is a second call for the same reason.
    private static func writeToTmux(_ text: String, pane: String) -> Bool {
        guard tmux(["send-keys", "-t", pane, "-l", "--", text]) != nil else { return false }
        return tmux(["send-keys", "-t", pane, "Enter"]) != nil
    }

    private static func tmux(_ args: [String]) -> String? {
        for path in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return run(path, args)
        }
        return nil
    }

    // MARK: - The fallback: clipboard, ⌘V, Return

    /// Bring the app forward, paste, submit, and put the focus back.
    ///
    /// Every part of this is a compromise the other two paths do not have to
    /// make, and it exists only because VS Code and IntelliJ host their
    /// terminals inside windows nothing outside the app can address. The focus
    /// does move — for about a fifth of a second — which is survivable because
    /// by the time this runs Wispr has long finished pasting its transcript
    /// wherever it was going to.
    ///
    /// The clipboard is restored, because the relay must not cost Victor
    /// whatever he was carrying on it.
    private static func paste(_ text: String, into app: NSRunningApplication) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let previous = NSWorkspace.shared.frontmostApplication
        guard app.activate(options: []) else { return false }

        // Activation is asynchronous and a paste into the app that *was* in
        // front is the one outcome worth spending 200ms to avoid.
        var waited = 0
        while !app.isActive && waited < 40 { usleep(5_000); waited += 1 }
        guard app.isActive else {
            if let saved = saved { restore(saved, to: pasteboard) }
            return false
        }

        tap(key: 0x09, command: true)     // ⌘V
        usleep(60_000)
        tap(key: 0x24, command: false)    // Return
        usleep(80_000)

        // Back where he was, so the relay is not also a window manager.
        if previous?.processIdentifier != app.processIdentifier { previous?.activate(options: []) }
        if let saved = saved {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { restore(saved, to: pasteboard) }
        }
        return true
    }

    private static func restore(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func tap(key: CGKeyCode, command: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        if command {
            down?.flags = .maskCommand
            up?.flags = .maskCommand
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - What is running there

    /// The command in the tty's **foreground** process group — the one that
    /// would receive what we type. BSD `ps` marks it with `+` in `STAT`.
    ///
    /// Returns nil when the tty has no processes left at all, which is how a
    /// closed tab announces itself.
    private static func foregroundCommand(onTTY tty: String) -> String? {
        let device = (tty as NSString).lastPathComponent
        guard let out = run("/bin/ps", ["-t", device, "-o", "stat=,comm="]), !out.isEmpty else { return nil }
        for line in out.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0].contains("+") else { continue }
            return (String(parts[1]).trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        }
        return nil
    }

    /// The tty a process is attached to, `/dev/ttys004` style.
    ///
    /// The editor extensions hand back the **shell's pid** rather than a tty,
    /// because a pid is what their API has. Everything the relay already knows
    /// how to ask — what is in the foreground, which directory a Claude Code
    /// published — is keyed on the tty, so this is the one hop between them.
    static func tty(ofPID pid: pid_t) -> String? {
        guard let out = run("/bin/ps", ["-o", "tty=", "-p", String(pid)])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty, out != "??"
        else { return nil }
        return out.hasPrefix("/dev/") ? out : "/dev/" + out
    }

    /// Would typing here run a command rather than talk to a program?
    ///
    /// Deliberately a **shell** test and not a "is this Claude Code" test. What
    /// makes a delivery dangerous is precisely and only that a shell is reading
    /// the line; everything else — `claude`, `node`, an editor, a REPL — merely
    /// receives text on stdin, which is the intended behaviour and is not the
    /// relay's business to police. Naming the agent instead would also have to
    /// guess how it appears in `ps`, and guess again on every release.
    private static func isShell(_ command: String) -> Bool {
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh", "-zsh", "-bash", "login"]
        return shells.contains(command) || shells.contains(command.replacingOccurrences(of: "-", with: ""))
    }

    /// What the app is called **on screen**, which is not always what macOS calls
    /// it. VS Code's bundle name is the single word `Code`, and a chip that says
    /// `Code` beside a folder name reads as a noun, not as an application. Victor
    /// calls it Visual Code, so that is what the overlay calls it.
    static func display(_ appName: String) -> String {
        appName == "Code" || appName == "Code - OSS" ? "Visual Code" : appName
    }

    /// `folder@branch` for whatever Claude Code is running on this tty — the
    /// directory it is **working in**, which is not the same thing as the
    /// directory its process is in.
    ///
    /// **Claude Code keeps two.** The process is launched somewhere and stays
    /// there forever; the *session* moves, and that move is what its status line
    /// shows and what Victor means by "which folder". Measured on a live session
    /// working in `walkie-talkie`: `lsof -d cwd` on the pid still answered
    /// `~/workspace`, which is also why the branch went missing — `~/workspace`
    /// is not a repo, so there was nothing to put after the `@`.
    ///
    /// Neither is the agent's own shell any help: it has **no controlling
    /// terminal** (so `ps -t` cannot see it) and it is spawned per command, so
    /// most of the time — including the moment ⌘⌃D is pressed — it does not
    /// exist at all.
    ///
    /// So the session directory is *published* rather than inferred, and keyed by
    /// **the tty** — the one handle both sides hold. Victor's status line already
    /// receives the directory from Claude Code and now writes it to
    /// `~/.claude/cwd/<ttysNNN>` (under its *parent's* tty: Claude Code spawns it
    /// without a controlling terminal of its own, but keeps one itself).
    ///
    /// `TERM_SESSION_ID` looked like the better key — free, already in the
    /// environment — and is not usable: macOS shows a process's environment only
    /// to its own descendants, so an app launched separately reads nothing back
    /// (measured: 2926 bytes of environment for a process in the caller's
    /// ancestry, 4 for an unrelated terminal's).
    ///
    /// The process directory remains the fallback. It is right whenever the
    /// session never moved, and it is all there is for a terminal running
    /// something other than Claude Code — or one whose status line is somebody
    /// else's.
    /// `folder@branch` for an IDE panel, by whichever of the two routes answers.
    ///
    /// The pid is preferred where it exists: it is the process actually reading
    /// the keystrokes, and it keeps IDE targets on the same footing as a
    /// Terminal.app tab — the published session directory included. The editor's
    /// own answer is behind it because a pid is not always on offer: IntelliJ
    /// 2026.2 runs its terminal in a backend process and hands out a connector
    /// with no `Process` at all, which is why the chip beside the cursor sat
    /// there saying `IntelliJ IDEA` while the panel was plainly in `petclinic`.
    private static func folder(ofIDE handle: IDEBridge.Handle) -> String? {
        if let pid = handle.shellPID, let label = folderLabel(shellPID: pid) { return label }
        return handle.cwd.map { label(forDirectory: $0) }
    }

    /// `folder@branch` for an IDE panel, from the shell pid its extension named.
    ///
    /// **The same route a Terminal.app tab takes**, and it has to be: this used
    /// to call `publishedDirectory` directly with what `tty(ofPID:)` returns —
    /// `/dev/ttys004` — while that function guards on `hasPrefix("ttys")` and
    /// `!contains("/")` because it is naming a file in `~/.claude/cwd`. It
    /// therefore answered nil for *every* IDE binding, the chip fell back to the
    /// app name, and VS Code sat next to the cursor saying `Visual Code` for as
    /// long as the feature existed. `sessionLabel` takes the device name off the
    /// path itself, which is why the tty paths never had the bug.
    ///
    /// **And a second answer behind it.** `sessionLabel` asks the published file
    /// first and the tty's foreground process second — both are about a *tty*,
    /// and an IDE panel is the one target that can be freshly opened, at a
    /// prompt, with nothing published for it yet. The shell's own working
    /// directory is the honest fallback: it is the folder the panel is in, which
    /// is exactly what the chip claims to be showing.
    private static func folderLabel(shellPID pid: pid_t) -> String? {
        if let tty = tty(ofPID: pid), let label = sessionLabel(onTTY: tty) { return label }
        return workingDirectory(ofPID: pid).map { label(forDirectory: $0) }
    }

    private static func sessionLabel(onTTY tty: String) -> String? {
        let device = (tty as NSString).lastPathComponent

        // **The session's directory first, and only from a file that provably
        // belongs to the process sitting on this tty.**
        //
        // The order here has now been wrong in both directions, for opposite
        // reasons, and this is the version that answers both.
        //
        // Reading the published file blindly was wrong because `ttysNNN` is a
        // number macOS hands to the next tab that opens, so a tab on a recycled
        // number read back the folder of a session that ended hours ago
        // (measured: a fresh zsh in `petclinic` bound as `victor-macos-addons`).
        //
        // Preferring the live process's `cwd` was wrong because of the claim it
        // rested on — that the two are equal, "because Claude Code's own
        // directory is where it was started". They are not. Claude Code keeps a
        // *session* directory that follows the agent as it works, and a
        // *process* directory that never leaves the launch folder. Measured on
        // this Mac: **9 of the 20 live ttys disagreed**, every one of them a
        // session whose agent had moved — `~/.claude/cwd/ttys003` said
        // `victor-macos-addons` while `lsof` on its pid still said `~/workspace`.
        // That is exactly the chip saying `workspace` beside a terminal whose
        // status line reads `victor-macos-addons`.
        //
        // So: ask for the published value **keyed by the pid**, not by the tty.
        // The status line writes `~/.claude/cwd/.last-<its parent pid>` beside
        // the tty file, and that parent is the very process `foreground` finds
        // here. A pid can be recycled too, so the file must also postdate the
        // process — `ps -o lstart=` is the one process timestamp macOS does
        // offer, now that `etimes` is known not to exist here. A file that
        // survives both checks was written by *this* session.
        //
        // The rest stays as a fallback, in the order it was already in: the live
        // `cwd` (right for a plain shell, and for any terminal not running Claude
        // Code) and then the tty-keyed file (all there is when the foreground
        // process cannot be read at all).
        let live = foreground(onTTY: device)
        if let (pid, _) = live, let dir = publishedDirectory(ownedBy: pid) {
            return label(forDirectory: dir)
        }
        if let (pid, _) = live, let dir = workingDirectory(ofPID: pid) {
            return label(forDirectory: dir)
        }
        return publishedDirectory(forTTY: device).map { label(forDirectory: $0) }
    }

    /// The session directory the status line last published *for this process*,
    /// from `~/.claude/cwd/.last-<pid>`.
    ///
    /// Two guards, and both are needed. The **modification date must postdate
    /// the process**, or a pid the kernel has recycled inherits the folder of
    /// whatever held it before. And the path must still be a directory — the
    /// same defence `publishedDirectory(forTTY:)` takes, since nothing ever
    /// cleans these files up.
    private static func publishedDirectory(ownedBy pid: Int32) -> String? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/cwd").appendingPathComponent(".last-\(pid)")
        guard let written = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
              let started = processStart(pid), written > started,
              let raw = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDirectory: ObjCBool = false
        guard !trimmed.isEmpty,
              FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return trimmed
    }

    /// When a process started. `ps -o lstart=` prints `Fri Aug 28 02:55:03 2026`
    /// — and pads a single-digit day with a *second* space, which is why the run
    /// of spaces is collapsed before parsing rather than trusted to a format
    /// string.
    private static func processStart(_ pid: Int32) -> Date? {
        guard let out = run("/bin/ps", ["-o", "lstart=", "-p", String(pid)]) else { return nil }
        let normalized = out.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return fmt.date(from: normalized)
    }

    /// The foreground process on a tty: its pid and its command, in one `ps`.
    private static func foreground(onTTY device: String) -> (pid: Int32, command: String)? {
        guard let out = run("/bin/ps", ["-t", device, "-o", "pid=,stat=,comm="]) else { return nil }
        for line in out.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, parts[1].contains("+"), let pid = Int32(parts[0]) else { continue }
            let command = (String(parts[2]).trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
            return (pid, command)
        }
        return nil
    }


    /// The session directory last published for this tty, if any.
    ///
    /// Checked defensively at every step: the file is written by a shell script
    /// on a schedule of its own, so a missing directory, a stale entry from a tab
    /// that has since closed, or a path that no longer exists all mean the same
    /// thing here — fall back to the process. The **existence check is what makes
    /// a stale file harmless**, since a tty number is reused by the next tab to
    /// open.
    private static func publishedDirectory(forTTY device: String) -> String? {
        guard device.hasPrefix("ttys"), !device.contains("/") else { return nil }
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/cwd").appendingPathComponent(device)
        guard let dir = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let trimmed = dir.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDirectory: ObjCBool = false
        guard !trimmed.isEmpty,
              FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return trimmed
    }

    /// `lsof -p <pid> -a -d cwd` is the only way to read another process's
    /// working directory without being it.
    private static func workingDirectory(ofPID pid: Int32) -> String? {
        guard let out = run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]) else { return nil }
        for line in out.components(separatedBy: "\n") where line.hasPrefix("n/") {
            return String(line.dropFirst())
        }
        return nil
    }

    /// `folder`, or `folder@branch` when the branch is worth saying.
    ///
    /// **`main` and `master` are not worth saying.** They are where most of these
    /// sessions are most of the time, so `@main` was on the chip permanently —
    /// the same six characters on every bind, carrying no information and costing
    /// width on a label that rides over Victor's work. A branch that is *not* the
    /// default is the one fact worth interrupting for: it says this session is
    /// somewhere other than where he usually is.
    static func label(forDirectory dir: String) -> String {
        let folder = (dir as NSString).lastPathComponent
        guard let branch = run("/usr/bin/git", ["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"]),
              !branch.isEmpty, branch != "HEAD",
              branch != "main", branch != "master" else { return folder }
        // Spaces around the `@`: `petclinic @ fix/tax-bug` reads as two facts,
        // where `petclinic@fix/tax-bug` reads as one long token — an email
        // address, or a package name — and the eye stops to parse it.
        return "\(folder) @ \(branch)"
    }

    // MARK: - Text

    /// **One line, always.** Whatever carries this to the terminal ends with a
    /// Return, so an embedded newline is not formatting — it is an early submit
    /// that cuts the sentence in half and sends the rest as a second prompt.
    /// Tabs go for a related reason: in a TUI they are a completion key.
    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// AppleScript string literals understand exactly two escapes, and a
    /// dictation is arbitrary text: without this a spoken quotation mark ends
    /// the string and the rest of the sentence is parsed as code.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Subprocesses

    private static func osascript(_ script: String) -> String? {
        run("/usr/bin/osascript", ["-e", script])
    }

    /// Trimmed stdout, or nil on a non-zero exit — so every caller can treat
    /// "it failed" and "it said nothing" as the same thing, which for all of
    /// them it is.
    private static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            Log.error("\(path) would not run: \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
