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
  };
  const trip = (name, args) => { if (state.failWhen(name, args)) throw new Error(`${name} failed`); };
  const created = [];
  const reindex = () => state.tabs.forEach((t, i) => { t.index = i; });
  const dropEmptyGroups = () => { state.groups = state.groups.filter((g) => state.tabs.some((t) => t.groupId === g.id)); };
  const findTab = (id) => state.tabs.find((t) => t.id === id);
  const ports = [];
  const registered = { alarm: [], startup: [], installed: [], removed: [], forbidden: [] };
  const listener = (bucket) => ({ addListener: (fn) => bucket.push(fn) });
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
      update: async () => ({}),
      create: async ({ url, active }) => {
        state.calls.push(['tabs.create', { url, active }]);
        const tab = { id: state.nextTab++, index: state.tabs.length, groupId: -1, windowId: 1, active: Boolean(active), title: '', url: '', pendingUrl: url };
        state.tabs.push(tab);
        for (const fn of created) fn({ ...tab });
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
    scripting: { executeScript: async () => [] },
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
  assert.deepEqual(reply.result, { tab: { id: 100, title: '', url: 'https://a.example/x', active: false } });
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
  assert.deepEqual(state.calls, [], 'no ungroup, no move');
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
