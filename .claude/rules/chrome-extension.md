---
paths:
  - "chrome-extension/**"
  - "Sources/WalkieTalkie/ElementPicker.swift"
  - "Sources/WalkieTalkie/MusicBridge.swift"
---

# Chrome extension: element picking and the music bridge

Covers `chrome-extension/` (`inspect.js`, `relay.js`), its HTTP mailbox `ElementPicker`, what a pick carries and how it is worded, and `MusicBridge`. Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## Shape

- **It is a Chrome extension, and the relay is only a mailbox. Not CDP.** Since Chrome 136 `--remote-debugging-port` is refused on the default profile, and `--load-extension` is ignored outright as of 151 (verified 2026-08-15: the flag loads nothing, and `--disable-extensions-except` alongside it disables everything). Driving Victor's *actual* browser over CDP would mean a throwaway `--user-data-dir` without his tabs or logins. Inside the page `elementFromPoint` / `getBoundingClientRect` are already in the outline's coordinate system and stay right after a zoom. → journal: *Picking elements in Chrome*
- **`ElementPicker.swift` is an HTTP listener on loopback and nothing else.** The inspector — outline, label, ⌘⇧ gate, swallowed click, selector — is `inspect.js`. Ports 8917–8919, first free one per relay; the extension posts to **all** of them, same shape as the outbox. → journal: *Picking elements in Chrome*
- **Installing is manual, once**: `chrome://extensions` → Developer mode → Load unpacked. `Extensions.loadUnpacked` over CDP works only for a browser started with `--enable-unsafe-extension-debugging`, which his is not. → journal: *Picking elements in Chrome*
- **The extension's user-facing strings are English**: the label beside the outline in `inspect.js`, its one error string (`⚠ no relay session took it`), the toolbar title in `relay.js`, and the chip's `⌘⇧` / `×2 div#cart > span.price` row. → journal: *Picking elements in Chrome*
- **Picker callbacks run on `ElementPicker`'s listener thread — every AppKit call in one needs its own hop to main.** A start route that called `overlay.setSpawnDestination` directly took the whole app down with a `SIGTRAP` inside `NSWMWindowCoordinator` (`layoutContent` sets a window frame). `captureContext` never had the problem because it already hops. → journal: *Picking elements in Chrome*

## Gate: only while dictating, only when held

- **`/ping` answers 503 outside a dictation.** `ElementPicker.dictating` is set from the same `listening` as the shutter, by `syncBorrowedGestures()`; the extension reads the refusal like no relay at all and ⌘⇧ goes straight back to opening links in new tabs. Armed around the clock it was a browser that intermittently stopped opening links with nothing on screen to explain why. `PROBE_TTL_MS` is 1 s because the answer flips every time he starts and stops talking. → journal: *It lives only while the recording row does*
- **⌘⇧ has to be held 400 ms, alone** (`HOLD_MS`; any other keypress sets `poisoned`, which survives until the chord breaks). A quick ⌘⇧-click still opens a link in a new tab; every ⌘⇧ shortcut is typed faster than the gate, so ⌘⇧T/⌘⇧N/⌘⇧R never arm it. **Both halves, not bare ⌘** — ⌘-click is how a link opens in a new tab all day; releasing *either* half ends the gesture, so ⌘C then reaching for ⇧ without letting go of ⌘ stays a shortcut. → journal: *⌘⇧ has to be *held**
- **"Sometimes it does not catch" has exactly two causes** (2026-09-09). One is not a bug: the gesture only exists while a dictation is open — `GET /ping` idle → **503 in 1.4 ms**; the answer is *start the dictation first*. The other is real latency: an MV3 service worker torn down after ~30 s idle has to be *started* before it answers, a variable few hundred ms during which `armed` is false and the click falls through to Chrome. → journal: *"Sometimes it does not catch the element" (2026-09-09)*
- **The probe starts with the hold, not after it** (`beginHold` sets `probing`, `tryArm` awaits it) — the worker gets the whole 400 ms to wake in. The loopback is free (1.4 ms live, 0.2 ms refused; the three-port fan-out is noise). **A spinner appears beside the cursor 150 ms after the chord completes** if the outline is not up yet (never for a shortcut — those are poisoned within tens of ms), and **the arm time is logged**: `[walkie] armed 431ms after ⌘⇧ went down`. A refused arm prints nothing. → journal: *"Sometimes it does not catch the element" (2026-09-09)*
- **The spinner is the one departure from "a page that never sees ⌘⇧ held never gets a node from us"**: the node is still 0×0, `pointer-events:none`, inside a closed shadow root. → journal: *"Sometimes it does not catch the element" (2026-09-09)*

## What he sees

- **The chip row is Chrome's icon and `⌘⇧`, nothing else, until the first pick; then `×2 div#cart > span.price`.** Words (`hold ⌘⇧🖱️`, `select element ⌘⇧🖱️`) and the mouse glyph (2026-08-31) were stripped: the row is glanced at by someone who knows the gesture and needs the keys. → journal: *The hint is the row, and the row is beside the cursor*
- **The glyph is Chrome's own icon at 0.8 of what the system hands out** (2026-09-02), looked up via `NSWorkspace.icon(forFile:)` on whatever `com.google.Chrome` resolves to — never shipped in the repo. `pickGlyph` is an `NSImageView`, `pickGlyphWidth` the constant `pickGlyphSize`: an image has no font metrics. → journal: *The hint is the row, and the row is beside the cursor*
- **The cursor is `grab`, not a crosshair** (`cursor: grab !important` on the page's own elements while the outline is up; it cannot live in the shadow root). A crosshair chooses a *point*; this picks up the thing under it whole. It closes to `grabbing` during a drag. → journal: *The cursor is a hand, not a crosshair*
- **`ElementPick.short` is the tail of the selector**; the head is the page he is already looking at. The row uses a separate glyph label and `glyphRowWidth` asks it via `sizeToFit` — `measure()` is a font metric and 🎯/`×` fall back to faces it knows nothing about (~2 characters under; AppKit ellipsized the count away). → journal: *Why the row names the newest pick*

## ⌘⇧-drag (2026-09-09)

- **Nothing in the page moves.** The element keeps its position, styles and listeners; what reaches the agent is an *instruction* to carry out in the source. Only the outline travels, translucent (`.dragging` clears fill and glow, dashes the border). → journal: *⌘⇧-drag: where he would move it, without moving it (2026-09-09)*
- **Page coordinates, top-left of the element's own corner**, not of the pointer (grab offset subtracted at the drop). `from` is measured against the scroll at the grab, `to` against the scroll at the drop. The live readout (`500, 205 page`) follows the box — a drop he cannot read until the message arrives is one he makes twice. → journal: *⌘⇧-drag: where he would move it, without moving it (2026-09-09)*
- **The pick fires at the press; the drag amends it.** `AppDelegate.record` **replaces** the entry when the incoming pick carries `move` and the *newest* pending pick has the same path — matched only against the newest, so two picks of two things never collapse. An abandoned drag (chord released) sends nothing; under `DRAG_MIN_PX` (4) it was a click. Verified through `/test/dictation/start`, two `/pick`s, `/test/dictation`: one entry carrying the move. → journal: *⌘⇧-drag: where he would move it, without moving it (2026-09-09)*

## The queue

- **`pendingPicks` survives `captureContext`, because Cancel puts them back** (`releaseHeld(send: false)`). Re-taking a pick means finding the element again — the expensive half. Those picks legitimately predate the dictation they ride, so stamps can be **negative** (`🎯 −0:08 …`). Shots are not restored. → journal: *The pick queue still survives a dictation opening*
- **Picks go stale after 10 minutes (`pickTTL`).** Nothing else clears them: `flushOrphaned` releases the *shots* on their own (a picture is worth looking at unaccompanied) but not picks — a bare selector is nothing to act on. → journal: *The pick queue still survives a dictation opening*

## What a pick carries

- **Each `elements` entry is `{path, tag, text, label, href, url, title, frame}`, plus `move`** — built in `describe()` (`inspect.js`), clamped by `ElementPick(json:)`, emitted by `ElementPick.json`. **Nothing in that chain may rename or drop a key**: the `relay` skill documents them by name. Adding one is free. → journal: *What a pick carries: the page, and what the thing said*
- **`move` (`{from: {x, y}, to: {x, y}}`) is parsed all or nothing** (`ElementPick.move(_:)`) — a half-parsed corner would put `0,0` into the message as if he had dropped it there. → journal: *What a pick carries: the page, and what the thing said*
- **`url` is `window.top.location.href`**, falling back to `location.href` when the top is cross-origin; `location.href` alone inside an iframe put the page he was on nowhere (`frame` already carried the iframe). **`text` falls back to `value`** (`elementText()`): `innerText` is empty for `<input>`, `<textarea>`, `<select>` — the selected option's label for a `<select>`. → journal: *What a pick carries: the page, and what the thing said*

## The clause (2026-09-09)

```
[elements I picked in Chrome, on https://shop.example/cart, oldest first, each
 stamped with when in the sentence I clicked it: 0:12 div#cart > span.price
 (1.299,00 lei) · 0:21 button.buy-button (Cumpără acum), moved from 120,340 to
 500,205 (top-left, page coordinates)]
```

- **`picked … in Chrome`, stamped, with the page URL** — `AppDelegate.picksClause`, shared by `terminalLine` and `caretLine`. Stamps and the panel's `pickLines` both come out of one `stamp(_:since:)` so they cannot drift; `Message.startedAt` carries the zero because `dictationStartedAt` is cleared as the message is built and the panel holds the prompt afterwards. → journal: *The clause: when, what, and on which page (2026-09-09)*
- **Factor the URL out only when every entry came from one page.** Mixed pages put it on each entry; an entry with no URL blocks the factoring outright, or it would silently inherit another entry's page. → journal: *The clause: when, what, and on which page (2026-09-09)*
- **Singular and plural are both written** — `elements I picked … oldest first: 0:12 button` for one pick reads as a list with something missing. → journal: *The clause: when, what, and on which page (2026-09-09)*

## The music pauses for a dictation

- **`MusicBridge` pushes `{type:"dictation", active, seq}` over a WebSocket on 127.0.0.1:8920; `relay.js` pauses every audible tab and resumes exactly those.** Chrome decides which tab because CoreAudio funnels all tabs through one helper process; `chrome.tabs.query({audible: true})` exists only inside the extension. → journal: *The music pauses for the length of a dictation*
- **8920, not 8766** — Victor Addons holds 8766. Both may pause harmlessly: each marks what it stopped (`data-wt-dictation-paused` here, `data-va-dictation-paused` there) and resumes only its own marks. → journal: *The music pauses for the length of a dictation*
- **Push, not poll; ping every 20 s; replay state on connect.** An MV3 worker is torn down after ~30 s idle and socket traffic resets that timer; a worker torn down mid-dictation comes back knowing it owes a resume. → journal: *The music pauses for the length of a dictation*
- **Gate the socket on a `/ping` probe; never blindly retry.** A refused WebSocket is a runtime error on the extension's *Errors* page, one per attempt, and "nothing on 8920" is the ordinary state; a refused `fetch` in `ask()` is silent, and `AppDelegate` starts both together (`picker.start(); music.start()`). The retry is a `chrome.alarms` period of 30 s (a `setTimeout` from a torn-down worker never fires) — hence the **`alarms`** permission. A ⌘⇧ hold that finds the picker alive reconnects immediately. → journal: *The music pauses for the length of a dictation*
- **A dead socket resumes** — the relay is started and killed per agent session, so a relay gone mid-sentence must not leave the music off. A blip costs a stutter. `applicationWillTerminate` also calls `music.stop()`. → journal: *The music pauses for the length of a dictation*
- **Gated on `live`, not on `listening`.** A dictation the relay is not relaying is Victor talking into some other app; silencing his music for it would be the relay reaching outside its own session. → journal: *The music pauses for the length of a dictation*
- **Needs `tabs`, `scripting`, `storage` and `<all_urls>`; a manifest change needs a Reload in `chrome://extensions`** — the pause silently does nothing until then. → journal: *The music pauses for the length of a dictation*

## Do not

- Nothing in the `describe()` → `ElementPick(json:)` → `ElementPick.json` chain may rename or drop a key.
- Do not ship Chrome's icon in the repo; look it up.
- Do not reconnect the 8920 socket without a probe that answered.
