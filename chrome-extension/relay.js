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
      ? `Wispr Relay Inspector — ⌘⇧-hold to pick, feeding ${cached.sessions.join(', ')}`
      : 'Wispr Relay Inspector — no relay session dictating',
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
