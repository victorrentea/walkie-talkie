import AppKit
import Foundation

/// **A Wispr Flow that makes its row but never opens its microphone is wedged —
/// restart it, quietly** (2026-11-03).
///
/// Victor: *"nu a mers de loc toata ziua wisprflow ca motor. da cumva cancel singur
/// si mereu face fallback pe model local"*, then *"da, autodetect. + restart wispr
/// flow, daca reusesti sa-l faci sa porneasca fara fereastra de startup"*.
///
/// What happened: Wispr (up since 31 Oct, 1.6.1337) stopped opening its input at
/// 11-02 17:20 — the first miss came with an `AVAudioEngineConfigurationChange` on
/// Wireless Mic Rx. From then on **every** chord still made a `History` row (≈100 ms
/// after it), the row stayed NULL forever (no status, no `micDevice`, not even
/// `dismissed` after the ⌃Escape), and `micOpenGrace` handed all 64 sentences of the
/// next day to the local model. A kill + relaunch fixed it at once (mic open 502 ms
/// after the gesture). Nothing on Wispr's side ever recovers on its own.
///
/// **The signature is `row made, microphone never opened`** (`WisprFlowSource.
/// armMicOpenWatch`, `hadRow != nil`), `threshold` times in a row with no
/// microphone opened in between. A chord Wispr did not answer at all (no row) is a
/// different failure and neither counts nor resets. Then, the moment the relay is
/// quiet (`isQuiet`: nothing recording, transcribing or queued, Wispr's microphone
/// shut), Wispr's main process is SIGKILLed and launched again **as a login item**
/// (`launchHidden`). At most once per `cooldown`: a Wispr that is broken for another
/// reason (permission, device) is restarted once and then left to the local model.
/// `WT_WISPR_AUTORESTART=0` (env, then `elevenlabs.env`) turns it off.
///
/// ## Launched without the hub window
///
/// Wispr's main (`shouldShowHubWindowAtLaunch`, in `app.asar`) shows the 1350×850 hub
/// on every launch except an update restart, `--<relaunch-hub flag>`, or
/// `app.getLoginItemSettings().wasOpenedAtLogin` — and on macOS that is Chromium's
/// `WasLaunchedAsLoginOrResumeItem`, which reads the launching Apple event's
/// `keyAEPropData == keyAELaunchedAsLogInItem`. `NSWorkspace.OpenConfiguration.
/// appleEvent` carries exactly that event, so the launch reads as a login: measured
/// 2026-11-03 19:57, no window of Wispr's on screen, microphone open 285 ms after the
/// next chord. The other way out (`prefs.isUpdating` in `config.json`) would mean
/// writing Wispr's own file, which it rewrites on its own schedule.
enum WisprWedge {
    static let threshold = 2
    static let cooldown: TimeInterval = 600
    /// How long a pending restart waits for the relay to go quiet before giving up.
    static let quietWait: TimeInterval = 300

    static var isOn: Bool {
        (ProcessInfo.processInfo.environment["WT_WISPR_AUTORESTART"]
            ?? ElevenLabsSource.fileValue("WT_WISPR_AUTORESTART")) != "0"
    }

    /// Asked on main before the kill: true when nothing of the relay's is on Wispr.
    static var isQuiet: () -> Bool = { false }

    // Main-queue state.
    private(set) static var misses = 0
    private(set) static var lastRestartAt: Date?
    private(set) static var restarts = 0
    private static var pendingSince: CFAbsoluteTime?
    private static var poll: Timer?

    /// Wispr opened its microphone — whatever was counted was not a wedge.
    static func noteMicOpened() {
        onMain {
            if misses > 0 { Log.info("🩺 Wispr Flow opened its microphone — the \(misses) miss(es) before were not a wedge") }
            misses = 0
            if pendingSince != nil { Log.info("🩺 the pending Wispr restart is dropped — it heard the last sentence") }
            cancelPending()
        }
    }

    /// Wispr made row `row` for this chord but its microphone did not open in time.
    static func noteMissedMic(row: Int64) {
        onMain {
            misses += 1
            guard misses >= threshold else {
                Log.info("🩺 Wispr Flow made row \(row) and never opened its microphone — miss \(misses) of \(threshold) before a restart")
                return
            }
            guard isOn else {
                Log.info("🩺 Wispr Flow looks wedged (\(misses) sentences in a row without its microphone) — not restarted, WT_WISPR_AUTORESTART=0")
                return
            }
            if let at = lastRestartAt, Date().timeIntervalSince(at) < cooldown {
                Log.error(String(format: "🩺 Wispr Flow still never opens its microphone (%d in a row) — restarted %.0f s ago, not again within %.0f min; the local model carries the sentences",
                                 misses, Date().timeIntervalSince(at), cooldown / 60))
                return
            }
            guard pendingSince == nil else { return }
            Log.error("🩺 Wispr Flow is wedged — \(misses) sentences in a row made a row and never opened the microphone; it is restarted as soon as the relay is quiet")
            pendingSince = CFAbsoluteTimeGetCurrent()
            poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() }
        }
    }

    private static func tick() {
        guard let since = pendingSince else { cancelPending(); return }
        if CFAbsoluteTimeGetCurrent() - since > quietWait {
            Log.error(String(format: "🩺 the Wispr restart gave up — the relay was not quiet for %.0f min", quietWait / 60))
            cancelPending()
            return
        }
        guard isQuiet() else { return }
        cancelPending()
        restart(why: "\(misses) sentences in a row without its microphone")
    }

    private static func cancelPending() {
        poll?.invalidate()
        poll = nil
        pendingSince = nil
    }

    /// SIGKILL Wispr's main process (AppleScript quit and SIGTERM are ignored by its
    /// Electron main), wait ≤ 3 s for it to go, then `launchHidden`.
    static func restart(why: String) {
        lastRestartAt = Date()
        restarts += 1
        misses = 0
        let pid = WisprFlowSource.wisprMainPid
        Log.error("🩺 restarting Wispr Flow (pid \(pid)) — \(why)")
        DispatchQueue.global().async {
            if pid != 0 {
                kill(pid, SIGKILL)
                for _ in 0..<60 where WisprFlowSource.wisprMainPid != 0 { usleep(50_000) }
            }
            DispatchQueue.main.async {
                launchHidden { newPid, error in
                    if let error { Log.error("🩺 Wispr Flow did not come back — \(error)") }
                    else { Log.info("🩺 Wispr Flow is back as pid \(newPid), launched as a login item (no hub window)") }
                }
            }
        }
    }

    /// **Wispr Flow launched by path, in the background, read as a login item** —
    /// so its hub window stays shut (see above). Never `open -a` (the nested helper).
    static func launchHidden(_ done: ((pid_t, String?) -> Void)? = nil) {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                           eventID: AEEventID(kAEOpenApplication),
                                           targetDescriptor: nil,
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
                       forKeyword: AEKeyword(keyAEPropData))
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        cfg.hides = true
        cfg.addsToRecentItems = false
        cfg.appleEvent = event
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: WisprProc.appPath), configuration: cfg) { app, error in
            done?(app?.processIdentifier ?? 0, error?.localizedDescription)
        }
    }

    /// `POST /test/wispr-wedge {"clearCooldown": true}`.
    static func clearCooldownForTest() { lastRestartAt = nil }

    /// `GET /test/state.wisprWedge`.
    static func describe() -> [String: Any] {
        ["on": isOn, "misses": misses, "threshold": threshold, "restarts": restarts,
         "pending": pendingSince != nil,
         "lastRestartAt": lastRestartAt.map { Outbox.iso($0) } ?? NSNull()]
    }

    private static func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }
}
