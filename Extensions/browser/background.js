import {
  trimMessage, detectBrowser, validateCall, errorReply, reconnectPlan, classifyInbound,
  nextGeneration, makeReplyGuard, sanitizeTab, buildPage,
} from './lib/wire.js';

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
    default: return Promise.resolve({ error: { code: 'invalid_args', message: 'unknown tool' } });
  }
}

async function tabs() {
  const all = await chrome.tabs.query({});
  return { tabs: all.filter((t) => Number.isInteger(t.id)).map(sanitizeTab) };
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

chrome.tabs.onRemoved.addListener((tabId) => tabState.delete(tabId));

// An alarm wakes a sleeping worker; reconnecting here is what keeps the link alive across MV3 suspends.
chrome.alarms.create('companion-keepalive', { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(() => {
  reconnect = reconnectPlan(reconnect, 'tick');
  connect();
});
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
