import test, { mock, afterEach } from 'node:test';
import assert from 'node:assert/strict';

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
