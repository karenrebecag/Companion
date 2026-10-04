import {
  trimMessage, detectBrowser, validateCall, errorReply, reconnectPlan, classifyInbound,
  nextGeneration, makeReplyGuard, sanitizeTab, buildPage,
} from './lib/wire.js';
import { GROUP_TITLE, groupPlan, releasePlan, cleanupPlan, recordCreated } from './lib/groups.js';
import { createCdp, isControl } from './lib/cdp.js';

const HOST = 'com.karen.companion.browser';
const PROTOCOL = 1;
const CALL_TIMEOUT_MS = 12000;
const BACKOFF_START_MS = 1000;

// No chrome.runtime.onMessageExternal and no window.message listener: the native port is the only way in.

let port = null;
let reconnect = { backoff: BACKOFF_START_MS, hold: false };
let reconnectTimer = null;
// Per-tab: current generation and the map from global element id to (frame, frame-local id).
// Lost when the worker dies, which correctly turns old ids into stale_id.
const tabState = new Map();
let generationCounter = 0;
const replies = makeReplyGuard();
const cdp = createCdp(globalThis.chrome, { onDetached: (tabId) => { hideCursor(tabId); } });
const GROUPS_KEY = 'companionGroups';
// Where each taken tab was before we grouped it. Memory only: after a worker restart release simply ungroups.
const taken = new Map();
let createdAt = new Map();
// Group changes read then write Chrome state; running two at once could create two Companion groups.
let groupChain = Promise.resolve();
const serial = (fn) => {
  const run = groupChain.then(fn, fn);
  groupChain = run.catch(() => {});
  return run;
};

function send(message) {
  if (!port) return;
  try {
    port.postMessage(trimMessage(message));
  } catch (error) {
    console.warn('companion: postMessage failed', error?.message);
  }
}

function connect() {
  if (port) return;
  clearTimeout(reconnectTimer);
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (error) {
    port = null;
    scheduleReconnect();
    return;
  }
  const mine = port;
  mine.onMessage.addListener((message) => {
    const event = classifyInbound(message);
    if (event !== 'other_message') reconnect = reconnectPlan(reconnect, event);
    handleInbound(message);
  });
  mine.onDisconnect.addListener(() => {
    // Reading lastError is required or Chrome logs an unchecked-error warning.
    void chrome.runtime.lastError;
    if (port === mine) port = null;
    // With no app on the other end nobody is steering these tabs, so hand them back to the user.
    dissolveOurGroups();
    scheduleReconnect();
  });
  // The native relay adds the token; the extension never holds a secret.
  send({
    id: 1,
    method: 'hello',
    params: {
      extension: chrome.runtime.id,
      browser: detectBrowser(navigator),
      version: chrome.runtime.getManifest().version,
      protocol: PROTOCOL,
    },
  });
}

function scheduleReconnect() {
  clearTimeout(reconnectTimer);
  reconnect = reconnectPlan(reconnect, 'disconnect');
  if (reconnect.delay !== null) reconnectTimer = setTimeout(connect, reconnect.delay);
}

async function handleInbound(message) {
  if (!message || typeof message !== 'object' || typeof message.id !== 'number') return;
  if (message.method !== 'call') return; // hello ack and anything else needs no reply
  const id = message.id;
  const checked = validateCall(message.params);
  if (!checked.ok) return send(errorReply(id, checked.error.code, checked.error.message));
  replies.open(id);
  // WHY the guard: a DOM action that already started inside the tab cannot be cancelled. All we can do is
  // make sure its late result is not sent as a second answer to an id the app already saw time out.
  const timer = setTimeout(() => {
    if (replies.claim(id)) send(errorReply(id, 'timeout', 'the tab did not answer in time'));
  }, CALL_TIMEOUT_MS);
  try {
    const result = await dispatch(checked.name, checked.args);
    if (!replies.claim(id)) return;
    if (result.error) send(errorReply(id, result.error.code, result.error.message));
    else send({ id, result });
  } catch (error) {
    if (replies.claim(id)) send(errorReply(id, 'invalid_args', String(error?.message ?? error)));
  } finally {
    clearTimeout(timer);
  }
}

function dispatch(name, args) {
  switch (name) {
    case 'browser_tabs': return tabs();
    case 'browser_read': return readTab(args.tab, args.selector ?? null);
    case 'browser_click': return trustedPress(args, GESTURES.click);
    case 'browser_double_click': return trustedPress(args, GESTURES.double);
    case 'browser_right_click': return trustedPress(args, GESTURES.right);
    case 'browser_type': return trustedType(args);
    case 'browser_hover': return trustedPress(args, GESTURES.hover);
    case 'browser_scroll': return args.element != null ? scrollToElement(args) : trustedScroll(args);
    case 'browser_drag': return trustedDrag(args);
    case 'browser_click_at': return trustedClickAt(args);
    case 'browser_navigate': return navigate(args.tab, args.url);
    case 'browser_open': return openTab(args.url);
    case 'browser_take': return serial(() => takeTab(args.tab));
    case 'browser_release': return serial(() => releaseTab(args.tab));
    default: return Promise.resolve({ error: { code: 'invalid_args', message: 'unknown tool' } });
  }
}

async function tabs() {
  const all = await chrome.tabs.query({});
  const groupIds = await ourGroupIds();
  return {
    tabs: all
      .filter((t) => Number.isInteger(t.id))
      .map((t) => sanitizeTab(t, { controlled: groupIds.includes(t.groupId), createdAt: createdAt.get(t.id) ?? null })),
  };
}

// Storage says which groups we made; the live title check drops ids Chrome has since removed or reused.
async function ourGroupIds(windowId) {
  const stored = (await chrome.storage.session.get(GROUPS_KEY))[GROUPS_KEY];
  const groups = await chrome.tabGroups.query(windowId === undefined ? {} : { windowId });
  return cleanupPlan({ stored, groups });
}

async function rememberGroup(groupId) {
  const stored = (await chrome.storage.session.get(GROUPS_KEY))[GROUPS_KEY];
  const known = Array.isArray(stored) ? stored : [];
  if (!known.includes(groupId)) await chrome.storage.session.set({ [GROUPS_KEY]: [...known, groupId] });
}

const staleTab = { error: { code: 'stale_id', message: 'no such tab' } };

async function putInGroup(tab) {
  const plan = groupPlan({ tab, ourGroupIds: await ourGroupIds(tab.windowId) });
  if (plan.noop) return;
  taken.set(tab.id, plan.record);
  try {
    if (plan.target !== null) {
      await chrome.tabs.group({ groupId: plan.target, tabIds: [tab.id] });
      return;
    }
    const groupId = await chrome.tabs.group({ tabIds: [tab.id], createProperties: { windowId: tab.windowId } });
    await rememberGroup(groupId);
    await chrome.tabGroups.update(groupId, { title: GROUP_TITLE, color: 'blue', collapsed: false });
    // Pinned tabs can make index 0 unavailable; the group is still ours and usable where it landed.
    await chrome.tabGroups.move(groupId, { index: 0 }).catch(() => {});
  } catch (error) {
    taken.delete(tab.id);
    throw error;
  }
}

async function takeTab(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab) return staleTab;
  await putInGroup(tab);
  await cdp.ensureAttached(tabId).catch((error) => console.warn('companion: debugger attach failed', error?.message));
  return { done: 'taken' };
}

// Incredible's observation budget: past it the page is reported as still loading, not waited on.
const LOAD_BUDGET_MS = 5000;
const STILL_LOADING = 'still loading';

// Starts listening before the navigation does, so a page that finishes first is not missed.
function watchLoad() {
  const started = new Set();
  const loaded = new Set();
  const gone = new Set();
  let waiting = null;
  const answer = (tabId, outcome) => { if (waiting?.tabId === tabId) waiting.finish(outcome); };
  const onUpdated = (tabId, change) => {
    if (change.status === 'loading') started.add(tabId);
    // A complete before this navigation's own loading belongs to the page being replaced.
    if (change.status === 'complete' && started.has(tabId)) {
      loaded.add(tabId);
      answer(tabId, 'loaded');
    }
  };
  const onRemoved = (tabId) => {
    gone.add(tabId);
    answer(tabId, 'gone');
  };
  chrome.tabs.onUpdated.addListener(onUpdated);
  chrome.tabs.onRemoved.addListener(onRemoved);
  const stop = () => {
    chrome.tabs.onUpdated.removeListener(onUpdated);
    chrome.tabs.onRemoved.removeListener(onRemoved);
  };
  const until = (tabId) => {
    const known = loaded.has(tabId) ? 'loaded' : gone.has(tabId) ? 'gone' : null;
    if (known) {
      stop();
      return Promise.resolve(known);
    }
    return new Promise((resolve) => {
      const timer = setTimeout(() => waiting.finish('loading'), LOAD_BUDGET_MS);
      waiting = { tabId, finish: (outcome) => { clearTimeout(timer); stop(); resolve(outcome); } };
    });
  };
  return { until, stop, started: (tabId) => started.has(tabId) };
}

// Only the tab and its group need the queue; waiting for the page inside it would hold every
// take, release and open behind one slow site.
async function openTab(url) {
  const { created, load } = await serial(() => createInGroup(url));
  const outcome = await load.until(created.id);
  if (outcome === 'gone') return staleTab;
  const { id, title, url: shown, active } = sanitizeTab({ ...created, url: created.url || created.pendingUrl || url });
  return { tab: { id, title, url: shown, active, loading: outcome === 'loading' } };
}

async function createInGroup(url) {
  const load = watchLoad();
  let created;
  try {
    created = await chrome.tabs.create({ url, active: false });
    await putInGroup(created);
  } catch (error) {
    load.stop();
    // An ungrouped tab would sit in the user's window with no owner to ever release it.
    if (created) await chrome.tabs.remove(created.id).catch(() => {});
    throw error;
  }
  await cdp.ensureAttached(created.id).catch((error) => console.warn('companion: debugger attach failed', error?.message));
  return { created, load };
}

async function releaseTab(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab) return staleTab;
  const record = taken.get(tabId) ?? null;
  taken.delete(tabId);
  await cdp.detach(tabId);
  const inWindow = new Set((await chrome.tabGroups.query({ windowId: tab.windowId })).map((g) => g.id));
  const plan = releasePlan({ record, tab, ourGroupIds: await ourGroupIds(tab.windowId), groupExists: (id) => inWindow.has(id) });
  if (!plan.act) return { done: 'released' };
  // Ungrouping the last tab removes the group, so there is no separate dissolve step here.
  await chrome.tabs.ungroup([tabId]);
  if (plan.regroup !== null) {
    try {
      await chrome.tabs.group({ groupId: plan.regroup, tabIds: [tabId] });
    } catch {
      // The user's group vanished meanwhile: the tab is already ours to give back, so put it where it was.
      if (record?.index !== undefined) await chrome.tabs.move(tabId, { index: record.index }).catch(() => {});
    }
  } else if (plan.moveTo !== null) await chrome.tabs.move(tabId, { index: plan.moveTo });
  return { done: 'released' };
}

function dissolveOurGroups() {
  taken.clear();
  cdp.detachAll();
  return serial(async () => {
    try {
      const stored = (await chrome.storage.session.get(GROUPS_KEY))[GROUPS_KEY];
      const ids = cleanupPlan({ stored, groups: await chrome.tabGroups.query({}) });
      for (const groupId of ids) {
        const members = await chrome.tabs.query({ groupId });
        const tabIds = members.map((t) => t.id).filter(Number.isInteger);
        if (tabIds.length > 0) await chrome.tabs.ungroup(tabIds);
      }
      await chrome.storage.session.set({ [GROUPS_KEY]: [] });
    } catch (error) {
      console.warn('companion: could not dissolve groups', error?.message);
    }
  });
}

async function inject(target) {
  await chrome.scripting.executeScript({ target, files: ['lib/page.js'], world: 'ISOLATED' });
}

async function run(target, func, args) {
  const results = await chrome.scripting.executeScript({ target, func, args, world: 'ISOLATED' });
  return results.filter((r) => r && r.result);
}

async function readTab(tabId, selector) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab) return staleTab;
  await cdp.ensureAttached(tabId).catch(() => {});
  generationCounter = nextGeneration(generationCounter, Date.now());
  const generation = generationCounter;
  // With a selector only the top frame runs: it descends into same-origin iframes itself, and
  // running every frame would return the same nodes once per frame.
  const target = selector == null ? { tabId, allFrames: true } : { tabId, frameIds: [0] };
  try {
    await inject(target);
  } catch (error) {
    return { error: { code: 'unreadable_page', message: 'this tab cannot be read: ' + String(error?.message ?? error).slice(0, 120) } };
  }
  const frames = await run(target, (g, s, f) => globalThis.__companionPage.read(g, s, f), [generation, selector, null]);
  const built = buildPage(tab, tabId, generation, selector, frames);
  if (built.error) return built;
  tabState.set(tabId, { generation, map: built.map });
  return { page: built.page };
}

async function act(args, func, extra) {
  const state = tabState.get(args.tab);
  const entry = state && state.generation === args.generation ? state.map.get(args.element) : null;
  if (!entry) return { error: { code: 'stale_id', message: 'read the page again to get fresh element ids' } };
  const target = { tabId: args.tab, frameIds: [entry.frameId] };
  try {
    await inject(target);
  } catch (error) {
    return { error: { code: 'stale_id', message: 'the tab is no longer reachable' } };
  }
  const [hit] = await run(target, func, [args.generation, entry.localId, ...extra]);
  return hit ? hit.result : { error: { code: 'stale_id', message: 'the frame is gone' } };
}

const CLICK_ATTEMPTS = 3;
const staleElement = { error: { code: 'stale_id', message: 'read the page again to get fresh element ids' } };

function entryFor(args) {
  const state = tabState.get(args.tab);
  return state && state.generation === args.generation ? state.map.get(args.element) ?? null : null;
}

async function inPage(target, func, args = []) {
  const [hit] = await run(target, func, args);
  return hit ? hit.result : null;
}

// Decoration: a page that refuses injection simply has no cursor, and the action goes ahead.
async function showCursor(target, x, y, label) {
  try {
    await chrome.scripting.executeScript({ target, files: ['lib/cursor.js'], world: 'ISOLATED' });
    await chrome.scripting.executeScript({
      target, world: 'ISOLATED', args: [x, y, label],
      func: (cx, cy, text) => globalThis.__companionCursor?.moveTo(cx, cy, text),
    });
  } catch {
    // Restricted page or frame gone.
  }
}

async function pressCursor(target) {
  await chrome.scripting.executeScript({ target, world: 'ISOLATED', func: () => { globalThis.__companionCursor?.press(); } })
    .catch(() => {});
}

async function hideCursor(tabId) {
  await chrome.scripting.executeScript({
    target: { tabId, frameIds: [0] }, world: 'ISOLATED', func: () => { globalThis.__companionCursor?.destroy(); },
  }).catch(() => {});
}

// false only when the armed document saw a click that missed; a navigation or an unreadable page counts as landed.
async function didLand(target, token) {
  try {
    const out = await inPage(target, (t) => ({ landed: globalThis.__companionPage?.landed(t) ?? null }), [token]);
    return out?.landed !== false;
  } catch {
    return true;
  }
}

const coveredElement = { error: { code: 'stale_id', message: 'something covers this element (a dialog or banner); read the page again' } };
const coveredAfterFirstPress = { error: { code: 'stale_id', message: 'pressed once; something covered the element before the second press, read the page again' } };
const revokedReply = (error) => ({ error: { code: 'debugger_revoked', message: error.message } });
// Cancel mid-action, DevTools taking over, or a page Chrome will not let us attach to: the caller
// needs a stable code, not a raw message under invalid_args.
// A Cancel that lands mid-action surfaces as a plain "not attached" error, so the revocation is checked
// again: a model told "unavailable" would retry what the user just stopped.
async function inputFailed(tabId, error) {
  if (error?.code === 'debugger_revoked' || await cdp.isRevoked(tabId)) {
    return revokedReply({ message: 'the user stopped Companion from controlling this tab' });
  }
  return { error: { code: 'debugger_unavailable', message: String(error?.message ?? error).slice(0, 200) } };
}
const LOCATE_ATTEMPTS = 3;

// Moves the cursor to the element and presses there with a real mouse, at most ONCE: a press that
// could not be confirmed may still have landed, and pressing again could buy or send twice.
// Only locating is retried. Returns 'pressed', 'offscreen' (never pressed), or an error reply.
async function pressElement(args, entry, target, gesture) {
  for (let attempt = 1; attempt <= LOCATE_ATTEMPTS; attempt++) {
    const token = `${Date.now()}-${attempt}`;
    const spot = await inPage(target, (g, id, t, event) => globalThis.__companionPage.locate(g, id, t, event),
      [args.generation, entry.localId, token, gesture.landing]);
    if (!spot) return staleElement;
    if (spot.error) return spot;
    if (spot.inFrame) return 'frame';
    if (!spot.inView) continue;
    if (spot.blocked) {
      if (attempt < LOCATE_ATTEMPTS) continue;
      return coveredElement;
    }
    await showCursor(target, spot.box.x, spot.box.y, `${gesture.verb} · ${spot.label || spot.role}`);
    const hits = async () => (await inPage(target, (g, id, x, y) => ({ hit: globalThis.__companionPage.hitsAt(g, id, x, y) }),
      [args.generation, entry.localId, spot.box.x, spot.box.y]))?.hit === true;
    if (!(await hits())) return coveredElement;
    if (!gesture.mouse) {
      await cdp.mouseMove(args.tab, spot.box.x, spot.box.y);
      return 'pressed';
    }
    // The first press of a double click can open something at that very pixel; the second must not land on it.
    const whole = await cdp.mouseClick(args.tab, spot.box.x, spot.box.y, { ...gesture.mouse, beforeRepeat: hits });
    if (!whole) return coveredAfterFirstPress;
    await pressCursor(target);
    if (!(await didLand(target, token))) console.warn('companion: press not confirmed on the element; not repeating it');
    return 'pressed';
  }
  return 'offscreen';
}

// One press of the mouse on an element: the cursor label, the CDP buttons, the event that proves it landed,
// the page's synthetic stand-in and the reply. A right click lands as contextmenu; it never fires click.
const GESTURES = {
  click: { verb: 'Clic', mouse: { button: 'left', count: 1 }, landing: 'click', synthetic: 'click', done: 'clicked' },
  double: { verb: 'Doble clic', mouse: { button: 'left', count: 2 }, landing: 'click', synthetic: 'doubleClick', done: 'double-clicked' },
  right: { verb: 'Clic derecho', mouse: { button: 'right', count: 1 }, landing: 'contextmenu', synthetic: 'contextClick', done: 'right-clicked' },
  // No button: the pointer only arrives, so there is no landing to prove and nothing to repeat.
  hover: { verb: 'Señalando', mouse: null, landing: null, synthetic: 'hover', done: 'hovered' },
};

// Only the top frame gets the trusted path: an iframe's box is in its own coordinates, not the tab's.
async function trustedPress(args, gesture) {
  const entry = entryFor(args);
  if (!entry) return staleElement;
  const synthetic = (g, id, name) => globalThis.__companionPage[name](g, id);
  if (entry.frameId !== 0) return act(args, synthetic, [gesture.synthetic]);
  const target = { tabId: args.tab, frameIds: [0] };
  try {
    await inject(target);
  } catch {
    return { error: { code: 'stale_id', message: 'the tab is no longer reachable' } };
  }
  if (await cdp.isRevoked(args.tab)) return revokedReply({ message: 'the user stopped Companion from controlling this tab' });
  return cdp.withInput(args.tab, async () => {
    const pressed = await pressElement(args, entry, target, gesture);
    if (pressed === 'pressed') return { done: gesture.done };
    if (typeof pressed === 'object') return pressed;
    // Never pressed (off-screen or zero-size): the synthetic click targets the element itself, nothing on top of it.
    const fallback = await inPage(target, synthetic, [args.generation, entry.localId, gesture.synthetic]);
    return fallback ?? staleElement;
  }).catch((error) => inputFailed(args.tab, error));
}

async function scrollToElement(args) {
  return act(args, (g, id) => globalThis.__companionPage.scrollTo(g, id), []);
}

// The wheel goes to the middle of the viewport, where the page's main scroller almost always is.
async function trustedScroll(args) {
  const target = { tabId: args.tab, frameIds: [0] };
  try {
    await inject(target);
  } catch {
    return { error: { code: 'stale_id', message: 'the tab is no longer reachable' } };
  }
  if (await cdp.isRevoked(args.tab)) return revokedReply({ message: 'the user stopped Companion from controlling this tab' });
  return cdp.withInput(args.tab, async () => {
    const view = await inPage(target, () => globalThis.__companionPage.viewport(), []);
    const x = Math.max(1, Math.round((view?.w ?? 2) / 2));
    const y = Math.max(1, Math.round((view?.h ?? 2) / 2));
    await cdp.mouseWheel(args.tab, x, y, args.dx, args.dy);
    return { done: 'scrolled' };
  }).catch((error) => inputFailed(args.tab, error));
}

const offPage = { error: { code: 'stale_id', message: 'that point is not on the visible page; read the page again' } };
const frameAtPoint = { error: { code: 'stale_id', message: 'an embedded frame or something new is at that point, so Companion did not press; read the page again' } };
const dragInFrame = { error: { code: 'stale_id', message: 'dragging inside a frame is not supported; read the page again' } };

// Fails closed: a page that cannot answer is not a point known to be clear.
async function pointClear(target, point, token, phase) {
  const at = await inPage(target, (x, y, t, p) => globalThis.__companionPage.pointAt(x, y, t, p),
    [point.x, point.y, token, phase]);
  return at?.frame === false && at.same === true;
}

const inside = (view, point) => !!view && point.x >= 0 && point.y >= 0 && point.x < view.w && point.y < view.h;

async function topFrame(tabId) {
  const target = { tabId, frameIds: [0] };
  try {
    await inject(target);
  } catch {
    return { error: { code: 'stale_id', message: 'the tab is no longer reachable' } };
  }
  if (await cdp.isRevoked(tabId)) return revokedReply({ message: 'the user stopped Companion from controlling this tab' });
  return { target };
}

// HACK: CDP mouse events do not start a native HTML5 drag (draggable="true" with dragstart and drop), so a
// list built on it sees a press and a release, not a drop. Intercept with Input.setInterceptDrags and replay
// through Input.dispatchDragEvent once a real page the user needs works that way.
async function trustedDrag(args) {
  const entry = entryFor(args);
  const goal = args.to != null ? entryFor({ ...args, element: args.to }) : null;
  if (!entry || (args.to != null && !goal)) return staleElement;
  // Only the top frame: a frame's boxes are in its own coordinates, not the tab's.
  if (entry.frameId !== 0 || (goal && goal.frameId !== 0)) return dragInFrame;
  const reached = await topFrame(args.tab);
  if (reached.error) return reached;
  const { target } = reached;
  return cdp.withInput(args.tab, async () => {
    const spot = await inPage(target, (g, id, t) => globalThis.__companionPage.locate(g, id, t, null),
      [args.generation, entry.localId, `${Date.now()}-drag`]);
    if (!spot) return staleElement;
    if (spot.error) return spot;
    if (spot.inFrame) return dragInFrame;
    if (!spot.inView) return offPage;
    if (spot.blocked) return coveredElement;
    let drop = { x: spot.box.x + (args.dx ?? 0), y: spot.box.y + (args.dy ?? 0) };
    if (goal) {
      const end = await inPage(target, (g, id) => globalThis.__companionPage.boxOf(g, id), [args.generation, goal.localId]);
      if (!end) return staleElement;
      if (end.error) return end;
      if (end.inFrame) return dragInFrame;
      if (!end.inView) return offPage;
      drop = end.box;
    }
    const view = await inPage(target, () => globalThis.__companionPage.viewport(), []);
    if (!inside(view, drop)) return offPage;
    const token = `${Date.now()}-drag`;
    const hits = async (id, point) => (await inPage(target,
      (g, local, x, y) => ({ hit: globalThis.__companionPage.hitsAt(g, local, x, y) }),
      [args.generation, id, point.x, point.y]))?.hit === true;
    // The yes covered dropping onto that element; something else at the drop point would get it instead.
    // Both ends: a frame inside the source would take the press as surely as one at the drop point.
    const clear = async (phase) => (await pointClear(target, spot.box, `${token}-source`, phase))
      && (await pointClear(target, drop, `${token}-drop`, phase))
      && (!goal || await hits(goal.localId, drop)) && await hits(entry.localId, spot.box);
    if (!(await clear('mark'))) return coveredElement;
    await showCursor(target, spot.box.x, spot.box.y, `Arrastrando · ${spot.label || spot.role}`);
    // The page had the whole glide to slip a frame, an overlay or another control under either end.
    if (!(await clear('check'))) return coveredElement;
    await cdp.mouseDrag(args.tab, spot.box, drop);
    return { done: 'dragged' };
  }).catch((error) => inputFailed(args.tab, error));
}

// A bare point has no element to re-check, so it is bound to the read it came from by its generation and must
// fall inside the page as it is now, outside any embedded frame.
async function trustedClickAt(args) {
  const state = tabState.get(args.tab);
  if (!state || state.generation !== args.generation) return staleElement;
  const reached = await topFrame(args.tab);
  if (reached.error) return reached;
  const { target } = reached;
  const point = { x: args.x, y: args.y };
  return cdp.withInput(args.tab, async () => {
    const view = await inPage(target, () => globalThis.__companionPage.viewport(), []);
    if (!inside(view, point)) return offPage;
    const token = `${Date.now()}-point`;
    if (!(await pointClear(target, point, token, 'mark'))) return frameAtPoint;
    await showCursor(target, point.x, point.y, 'Clic');
    // The page had the whole glide to put a frame or a different control under the point.
    if (!(await pointClear(target, point, token, 'check'))) return frameAtPoint;
    await cdp.mouseClick(args.tab, point.x, point.y);
    await pressCursor(target);
    return { done: 'clicked' };
  }).catch((error) => inputFailed(args.tab, error));
}

// The host matches this exact text to tell the model its line breaks did not go in.
const TYPED_WITHOUT_BREAKS = 'typed without line breaks';

// One insert keeps the breaks keys would drop; the read-back decides whether they really went in.
async function typeLines(args, entry, target, typeSynthetic) {
  const typed = await typeSynthetic();
  if (!typed || typed.error) return typed ?? staleElement;
  const after = await inPage(target, (g, id) => globalThis.__companionPage.typedValue(g, id), [args.generation, entry.localId]);
  // A textarea stores every line ending as \n.
  const wanted = args.text.replace(/\r\n?/g, '\n');
  // Only a value that is the text minus its breaks proves they were dropped; a cut or reformatted
  // value is not "on one line", so it keeps the unverified answer the old way always gave.
  const lostBreaks = after && !after.error && after.value !== wanted && after.value === wanted.replace(/\n/g, '');
  return { done: lostBreaks ? TYPED_WITHOUT_BREAKS : 'typed' };
}

async function trustedType(args) {
  const entry = entryFor(args);
  if (!entry) return staleElement;
  const typeSynthetic = () => act(args, (g, id, text) => globalThis.__companionPage.type(g, id, text), [args.text]);
  if (entry.frameId !== 0) return typeSynthetic();
  const target = { tabId: args.tab, frameIds: [0] };
  try {
    await inject(target);
  } catch {
    return { error: { code: 'stale_id', message: 'the tab is no longer reachable' } };
  }
  const prepare = () => inPage(target, (g, id) => globalThis.__companionPage.prepareType(g, id), [args.generation, entry.localId]);
  // Refuse a sensitive or unfit field before the cursor ever goes near it.
  const checked = await prepare();
  if (!checked) return staleElement;
  if (checked.error) return checked;
  if (await cdp.isRevoked(args.tab)) return revokedReply({ message: 'the user stopped Companion from controlling this tab' });
  return cdp.withInput(args.tab, async () => {
    const pressed = await pressElement(args, entry, target, { ...GESTURES.click, verb: 'Escribiendo' });
    if (pressed === 'frame') return typeSynthetic();
    if (typeof pressed === 'object') return pressed;
    const ready = await prepare();
    if (!ready) return staleElement;
    if (ready.error) return ready;
    if (ready.multiline && /[\r\n]/.test(args.text)) return typeLines(args, entry, target, typeSynthetic);
    await cdp.typeText(args.tab, args.text);
    const expected = Array.from(args.text).filter((ch) => !isControl(ch)).join('');
    const after = await inPage(target, (g, id) => globalThis.__companionPage.typedValue(g, id), [args.generation, entry.localId]);
    // A field that swallowed the keys (masked inputs, some editors) still gets the value the old way.
    if (!after || after.error || after.value !== expected) {
      const typed = await typeSynthetic();
      // This field is not multi-line, so the old way drops the breaks just as the keys did.
      return typed?.done && /[\r\n]/.test(args.text) ? { done: TYPED_WITHOUT_BREAKS } : typed;
    }
    // The model has to know its line breaks did not go in, or it would report text that is not there.
    return { done: expected.length === Array.from(args.text).length ? 'typed' : TYPED_WITHOUT_BREAKS };
  }).catch((error) => inputFailed(args.tab, error));
}

async function navigate(tabId, url) {
  const load = watchLoad();
  try {
    await chrome.tabs.update(tabId, { url });
  } catch (error) {
    load.stop();
    return { error: { code: 'invalid_args', message: 'no such tab' } };
  }
  tabState.delete(tabId);
  // A jump to an anchor in the same page never reports loading: it is done once the address shows it.
  // HACK: a reload of the very address shown relies on Chrome marking the tab loading by the time
  // update resolves. If such a reload is reported as navigated too early, wait for its loading instead.
  const now = await chrome.tabs.get(tabId).catch(() => null);
  if (!load.started(tabId) && now?.status === 'complete' && sameAddress(now.url, url)) {
    load.stop();
    return { done: 'navigated' };
  }
  const outcome = await load.until(tabId);
  if (outcome === 'gone') return staleTab;
  return { done: outcome === 'loaded' ? 'navigated' : STILL_LOADING };
}

function sameAddress(a, b) {
  try {
    return new URL(a).href === new URL(b).href;
  } catch {
    return false;
  }
}

chrome.tabs.onRemoved.addListener((tabId) => {
  tabState.delete(tabId);
  cdp.forget(tabId);
  taken.delete(tabId);
  createdAt = new Map([...createdAt].filter(([id]) => id !== tabId));
});
// Chrome does not expose a tab's creation time, so stamp it here; tabs made before this worker started stay null.
chrome.tabs.onCreated.addListener((tab) => { createdAt = recordCreated(createdAt, tab, Date.now()); });

// An alarm wakes a sleeping worker; reconnecting here is what keeps the link alive across MV3 suspends.
chrome.alarms.create('companion-keepalive', { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(() => {
  reconnect = reconnectPlan(reconnect, 'tick');
  connect();
});
dissolveOurGroups();
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
