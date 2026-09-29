import {
  trimMessage, detectBrowser, validateCall, errorReply, reconnectPlan, classifyInbound,
  nextGeneration, makeReplyGuard, sanitizeTab, buildPage,
} from './lib/wire.js';
import { GROUP_TITLE, groupPlan, releasePlan, cleanupPlan, recordCreated } from './lib/groups.js';

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
    case 'browser_click': return act(args, (g, id) => globalThis.__companionPage.click(g, id), []);
    case 'browser_type': return act(args, (g, id, text) => globalThis.__companionPage.type(g, id, text), [args.text]);
    case 'browser_navigate': return navigate(args.tab, args.url);
    case 'browser_open': return serial(() => openTab(args.url));
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
  return { done: 'taken' };
}

async function openTab(url) {
  const created = await chrome.tabs.create({ url, active: false });
  try {
    await putInGroup(created);
  } catch (error) {
    // An ungrouped tab would sit in the user's window with no owner to ever release it.
    await chrome.tabs.remove(created.id).catch(() => {});
    throw error;
  }
  const { id, title, url: shown, active } = sanitizeTab({ ...created, url: created.url || created.pendingUrl || url });
  return { tab: { id, title, url: shown, active } };
}

async function releaseTab(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab) return staleTab;
  const record = taken.get(tabId) ?? null;
  taken.delete(tabId);
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
  if (!tab) return { error: { code: 'invalid_args', message: 'no such tab' } };
  generationCounter = nextGeneration(generationCounter, Date.now());
  const generation = generationCounter;
  // With a selector only the top frame runs: it descends into same-origin iframes itself, and
  // running every frame would return the same nodes once per frame.
  const target = selector == null ? { tabId, allFrames: true } : { tabId, frameIds: [0] };
  try {
    await inject(target);
  } catch (error) {
    return { error: { code: 'invalid_args', message: 'this tab cannot be read: ' + String(error?.message ?? error).slice(0, 120) } };
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

async function navigate(tabId, url) {
  try {
    await chrome.tabs.update(tabId, { url });
  } catch (error) {
    return { error: { code: 'invalid_args', message: 'no such tab' } };
  }
  tabState.delete(tabId);
  return { done: 'navigated' };
}

chrome.tabs.onRemoved.addListener((tabId) => {
  tabState.delete(tabId);
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
