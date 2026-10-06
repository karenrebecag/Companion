import test, { mock, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { PRESS_KEYS } from '../lib/wire.js';

const EXTENSION_ID = 'gaipfdnbliibnfchgcnamnjpfgkilnll';
let importCount = 0;

// A stand-in for the pieces of `chrome` that background.js touches. Every registration is recorded so a test
// can also assert what was NOT registered.
function makeChrome({ query, tabs: seedTabs = [], groups: seedGroups = [], stored = {} } = {}) {
  const state = {
    tabs: seedTabs.map((t) => ({ windowId: 1, groupId: -1, active: false, title: '', url: 'https://x.example/', ...t })),
    groups: seedGroups.map((g) => ({ windowId: 1, ...g })),
    stored: { ...stored },
    nextTab: 100,
    nextGroup: 500,
    calls: [],
    // A test sets this to make a chrome call throw: (name, args) => boolean.
    failWhen: () => false,
    cdp: [],
    debugTargets: [],
    attachError: null,
    page: null,
    cursor: undefined,
    // A test sets this to keep page loads from finishing until it calls `finishLoad`.
    holdLoads: false,
  };
  const updated = [];
  state.updatedListeners = updated;
  state.finishLoad = (id) => { for (const fn of [...updated]) fn(id, { status: 'complete' }, {}); };
  // Chrome reports loading as the navigation starts, then complete; a test can hold the second.
  const loadStarted = (id) => {
    for (const fn of [...updated]) fn(id, { status: 'loading' }, {});
    if (!state.holdLoads) queueMicrotask(() => state.finishLoad(id));
  };
  state.closeTab = (id) => {
    state.tabs = state.tabs.filter((t) => t.id !== id);
    for (const fn of [...registered.removed]) fn(id, {});
  };
  const trip = (name, args) => { if (state.failWhen(name, args)) throw new Error(`${name} failed`); };
  const created = [];
  const reindex = () => state.tabs.forEach((t, i) => { t.index = i; });
  const dropEmptyGroups = () => { state.groups = state.groups.filter((g) => state.tabs.some((t) => t.groupId === g.id)); };
  const findTab = (id) => state.tabs.find((t) => t.id === id);
  const ports = [];
  const registered = { alarm: [], startup: [], installed: [], removed: [], forbidden: [], detach: [] };
  const listener = (bucket) => ({
    addListener: (fn) => bucket.push(fn),
    removeListener: (fn) => { if (bucket.includes(fn)) bucket.splice(bucket.indexOf(fn), 1); },
  });
  const chrome = {
    runtime: {
      id: EXTENSION_ID,
      lastError: undefined,
      getManifest: () => ({ version: '0.1.0' }),
      connectNative(host) {
        const port = {
          host,
          sent: [],
          messageListeners: [],
          disconnectListeners: [],
          onMessage: { addListener(fn) { port.messageListeners.push(fn); } },
          onDisconnect: { addListener(fn) { port.disconnectListeners.push(fn); } },
          postMessage(message) { port.sent.push(message); },
          receive(message) { for (const fn of port.messageListeners) fn(message); },
          hangUp() { for (const fn of port.disconnectListeners) fn(); },
        };
        ports.push(port);
        return port;
      },
      onStartup: listener(registered.startup),
      onInstalled: listener(registered.installed),
      onMessageExternal: listener(registered.forbidden),
      onConnectExternal: listener(registered.forbidden),
      onMessage: listener(registered.forbidden),
      onConnect: listener(registered.forbidden),
    },
    alarms: { create() {}, onAlarm: listener(registered.alarm) },
    tabs: {
      query: query ?? (async (filter = {}) => state.tabs.filter((t) => filter.groupId === undefined || t.groupId === filter.groupId).map((t) => ({ ...t }))),
      get: async (id) => {
        const tab = findTab(id);
        if (!tab) throw new Error('No tab with id: ' + id);
        return { ...tab };
      },
      update: async (id, props = {}) => {
        state.calls.push(['tabs.update', id]);
        trip('tabs.update', id);
        // The page that was still loading finishes after the listener is up but before the new one starts.
        if (state.staleComplete) state.finishLoad(id);
        if (state.sameDocument) Object.assign(findTab(id), { status: 'complete', url: props.url });
        else loadStarted(id);
        return {};
      },
      create: async ({ url, active }) => {
        state.calls.push(['tabs.create', { url, active }]);
        trip('tabs.create', { url, active });
        const tab = { id: state.nextTab++, index: state.tabs.length, groupId: -1, windowId: 1, active: Boolean(active), title: '', url: '', pendingUrl: url };
        state.tabs.push(tab);
        for (const fn of created) fn({ ...tab });
        loadStarted(tab.id);
        return { ...tab };
      },
      group: async ({ groupId, tabIds, createProperties }) => {
        state.calls.push(['tabs.group', { groupId, tabIds, createProperties }]);
        trip('tabs.group', { groupId, tabIds });
        let gid = groupId;
        if (gid === undefined) {
          gid = state.nextGroup++;
          state.groups.push({ id: gid, title: '', windowId: createProperties?.windowId ?? 1 });
        }
        for (const id of tabIds) findTab(id).groupId = gid;
        dropEmptyGroups();
        return gid;
      },
      remove: async (ids) => {
        state.calls.push(['tabs.remove', ids]);
        trip('tabs.remove', ids);
        state.tabs = state.tabs.filter((t) => ![].concat(ids).includes(t.id));
        reindex();
      },
      ungroup: async (ids) => {
        state.calls.push(['tabs.ungroup', ids]);
        for (const id of [].concat(ids)) findTab(id).groupId = -1;
        dropEmptyGroups();
      },
      move: async (id, { index }) => {
        state.calls.push(['tabs.move', id, index]);
        const [tab] = state.tabs.splice(state.tabs.indexOf(findTab(id)), 1);
        state.tabs.splice(index, 0, tab);
        reindex();
      },
      onRemoved: listener(registered.removed),
      onCreated: { addListener: (fn) => created.push(fn) },
      onUpdated: {
        addListener: (fn) => updated.push(fn),
        removeListener: (fn) => { updated.splice(updated.indexOf(fn), 1); },
      },
    },
    tabGroups: {
      query: async (filter = {}) => state.groups.filter((g) => filter.windowId === undefined || g.windowId === filter.windowId).map((g) => ({ ...g })),
      update: async (id, props) => {
        state.calls.push(['tabGroups.update', id, props]);
        Object.assign(state.groups.find((g) => g.id === id), props);
      },
      move: async (id, { index }) => { state.calls.push(['tabGroups.move', id, index]); },
    },
    storage: {
      session: {
        get: async (key) => (key in state.stored ? { [key]: state.stored[key] } : {}),
        set: async (values) => { Object.assign(state.stored, values); },
      },
    },
    // Runs the injected func against `state.page`, a stand-in for page.js; files injection is a no-op.
    scripting: {
      executeScript: async ({ target, func, args, files }) => {
        if (files || !func) return [];
        globalThis.__companionCursor = state.cursor;
        // An all-frames run also answers from each frame a test adds in `state.frames`.
        const pages = target.allFrames ? [[0, state.page], ...(state.frames ?? [])] : [[target.frameIds?.[0] ?? 0, state.page]];
        const out = [];
        for (const [frameId, page] of pages) {
          globalThis.__companionPage = page;
          out.push({ frameId, result: await func(...(args ?? [])) });
        }
        return out;
      },
    },
    debugger: {
      attach(target, version, cb) {
        state.calls.push(['debugger.attach', target.tabId]);
        if (state.attachError) chrome.runtime.lastError = { message: state.attachError };
        cb();
        chrome.runtime.lastError = undefined;
      },
      detach(target, cb) { state.calls.push(['debugger.detach', target.tabId]); cb(); },
      sendCommand(target, method, params, cb) { state.cdp.push([target.tabId, method, params]); cb({}); },
      getTargets(cb) { cb(state.debugTargets); },
      onDetach: listener(registered.detach),
    },
  };
  return { chrome, ports, registered, state };
}

// A fresh module instance per test: background.js keeps its state at module level.
async function boot(options) {
  mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  const rig = makeChrome(options);
  globalThis.chrome = rig.chrome;
  await import(`../background.js?case=${importCount++}`);
  return rig;
}

const settle = () => new Promise((resolve) => setImmediate(resolve));
const call = (id, name = 'browser_tabs', args = {}) => ({ id, method: 'call', params: { name, arguments: args } });
const ask = async (port, id, name, args) => { port.receive(call(id, name, args)); await settle(); return answersTo(port, id)[0]; };
const answersTo = (port, id) => port.sent.filter((m) => m.id === id);

afterEach(() => {
  mock.timers.reset();
  delete globalThis.chrome;
  delete globalThis.__companionPage;
  delete globalThis.__companionCursor;
});

test('the first message on a new port is a hello that carries no token', async () => {
  const { ports } = await boot();
  assert.equal(ports.length, 1);
  assert.equal(ports[0].host, 'com.karen.companion.browser');
  const [hello] = ports[0].sent;
  assert.equal(hello.method, 'hello');
  assert.equal(hello.id, 1);
  assert.equal(hello.params.extension, EXTENSION_ID);
  assert.equal(hello.params.protocol, 1);
  assert.equal(hello.params.version, '0.1.0');
  assert.ok(!('token' in hello.params), 'the relay adds the token; the extension never holds one');
  assert.equal(JSON.stringify(hello).includes('token'), false);
});

test('after a disconnect it reconnects on the backoff schedule, doubling while nothing answers', async () => {
  const { ports } = await boot();
  ports[0].hangUp();
  mock.timers.tick(999);
  assert.equal(ports.length, 1, 'not before the first delay (1000 ms)');
  mock.timers.tick(1);
  assert.equal(ports.length, 2);
  ports[1].hangUp();
  mock.timers.tick(1999);
  assert.equal(ports.length, 2, 'the second delay doubled to 2000 ms');
  mock.timers.tick(1);
  assert.equal(ports.length, 3);
});

test('a hello ack resets the backoff to the start', async () => {
  const { ports } = await boot();
  ports[0].hangUp();
  mock.timers.tick(1000);
  ports[1].hangUp();
  mock.timers.tick(2000);
  assert.equal(ports.length, 3);
  ports[2].receive({ id: 1, result: { ok: true } });
  ports[2].hangUp();
  mock.timers.tick(1000);
  assert.equal(ports.length, 4, 'back to 1000 ms after a proven link');
});

for (const code of ['bad_token', 'busy']) {
  test(`${code} stops reconnecting until the next alarm`, async () => {
    const { ports, registered } = await boot();
    ports[0].receive({ id: 1, error: { code, message: 'no' } });
    ports[0].hangUp();
    mock.timers.tick(10 * 60 * 1000);
    assert.equal(ports.length, 1, 'no respawn loop after a refusal');
    assert.equal(registered.alarm.length, 1);
    registered.alarm[0]();
    assert.equal(ports.length, 2, 'the alarm tick tries again');
  });
}

test('an ordinary error frame does not put the reconnect on hold', async () => {
  const { ports } = await boot();
  ports[0].receive({ id: 5, error: { code: 'stale_id', message: 'x' } });
  ports[0].hangUp();
  mock.timers.tick(1000);
  assert.equal(ports.length, 2);
});

test('a call whose timeout fires first is answered once, with timeout, and the late result stays silent', async () => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const { ports } = await boot({ query: () => gate });
  ports[0].receive(call(7));
  mock.timers.tick(12000);
  await settle();
  release([{ id: 3, title: 't', url: 'https://x.example/', active: true }]);
  await settle();
  const replies = answersTo(ports[0], 7);
  assert.equal(replies.length, 1);
  assert.equal(replies[0].error.code, 'timeout');
});

test('a call whose result lands first is answered once and its timer no longer fires an error', async () => {
  const { ports } = await boot({ query: async () => [{ id: 3, title: 't', url: 'https://x.example/', active: true }] });
  ports[0].receive(call(8));
  await settle();
  mock.timers.tick(12000);
  await settle();
  const replies = answersTo(ports[0], 8);
  assert.equal(replies.length, 1);
  assert.ok(replies[0].result.tabs, 'the result, not a timeout');
});

test('the result and the timeout in the same turn still answer once', async () => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const { ports } = await boot({ query: () => gate });
  ports[0].receive(call(9));
  release([]);
  mock.timers.tick(12000);
  await settle();
  assert.equal(answersTo(ports[0], 9).length, 1);
});

test('an invalid call gets invalid_args and nothing is dispatched', async () => {
  const { ports } = await boot();
  ports[0].receive(call(4, 'browser_delete_everything'));
  await settle();
  const [reply] = answersTo(ports[0], 4);
  assert.equal(reply.error.code, 'invalid_args');
});

test('nothing but the native port is a way in: no external, internal or window message listener', async () => {
  const windowListeners = [];
  globalThis.addEventListener = (type) => windowListeners.push(type);
  try {
    const { registered } = await boot();
    assert.deepEqual(registered.forbidden, []);
    assert.deepEqual(windowListeners, []);
  } finally {
    delete globalThis.addEventListener;
  }
});

const userTabs = () => [{ id: 1, index: 0 }, { id: 2, index: 1 }, { id: 3, index: 2 }, { id: 4, index: 3 }];
const ours = (state) => state.groups.filter((g) => g.title === 'Companion');

test('browser_open creates a background tab and puts it in a new Companion group', async () => {
  const { ports, state } = await boot({ tabs: userTabs() });
  const reply = await ask(ports[0], 20, 'browser_open', { url: 'https://a.example/x' });
  assert.deepEqual(reply.result, { tab: { id: 100, title: '', url: 'https://a.example/x', active: false, loading: false } });
  assert.deepEqual(state.calls.find((c) => c[0] === 'tabs.create'), ['tabs.create', { url: 'https://a.example/x', active: false }]);
  const [group] = ours(state);
  assert.equal(group.color, 'blue');
  assert.equal(group.collapsed, false);
  assert.equal(state.tabs.find((t) => t.id === 100).groupId, group.id);
  assert.deepEqual(state.calls.find((c) => c[0] === 'tabGroups.move').slice(1), [group.id, 0]);
  assert.deepEqual(state.stored.companionGroups, [group.id]);
});

test('browser_open rejects a non-http url without creating anything', async () => {
  const { ports, state } = await boot({ tabs: userTabs() });
  for (const url of ['javascript:alert(1)', 'chrome://settings', 'file:///etc/passwd']) {
    const reply = await ask(ports[0], 21, 'browser_open', { url });
    assert.equal(reply.error.code, 'invalid_args');
    ports[0].sent.length = 0;
  }
  assert.equal(state.tabs.length, 4);
  assert.deepEqual(state.calls, []);
});

test('two opens share one Companion group', async () => {
  const { ports, state } = await boot({ tabs: userTabs() });
  ports[0].receive(call(22, 'browser_open', { url: 'https://a.example/' }));
  ports[0].receive(call(23, 'browser_open', { url: 'https://b.example/' }));
  await settle();
  await settle();
  assert.equal(ours(state).length, 1);
  assert.equal(answersTo(ports[0], 22).length + answersTo(ports[0], 23).length, 2);
});

test('browser_take groups the tab, keeps its index on record and answers taken', async () => {
  const { ports, state } = await boot({ tabs: userTabs() });
  const reply = await ask(ports[0], 30, 'browser_take', { tab: 3 });
  assert.deepEqual(reply.result, { done: 'taken' });
  assert.equal(state.tabs.find((t) => t.id === 3).groupId, ours(state)[0].id);
});

test('browser_take on a missing tab is stale_id', async () => {
  const { ports } = await boot({ tabs: userTabs() });
  const reply = await ask(ports[0], 31, 'browser_take', { tab: 999 });
  assert.equal(reply.error.code, 'stale_id');
});

// H-3: a read the browser cannot serve names why, so the host can pick the next step.
test('browser_read on a missing tab is stale_id, so the host lets the lease go', async () => {
  const { ports } = await boot({ tabs: userTabs() });
  const reply = await ask(ports[0], 32, 'browser_read', { tab: 999 });
  assert.equal(reply.error.code, 'stale_id');
});

test('a page the browser will not let us read is unreadable_page, not invalid_args', async () => {
  const { ports, chrome } = await boot({ tabs: userTabs() });
  chrome.scripting.executeScript = async () => { throw new Error('Cannot access a chrome:// URL'); };
  const reply = await ask(ports[0], 33, 'browser_read', { tab: 3 });
  assert.equal(reply.error.code, 'unreadable_page');
});

test('browser_release puts the tab back at its original index', async () => {
  const { ports, state } = await boot({ tabs: userTabs() });
  await ask(ports[0], 32, 'browser_take', { tab: 3 });
  const reply = await ask(ports[0], 33, 'browser_release', { tab: 3 });
  assert.deepEqual(reply.result, { done: 'released' });
  const tab = state.tabs.find((t) => t.id === 3);
  assert.equal(tab.groupId, -1);
  assert.equal(tab.index, 2);
  assert.deepEqual(ours(state), [], 'the empty group is gone');
});

test('browser_release restores the original user group when it still exists', async () => {
  const { ports, state } = await boot({
    tabs: [{ id: 1, index: 0 }, { id: 2, index: 1, groupId: 40 }, { id: 3, index: 2, groupId: 40 }],
    groups: [{ id: 40, title: 'Work' }],
  });
  await ask(ports[0], 34, 'browser_take', { tab: 2 });
  assert.equal(state.tabs.find((t) => t.id === 2).groupId, ours(state)[0].id);
  await ask(ports[0], 35, 'browser_release', { tab: 2 });
  assert.equal(state.tabs.find((t) => t.id === 2).groupId, 40);
});

test('browser_release after the user moved the tab out does nothing', async () => {
  const { ports, state } = await boot({ tabs: userTabs() });
  await ask(ports[0], 36, 'browser_take', { tab: 3 });
  const tab = state.tabs.find((t) => t.id === 3);
  tab.groupId = -1;
  state.tabs.push(state.tabs.splice(state.tabs.indexOf(tab), 1)[0]);
  state.tabs.forEach((t, i) => { t.index = i; });
  state.calls.length = 0;
  const reply = await ask(ports[0], 37, 'browser_release', { tab: 3 });
  assert.deepEqual(reply.result, { done: 'released' });
  // Releasing always drops the debugger; what must not happen is touching the tab's place.
  assert.deepEqual(state.calls.filter((c) => !c[0].startsWith('debugger.')), [], 'no ungroup, no move');
  assert.equal(state.tabs.at(-1).id, 3);
});

test('browser_release on a missing tab is stale_id', async () => {
  const { ports } = await boot({ tabs: userTabs() });
  const reply = await ask(ports[0], 38, 'browser_release', { tab: 999 });
  assert.equal(reply.error.code, 'stale_id');
});

test('a disconnect dissolves the groups this extension made and no others', async () => {
  const { ports, state } = await boot({
    tabs: [{ id: 1, index: 0, groupId: 40 }, { id: 2, index: 1 }],
    groups: [{ id: 40, title: 'Companion' }],
  });
  await ask(ports[0], 40, 'browser_take', { tab: 2 });
  const mine = ours(state).find((g) => g.id !== 40);
  ports[0].hangUp();
  await settle();
  assert.equal(state.tabs.find((t) => t.id === 2).groupId, -1);
  assert.ok(!state.groups.some((g) => g.id === mine.id));
  assert.equal(state.tabs.find((t) => t.id === 1).groupId, 40, 'a group titled Companion that we did not make stays');
  assert.deepEqual(state.stored.companionGroups, []);
});

test('on boot it dissolves the groups a previous worker stored, and only those', async () => {
  const { state } = await boot({
    tabs: [{ id: 1, index: 0, groupId: 500 }, { id: 2, index: 1, groupId: 501 }, { id: 3, index: 2, groupId: 502 }],
    groups: [{ id: 500, title: 'Companion' }, { id: 501, title: 'Companion' }, { id: 502, title: 'Work' }],
    stored: { companionGroups: [500, 502] },
  });
  await settle();
  assert.equal(state.tabs.find((t) => t.id === 1).groupId, -1);
  assert.equal(state.tabs.find((t) => t.id === 2).groupId, 501, 'unknown Companion group untouched');
  assert.equal(state.tabs.find((t) => t.id === 3).groupId, 502, 'a stored id that is now a user group untouched');
});

test('browser_tabs reports controlled, opener and createdAt', async () => {
  const { ports, state } = await boot({ tabs: [{ id: 1, index: 0, openerTabId: undefined }, { id: 2, index: 1, openerTabId: 1 }] });
  await ask(ports[0], 50, 'browser_open', { url: 'https://a.example/' });
  await ask(ports[0], 51, 'browser_take', { tab: 2 });
  const reply = await ask(ports[0], 52, 'browser_tabs');
  const byId = Object.fromEntries(reply.result.tabs.map((t) => [t.id, t]));
  assert.equal(byId[1].controlled, false);
  assert.equal(byId[1].opener, null);
  assert.equal(byId[1].createdAt, null, 'unknown when this worker never saw it created');
  assert.equal(byId[2].controlled, true);
  assert.equal(byId[2].opener, 1);
  assert.equal(byId[100].controlled, true);
  assert.equal(typeof byId[100].createdAt, 'number');
  assert.ok(state.tabs.length === 3);
});

test('browser_open closes the tab it created when it cannot put it in a group, and reports the error', async () => {
  const { ports, state } = await boot({ tabs: userTabs() });
  state.failWhen = (name) => name === 'tabs.group';
  const reply = await ask(ports[0], 60, 'browser_open', { url: 'https://a.example/x' });
  assert.ok(reply.error, 'the failure is reported');
  assert.ok(!state.tabs.some((t) => t.id === 100), 'no ungrouped background tab is left behind');
  assert.equal(state.tabs.length, 4);
});

test('browser_open still reports the grouping error when closing the tab fails too', async () => {
  const { ports, state } = await boot({ tabs: userTabs() });
  state.failWhen = (name) => name === 'tabs.group' || name === 'tabs.remove';
  const reply = await ask(ports[0], 61, 'browser_open', { url: 'https://a.example/x' });
  assert.ok(reply.error, 'the original failure is what is reported');
  assert.ok(state.calls.some((c) => c[0] === 'tabs.remove'), 'it tried to close it');
});

test('browser_release falls back to the original index when regrouping fails, and reports released', async () => {
  const { ports, state } = await boot({
    tabs: [{ id: 1, index: 0 }, { id: 2, index: 1, groupId: 40 }, { id: 3, index: 2, groupId: 40 }, { id: 4, index: 3 }],
    groups: [{ id: 40, title: 'Work' }],
  });
  await ask(ports[0], 62, 'browser_take', { tab: 2 });
  state.failWhen = (name, args) => name === 'tabs.group' && args.groupId === 40;
  const reply = await ask(ports[0], 63, 'browser_release', { tab: 2 });
  assert.deepEqual(reply.result, { done: 'released' });
  const tab = state.tabs.find((t) => t.id === 2);
  assert.equal(tab.groupId, -1, 'not left in our group');
  assert.ok(state.calls.some((c) => c[0] === 'tabs.move' && c[1] === 2 && c[2] === 1), 'moved back to its index');
});

// --- Trusted input (18c) ---------------------------------------------------------------------------

const presses = (state) => state.cdp.filter(([, method, params]) => method === 'Input.dispatchMouseEvent' && params.type === 'mousePressed');

// A page with one button, read so element 1 of the reply's generation is live.
async function readyButton(rig, spot, { landed = true } = {}) {
  const clicked = [];
  rig.state.page = {
    read: () => ({ origin: 'https://a.example', text: 'Go', elements: [{ id: 1, frame: 0, role: 'button', label: 'Go', context: '', inputType: null, autocomplete: null, value: null, frameOrigin: null, href: null, fieldName: null, fieldId: null }] }),
    locate: (...args) => {
      rig.state.locates = (rig.state.locates ?? 0) + 1;
      rig.state.landingEvent = args[3];
      return typeof spot === 'function' ? spot() : spot;
    },
    hitsAt: () => (typeof rig.state.stillHits === 'function' ? rig.state.stillHits() : rig.state.stillHits ?? true),
    landed: () => landed,
    click: () => { clicked.push(1); return { done: 'clicked' }; },
  };
  const read = await ask(rig.ports[0], 50, 'browser_read', { tab: 3 });
  return { generation: read.result.page.generation, clicked };
}

const onScreen = { box: { x: 40, y: 60, w: 20, h: 10 }, inView: true, blocked: false, label: 'Go', role: 'button' };

test('a trusted click presses once at the element center and answers clicked', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  const reply = await ask(rig.ports[0], 51, 'browser_click', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'clicked' });
  assert.equal(presses(rig.state).length, 1);
  assert.deepEqual([presses(rig.state)[0][2].x, presses(rig.state)[0][2].y], [40, 60]);
});

const pressParams = (state) => presses(state).map(([, , params]) => params);

test('a trusted double click presses twice at the center, counted 1 then 2', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  const reply = await ask(rig.ports[0], 151, 'browser_double_click', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'double-clicked' });
  assert.deepEqual(pressParams(rig.state).map((p) => [p.button, p.clickCount, p.x, p.y]),
    [['left', 1, 40, 60], ['left', 2, 40, 60]]);
  assert.equal(rig.state.locates, 1, 'located once: the second press is the same gesture, not a retry');
  assert.equal(rig.state.landingEvent, 'click', 'a double click lands as a click');
});

test('a trusted right click presses once with the right button', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  const reply = await ask(rig.ports[0], 152, 'browser_right_click', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'right-clicked' });
  assert.deepEqual(pressParams(rig.state).map((p) => [p.button, p.buttons, p.clickCount]), [['right', 2, 1]]);
  assert.equal(rig.state.landingEvent, 'contextmenu', 'its landing is proven by contextmenu, which a right click fires');
});

test('a double click whose first press covered the element does not press it a second time', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  let checks = 0;
  rig.state.stillHits = () => ++checks === 1;
  const reply = await ask(rig.ports[0], 157, 'browser_double_click', { tab: 3, generation, element: 1 });
  assert.equal(presses(rig.state).length, 1, 'the second press would land on what the first one opened');
  assert.equal(reply.error.code, 'stale_id');
  assert.match(reply.error.message, /pressed once/);
});

test('a double click whose landing cannot be confirmed is still two presses, never repeated', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, clicked } = await readyButton(rig, onScreen, { landed: false });
  const reply = await ask(rig.ports[0], 158, 'browser_double_click', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'double-clicked' });
  assert.equal(presses(rig.state).length, 2);
  assert.equal(rig.state.locates, 1);
  assert.equal(clicked.length, 0, 'no synthetic click on top');
});

for (const [id, name, method, done] of [
  [159, 'browser_double_click', 'doubleClick', 'double-clicked'],
  [160, 'browser_right_click', 'contextClick', 'right-clicked'],
]) {
  test(`${name} on an element inside a frame uses its own synthetic gesture there`, async () => {
    const rig = await boot({ tabs: userTabs() });
    const run = rig.chrome.scripting.executeScript;
    // The read reports the element from frame 2, so the action must go back to frame 2.
    rig.chrome.scripting.executeScript = async (opts) => {
      const out = await run(opts);
      return opts.target.allFrames ? out.map((hit) => ({ ...hit, frameId: 2 })) : out;
    };
    const { generation, clicked } = await readyButton(rig, onScreen);
    const synthetic = [];
    rig.state.page[method] = () => { synthetic.push(method); return { done }; };
    const reply = await ask(rig.ports[0], id, name, { tab: 3, generation, element: 1 });
    assert.deepEqual(reply.result, { done });
    assert.deepEqual(synthetic, [method]);
    assert.equal(clicked.length, 0, 'never a plain click');
    assert.equal(presses(rig.state).length, 0, 'a frame box is not in the tab\'s coordinates');
  });
}

for (const [id, name] of [[153, 'browser_double_click'], [154, 'browser_right_click']]) {
  test(`${name} never presses an element something else covers`, async () => {
    const rig = await boot({ tabs: userTabs() });
    const { generation, clicked } = await readyButton(rig, { ...onScreen, blocked: true });
    const reply = await ask(rig.ports[0], id, name, { tab: 3, generation, element: 1 });
    assert.equal(reply.error.code, 'stale_id');
    assert.equal(presses(rig.state).length, 0, 'no press');
    assert.equal(clicked.length, 0, 'no synthetic click');
  });
}

for (const [id, name, method, done] of [
  [155, 'browser_double_click', 'doubleClick', 'double-clicked'],
  [156, 'browser_right_click', 'contextClick', 'right-clicked'],
]) {
  test(`${name} off screen gets its own synthetic gesture, not a plain click`, async () => {
    const rig = await boot({ tabs: userTabs() });
    const { generation, clicked } = await readyButton(rig, { ...onScreen, inView: false });
    const synthetic = [];
    rig.state.page[method] = () => { synthetic.push(method); return { done }; };
    const reply = await ask(rig.ports[0], id, name, { tab: 3, generation, element: 1 });
    assert.deepEqual(reply.result, { done });
    assert.deepEqual(synthetic, [method], 'its own synthetic gesture');
    assert.equal(clicked.length, 0, 'never a plain click');
    assert.equal(presses(rig.state).length, 0, 'no mouse press off screen');
  });
}
// --- H-7 P5b: hover and scroll ------------------------------------------------------------------------

const mouseEvents = (state, type) => state.cdp.filter(([, method, params]) => method === 'Input.dispatchMouseEvent' && params.type === type).map(([, , p]) => p);

test('a trusted hover moves the pointer to the element center and presses nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, clicked } = await readyButton(rig, onScreen);
  const reply = await ask(rig.ports[0], 161, 'browser_hover', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'hovered' });
  assert.deepEqual(mouseEvents(rig.state, 'mouseMoved').map((p) => [p.x, p.y, p.buttons]), [[40, 60, 0]]);
  assert.equal(presses(rig.state).length, 0, 'a hover never presses');
  assert.equal(clicked.length, 0);
  assert.equal(rig.state.landingEvent, null, 'no click landing is armed for a hover');
});

test('a hover over an element something else covers moves nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, { ...onScreen, blocked: true });
  const reply = await ask(rig.ports[0], 162, 'browser_hover', { tab: 3, generation, element: 1 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(mouseEvents(rig.state, 'mouseMoved').length, 0);
});

test('a hover off screen uses the synthetic hover, never a press', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, clicked } = await readyButton(rig, { ...onScreen, inView: false });
  const hovered = [];
  rig.state.page.hover = () => { hovered.push(1); return { done: 'hovered' }; };
  const reply = await ask(rig.ports[0], 163, 'browser_hover', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'hovered' });
  assert.equal(hovered.length, 1);
  assert.equal(clicked.length, 0);
  assert.equal(mouseEvents(rig.state, 'mouseMoved').length, 0);
});

test('a hover on an element inside a frame uses the synthetic hover in that frame', async () => {
  const rig = await boot({ tabs: userTabs() });
  const run = rig.chrome.scripting.executeScript;
  const frames = [];
  rig.chrome.scripting.executeScript = async (opts) => {
    if (opts.func && !opts.target.allFrames) frames.push(opts.target.frameIds?.[0]);
    const out = await run(opts);
    return opts.target.allFrames ? out.map((hit) => ({ ...hit, frameId: 2 })) : out;
  };
  const { generation, clicked } = await readyButton(rig, onScreen);
  const hovered = [];
  rig.state.page.hover = () => { hovered.push(1); return { done: 'hovered' }; };
  const reply = await ask(rig.ports[0], 167, 'browser_hover', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'hovered' });
  assert.equal(hovered.length, 1);
  assert.equal(frames.at(-1), 2, 'run in the frame the read found it in');
  assert.equal(clicked.length, 0);
  assert.equal(mouseEvents(rig.state, 'mouseMoved').length, 0, 'a frame box is not in the tab\'s coordinates');
});

test('a scroll by an offset wheels at the middle of the viewport', async () => {
  const rig = await boot({ tabs: userTabs() });
  await readyButton(rig, onScreen);
  rig.state.page.viewport = () => ({ w: 1000, h: 800 });
  const reply = await ask(rig.ports[0], 164, 'browser_scroll', { tab: 3, dx: -40, dy: 600 });
  assert.deepEqual(reply.result, { done: 'scrolled' });
  assert.deepEqual(mouseEvents(rig.state, 'mouseWheel').map((p) => [p.x, p.y, p.deltaX, p.deltaY]), [[500, 400, -40, 600]]);
  assert.equal(presses(rig.state).length, 0);
  assert.equal(mouseEvents(rig.state, 'mouseMoved').length, 0, 'the wheel carries its own point; no hover over whatever is there');
});

test('a scroll whose viewport cannot be read still wheels, at the top-left corner', async () => {
  const rig = await boot({ tabs: userTabs() });
  await readyButton(rig, onScreen);
  rig.state.page.viewport = () => null;
  const reply = await ask(rig.ports[0], 168, 'browser_scroll', { tab: 3, dx: 0, dy: 300 });
  assert.deepEqual(reply.result, { done: 'scrolled' });
  assert.deepEqual(mouseEvents(rig.state, 'mouseWheel').map((p) => [p.x, p.y]), [[1, 1]]);
});

test('a scroll on a tab the page script cannot reach is stale and wheels nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  await readyButton(rig, onScreen);
  const run = rig.chrome.scripting.executeScript;
  rig.chrome.scripting.executeScript = async (opts) => {
    if (opts.files) throw new Error('Cannot access contents of the page');
    return run(opts);
  };
  const reply = await ask(rig.ports[0], 169, 'browser_scroll', { tab: 3, dx: 0, dy: 300 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(mouseEvents(rig.state, 'mouseWheel').length, 0);
});

test('a scroll after the user stopped Companion on that tab is refused', async () => {
  const rig = await boot({ tabs: userTabs() });
  await readyButton(rig, onScreen);
  rig.state.page.viewport = () => ({ w: 1000, h: 800 });
  for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
  const reply = await ask(rig.ports[0], 165, 'browser_scroll', { tab: 3, dx: 0, dy: 300 });
  assert.equal(reply.error.code, 'debugger_revoked');
  assert.equal(mouseEvents(rig.state, 'mouseWheel').length, 0);
});

test('a scroll to an element brings that element into view in its own frame', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  const scrolled = [];
  rig.state.page.scrollTo = (g, id) => { scrolled.push([g, id]); return { done: 'scrolled' }; };
  const reply = await ask(rig.ports[0], 166, 'browser_scroll', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'scrolled' });
  assert.equal(scrolled.length, 1);
  assert.equal(mouseEvents(rig.state, 'mouseWheel').length, 0, 'no wheel: the element is brought into view itself');
});

test('an element something else covers is never pressed with the mouse', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, clicked } = await readyButton(rig, { ...onScreen, blocked: true });
  const reply = await ask(rig.ports[0], 52, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(presses(rig.state).length, 0);
  assert.equal(clicked.length, 0);
  assert.equal(reply.error.code, 'stale_id');
});

// H-1: the page refuses an element that changed since the read; the background must not press it anyway.
test('an element that changed since the read is never pressed, trusted or synthetic', async () => {
  const rig = await boot({ tabs: userTabs() });
  const changed = { error: { code: 'stale_id', message: 'element changed since the read, read the page again' } };
  const { generation, clicked } = await readyButton(rig, changed);
  const reply = await ask(rig.ports[0], 54, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(presses(rig.state).length, 0);
  assert.equal(clicked.length, 0);
});

test('a press whose landing cannot be confirmed is not pressed again nor clicked synthetically', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, clicked } = await readyButton(rig, onScreen, { landed: false });
  const reply = await ask(rig.ports[0], 53, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(presses(rig.state).length, 1);
  assert.equal(clicked.length, 0);
  assert.deepEqual(reply.result, { done: 'clicked' });
});

test('after the user cancels the debugging banner nothing re-attaches and input is refused', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  const attaches = () => rig.state.calls.filter((c) => c[0] === 'debugger.attach').length;
  const before = attaches();
  for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
  const reply = await ask(rig.ports[0], 54, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(reply.error.code, 'debugger_revoked');
  assert.equal(presses(rig.state).length, 0);
  assert.equal(attaches(), before);
});

test('an attachment an earlier worker left behind is adopted instead of breaking the tab', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.attachError = 'Another debugger is already attached to the tab with id: 3.';
  rig.state.debugTargets = [{ tabId: 3, attached: true, extensionId: EXTENSION_ID }];
  const { generation } = await readyButton(rig, onScreen);
  const reply = await ask(rig.ports[0], 55, 'browser_click', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'clicked' });
  assert.equal(presses(rig.state).length, 1);
});

test('an element covered while the cursor glided is not pressed', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, clicked } = await readyButton(rig, onScreen);
  rig.state.stillHits = false;
  const reply = await ask(rig.ports[0], 56, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(presses(rig.state).length, 0);
  assert.equal(clicked.length, 0);
  assert.equal(reply.error.code, 'stale_id');
});

test('taking the tab again does not lift the user\'s Cancel on the debugging banner', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
  await ask(rig.ports[0], 57, 'browser_take', { tab: 3 });
  const reply = await ask(rig.ports[0], 58, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(reply.error.code, 'debugger_revoked');
  assert.equal(presses(rig.state).length, 0);
});

test('releasing a tab an earlier worker attached to still detaches it', async () => {
  const rig = await boot({ tabs: userTabs() });
  await ask(rig.ports[0], 59, 'browser_take', { tab: 2 });
  rig.state.debugTargets = [{ tabId: 3, attached: true, extensionId: EXTENSION_ID }];
  await ask(rig.ports[0], 60, 'browser_release', { tab: 3 });
  assert.ok(rig.state.calls.some((c) => c[0] === 'debugger.detach' && c[1] === 3));
});

test('a disconnect detaches every attachment of ours, also those an earlier worker left', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.debugTargets = [
    { tabId: 3, attached: true, extensionId: EXTENSION_ID },
    { tabId: 2, attached: true, extensionId: 'someoneelse' },
  ];
  rig.ports[0].hangUp();
  await settle();
  await settle();
  const detached = rig.state.calls.filter((c) => c[0] === 'debugger.detach').map((c) => c[1]);
  assert.deepEqual(detached, [3]);
});

// A page with one text field; `value` is what the field reads back after the keys.
async function readyField(rig, { prepare = { ready: true }, spot = onScreen, readBack = null } = {}) {
  const log = { synthetic: [], prepared: 0 };
  rig.state.page = {
    read: () => ({ origin: 'https://a.example', text: '', elements: [{ id: 1, frame: 0, role: 'textbox', label: 'Name', context: '', inputType: 'text', autocomplete: null, value: '', frameOrigin: null, href: null, fieldName: null, fieldId: null }] }),
    locate: () => spot,
    hitsAt: () => true,
    landed: () => true,
    prepareType: () => { log.prepared++; return prepare; },
    typedValue: () => ({ value: readBack ?? log.typed ?? '' }),
    type: (g, id, text) => { log.synthetic.push(text); return { done: 'typed' }; },
  };
  const read = await ask(rig.ports[0], 70, 'browser_read', { tab: 3 });
  return { generation: read.result.page.generation, log };
}

const keysSent = (state) => state.cdp.filter(([, method, params]) => method === 'Input.dispatchKeyEvent' && params.type === 'char').map(([, , p]) => p.text).join('');
const inputCalls = (state) => state.cdp.filter(([, method]) => method.startsWith('Input.'));

test('trusted typing presses the field once and sends every printable key', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { readBack: 'Ana' });
  const reply = await ask(rig.ports[0], 71, 'browser_type', { tab: 3, generation, element: 1, text: 'Ana' });
  assert.deepEqual(reply.result, { done: 'typed' });
  assert.equal(presses(rig.state).length, 1);
  assert.deepEqual(presses(rig.state).map(([, , p]) => [p.button, p.clickCount]), [['left', 1]], 'one plain left press focuses it');
  assert.equal(keysSent(rig.state), 'Ana');
});

test('a field that changed since the read gets no keys at all', async () => {
  const rig = await boot({ tabs: userTabs() });
  const changed = { error: { code: 'stale_id', message: 'element changed since the read, read the page again' } };
  const { generation, log } = await readyField(rig, { prepare: changed });
  const reply = await ask(rig.ports[0], 73, 'browser_type', { tab: 3, generation, element: 1, text: 'Ana' });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(inputCalls(rig.state).length, 0);
  assert.deepEqual(log.synthetic, []);
});

test('typing never sends Return, Escape or any other control key, and says so', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { readBack: 'ab' });
  const reply = await ask(rig.ports[0], 72, 'browser_type', { tab: 3, generation, element: 1, text: 'a\nb\r\u001b\u007f' });
  assert.equal(keysSent(rig.state), 'ab');
  const keys = rig.state.cdp.filter(([, method]) => method === 'Input.dispatchKeyEvent').map(([, , p]) => p.key);
  for (const forbidden of ['Enter', '\n', '\r', '\u001b', 'Escape', '\u007f']) assert.ok(!keys.includes(forbidden), forbidden);
  assert.equal(reply.result.done, 'typed without line breaks');
});

// H-5: keys cannot carry a line break, but a textarea takes the whole text in one insert.
test('multi-line text into a textarea keeps its line breaks', async () => {
  const rig = await boot({ tabs: userTabs() });
  const text = 'Hola Ana,\n\nGracias.\nKaren';
  const { generation, log } = await readyField(rig, { prepare: { ready: true, multiline: true }, readBack: text });
  const reply = await ask(rig.ports[0], 74, 'browser_type', { tab: 3, generation, element: 1, text });
  assert.deepEqual(reply.result, { done: 'typed' });
  assert.deepEqual(log.synthetic, [text], 'the whole text, breaks included, in one insert');
  assert.equal(keysSent(rig.state), '', 'no key-by-key typing that would drop them');
  assert.equal(presses(rig.state).length, 1, 'the field was still pressed first');
});

test('a textarea that did not keep the breaks is reported as without line breaks', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { prepare: { ready: true, multiline: true }, readBack: 'HolaAna' });
  const reply = await ask(rig.ports[0], 75, 'browser_type', { tab: 3, generation, element: 1, text: 'Hola\nAna' });
  assert.equal(reply.result.done, 'typed without line breaks');
});

test('a field that rejected the keys and then lost the breaks in the fallback says so', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, log } = await readyField(rig, { readBack: 'garbled' });
  const reply = await ask(rig.ports[0], 76, 'browser_type', { tab: 3, generation, element: 1, text: 'a\nb' });
  assert.deepEqual(log.synthetic, ['a\nb'], 'the old way ran');
  assert.equal(reply.result.done, 'typed without line breaks');
});

test('Windows line endings count as kept when the textarea stored them as \\n', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { prepare: { ready: true, multiline: true }, readBack: 'a\nb' });
  const reply = await ask(rig.ports[0], 77, 'browser_type', { tab: 3, generation, element: 1, text: 'a\r\nb' });
  assert.deepEqual(reply.result, { done: 'typed' });
});

test('old Mac line endings count as kept when the textarea stored them as \\n', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { prepare: { ready: true, multiline: true }, readBack: 'a\nb' });
  const reply = await ask(rig.ports[0], 77, 'browser_type', { tab: 3, generation, element: 1, text: 'a\rb' });
  assert.deepEqual(reply.result, { done: 'typed' });
});

test('a textarea that cut the text short is never reported as on one line', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { prepare: { ready: true, multiline: true }, readBack: 'Hola' });
  const reply = await ask(rig.ports[0], 79, 'browser_type', { tab: 3, generation, element: 1, text: 'Hola\nAna' });
  assert.notEqual(reply.result.done, 'typed without line breaks');
});

test('a refusal on the insert path is passed through, never reported as typed', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { prepare: { ready: true, multiline: true }, readBack: 'a\nb' });
  rig.state.page.type = () => ({ error: { code: 'stale_id', message: 'element changed since the read, read the page again' } });
  const reply = await ask(rig.ports[0], 78, 'browser_type', { tab: 3, generation, element: 1, text: 'a\nb' });
  assert.equal(reply.error.code, 'stale_id');
});

test('a multi-line text whose focus moved is refused before the first line and never read back', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, log } = await readyField(rig, { prepare: { ready: true, multiline: true } });
  let readBacks = 0;
  rig.state.page.typedValue = () => { readBacks++; return { value: '' }; };
  rig.state.page.type = (g, id, text) => { log.synthetic.push(text); return { error: { code: 'secure_field', message: 'sensitive field, typing refused' } }; };
  const reply = await ask(rig.ports[0], 80, 'browser_type', { tab: 3, generation, element: 1, text: 'a\nb' });
  assert.equal(reply.error.code, 'secure_field');
  assert.equal(readBacks, 0);
  assert.equal(keysSent(rig.state), '');
});

// The press is a real click: its handlers are the likeliest thing to move the focus.
test('a focus that moved because of the click sends no key', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, log } = await readyField(rig);
  const moved = { error: { code: 'secure_field', message: 'focus moved to a sensitive field, typing refused' } };
  rig.state.page.prepareType = () => (log.prepared++ === 0 ? { ready: true } : moved);
  const reply = await ask(rig.ports[0], 81, 'browser_type', { tab: 3, generation, element: 1, text: 'hunter2' });
  assert.equal(reply.error.code, 'secure_field');
  assert.equal(presses(rig.state).length, 1);
  assert.equal(log.prepared, 2, 'checked again after the press');
  assert.equal(keysSent(rig.state), '');
  assert.deepEqual(log.synthetic, []);
});

test('a sensitive field is refused before any input reaches the page', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { prepare: { error: { code: 'secure_field', message: 'sensitive field, typing refused' } } });
  const reply = await ask(rig.ports[0], 73, 'browser_type', { tab: 3, generation, element: 1, text: 'hunter2' });
  assert.equal(reply.error.code, 'secure_field');
  assert.deepEqual(inputCalls(rig.state), []);
});

test('a field that did not take the keys gets the value the old way', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, log } = await readyField(rig, { readBack: 'garbled' });
  const reply = await ask(rig.ports[0], 74, 'browser_type', { tab: 3, generation, element: 1, text: 'Ana' });
  assert.deepEqual(log.synthetic, ['Ana']);
  assert.deepEqual(reply.result, { done: 'typed' });
});

test('an element inside a frame is clicked the old way, not refused as covered', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, clicked } = await readyButton(rig, { ...onScreen, inFrame: true });
  const reply = await ask(rig.ports[0], 75, 'browser_click', { tab: 3, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'clicked' });
  assert.equal(clicked.length, 1);
  assert.equal(presses(rig.state).length, 0);
});

test('a debugger that goes away mid-action answers debugger_unavailable, not invalid_args', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  rig.chrome.debugger.sendCommand = (target, method, params, cb) => {
    if (method === 'Input.dispatchMouseEvent') rig.chrome.runtime.lastError = { message: 'Debugger is not attached to the tab with id: 3.' };
    cb({});
    rig.chrome.runtime.lastError = undefined;
  };
  const reply = await ask(rig.ports[0], 76, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(reply.error.code, 'debugger_unavailable');
});

test('the Cancel on the debugging banner survives a worker restart', async () => {
  const rig = await boot({ tabs: userTabs() });
  for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
  await settle();
  const stored = { ...rig.state.stored };
  mock.timers.reset();
  const again = await boot({ tabs: userTabs(), stored });
  const { generation } = await readyButton(again, onScreen);
  const reply = await ask(again.ports[0], 77, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(reply.error.code, 'debugger_revoked');
  assert.equal(presses(again.state).length, 0);
});

test('the cursor is removed when the user cancels the debugging banner', async () => {
  const rig = await boot({ tabs: userTabs() });
  await readyButton(rig, onScreen);
  let destroyed = 0;
  const run = rig.chrome.scripting.executeScript;
  rig.chrome.scripting.executeScript = async (opts) => {
    globalThis.__companionCursor = { destroy: () => { destroyed++; } };
    return opts.func ? [{ frameId: 0, result: opts.func(...(opts.args ?? [])) }] : run(opts);
  };
  for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
  await settle();
  assert.equal(destroyed, 1);
});

// --- QA review follow-ups ---------------------------------------------------------------------------

const offScreen = { ...onScreen, inView: false };

test('an element that never comes on screen is not pressed and is clicked synthetically once', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, clicked } = await readyButton(rig, offScreen);
  const reply = await ask(rig.ports[0], 80, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(presses(rig.state).length, 0);
  assert.equal(clicked.length, 1);
  assert.deepEqual(reply.result, { done: 'clicked' });
});

test('a cover that goes away is waited out and the element is pressed exactly once', async () => {
  const rig = await boot({ tabs: userTabs() });
  let n = 0;
  const { generation } = await readyButton(rig, () => (++n === 1 ? { ...onScreen, blocked: true } : onScreen));
  await ask(rig.ports[0], 81, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(presses(rig.state).length, 1);
});

test('a cover that stays is checked three times and never pressed', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, { ...onScreen, blocked: true });
  await ask(rig.ports[0], 82, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(rig.state.locates, 3);
  assert.equal(presses(rig.state).length, 0);
});

test('typing into a covered field sends no press and no key', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { spot: { ...onScreen, blocked: true } });
  const reply = await ask(rig.ports[0], 83, 'browser_type', { tab: 3, generation, element: 1, text: 'Ana' });
  assert.equal(reply.error.code, 'stale_id');
  assert.deepEqual(inputCalls(rig.state), []);
});

test('typing into a field off screen focuses it without a press and still types real keys', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, log } = await readyField(rig, { spot: offScreen, readBack: 'Ana' });
  const reply = await ask(rig.ports[0], 84, 'browser_type', { tab: 3, generation, element: 1, text: 'Ana' });
  assert.equal(presses(rig.state).length, 0);
  assert.equal(keysSent(rig.state), 'Ana');
  assert.equal(log.prepared, 2);
  assert.deepEqual(reply.result, { done: 'typed' });
});

test('two actions on one tab never interleave their input', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  rig.ports[0].receive(call(85, 'browser_click', { tab: 3, generation, element: 1 }));
  rig.ports[0].receive(call(86, 'browser_click', { tab: 3, generation, element: 1 }));
  for (let i = 0; i < 10; i++) await settle();
  const kinds = rig.state.cdp.filter(([, m]) => m === 'Emulation.setFocusEmulationEnabled' || m === 'Input.dispatchMouseEvent')
    .map(([, m, p]) => (m === 'Emulation.setFocusEmulationEnabled' ? (p.enabled ? 'on' : 'off') : p.type));
  const block = ['on', 'mouseMoved', 'mousePressed', 'mouseReleased', 'off'];
  assert.deepEqual(kinds, [...block, ...block]);
});

test('taking a tab attaches once and keeps its page lifecycle active', async () => {
  const rig = await boot({ tabs: userTabs() });
  await ask(rig.ports[0], 87, 'browser_take', { tab: 3 });
  await readyButton(rig, onScreen);
  assert.equal(rig.state.calls.filter((c) => c[0] === 'debugger.attach').length, 1);
  const methods = rig.state.cdp.filter(([tab]) => tab === 3).map(([, m, p]) => [m, p]);
  assert.ok(methods.some(([m]) => m === 'Page.enable'));
  assert.ok(methods.some(([m, p]) => m === 'Page.setWebLifecycleState' && p.state === 'active'));
});

test('focus emulation is switched off even when the action fails', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  const send = rig.chrome.debugger.sendCommand;
  rig.chrome.debugger.sendCommand = (target, method, params, cb) => {
    if (method === 'Input.dispatchMouseEvent') rig.chrome.runtime.lastError = { message: 'boom' };
    send(target, method, params, cb);
    rig.chrome.runtime.lastError = undefined;
  };
  await ask(rig.ports[0], 88, 'browser_click', { tab: 3, generation, element: 1 });
  const last = rig.state.cdp.filter(([, m]) => m === 'Emulation.setFocusEmulationEnabled').at(-1);
  assert.deepEqual(last[2], { enabled: false });
});

test('a tab Chrome will not let us attach to answers debugger_unavailable and is never pressed', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.attachError = 'Cannot access a chrome:// URL';
  const { generation } = await readyButton(rig, onScreen);
  const take = await ask(rig.ports[0], 89, 'browser_take', { tab: 2 });
  assert.deepEqual(take.result, { done: 'taken' });
  const reply = await ask(rig.ports[0], 90, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(reply.error.code, 'debugger_unavailable');
  assert.equal(presses(rig.state).length, 0);
});

test('an attachment held by someone else is not adopted', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.attachError = 'Another debugger is already attached to the tab with id: 3.';
  rig.state.debugTargets = [{ tabId: 3, attached: true, extensionId: 'someoneelse' }];
  const { generation } = await readyButton(rig, onScreen);
  const reply = await ask(rig.ports[0], 91, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(reply.error.code, 'debugger_unavailable');
  assert.equal(presses(rig.state).length, 0);
});

test('a Cancel that lands in the middle of an action answers debugger_revoked', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  rig.chrome.debugger.sendCommand = (target, method, params, cb) => {
    if (method === 'Input.dispatchMouseEvent') {
      for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
      rig.chrome.runtime.lastError = { message: 'Debugger is not attached to the tab with id: 3.' };
    }
    cb({});
    rig.chrome.runtime.lastError = undefined;
  };
  const reply = await ask(rig.ports[0], 92, 'browser_click', { tab: 3, generation, element: 1 });
  assert.equal(reply.error.code, 'debugger_revoked');
});

test('typing after the user cancelled the banner is refused with no input at all', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyField(rig, { readBack: 'Ana' });
  for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
  const reply = await ask(rig.ports[0], 93, 'browser_type', { tab: 3, generation, element: 1, text: 'Ana' });
  assert.equal(reply.error.code, 'debugger_revoked');
  assert.deepEqual(inputCalls(rig.state), []);
});

test('reading after the user cancelled the banner does not re-attach', async () => {
  const rig = await boot({ tabs: userTabs() });
  await readyButton(rig, onScreen);
  const attaches = () => rig.state.calls.filter((c) => c[0] === 'debugger.attach').length;
  const before = attaches();
  for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
  await ask(rig.ports[0], 94, 'browser_read', { tab: 3 });
  assert.equal(attaches(), before);
});

async function countDestroys(rig) {
  const seen = { destroyed: 0 };
  rig.state.cursor = { destroy: () => { seen.destroyed++; } };
  return seen;
}

test('the cursor is removed when the tab is released', async () => {
  const rig = await boot({ tabs: userTabs() });
  await ask(rig.ports[0], 95, 'browser_take', { tab: 3 });
  const seen = await countDestroys(rig);
  await ask(rig.ports[0], 96, 'browser_release', { tab: 3 });
  assert.equal(seen.destroyed, 1);
});

test('the cursor is removed from every controlled tab when the app goes away', async () => {
  const rig = await boot({ tabs: userTabs() });
  await ask(rig.ports[0], 97, 'browser_take', { tab: 3 });
  const seen = await countDestroys(rig);
  rig.ports[0].hangUp();
  for (let i = 0; i < 5; i++) await settle();
  assert.equal(seen.destroyed, 1);
});

// H-6: open and navigate answered before the page loaded, so an immediate read saw an empty or old
// page. Like Incredible, they now wait within a five-second budget and say when it ran out.
test('browser_navigate answers navigated once the page has loaded', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.holdLoads = true;
  rig.ports[0].receive(call(90, 'browser_navigate', { tab: 3, url: 'https://a.example/y' }));
  await settle();
  assert.deepEqual(answersTo(rig.ports[0], 90), [], 'no answer while the page loads');
  rig.state.finishLoad(3);
  await settle();
  assert.deepEqual(answersTo(rig.ports[0], 90)[0].result, { done: 'navigated' });
});

test('browser_navigate says still loading when the budget runs out', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.holdLoads = true;
  rig.ports[0].receive(call(91, 'browser_navigate', { tab: 3, url: 'https://a.example/y' }));
  await settle();
  mock.timers.tick(4999);
  await settle();
  assert.deepEqual(answersTo(rig.ports[0], 91), []);
  mock.timers.tick(1);
  await settle();
  assert.deepEqual(answersTo(rig.ports[0], 91)[0].result, { done: 'still loading' });
});

test('another tab finishing its load does not end the wait', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.holdLoads = true;
  rig.ports[0].receive(call(92, 'browser_navigate', { tab: 3, url: 'https://a.example/y' }));
  await settle();
  rig.state.finishLoad(2);
  await settle();
  assert.deepEqual(answersTo(rig.ports[0], 92), []);
  rig.state.finishLoad(3);
  await settle();
  assert.deepEqual(answersTo(rig.ports[0], 92)[0].result, { done: 'navigated' });
});

test('browser_open waits for the new tab to load and says when it is still loading', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.holdLoads = true;
  rig.ports[0].receive(call(93, 'browser_open', { url: 'https://a.example/x' }));
  await settle();
  assert.deepEqual(answersTo(rig.ports[0], 93), []);
  mock.timers.tick(5000);
  await settle();
  assert.equal(answersTo(rig.ports[0], 93)[0].result.tab.loading, true);
});

test('a page that loads before the wait starts still counts as loaded', async () => {
  const rig = await boot({ tabs: userTabs() });
  const reply = await ask(rig.ports[0], 94, 'browser_open', { url: 'https://a.example/x' });
  assert.equal(reply.result.tab.loading, false);
});

// A service worker that keeps one listener per call slows every tab update for its whole life.
test('the load listener is removed however open and navigate end', async () => {
  const cases = [
    ['navigate loads', async (rig) => { await ask(rig.ports[0], 95, 'browser_navigate', { tab: 3, url: 'https://a.example/y' }); }],
    ['navigate runs out', async (rig) => {
      rig.state.holdLoads = true;
      rig.ports[0].receive(call(96, 'browser_navigate', { tab: 3, url: 'https://a.example/y' }));
      await settle();
      mock.timers.tick(5000);
      await settle();
    }],
    ['open loads', async (rig) => { await ask(rig.ports[0], 97, 'browser_open', { url: 'https://a.example/x' }); }],
    ['open cannot group', async (rig) => {
      rig.state.failWhen = (name) => name === 'tabs.group';
      await ask(rig.ports[0], 98, 'browser_open', { url: 'https://a.example/x' });
    }],
    ['open cannot create', async (rig) => {
      rig.state.failWhen = (name) => name === 'tabs.create';
      await ask(rig.ports[0], 99, 'browser_open', { url: 'https://a.example/x' });
      assert.ok(!rig.state.calls.some((c) => c[0] === 'tabs.remove'), 'nothing to close');
    }],
  ];
  for (const [name, run] of cases) {
    const rig = await boot({ tabs: userTabs() });
    await run(rig);
    assert.equal(rig.state.updatedListeners.length, 0, name);
    mock.timers.reset();
  }
});

test('navigating a tab that is gone answers invalid_args at once, with no wait left behind', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.failWhen = (name) => name === 'tabs.update';
  const reply = await ask(rig.ports[0], 100, 'browser_navigate', { tab: 3, url: 'https://a.example/y' });
  assert.equal(reply.error.code, 'invalid_args');
  assert.equal(rig.state.updatedListeners.length, 0);
  mock.timers.tick(5000);
  await settle();
  assert.equal(answersTo(rig.ports[0], 100).length, 1, 'no second answer when the budget would have run out');
});

test('the old page finishing after the navigation was asked for does not count as the new one loading', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.holdLoads = true;
  rig.state.staleComplete = true;
  rig.ports[0].receive(call(101, 'browser_navigate', { tab: 3, url: 'https://a.example/y' }));
  await settle();
  assert.deepEqual(answersTo(rig.ports[0], 101), [], 'still waiting for the new page');
  rig.state.finishLoad(3);
  await settle();
  assert.deepEqual(answersTo(rig.ports[0], 101)[0].result, { done: 'navigated' });
});

test('a jump within the same page counts as loaded without waiting out the budget', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.sameDocument = true;
  const reply = await ask(rig.ports[0], 102, 'browser_navigate', { tab: 3, url: 'https://x.example/#faq' });
  assert.deepEqual(reply.result, { done: 'navigated' });
  assert.equal(rig.state.updatedListeners.length, 0);
});

test('a tab closed while it loads answers stale_id, never navigated or still loading', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.holdLoads = true;
  rig.ports[0].receive(call(103, 'browser_navigate', { tab: 3, url: 'https://a.example/y' }));
  await settle();
  rig.state.closeTab(3);
  await settle();
  assert.equal(answersTo(rig.ports[0], 103)[0].error?.code, 'stale_id');
  assert.equal(rig.state.updatedListeners.length, 0);
});

test('a new tab closed while it loads answers stale_id', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.holdLoads = true;
  rig.ports[0].receive(call(104, 'browser_open', { url: 'https://a.example/x' }));
  await settle();
  rig.state.closeTab(100);
  await settle();
  assert.equal(answersTo(rig.ports[0], 104)[0].error?.code, 'stale_id');
});

test('a slow page does not hold the next open behind it', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.holdLoads = true;
  rig.ports[0].receive(call(105, 'browser_open', { url: 'https://a.example/' }));
  rig.ports[0].receive(call(106, 'browser_open', { url: 'https://b.example/' }));
  await settle();
  await settle();
  assert.equal(rig.state.calls.filter((c) => c[0] === 'tabs.create').length, 2, 'both tabs were created while the first still loads');
  rig.state.finishLoad(101);
  await settle();
  assert.equal(answersTo(rig.ports[0], 106)[0].result.tab.loading, false, 'the second answers on its own load');
  assert.deepEqual(answersTo(rig.ports[0], 105), [], 'the first is still waiting');
});

// H-7 P2a: the finder fields reach the page as one query; within names an element of the last read.
function recordingPage(rig, elements = 1) {
  const queries = [];
  rig.state.page = {
    read: (g, q) => {
      queries.push(q);
      return {
        origin: 'https://a.example', text: 'Go',
        elements: Array.from({ length: elements }, (_, i) => ({ id: i + 1, frame: 0, role: 'button', label: `B${i + 1}`, context: '', inputType: null, autocomplete: null, value: null, frameOrigin: null, href: null, fieldName: null, fieldId: null })),
      };
    },
  };
  return queries;
}

test('the finder fields reach the page as one query', async () => {
  const rig = await boot({ tabs: userTabs() });
  const queries = recordingPage(rig);
  await ask(rig.ports[0], 110, 'browser_read', { tab: 3, text: 'Go', exact: true, role: 'button', name: 'Go', maxChars: 50 });
  assert.deepEqual(queries[0], { selector: null, text: 'Go', exact: true, role: 'button', name: 'Go', max: null, maxChars: 50 });
});

test('within reads inside an element of the last read, in its own frame', async () => {
  const rig = await boot({ tabs: userTabs() });
  const queries = recordingPage(rig);
  const first = await ask(rig.ports[0], 111, 'browser_read', { tab: 3 });
  const generation = first.result.page.generation;
  await ask(rig.ports[0], 112, 'browser_read', { tab: 3, generation, within: 1 });
  assert.equal(queries[1].withinGeneration, generation);
  assert.equal(queries[1].withinLocal, 1);
});

test('within an element of an old read is refused as stale, before the page runs', async () => {
  const rig = await boot({ tabs: userTabs() });
  const queries = recordingPage(rig);
  const first = await ask(rig.ports[0], 113, 'browser_read', { tab: 3 });
  const reply = await ask(rig.ports[0], 114, 'browser_read', { tab: 3, generation: first.result.page.generation - 1, within: 1 });
  assert.equal(reply.error?.code, 'stale_id');
  assert.equal(queries.length, 1);
});

test('a finder that misses everywhere passes the page answer through', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.page = { read: () => ({ error: { code: 'selector_hidden', message: 'everything the search matches is hidden' } }) };
  const reply = await ask(rig.ports[0], 115, 'browser_read', { tab: 3, text: 'Cerrar' });
  assert.equal(reply.error?.code, 'selector_hidden');
});

test('max caps the elements of the merged page', async () => {
  const rig = await boot({ tabs: userTabs() });
  recordingPage(rig, 4);
  const reply = await ask(rig.ports[0], 116, 'browser_read', { tab: 3, max: 2 });
  assert.deepEqual(reply.result.page.elements.map((e) => e.label), ['B1', 'B2']);
});

const missing = (code) => ({ read: () => ({ error: { code, message: 'm' } }) });
const oneButton = (label) => ({ read: () => ({ origin: 'https://a.example', text: label, elements: [{ id: 1, frame: 0, role: 'button', label, context: '', inputType: null, autocomplete: null, value: null, frameOrigin: null, href: null, fieldName: null, fieldId: null }] }) });

test('a finder that matches in one frame and misses in another answers with the match', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.page = missing('selector_no_match');
  rig.state.frames = [[7, oneButton('Cerrar')]];
  const reply = await ask(rig.ports[0], 117, 'browser_read', { tab: 3, text: 'Cerrar' });
  assert.equal(reply.error, undefined);
  assert.deepEqual(reply.result.page.elements.map((e) => e.label), ['Cerrar']);
});

test('a finder that misses in every frame names hidden over nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.page = missing('selector_no_match');
  rig.state.frames = [[7, missing('selector_hidden')]];
  const reply = await ask(rig.ports[0], 118, 'browser_read', { tab: 3, text: 'Cerrar' });
  assert.equal(reply.error?.code, 'selector_hidden');
});

test('maxChars caps the text of every frame together', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.page = oneButton('Primero');
  rig.state.frames = [[7, oneButton('Segundo')]];
  const reply = await ask(rig.ports[0], 119, 'browser_read', { tab: 3, maxChars: 10 });
  assert.equal(Array.from(reply.result.page.text).length, 10);
  assert.ok(reply.result.page.text.startsWith('Primero'));
});

// P3: a native <select> has no trusted path to drive (its list is the browser's, not the page's),
// so the choice is made in the page and no input event goes out.
test('browser_select chooses in the page by the read generation, without trusted input', async () => {
  const rig = await boot({ tabs: userTabs() });
  const chosen = [];
  rig.state.page = {
    read: () => ({ origin: 'https://a.example', text: '', elements: [{ id: 1, frame: 0, role: 'combobox', label: 'Pais', context: '', inputType: 'select', autocomplete: null, value: 'Chile', frameOrigin: null, href: null, fieldName: null, fieldId: null }] }),
    select: (g, id, option) => { chosen.push([g, id, option]); return { done: 'selected' }; },
  };
  const read = await ask(rig.ports[0], 90, 'browser_read', { tab: 3 });
  const generation = read.result.page.generation;
  const reply = await ask(rig.ports[0], 91, 'browser_select', { tab: 3, generation, element: 1, option: 'México' });
  assert.deepEqual(reply.result, { done: 'selected' });
  assert.deepEqual(chosen, [[generation, 1, 'México']]);
  assert.deepEqual(inputCalls(rig.state), []);
  const stale = await ask(rig.ports[0], 92, 'browser_select', { tab: 3, generation: generation - 1, element: 1, option: 'México' });
  assert.equal(stale.error.code, 'stale_id');
  assert.equal(chosen.length, 1);
});

test('the page refusal of a select comes back as its code', async () => {
  const rig = await boot({ tabs: userTabs() });
  rig.state.page = {
    read: () => ({ origin: 'https://a.example', text: '', elements: [{ id: 1, frame: 0, role: 'combobox', label: 'Pais', context: '', inputType: 'select', autocomplete: null, value: '', frameOrigin: null, href: null, fieldName: null, fieldId: null }] }),
    select: () => ({ error: { code: 'option_not_found', message: 'Argentina | Chile' } }),
  };
  const read = await ask(rig.ports[0], 93, 'browser_read', { tab: 3 });
  const reply = await ask(rig.ports[0], 94, 'browser_select', { tab: 3, generation: read.result.page.generation, element: 1, option: 'Peru' });
  assert.deepEqual(reply.error, { code: 'option_not_found', message: 'Argentina | Chile' });
});

// ---- P4: browser_press ----

async function pressPage(rig, { focused = true } = {}) {
  const log = { focused: 0 };
  rig.state.page = {
    read: () => ({ origin: 'https://a.example', text: '', elements: [{ id: 1, frame: 0, role: 'textbox', label: 'Buscar', context: '', inputType: 'text', autocomplete: null, value: '', frameOrigin: null, href: null, fieldName: null, fieldId: null, submit: 'Buscar' }] }),
    focus: () => { log.focused++; return { focused }; },
  };
  const read = await ask(rig.ports[0], 80, 'browser_read', { tab: 3 });
  return { generation: read.result.page.generation, log };
}

const keyEvents = (state) => state.cdp.filter(([, method]) => method === 'Input.dispatchKeyEvent').map(([, , p]) => p);

test('a press on an element focuses it, then sends the trusted key the asked number of times', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, log } = await pressPage(rig);
  const reply = await ask(rig.ports[0], 81, 'browser_press', { tab: 3, key: 'Enter', times: 1, generation, element: 1 });
  assert.deepEqual(reply.result, { done: 'pressed' });
  assert.equal(log.focused, 1);
  const events = keyEvents(rig.state);
  assert.deepEqual(events.map((e) => e.type), ['keyDown', 'keyUp']);
  await ask(rig.ports[0], 88, 'browser_press', { tab: 3, key: 'Tab', times: 2, generation, element: 1 });
  assert.deepEqual(keyEvents(rig.state).slice(2).map((e) => e.type), ['rawKeyDown', 'keyUp', 'rawKeyDown', 'keyUp']);
  assert.deepEqual([events[0].key, events[0].code, events[0].windowsVirtualKeyCode, events[0].text], ['Enter', 'Enter', 13, '\r']);
});

test('a key that types nothing goes down raw, and Shift+Tab carries the Shift modifier', async () => {
  const rig = await boot({ tabs: userTabs() });
  await pressPage(rig);
  await ask(rig.ports[0], 82, 'browser_press', { tab: 3, key: 'Escape', times: 1, generation: null, element: null });
  await ask(rig.ports[0], 83, 'browser_press', { tab: 3, key: 'Shift+Tab', times: 1, generation: null, element: null });
  const events = keyEvents(rig.state);
  assert.deepEqual(events.map((e) => [e.type, e.key, e.text, e.modifiers ?? 0]), [
    ['rawKeyDown', 'Escape', undefined, 0], ['keyUp', 'Escape', undefined, 0],
    ['rawKeyDown', 'Tab', undefined, 8], ['keyUp', 'Tab', undefined, 8],
  ]);
});

test('Space carries its text so it activates, like a real key', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await pressPage(rig);
  await ask(rig.ports[0], 87, 'browser_press', { tab: 3, key: 'Space', times: 1, generation, element: 1 });
  const [down] = keyEvents(rig.state);
  assert.deepEqual([down.type, down.key, down.code, down.windowsVirtualKeyCode, down.text], ['keyDown', ' ', 'Space', 32, ' ']);
});

// A key in the allowlist the CDP table did not know would pass validation and fail at the press.
test('every key the wire accepts is one the extension can press', async () => {
  const rig = await boot({ tabs: userTabs() });
  await pressPage(rig);
  let id = 300;
  for (const key of PRESS_KEYS) {
    const reply = await ask(rig.ports[0], id++, 'browser_press', { tab: 3, key, times: 1, generation: null, element: null });
    assert.deepEqual(reply.result, { done: 'pressed' }, key);
  }
  assert.equal(keyEvents(rig.state).filter((e) => e.type === 'keyUp').length, PRESS_KEYS.length);
});

test('without an element the key goes to the page focus and nothing is focused first', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { log } = await pressPage(rig);
  const reply = await ask(rig.ports[0], 84, 'browser_press', { tab: 3, key: 'ArrowDown', times: 3, generation: null, element: null });
  assert.deepEqual(reply.result, { done: 'pressed' });
  assert.equal(log.focused, 0);
  assert.equal(keyEvents(rig.state).filter((e) => e.type === 'rawKeyDown').length, 3);
});

// A key sent while the focus is elsewhere lands on whatever holds it: an Enter nobody approved.
test('an element that does not take the focus gets not_focused and no key', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await pressPage(rig, { focused: false });
  const reply = await ask(rig.ports[0], 85, 'browser_press', { tab: 3, key: 'Enter', times: 1, generation, element: 1 });
  assert.equal(reply.error.code, 'not_focused');
  assert.deepEqual(keyEvents(rig.state), []);
});

test('a press on an element of an old read is stale and sends no key', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation, log } = await pressPage(rig);
  const reply = await ask(rig.ports[0], 86, 'browser_press', { tab: 3, key: 'Enter', times: 1, generation: generation - 1, element: 1 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(log.focused, 0);
  assert.deepEqual(keyEvents(rig.state), []);
});

// --- H-7 P7: drag and click at a point -------------------------------------------------------------------

// Two items in the top frame; the source is located at (40, 60), the target measured at (200, 300).
async function readyPair(rig, { target = { box: { x: 200, y: 300 }, inView: true }, frame = false, view = { w: 1000, h: 800 } } = {}) {
  const item = (id, label) => ({ id, frame: 0, role: 'listitem', label, context: '', inputType: null, autocomplete: null, value: null, frameOrigin: null, href: null, fieldName: null, fieldId: null });
  rig.state.hits = [];
  rig.state.page = {
    read: () => ({ origin: 'https://a.example', text: 'Uno Dos', elements: [item(1, 'Uno'), item(2, 'Dos')] }),
    locate: (...args) => { rig.state.landingEvent = args[3]; return onScreen; },
    boxOf: () => target,
    pointAt: (...args) => { rig.state.points = (rig.state.points ?? 0) + 1; return typeof frame === 'function' ? frame(...args) : { frame, same: true }; },
    viewport: () => view,
    hitsAt: (g, id, x, y) => { rig.state.hits.push([id, x, y]); return rig.state.stillHits?.(id) ?? true; },
    landed: () => true,
  };
  const read = await ask(rig.ports[0], 70, 'browser_read', { tab: 3 });
  return read.result.page.generation;
}

const releases = (state) => mouseEvents(state, 'mouseReleased');

test('a drag onto an element presses the source, moves holding the button and lets go on the target', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  const reply = await ask(rig.ports[0], 171, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.deepEqual(reply.result, { done: 'dragged' });
  assert.deepEqual(pressParams(rig.state).map((p) => [p.x, p.y, p.button, p.buttons]), [[40, 60, 'left', 1]]);
  const held = mouseEvents(rig.state, 'mouseMoved').filter((p) => p.buttons === 1);
  assert.equal(held.length, 10, 'moved in steps, so the page sees a drag and not a jump');
  const order = rig.state.cdp.filter(([, method]) => method === 'Input.dispatchMouseEvent').map(([, , p]) => p.type + (p.buttons ? '+' : ''));
  assert.deepEqual(order, ['mouseMoved', 'mousePressed+', ...Array(10).fill('mouseMoved+'), 'mouseReleased']);
  assert.deepEqual([held.at(-1).x, held.at(-1).y], [200, 300]);
  assert.deepEqual(releases(rig.state).map((p) => [p.x, p.y, p.buttons]), [[200, 300, 0]]);
  assert.equal(rig.state.landingEvent, null, 'a drag arms no click landing');
  assert.ok(rig.state.hits.some(([id, x, y]) => id === 2 && x === 200 && y === 300), 'the target is hit-tested at the drop point');
});

test('a drag by an offset lets go that far from the source', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  const reply = await ask(rig.ports[0], 172, 'browser_drag', { tab: 3, generation, element: 1, dx: 100, dy: -20 });
  assert.deepEqual(reply.result, { done: 'dragged' });
  assert.deepEqual(releases(rig.state).map((p) => [p.x, p.y]), [[140, 40]]);
});

test('a drag never drops onto an embedded frame', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig, { frame: () => ({ frame: true, same: true }) });
  const reply = await ask(rig.ports[0], 173, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(presses(rig.state).length, 0);
});

test('a drag whose drop point is off the visible page presses nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  const reply = await ask(rig.ports[0], 174, 'browser_drag', { tab: 3, generation, element: 1, dx: 0, dy: 2000 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(presses(rig.state).length, 0);
});

test('a drag target that is off screen or covered is not dropped onto', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig, { target: { box: { x: 200, y: 300 }, inView: false } });
  const off = await ask(rig.ports[0], 175, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(off.error.code, 'stale_id', 'off screen');
  rig.state.page.boxOf = () => ({ box: { x: 200, y: 300 }, inView: true });
  rig.state.stillHits = (id) => id !== 2;
  const covered = await ask(rig.ports[0], 176, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(covered.error.code, 'stale_id', 'something else at the drop point');
  assert.equal(presses(rig.state).length, 0);
});

test('a drag with ids of another read is stale and presses nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  const reply = await ask(rig.ports[0], 177, 'browser_drag', { tab: 3, generation: generation - 1, element: 1, to: 2 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(presses(rig.state).length, 0);
});

test('a drag inside a frame is refused: its boxes are not in the tab\'s coordinates', async () => {
  const rig = await boot({ tabs: userTabs() });
  const run = rig.chrome.scripting.executeScript;
  rig.chrome.scripting.executeScript = async (opts) => {
    const out = await run(opts);
    return opts.target.allFrames ? out.map((hit) => ({ ...hit, frameId: 2 })) : out;
  };
  const generation = await readyPair(rig);
  const reply = await ask(rig.ports[0], 178, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(reply.error.reason, 'frame_drag');
  assert.equal(presses(rig.state).length, 0);
});

test('a click at a point of the current read presses once there', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  const reply = await ask(rig.ports[0], 181, 'browser_click_at', { tab: 3, generation, x: 400, y: 300 });
  assert.deepEqual(reply.result, { done: 'clicked' });
  assert.deepEqual(pressParams(rig.state).map((p) => [p.x, p.y, p.button, p.clickCount]), [[400, 300, 'left', 1]]);
});

test('a click at a point of another read is stale and presses nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  const reply = await ask(rig.ports[0], 182, 'browser_click_at', { tab: 3, generation: generation + 1, x: 400, y: 300 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(presses(rig.state).length, 0);
});

test('a click at a point outside the visible page or on an embedded frame presses nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  let frame = false;
  const generation = await readyPair(rig, { frame: () => ({ frame, same: true }) });
  const outside = await ask(rig.ports[0], 183, 'browser_click_at', { tab: 3, generation, x: 1200, y: 300 });
  assert.equal(outside.error.code, 'stale_id', 'past the right edge');
  frame = true;
  const framed = await ask(rig.ports[0], 184, 'browser_click_at', { tab: 3, generation, x: 400, y: 300 });
  assert.equal(framed.error.code, 'stale_id', 'a frame of another page is at that point');
  rig.state.page.viewport = () => null;
  frame = false;
  const unknown = await ask(rig.ports[0], 185, 'browser_click_at', { tab: 3, generation, x: 400, y: 300 });
  assert.equal(unknown.error.code, 'stale_id', 'a viewport that cannot be read is not one the point is inside');
  assert.equal(presses(rig.state).length, 0);
});

test('a click at a point after the user stopped Companion on that tab is refused', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
  const reply = await ask(rig.ports[0], 186, 'browser_click_at', { tab: 3, generation, x: 400, y: 300 });
  assert.equal(reply.error.code, 'debugger_revoked');
  assert.equal(presses(rig.state).length, 0);
});

test('a drag whose source is covered by the time the cursor arrives presses nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  rig.state.stillHits = (id) => id !== 1;
  const reply = await ask(rig.ports[0], 187, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(presses(rig.state).length, 0);
});

test('a drag target covered during the cursor glide is not dropped onto', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  let targetChecks = 0;
  rig.state.stillHits = (id) => id !== 2 || ++targetChecks === 1;
  const reply = await ask(rig.ports[0], 188, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(reply.error.code, 'stale_id');
  assert.ok(targetChecks >= 2, 'checked again right before the press');
  assert.equal(presses(rig.state).length, 0);
});

test('a source in a frame, off screen or covered, or a target in a frame, is never dragged', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  let id = 190;
  for (const spot of [{ inFrame: true }, { ...onScreen, inView: false }, { ...onScreen, blocked: true }]) {
    rig.state.page.locate = () => spot;
    const reply = await ask(rig.ports[0], id++, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
    assert.equal(reply.error.code, 'stale_id', JSON.stringify(spot));
  }
  rig.state.page.locate = () => onScreen;
  rig.state.page.boxOf = () => ({ inFrame: true });
  const framed = await ask(rig.ports[0], id++, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(framed.error.code, 'stale_id', 'target in a frame');
  assert.equal(presses(rig.state).length, 0);
});

test('a drag after the user stopped Companion on that tab is refused, onto an element or by pixels', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  for (const fn of rig.registered.detach) fn({ tabId: 3 }, 'canceled_by_user');
  const onto = await ask(rig.ports[0], 195, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  const by = await ask(rig.ports[0], 196, 'browser_drag', { tab: 3, generation, element: 1, dx: 10, dy: 0 });
  assert.equal(onto.error.code, 'debugger_revoked');
  assert.equal(by.error.code, 'debugger_revoked');
  assert.equal(presses(rig.state).length, 0);
});

test('something that slides in under the point during the glide stops the press, for a click and a drop', async () => {
  const rig = await boot({ tabs: userTabs() });
  let looks = 0;
  const generation = await readyPair(rig, { frame: () => ({ frame: false, same: ++looks === 1 }) });
  const click = await ask(rig.ports[0], 197, 'browser_click_at', { tab: 3, generation, x: 400, y: 300 });
  assert.equal(click.error.code, 'stale_id', 'click at');
  looks = 0;
  const drop = await ask(rig.ports[0], 198, 'browser_drag', { tab: 3, generation, element: 1, dx: 50, dy: 0 });
  assert.equal(drop.error.code, 'stale_id', 'drag by an offset');
  assert.equal(presses(rig.state).length, 0);
});

// The look at the drop must fail in the check phase, not the mark: a fake that fails the mark never reaches the check.
const dragSpots = [
  ['the source point', { element: 1, to: 2 }, { x: 40, y: 60 }],
  ['the drop point onto an element', { element: 1, to: 2 }, { x: 200, y: 300 }],
  ['the drop point of an offset', { element: 1, dx: 50, dy: 0 }, { x: 90, y: 60 }],
];

for (const [what, args, spot] of dragSpots) {
  test(`a drag is not pressed when something slides in under ${what} only at the check`, async () => {
    const rig = await boot({ tabs: userTabs() });
    const phases = [];
    const generation = await readyPair(rig, { frame: (x, y, token, phase) => {
      phases.push(phase);
      return { frame: false, same: !(phase === 'check' && x === spot.x && y === spot.y) };
    } });
    const reply = await ask(rig.ports[0], 211, 'browser_drag', { tab: 3, generation, ...args });
    assert.equal(reply.error?.code, 'stale_id');
    assert.ok(phases.includes('check'), 'the mark passed, so it was the check that stopped it');
    assert.equal(presses(rig.state).length, 0, 'nothing pressed');
    assert.equal(releases(rig.state).length, 0, 'nothing released');
  });

  test(`a frame that appears under ${what} only at the check stops the drag`, async () => {
    const rig = await boot({ tabs: userTabs() });
    const phases = [];
    const generation = await readyPair(rig, { frame: (x, y, token, phase) => {
      phases.push(phase);
      return { frame: phase === 'check' && x === spot.x && y === spot.y, same: true };
    } });
    const reply = await ask(rig.ports[0], 213, 'browser_drag', { tab: 3, generation, ...args });
    assert.equal(reply.error?.code, 'stale_id');
    assert.ok(phases.includes('check'), 'stopped at the check');
    assert.equal(presses(rig.state).length, 0, 'nothing pressed');
  });

  test(`the control: a drag whose ${what} is the same at every look is pressed`, async () => {
    const rig = await boot({ tabs: userTabs() });
    const generation = await readyPair(rig, { frame: () => ({ frame: false, same: true }) });
    const reply = await ask(rig.ports[0], 212, 'browser_drag', { tab: 3, generation, ...args });
    assert.deepEqual(reply.result, { done: 'dragged' });
    assert.equal(presses(rig.state).length, 1);
  });
}

test('a frame that appears at the point during the glide stops the press', async () => {
  const rig = await boot({ tabs: userTabs() });
  let looks = 0;
  const generation = await readyPair(rig, { frame: () => ({ frame: ++looks > 1, same: true }) });
  const reply = await ask(rig.ports[0], 199, 'browser_click_at', { tab: 3, generation, x: 400, y: 300 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(presses(rig.state).length, 0);
});

test('a click at the last pixel inside the page is pressed, and at the edge it is not', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig, { view: { w: 1000, h: 800 } });
  const edge = await ask(rig.ports[0], 200, 'browser_click_at', { tab: 3, generation, x: 1000, y: 300 });
  assert.equal(edge.error.code, 'stale_id', 'x equal to the width is past the page');
  const last = await ask(rig.ports[0], 201, 'browser_click_at', { tab: 3, generation, x: 999, y: 799 });
  assert.deepEqual(last.result, { done: 'clicked' });
});

test('a page that cannot say what is at the point is not pressed', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig, { frame: () => undefined });
  const click = await ask(rig.ports[0], 202, 'browser_click_at', { tab: 3, generation, x: 400, y: 300 });
  const drop = await ask(rig.ports[0], 203, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(click.error.code, 'stale_id');
  assert.equal(drop.error.code, 'stale_id');
  assert.equal(presses(rig.state).length, 0);
});

test('a drag source covered only once the cursor arrives is not pressed', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  let sourceChecks = 0;
  rig.state.stillHits = (id) => id !== 1 || ++sourceChecks === 1;
  const reply = await ask(rig.ports[0], 204, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(reply.error.code, 'stale_id');
  assert.ok(sourceChecks >= 2, 'checked again right before the press');
  assert.equal(presses(rig.state).length, 0);
});

test('a frame under the drag source is not pressed into', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig, { frame: (x, y) => ({ frame: x === 40 && y === 60, same: true }) });
  const reply = await ask(rig.ports[0], 205, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.equal(reply.error.code, 'stale_id');
  assert.equal(presses(rig.state).length, 0);
});

test('a drop point at the page edge or left of it is refused, and the last pixel is not', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig, { view: { w: 1000, h: 800 } });
  const edge = await ask(rig.ports[0], 206, 'browser_drag', { tab: 3, generation, element: 1, dx: 960, dy: 0 });
  assert.equal(edge.error.code, 'stale_id', 'x equal to the width');
  const left = await ask(rig.ports[0], 207, 'browser_drag', { tab: 3, generation, element: 1, dx: -100, dy: 0 });
  assert.equal(left.error.code, 'stale_id', 'left of the page');
  assert.equal(presses(rig.state).length, 0);
  const last = await ask(rig.ports[0], 208, 'browser_drag', { tab: 3, generation, element: 1, dx: 959, dy: 0 });
  assert.deepEqual(last.result, { done: 'dragged' });
});

test('each press marks its point before the glide and checks it right before pressing', async () => {
  const rig = await boot({ tabs: userTabs() });
  const phases = [];
  const generation = await readyPair(rig, { frame: (x, y, token, phase) => { phases.push(phase); return { frame: false, same: true }; } });
  await ask(rig.ports[0], 209, 'browser_click_at', { tab: 3, generation, x: 400, y: 300 });
  assert.deepEqual(phases, ['mark', 'check']);
});

test('a drag marks both ends before the glide and checks each against its own mark before pressing', async () => {
  const rig = await boot({ tabs: userTabs() });
  const looks = [];
  const generation = await readyPair(rig, { frame: (x, y, token, phase) => { looks.push({ x, y, token, phase }); return { frame: false, same: true }; } });
  const reply = await ask(rig.ports[0], 210, 'browser_drag', { tab: 3, generation, element: 1, to: 2 });
  assert.deepEqual(reply.result, { done: 'dragged' });
  assert.deepEqual(looks.map((l) => l.phase), ['mark', 'mark', 'check', 'check']);
  const [sourceMark, dropMark, sourceCheck, dropCheck] = looks;
  assert.deepEqual([sourceMark.x, sourceMark.y, dropMark.x, dropMark.y], [40, 60, 200, 300], 'source, then drop point');
  assert.notEqual(sourceMark.token, dropMark.token, 'one mark per end');
  assert.equal(sourceCheck.token, sourceMark.token);
  assert.equal(dropCheck.token, dropMark.token);
});

// --- Stale reasons and read history ---------------------------------------------------------------------
// The live symptom (2026-10-05): stale_id three times on a background tab with no read in between. One code
// for the model; the reason in the reply says which check refused, so the next live run names the cause.

const reasonOf = (reply) => [reply.error?.code, reply.error?.reason];

test('a click with no read, an unread generation or an unknown id names why it is stale', async () => {
  const rig = await boot({ tabs: userTabs() });
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 300, 'browser_click', { tab: 3, generation: 1, element: 1 })), ['stale_id', 'no_read']);
  const { generation } = await readyButton(rig, onScreen);
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 301, 'browser_click', { tab: 3, generation: generation + 7, element: 1 })), ['stale_id', 'generation_mismatch']);
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 302, 'browser_click', { tab: 3, generation, element: 9 })), ['stale_id', 'unknown_element']);
  assert.equal(presses(rig.state).length, 0);
});

test('a trusted click refused by the locate hit test names it blocked', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, { ...onScreen, blocked: true });
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 303, 'browser_click', { tab: 3, generation, element: 1 })), ['stale_id', 'blocked']);
  assert.equal(rig.state.locates, 3, 'located three times before giving up');
});

test('a trusted click covered while the cursor glided names it apart', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  rig.state.stillHits = false;
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 304, 'browser_click', { tab: 3, generation, element: 1 })), ['stale_id', 'covered_during_glide']);
});

test('a double click covered after its first press names it apart', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, onScreen);
  let checks = 0;
  rig.state.stillHits = () => ++checks === 1;
  const reply = await ask(rig.ports[0], 305, 'browser_double_click', { tab: 3, generation, element: 1 });
  assert.deepEqual(reasonOf(reply), ['stale_id', 'covered_after_first_press']);
  assert.match(reply.error.message, /pressed once/);
});

test('a page refusal keeps its own reason on the way out', async () => {
  const rig = await boot({ tabs: userTabs() });
  const changed = { error: { code: 'stale_id', message: 'element changed since the read, read the page again', reason: 'identity_changed' } };
  const { generation } = await readyButton(rig, changed);
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 306, 'browser_click', { tab: 3, generation, element: 1 })), ['stale_id', 'identity_changed']);
});

test('the synthetic fallback off screen keeps the page cover reason', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, { ...onScreen, inView: false });
  rig.state.page.click = () => ({ error: { code: 'stale_id', message: 'something covers this element (a dialog or banner); read the page again', reason: 'covered' } });
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 307, 'browser_click', { tab: 3, generation, element: 1 })), ['stale_id', 'covered']);
  assert.equal(presses(rig.state).length, 0);
});

test('a frame that stops answering and a tab that cannot be reached are told apart', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { generation } = await readyButton(rig, () => null);
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 308, 'browser_click', { tab: 3, generation, element: 1 })), ['stale_id', 'frame_gone']);
  const run = rig.chrome.scripting.executeScript;
  rig.chrome.scripting.executeScript = async (opts) => {
    if (opts.files) throw new Error('Cannot access contents of the page');
    return run(opts);
  };
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 309, 'browser_click', { tab: 3, generation, element: 1 })), ['stale_id', 'tab_gone']);
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 310, 'browser_read', { tab: 99 })), ['stale_id', 'tab_gone']);
});

test('a point refused by the page names why', async () => {
  const rig = await boot({ tabs: userTabs() });
  let frame = false;
  const generation = await readyPair(rig, { frame: () => ({ frame, same: true }) });
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 311, 'browser_click_at', { tab: 3, generation, x: 1200, y: 300 })), ['stale_id', 'not_in_view']);
  frame = true;
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 312, 'browser_click_at', { tab: 3, generation, x: 400, y: 300 })), ['stale_id', 'frame_at_point']);
});

// Two reads that differ: generation A shows "Uno", generation B shows "Dos", both as element 1.
async function twoReads(rig) {
  const labels = ['Uno', 'Dos'];
  let reads = 0;
  const located = [];
  rig.state.page = {
    read: () => {
      const label = labels[Math.min(reads++, 1)];
      return { origin: 'https://a.example', text: label, elements: [{ id: 1, frame: 0, role: 'button', label, context: '', inputType: null, autocomplete: null, value: null, frameOrigin: null, href: null, fieldName: null, fieldId: null }] };
    },
    locate: (g, id) => { located.push([g, id]); return onScreen; },
    hitsAt: () => true,
    landed: () => true,
  };
  const a = (await ask(rig.ports[0], 320, 'browser_read', { tab: 3 })).result.page.generation;
  const b = (await ask(rig.ports[0], 321, 'browser_read', { tab: 3 })).result.page.generation;
  return { a, b, located };
}

test('an id from a recent read of the tab still reaches its own generation in the page', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { a, b, located } = await twoReads(rig);
  assert.ok(b > a);
  const reply = await ask(rig.ports[0], 322, 'browser_click', { tab: 3, generation: a, element: 1 });
  assert.deepEqual(reply.result, { done: 'clicked' });
  assert.deepEqual(located.at(-1), [a, 1], 'the page checks it against the read it came from');
});

test('the 20th read back still clicks, bound to its own generation', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { a, located } = await twoReads(rig);
  for (let i = 0; i < 18; i++) await ask(rig.ports[0], 370 + i, 'browser_read', { tab: 3 });
  const reply = await ask(rig.ports[0], 390, 'browser_click', { tab: 3, generation: a, element: 1 });
  assert.deepEqual(reply.result, { done: 'clicked' });
  assert.deepEqual(located.at(-1), [a, 1]);
});

test('only the last 20 reads of a tab are kept', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { a } = await twoReads(rig);
  for (let i = 0; i < 19; i++) await ask(rig.ports[0], 330 + i, 'browser_read', { tab: 3 });
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 350, 'browser_click', { tab: 3, generation: a, element: 1 })), ['stale_id', 'generation_mismatch']);
  assert.equal(presses(rig.state).length, 0);
});

test('within and click_at still name only the last read', async () => {
  const rig = await boot({ tabs: userTabs() });
  const { a } = await twoReads(rig);
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 351, 'browser_read', { tab: 3, generation: a, within: 1 })), ['stale_id', 'generation_mismatch']);
  rig.state.page.viewport = () => ({ w: 1000, h: 800 });
  rig.state.page.pointAt = () => ({ frame: false, same: true });
  assert.deepEqual(reasonOf(await ask(rig.ports[0], 352, 'browser_click_at', { tab: 3, generation: a, x: 10, y: 10 })), ['stale_id', 'generation_mismatch']);
});

test('a read that finishes after a newer one does not take its place as the last read', async () => {
  const rig = await boot({ tabs: userTabs() });
  let release;
  const held = new Promise((resolve) => { release = resolve; });
  let reads = 0;
  const element = { id: 1, frame: 0, role: 'button', label: 'Go', context: '', inputType: null, autocomplete: null, value: null, frameOrigin: null, href: null, fieldName: null, fieldId: null };
  rig.state.page = {
    read: () => {
      const answer = { origin: 'https://a.example', text: 'Go', elements: [element] };
      return reads++ === 0 ? held.then(() => answer) : answer;
    },
    viewport: () => ({ w: 1000, h: 800 }),
    pointAt: () => ({ frame: false, same: true }),
  };
  rig.ports[0].receive(call(360, 'browser_read', { tab: 3 }));
  await settle();
  const newer = (await ask(rig.ports[0], 361, 'browser_read', { tab: 3 })).result.page.generation;
  release();
  await settle();
  await settle();
  const late = answersTo(rig.ports[0], 360)[0];
  assert.ok(late.result.page.generation < newer, 'the slow read started first');
  const reply = await ask(rig.ports[0], 362, 'browser_click_at', { tab: 3, generation: newer, x: 10, y: 10 });
  assert.deepEqual(reply.result, { done: 'clicked' });
});

test('a drag onto an id the read never listed is stale as unknown_element and presses nothing', async () => {
  const rig = await boot({ tabs: userTabs() });
  const generation = await readyPair(rig);
  const reply = await ask(rig.ports[0], 391, 'browser_drag', { tab: 3, generation, element: 1, to: 99 });
  assert.deepEqual(reasonOf(reply), ['stale_id', 'unknown_element']);
  assert.equal(presses(rig.state).length, 0);
});
