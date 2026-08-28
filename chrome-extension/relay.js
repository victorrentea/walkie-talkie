// The half of the inspector that is allowed to talk to localhost.
//
// A content script's fetch is the *page's* fetch — subject to the page's CSP,
// which on any serious site forbids http://127.0.0.1. The service worker has the
// extension's own host permissions and no CSP, so every byte that leaves for the
// relay leaves from here.

// Several relays can be up at once — one per agent session — and each takes the
// first free port. A pick goes to all of them: which session it belongs to is
// decided later, by which one Victor actually dictates into.
const PORTS = [8917, 8918, 8919];

// How long a probe may take before we call it dead. Generous enough for a
// loopback round trip on a busy machine, short enough that the ⌘⇧ hold does not
// visibly wait on it.
const PROBE_TIMEOUT_MS = 400;

// A probe is asked for on every ⌘⇧ hold, which is often, so the answer is worth
// remembering — but only briefly. It now flips every time Victor starts or stops
// talking, not once a session, and a stale "live" is an arming that swallows a
// ⌘⇧-click Chrome should have opened in a new tab.
const PROBE_TTL_MS = 1000;

let cached = { at: 0, ports: [], sessions: [] };

async function ask(port, path, init) {
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), PROBE_TIMEOUT_MS);
  try {
    const res = await fetch(`http://127.0.0.1:${port}${path}`, { ...init, signal: abort.signal });
    return res.ok ? await res.json() : null;
  } catch {
    return null;   // nothing listening there, which is the normal case for two of the three
  } finally {
    clearTimeout(timer);
  }
}

async function probe() {
  if (Date.now() - cached.at < PROBE_TTL_MS) return cached;

  const answers = await Promise.all(PORTS.map((p) => ask(p, '/ping')));
  cached = {
    at: Date.now(),
    ports: PORTS.filter((_, i) => answers[i]),
    sessions: answers.filter(Boolean).map((a) => a.session).filter(Boolean),
  };

  // The toolbar icon is the only place that can say "the relay is up" without
  // Victor having to hold a key down to find out.
  chrome.action.setBadgeText({ text: cached.ports.length ? String(cached.ports.length) : '' });
  chrome.action.setBadgeBackgroundColor({ color: '#ff453a' });
  chrome.action.setTitle({
    title: cached.sessions.length
      ? `Walkie Talkie Inspector — ⌘⇧-hold to pick, feeding ${cached.sessions.join(', ')}`
      : 'Walkie Talkie Inspector — no relay session dictating',
  });
  return cached;
}

async function deliver(pick) {
  const { ports } = await probe();
  const init = {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(pick),
  };
  const results = await Promise.all(ports.map((p) => ask(p, '/pick', init)));
  const accepted = results.filter(Boolean);
  // A relay that died between the probe and the click invalidates the cache, so
  // the next ⌘⇧ hold finds out rather than arming into a void.
  if (accepted.length !== ports.length) cached.at = 0;
  return { count: accepted.length, sessions: accepted.map((a) => a.session).filter(Boolean) };
}

// ---------------------------------------------------------------------------
// Pausing the music for the length of a dictation
//
// The other half of this file is Chrome asking the relay a question. This half
// is the relay telling Chrome something: a WebSocket on 127.0.0.1:8920 carrying
// {type:"dictation", active:bool}. It has to be a push — the extension would
// otherwise have to poll all day to catch the front edge of a sentence — and it
// has to be decided here, because "which tab is making noise" is knowable only
// inside the browser (see MusicBridge.swift for the CoreAudio half of that).
//
// State lives in chrome.storage.session rather than in a variable: an MV3
// service worker can be torn down between the pause and the resume, and the
// resume must still land on exactly the tabs that were paused.

const MUSIC_PORT = 8920;
const RECONNECT_MIN_MS = 1000;
const RECONNECT_MAX_MS = 30000;

let musicSocket = null;
let musicReconnectDelay = RECONNECT_MIN_MS;

// --- the two halves of the job, injected into the page ---------------------

// Pause every media element that is actually playing, and mark it, so the resume
// can find exactly those — and not the ones Victor had already paused himself.
function pauseAudibleMedia() {
  for (const el of document.querySelectorAll('video, audio')) {
    if (el.paused || el.ended) continue;
    el.dataset.wtDictationPaused = '1';
    el.pause();
  }
}

// Resume only what we paused. A tab he closed the media in, or navigated away
// from, simply has nothing marked — nothing happens.
function resumeMarkedMedia() {
  for (const el of document.querySelectorAll('[data-wt-dictation-paused]')) {
    delete el.dataset.wtDictationPaused;
    const p = el.play();
    if (p && typeof p.catch === 'function') p.catch(() => {});
  }
}

async function pauseEverythingAudible() {
  const { engaged } = await chrome.storage.session.get('engaged');
  if (engaged) return;                 // already paused for this dictation
  const tabs = await chrome.tabs.query({ audible: true });
  const ids = [];
  for (const tab of tabs) {
    try {
      await chrome.scripting.executeScript({
        target: { tabId: tab.id, allFrames: true },
        func: pauseAudibleMedia,
      });
      ids.push(tab.id);
    } catch (e) {
      // A tab we may not script: chrome://, the Web Store, the PDF viewer.
      console.log('[walkie-music] cannot script tab', tab.id, e.message);
    }
  }
  await chrome.storage.session.set({ engaged: true, pausedTabs: ids });
  console.log('[walkie-music] paused', ids.length, 'tab(s)');
}

async function resumeWhatWePaused() {
  const { engaged, pausedTabs } = await chrome.storage.session.get(['engaged', 'pausedTabs']);
  // Clear the latch first: a failure below must not leave us believing a pause
  // is still outstanding, or the next dictation would never pause anything.
  await chrome.storage.session.set({ engaged: false, pausedTabs: [] });
  if (!engaged) return;
  for (const tabId of pausedTabs || []) {
    try {
      await chrome.scripting.executeScript({
        target: { tabId, allFrames: true },
        func: resumeMarkedMedia,
      });
    } catch (e) {
      console.log('[walkie-music] tab gone on resume', tabId, e.message);
    }
  }
  console.log('[walkie-music] resumed', (pausedTabs || []).length, 'tab(s)');
}

function connectMusic() {
  if (musicSocket &&
      (musicSocket.readyState === WebSocket.OPEN || musicSocket.readyState === WebSocket.CONNECTING)) return;
  musicSocket = new WebSocket(`ws://127.0.0.1:${MUSIC_PORT}`);

  musicSocket.onopen = () => {
    musicReconnectDelay = RECONNECT_MIN_MS;
    console.log('[walkie-music] connected to the relay');
  };

  musicSocket.onmessage = (event) => {
    let msg;
    try { msg = JSON.parse(event.data); } catch { return; }
    if (msg.type === 'ping') return;   // keeps this worker resident
    if (msg.type !== 'dictation') return;
    // The relay replays the state on connect, so this is also how a worker that
    // was torn down mid-dictation learns it still owes a resume.
    (msg.active ? pauseEverythingAudible() : resumeWhatWePaused())
      .catch((e) => console.log('[walkie-music] failed', e));
  };

  const retry = () => {
    musicSocket = null;
    // **A dead socket resumes.** The relay is started and killed per agent
    // session, far more often than it is left running, and a relay that goes
    // away mid-sentence would otherwise leave the music off with nothing left
    // alive to turn it back on. A blip that is only a blip costs a stutter: the
    // reconnect replays active:true and pauses again.
    resumeWhatWePaused().catch(() => {});
    setTimeout(connectMusic, musicReconnectDelay);
    musicReconnectDelay = Math.min(musicReconnectDelay * 2, RECONNECT_MAX_MS);
  };
  musicSocket.onclose = retry;
  musicSocket.onerror = () => { try { musicSocket.close(); } catch {} };
}

chrome.runtime.onStartup.addListener(connectMusic);
chrome.runtime.onInstalled.addListener(connectMusic);
connectMusic();

chrome.runtime.onMessage.addListener((msg, _sender, respond) => {
  if (msg?.type === 'probe') {
    probe().then((c) => respond({ live: c.ports.length > 0, sessions: c.sessions }));
    return true;      // the answer comes later
  }
  if (msg?.type === 'pick') {
    deliver(msg.pick).then(respond);
    return true;
  }
  return false;
});
