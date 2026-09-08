// The inspector, in the page.
//
// Hold ⌘⇧ and the element under the cursor is outlined and named; ⌘⇧-click and
// its selector goes to the relay, which hands it to the agent with the next thing
// Victor says. "Make *this* button blue" becomes a sentence with the pronoun
// already resolved.
//
// This runs in the page rather than in the macOS app on purpose. From outside,
// pointing at a DOM node means mapping a screen point through the window origin,
// the height of the browser chrome, the page zoom and the device pixel ratio —
// and then mapping the element's box back out again to draw a rectangle around
// it. In here, `elementFromPoint` and `getBoundingClientRect` are already in the
// coordinate system the outline is drawn in, so there is no mapping to get
// wrong, and none to redo when he zooms.

(() => {
  'use strict';
  if (window.__walkieTalkieInspector) return;
  window.__walkieTalkieInspector = true;

  // The chord has to be *held*, not merely pressed.
  //
  // ⌘⇧ rather than bare ⌘ because bare ⌘-click is how a link opens in a new tab,
  // which Victor does all day: an inspector that ate it would be worse than no
  // inspector. ⌘⇧-click is the same thing plus "and switch to it", i.e. the same
  // family but far rarer, and two modifiers are much harder to hit by accident
  // than one.
  //
  // The hold survives on top of that as the second gate: a quick ⌘⇧-click stays a
  // ⌘⇧-click, every ⌘⇧ shortcut (⌘⇧T, ⌘⇧N, ⌘⇧R, ⌘⇧[) is typed faster than this,
  // and any other key cancels the hold outright.
  const HOLD_MS = 400;

  // **How long before the wait is admitted to.** The hold is 400ms by design and
  // the probe behind it is not free — a torn-down MV3 service worker has to be
  // started before it can answer, and three loopback fetches follow — so the gap
  // between "I am holding ⌘⇧" and "the outline is up" is regularly half a second
  // and occasionally more. Nothing said so, and a click made inside that gap
  // falls through to Chrome and opens a link in a new tab: reported 2026-09-09
  // as *"deseori când sunt pe Chrome și apăs ⌘⇧, nu prinde elementele"*.
  //
  // So a spinner appears at the cursor while the arm is being decided. It is
  // delayed rather than immediate because every ⌘⇧ *shortcut* passes through the
  // same code — ⌘⇧T, ⌘⇧N — and is poisoned within a few tens of milliseconds by
  // its third key; 150ms is comfortably past that and still well inside the
  // hold, so the spinner is only ever seen by a hold that is genuinely a hold.
  const SPINNER_MS = 150;

  // How far the pointer has to travel with the button down before this is a drag
  // and not a click. Four pixels is the usual threshold for the distinction and
  // is under the tremor of a deliberate press.
  const DRAG_MIN_PX = 4;

  // Beyond this the selector stops being read and starts being scrolled past.
  const MAX_STEPS = 8;

  // Framework-generated class names (`css-1x2y3z`, `svelte-a1b2c3`) identify a
  // build, not an element: they change on the next `npm run build`, so a selector
  // resting on one is a selector that stops resolving.
  const GENERATED = /^(css|sc|jsx|emotion|svelte|ng|_|v-)[-_]?[a-z0-9]{4,}$/i;

  const CHORD = ['Meta', 'Shift'];
  const down = { Meta: false, Shift: false };
  const complete = () => down.Meta && down.Shift;

  let heldSince = 0;        // when the chord last became complete; 0 = it is not
  let poisoned = false;     // another key joined it — this is a shortcut, not a hold
  let armed = false;
  let armTimer = 0;
  let current = null;       // the element under the outline
  let mouse = { x: 0, y: 0 };
  let ui = null;            // built on the first hold that lasts long enough
  let spinTimer = 0;
  // The arm's probe, started with the hold rather than after it — see beginHold.
  let probing = null;
  // A press that may become a drag: the element, where the button went down, the
  // element's box and the scroll at that instant, and whether it has moved yet.
  let drag = null;

  // ---------------------------------------------------------------- selector

  const esc = (s) => (window.CSS && CSS.escape ? CSS.escape(s) : String(s).replace(/[^\w-]/g, '\\$&'));

  const unique = (selector) => {
    try { return document.querySelectorAll(selector).length === 1; } catch { return false; }
  };

  /// A selector that resolves to exactly this element, kept as short as it can be
  /// while staying honest: an `id` that is genuinely unique ends the walk, since
  /// everything above it is noise the agent would have to read past.
  function cssPath(el) {
    const steps = [];
    let node = el;

    while (node && node.nodeType === 1 && steps.length < MAX_STEPS) {
      if (node.id) {
        const byId = '#' + esc(node.id);
        if (unique(byId)) { steps.unshift(byId); break; }
      }

      let step = node.localName;
      const classes = [...node.classList]
        .filter((c) => c && c.length < 32 && !GENERATED.test(c))
        .slice(0, 2);
      if (classes.length) step += '.' + classes.map(esc).join('.');

      // Only pay for `:nth-child` where the name alone is ambiguous. Most steps
      // do not need it, and every one that carries it is a step that breaks when
      // a sibling is inserted.
      const parent = node.parentElement;
      if (parent) {
        let twins = 0;
        try { twins = [...parent.children].filter((c) => c.matches(step)).length; } catch { twins = 2; }
        if (twins > 1) step += `:nth-child(${[...parent.children].indexOf(node) + 1})`;
      }

      steps.unshift(step);
      node = node.parentElement;
    }

    return steps.join(' > ');
  }

  /// The address of the **page**, not of the frame the element happens to sit in.
  /// Inside a same-origin iframe those differ, and it is the page that answers
  /// "where did this come from" — the frame's own URL still travels, in `frame`.
  /// Cross-origin, the top document is unreadable and the frame is the best true
  /// answer there is.
  function pageURL() {
    try { return window.top.location.href; } catch { return location.href; }
  }

  /// The words in the element. `innerText` is empty for form controls — their
  /// text is the `value` the user typed or chose — and empty is exactly the case
  /// where a pick arrives as a bare selector with nothing to recognise it by.
  function elementText(el) {
    const rendered = (el.innerText || el.textContent || '').trim().replace(/\s+/g, ' ');
    if (rendered) return rendered.slice(0, 160);
    if (el.localName === 'select') {
      return (el.selectedOptions?.[0]?.text || '').trim().slice(0, 160);
    }
    return (typeof el.value === 'string' ? el.value : '').trim().replace(/\s+/g, ' ').slice(0, 160);
  }

  /// Where the element's top-left corner sits **in the document**, rounded.
  ///
  /// Page coordinates rather than viewport ones: a viewport corner is a fact
  /// about how far the page happened to be scrolled at that instant, which is
  /// the one thing certain to have changed by the time anyone reads the message.
  function corner(rect, sx, sy) {
    return { x: Math.round(rect.left + sx), y: Math.round(rect.top + sy) };
  }

  /// What he would have called this thing out loud.
  function describe(el) {
    return {
      path: cssPath(el),
      tag: el.localName,
      text: elementText(el),
      label: el.getAttribute('aria-label') || el.getAttribute('alt') || el.getAttribute('title') ||
             el.getAttribute('placeholder') || el.getAttribute('name') || '',
      href: el.getAttribute('href') || el.getAttribute('src') || '',
      url: pageURL(),
      title: document.title,
      // Only when it is not the top document — otherwise it is the same as `url`
      // and says nothing.
      frame: window.top === window ? '' : location.href,
    };
  }

  // --------------------------------------------------------------------- ui

  /// Built lazily and inside a closed shadow root: a page that never sees ⌘⇧ held
  /// never gets a node from us, and one that does cannot style what it gets.
  function buildUI() {
    const host = document.createElement('div');
    host.style.cssText = 'all:initial;position:fixed;top:0;left:0;width:0;height:0;z-index:2147483647;pointer-events:none;';
    const shadow = host.attachShadow({ mode: 'closed' });
    shadow.innerHTML = `
      <style>
        :host { all: initial; }
        .box, .tag { position: fixed; pointer-events: none; box-sizing: border-box; }
        .box {
          border: 2px solid #ff453a;
          background: rgba(255, 69, 58, .10);
          border-radius: 2px;
          box-shadow: 0 0 0 1px rgba(0, 0, 0, .35), 0 0 14px rgba(255, 69, 58, .35);
          transition: opacity .08s linear;
        }
        .tag {
          max-width: 60vw;
          padding: 3px 7px;
          border-radius: 5px;
          background: rgba(28, 28, 30, .95);
          color: #fff;
          font: 500 11px/1.35 ui-monospace, SFMono-Regular, Menlo, monospace;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          box-shadow: 0 2px 10px rgba(0, 0, 0, .45);
        }
        .tag b { color: #ff8f88; font-weight: 600; }
        .tag i { color: rgba(255, 255, 255, .5); font-style: normal; }
        .picked .box { border-color: #32d74b; background: rgba(50, 215, 75, .16);
                       box-shadow: 0 0 0 1px rgba(0,0,0,.35), 0 0 18px rgba(50, 215, 75, .5); }
        .picked .tag b { color: #7ee89a; }
        /* **Only the outline while it travels**, and translucent — Victor's ask:
           the box is a picture of *where the element would go*, drawn on top of
           the page it would go on, so anything filled in it hides the very thing
           the drop is being judged against. The glow goes with the fill for the
           same reason. */
        .dragging .box { background: transparent !important;
                         border-style: dashed; opacity: .75;
                         box-shadow: 0 0 0 1px rgba(0, 0, 0, .35) !important; }
        .spin {
          position: fixed; width: 13px; height: 13px; box-sizing: border-box;
          border-radius: 50%;
          border: 2px solid rgba(255, 255, 255, .3);
          border-top-color: #ff453a;
          box-shadow: 0 0 0 1px rgba(0, 0, 0, .35);
          animation: wt-spin .6s linear infinite;
          pointer-events: none;
        }
        @keyframes wt-spin { to { transform: rotate(360deg); } }
        .hidden { display: none; }
      </style>
      <div class="spin hidden"></div>
      <div class="wrap hidden"><div class="box"></div><div class="tag"></div></div>`;

    // The cursor has to be on the page's own elements, so it cannot live in the
    // shadow root. It goes up with the outline and comes down with it.
    //
    // **A hand, not a crosshair.** A crosshair is the cursor for choosing a
    // *point* — a colour picker, a region to drag out — and what this gesture
    // does is pick up the thing under it whole. `grab` is the pointer every
    // browser already uses for "this is something you can take", so it says what
    // the outline round the element is already showing, in the one place the eye
    // is guaranteed to be.
    const cursor = document.createElement('style');
    cursor.textContent = 'html, html * { cursor: grab !important; }';

    (document.documentElement || document.body).appendChild(host);
    return {
      host, cursor,
      wrap: shadow.querySelector('.wrap'),
      box: shadow.querySelector('.box'),
      tag: shadow.querySelector('.tag'),
      spin: shadow.querySelector('.spin'),
    };
  }

  /// **The wait, admitted to.** A hold that has lasted `SPINNER_MS` and has not
  /// armed yet is a hold that is waiting on something — the rest of the 400ms,
  /// the service worker waking, the loopback probe — and until this existed the
  /// only evidence of any of it was that the gesture sometimes did not work.
  ///
  /// It builds the UI, which means a page that sees a long ⌘⇧ hold now gets a
  /// node from us even when the arm is then refused. That is a deliberate
  /// departure from *a page that never sees ⌘⇧ held never gets a node*: the node
  /// is still 0×0, still `pointer-events:none`, still inside a closed shadow
  /// root, and the alternative is a gesture whose latency is invisible.
  function showSpinner() {
    if (armed || !heldSince || poisoned) return;
    if (!ui) ui = buildUI();
    placeSpinner();
    ui.spin.classList.remove('hidden');
  }

  function placeSpinner() {
    if (!ui) return;
    Object.assign(ui.spin.style, { left: `${mouse.x + 16}px`, top: `${mouse.y + 16}px` });
  }

  function hideSpinner() {
    clearTimeout(spinTimer);
    ui?.spin.classList.add('hidden');
  }

  function paint(el) {
    const r = el.getBoundingClientRect();
    if (!r.width && !r.height) return hide();

    ui.wrap.classList.remove('hidden');
    Object.assign(ui.box.style, {
      left: `${r.left}px`, top: `${r.top}px`,
      width: `${r.width}px`, height: `${r.height}px`,
    });

    const path = cssPath(el);
    const steps = path.split(' > ');
    // The head of the path is the page he is already looking at; the tail is the
    // thing under his finger. Only the tail earns the emphasis.
    const head = steps.slice(0, -1).join(' > ');
    ui.tag.innerHTML =
      (head ? `<i>${escapeHTML(head)} &rsaquo; </i>` : '') +
      `<b>${escapeHTML(steps[steps.length - 1] || el.localName)}</b>` +
      ` <i>${Math.round(r.width)}&times;${Math.round(r.height)}</i>`;

    // Above the box, unless the box is against the top of the viewport.
    const tagHeight = 22;
    const above = r.top >= tagHeight + 4;
    Object.assign(ui.tag.style, {
      left: `${Math.max(4, Math.min(r.left, innerWidth - 8))}px`,
      top: above ? `${r.top - tagHeight - 2}px` : `${Math.min(r.bottom + 4, innerHeight - tagHeight - 4)}px`,
    });
  }

  const escapeHTML = (s) => String(s).replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  function hide() { if (ui) ui.wrap.classList.add('hidden'); }

  // ------------------------------------------------------------------ state

  /// The chord just became complete — start the clock, unless a stray key has
  /// already told us this is a shortcut being typed.
  function beginHold() {
    if (heldSince || poisoned) return;
    heldSince = Date.now();
    // **The probe rides alongside the hold, not behind it.** It used to be asked
    // for inside `tryArm`, i.e. only once the 400ms had already elapsed — so the
    // two waits were serial and the gesture armed at 400ms *plus* however long
    // the round trip took, which on a torn-down service worker is a few hundred
    // milliseconds more. Started here it has the whole hold to answer in, and in
    // the ordinary case the answer is already sitting there when the timer fires.
    //
    // It costs nothing when the hold turns out to be a shortcut: the answer is
    // simply dropped, and the probe itself is three loopback fetches the worker
    // caches for a second anyway.
    probing = askRelay();
    clearTimeout(armTimer);
    armTimer = setTimeout(tryArm, HOLD_MS);
    clearTimeout(spinTimer);
    spinTimer = setTimeout(showSpinner, SPINNER_MS);
  }

  /// Is a relay dictating right now? With nobody dictating, ⌘⇧ in Chrome must go
  /// back to meaning exactly what Chrome says it means — the relay refuses the
  /// probe outside a dictation, so the window in which the gesture is borrowed is
  /// the window in which the overlay is on screen saying so.
  async function askRelay() {
    try { return (await chrome.runtime.sendMessage({ type: 'probe' }))?.live === true; }
    catch { return false; }   // no extension context, no relay, no arm
  }

  async function tryArm() {
    if (armed || !heldSince || poisoned) return;

    const live = await (probing || askRelay());
    if (!live || !heldSince || poisoned) return hideSpinner();

    armed = true;
    hideSpinner();
    if (!ui) ui = buildUI();
    (document.head || document.documentElement).appendChild(ui.cursor);
    // The one number that answers "why did it not catch it": how long the whole
    // gesture actually took to arm, hold included. Read with
    // `read_console_messages` or DevTools, and it costs one line per hold.
    console.log(`[walkie] armed ${Date.now() - heldSince}ms after ⌘⇧ went down`);
    hover(mouse.x, mouse.y);
  }

  /// The chord broke, or focus left. `poisoned` clears here and nowhere else, so
  /// a ⌘C followed by reaching for ⇧ *without letting go of ⌘* stays a shortcut
  /// rather than turning into a hold halfway through.
  function disarm() {
    clearTimeout(armTimer);
    hideSpinner();
    probing = null;
    heldSince = 0;
    poisoned = false;
    down.Meta = down.Shift = false;
    current = null;
    // A drag abandoned by letting the chord go sends nothing: the gesture was
    // not finished, and a drop nobody made is not a coordinate to report.
    endDrag();
    if (!armed) return;
    armed = false;
    ui?.cursor.remove();
    ui?.wrap.classList.remove('picked');
    hide();
  }

  function hover(x, y) {
    if (!armed || drag) return;   // mid-drag the outline is the thing being moved
    const el = document.elementFromPoint(x, y);
    if (!el || el === current) return;
    current = el;
    ui.wrap.classList.remove('picked');
    paint(el);
  }

  // ------------------------------------------------------------------- drag

  /// **Dragging moves the outline and nothing else.**
  ///
  /// Victor's ask, 2026-09-09: *"să permit drag and drop de elemente prin
  /// extensie, dar să nu mut nimic în pagină … să capturăm poziția originală și
  /// coordonatele … dragul se duce translucent, doar chenarul … și când îl las,
  /// la mouse-up, comunică unde a ajuns elementul"*.
  ///
  /// **Nothing in the page is touched**, which is what makes this safe to do on
  /// somebody's live application: the element keeps its position, its styles and
  /// its listeners, and the only thing that travels is the red rectangle this
  /// extension was already drawing on top of it. What reaches the agent is a
  /// sentence — *moves from 120,340 to 500,200* — which is an instruction to be
  /// carried out in the source, not a change already made in the DOM.
  ///
  /// **The pick still fires at the press**, unchanged: the outline turning green
  /// under his finger is the receipt, and at the press nothing can know whether
  /// a drag is coming. A drag that then happens sends the same element again
  /// with its two corners on it, and the relay replaces the entry it already has
  /// (`AppDelegate.record`) — one gesture, one element in the message.
  function beginDrag(el, e) {
    const rect = el.getBoundingClientRect();
    drag = {
      el, rect,
      x: e.clientX, y: e.clientY,
      // The scroll *at the grab*, which is what the `from` corner is measured
      // against. The `to` corner reads the scroll again at the drop, so a page
      // scrolled mid-drag still reports two corners in the same frame.
      sx: window.scrollX, sy: window.scrollY,
      moved: false,
    };
  }

  function moveDrag(e) {
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    if (!drag.moved && Math.hypot(dx, dy) < DRAG_MIN_PX) return;
    if (!drag.moved) {
      drag.moved = true;
      ui.wrap.classList.add('dragging');
      // The closed hand: the page's own convention for *you are holding this*,
      // and the natural second half of the `grab` the outline already sets.
      ui.cursor.textContent = 'html, html * { cursor: grabbing !important; }';
    }
    const r = drag.rect;
    Object.assign(ui.box.style, { left: `${r.left + dx}px`, top: `${r.top + dy}px` });
    const to = corner(r, window.scrollX + dx, window.scrollY + dy);
    Object.assign(ui.tag.style, {
      left: `${Math.max(4, Math.min(r.left + dx, innerWidth - 8))}px`,
      top: `${r.top + dy >= 26 ? r.top + dy - 24 : Math.min(r.top + dy + r.height + 4, innerHeight - 26)}px`,
    });
    // Live, because the number is the whole payload: he is aiming at a
    // coordinate, and a drop he cannot read until the message arrives is a drop
    // he has to make twice.
    ui.tag.innerHTML = `<b>${to.x}, ${to.y}</b> <i>page</i>`;
  }

  /// The button came up. A drag that actually moved reports its two corners; a
  /// press that never moved was a plain click and has already been picked.
  function endDrag(e) {
    if (!drag) return;
    const it = drag;
    drag = null;
    ui?.wrap.classList.remove('dragging');
    if (ui) ui.cursor.textContent = 'html, html * { cursor: grab !important; }';
    if (!it.moved || !e || !armed) return void (armed && hover(mouse.x, mouse.y));

    // The grab offset inside the element, so the drop corner is where the
    // element's own top-left lands rather than where the pointer does.
    const ox = it.x - it.rect.left, oy = it.y - it.rect.top;
    const payload = describe(it.el);
    payload.move = {
      from: corner(it.rect, it.sx, it.sy),
      to: {
        x: Math.round(e.clientX - ox + window.scrollX),
        y: Math.round(e.clientY - oy + window.scrollY),
      },
    };
    if (payload.path) send(payload);
    current = null;
    hover(mouse.x, mouse.y);
  }

  async function pick() {
    if (!armed || !current) return;
    const payload = describe(current);
    if (!payload.path) return;

    // The receipt is instant and local, because the round trip is not: the box
    // turning green at the moment of the click is what tells him the click was
    // taken, and the count in the overlay confirms it a beat later.
    ui.wrap.classList.add('picked');
    send(payload);
  }

  /// Hand one element to whichever relays are listening, and say so if none was.
  /// Shared by the press and by the drop, so a drag cannot quietly fail where a
  /// click would have complained.
  async function send(payload) {
    let result = null;
    try { result = await chrome.runtime.sendMessage({ type: 'pick', pick: payload }); } catch { /* relay gone */ }

    if (!result?.count) {
      ui.wrap.classList.remove('picked');
      ui.tag.innerHTML = '<b>⚠ no relay session took it</b>';
      // Leaving the warning up would freeze the label over the next element he
      // hovers; a beat is enough to read it, then the label goes back to
      // describing whatever is under the cursor by then.
      setTimeout(() => { if (armed) { current = null; hover(mouse.x, mouse.y); } }, 1200);
    }
  }

  // ----------------------------------------------------------------- events

  addEventListener('keydown', (e) => {
    if (CHORD.includes(e.key)) {
      down[e.key] = true;
      if (complete()) beginHold();            // either order of ⌘ and ⇧ gets here
      return;
    }
    // Any other key with a modifier down makes this a shortcut, and a shortcut is
    // never a hold. Escape gets out of an arm that is already up.
    if (down.Meta || down.Shift || armed) {
      poisoned = true;
      clearTimeout(armTimer);
      heldSince = 0;
      if (armed) { armed = false; ui?.cursor.remove(); hide(); }
    }
  }, true);

  // Releasing **either** half ends it: the gesture is the pair, not the ⌘.
  addEventListener('keyup', (e) => { if (CHORD.includes(e.key)) disarm(); }, true);

  // ⌘⇥ away, or focus leaving for the address bar: the keyup never arrives, and
  // an outline left behind is an outline that outlives the key holding it up.
  // On the window and *not* in the capture phase — captured, this would also
  // catch every field in the page losing focus, which is not the same event.
  window.addEventListener('blur', disarm);
  document.addEventListener('visibilitychange', () => { if (document.hidden) disarm(); });

  addEventListener('mousemove', (e) => {
    mouse = { x: e.clientX, y: e.clientY };
    if (drag) return moveDrag(e);
    // Only while one is actually up: `ui` outlives every arm, and a style write
    // on every mousemove for a hidden node is a cost paid all day for nothing.
    if (heldSince && !armed) placeSpinner();
    if (armed) return hover(e.clientX, e.clientY);

    // The second way in, and the one that matters inside an iframe: keystrokes go
    // to the focused frame only, so a frame the cursor is over but which has
    // never had focus would otherwise never see the chord go down.
    if (e.metaKey && e.shiftKey) {
      down.Meta = down.Shift = true;
      beginHold();
    } else if (heldSince) {
      disarm();
    }
  }, true);

  // Not while dragging: the box is no longer registered with the element under
  // it, and repainting would snap it back to where the element still is.
  addEventListener('scroll', () => { if (armed && current && !drag) paint(current); }, true);

  // While armed the page gets none of it. ⌘⇧-click would open a new tab and jump
  // to it, ⇧-drag would extend a selection, and the point of the gesture is that
  // it does neither — it only says *this one*.
  for (const type of ['mousedown', 'mouseup', 'click', 'auxclick', 'dblclick', 'contextmenu']) {
    addEventListener(type, (e) => {
      if (!armed) return;
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
      // On the press, not the release: it is the half that his hand calls "the
      // click", and the release can land somewhere else entirely after a twitch.
      // A drag, when one follows, amends what this sent — see `beginDrag`.
      if (type === 'mousedown' && e.button === 0) {
        if (current) beginDrag(current, e);
        pick();
      }
      if (type === 'mouseup' && e.button === 0) endDrag(e);
    }, true);
  }
})();
