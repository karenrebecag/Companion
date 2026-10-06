import test, { mock, afterEach } from 'node:test';
import assert from 'node:assert/strict';

let importCount = 0;

function makeChrome({ tabs: seedTabs = [], stored = {} } = {}) {
  const state = {
    tabs: seedTabs.map((t) => ({ windowId: 1, groupId: -1, active: false, title: '', url: 'https://x.example/', ...t })),
    groups: [],
    stored: { ...stored },
    nextTab: 100,
    nextGroup: 500,
    calls: [],
    cdp: [],
    debugTargets: [],
    attachError: null,
    page: null,
    cursor: undefined,
    mainScripts: [],
  };
  const updated = [];
  const created = [];
  const registered = { alarm: [], startup: [], installed: [], removed: [], detach: [], event: [] };
  const ports = [];
  const listener = (bucket) => ({
    addListener: (fn) => bucket.push(fn),
    removeListener: (fn) => { if (bucket.includes(fn)) bucket.splice(bucket.indexOf(fn), 1); },
  });
  const findTab = (id) => state.tabs.find((t) => t.id === id);
  const reindex = () => state.tabs.forEach((t, i) => { t.index = i; });
  const dropEmptyGroups = () => { state.groups = state.groups.filter((g) => state.tabs.some((t) => t.groupId === g.id)); };
  const fireUpdated = (id, change) => { for (const fn of [...updated]) fn(id, change, {}); };
  const fireRemoved = (id) => { for (const fn of [...registered.removed]) fn(id, {}); };
  const fireEvent = (source, method, params) => { for (const fn of [...registered.event]) fn(source, method, params); };
  const chrome = {
    runtime: {
      id: 'gaipfdnbliibnfchgcnamnjpfgkilnll',
      lastError: undefined,
      getManifest: () => ({ version: '0.1.0' }),
      connectNative(host) {
        const port = {
          host, sent: [], messageListeners: [], disconnectListeners: [],
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
      onMessageExternal: listener(registered.forbidden = []),
      onConnectExternal: listener(registered.forbidden),
      onMessage: listener(registered.forbidden),
      onConnect: listener(registered.forbidden),
    },
    alarms: { create() {}, onAlarm: listener(registered.alarm) },
    tabs: {
      query: async (filter = {}) => state.tabs.filter((t) => filter.groupId === undefined || t.groupId === filter.groupId).map((t) => ({ ...t })),
      get: async (id) => {
        const tab = findTab(id);
        if (!tab) throw new Error('No tab with id: ' + id);
        return { ...tab };
      },
      update: async (id, props = {}) => {
        state.calls.push(['tabs.update', id]);
        if (state.sameDocument) Object.assign(findTab(id), { status: 'complete', url: props.url });
        else fireUpdated(id, { status: 'loading' });
        return {};
      },
      create: async ({ url, active }) => {
        state.calls.push(['tabs.create', { url, active }]);
        const tab = { id: state.nextTab++, index: state.tabs.length, groupId: -1, windowId: 1, active: Boolean(active), title: '', url: '', pendingUrl: url };
        state.tabs.push(tab);
        for (const fn of created) fn({ ...tab });
        fireUpdated(tab.id, { status: 'loading' });
        setImmediate(() => fireUpdated(tab.id, { status: 'complete' }));
        return { ...tab };
      },
      group: async ({ groupId, tabIds, createProperties }) => {
        let gid = groupId;
        if (gid === undefined) { gid = state.nextGroup++; state.groups.push({ id: gid, title: '', windowId: createProperties?.windowId ?? 1 }); }
        for (const id of tabIds) findTab(id).groupId = gid;
        dropEmptyGroups();
        return gid;
      },
      remove: async (ids) => { state.tabs = state.tabs.filter((t) => ![].concat(ids).includes(t.id)); reindex(); },
      ungroup: async (ids) => { for (const id of [].concat(ids)) findTab(id).groupId = -1; dropEmptyGroups(); },
      move: async (id, { index }) => { const [tab] = state.tabs.splice(state.tabs.indexOf(findTab(id)), 1); state.tabs.splice(index, 0, tab); reindex(); },
      onRemoved: listener(registered.removed),
      onCreated: { addListener: (fn) => created.push(fn) },
      onUpdated: { addListener: (fn) => updated.push(fn), removeListener: (fn) => { updated.splice(updated.indexOf(fn), 1); } },
    },
    tabGroups: {
      query: async (filter = {}) => state.groups.filter((g) => filter.windowId === undefined || g.windowId === filter.windowId).map((g) => ({ ...g })),
      update: async (id, props) => { Object.assign(state.groups.find((g) => g.id === id), props); },
      move: async () => {},
    },
    storage: { session: { get: async (key) => (key in state.stored ? { [key]: state.stored[key] } : {}), set: async (values) => { Object.assign(state.stored, values); } } },
    scripting: {
      executeScript: async ({ target, func, args, files, world }) => {
        if (files) {
          if (world === 'MAIN') state.mainScripts.push([target, files]);
          return [];
        }
        const pages = target.allFrames ? [[0, state.page]] : [[target.frameIds?.[0] ?? 0, state.page]];
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
      sendCommand(target, method, params, cb) {
        state.cdp.push([target.tabId, method, params]);
        // A debugger that refuses to accept: the answer must still fall back to staying put.
        if (state.refuseAccept && params?.accept === true) chrome.runtime.lastError = { message: 'refused' };
        cb({});
        chrome.runtime.lastError = undefined;
      },
      getTargets(cb) { cb(state.debugTargets); },
      onDetach: listener(registered.detach),
      onEvent: listener(registered.event),
    },
  };
  return { chrome, ports, registered, state, fireEvent, fireUpdated, fireRemoved };
}

async function boot(options) {
  mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  const rig = makeChrome(options);
  globalThis.chrome = rig.chrome;
  await import(`../background.js?case=${importCount++}`);
  return rig;
}

const settle = () => new Promise((resolve) => setImmediate(resolve));
const call = (id, name = 'browser_tabs', args = {}) => ({ id, method: 'call', params: { name, arguments: args } });
const ask = async (port, id, name, args) => {
  port.receive(call(id, name, args));
  for (let i = 0; i < 5; i++) await settle();
  return port.sent.filter((m) => m.id === id).at(-1);
};

afterEach(() => {
  mock.timers.reset();
  delete globalThis.chrome;
  delete globalThis.__companionPage;
  delete globalThis.__companionCursor;
});

const userTabs = () => [{ id: 1, index: 0 }, { id: 2, index: 1 }, { id: 3, index: 2 }];

async function openAndTake(rig, url) {
  const opened = await ask(rig.ports[0], 1, 'browser_open', { url });
  const tabId = opened.result.tab.id;
  await ask(rig.ports[0], 2, 'browser_take', { tab: tabId });
  return tabId;
}


const button = { id: 1, frame: 0, role: 'button', label: 'Go', context: '', inputType: null, autocomplete: null, value: null, frameOrigin: null, href: null, fieldName: null, fieldId: null, states: [], submit: null };
const clickablePage = (text = 'Go') => ({
  read: () => ({ origin: 'https://a.example', text, elements: [button] }),
  locate: () => ({ box: { x: 10, y: 20, w: 30, h: 10 }, inView: true, blocked: false, label: 'Go', role: 'button' }),
  hitsAt: () => true,
  landed: () => true,
  click: () => ({ done: 'clicked' }),
});
const fire = (rig, tabId, type, message = '', defaultPrompt = '') =>
  rig.fireEvent({ tabId }, 'Page.javascriptDialogOpening', { type, message, defaultPrompt, hasBrowserHandler: false, url: 'https://a.example/' });
const answers = (rig, tabId) => rig.state.cdp.filter(([t, m]) => t === tabId && m === 'Page.handleJavaScriptDialog').map(([, , p]) => p);
let nextId = 100;
const readTab = async (rig, tabId) => (await ask(rig.ports[0], nextId++, 'browser_read', { tab: tabId })).result;
const clickTab = async (rig, tabId, generation) => ask(rig.ports[0], nextId++, 'browser_click', { tab: tabId, generation, element: 1 });

test('T1 the answer sent to the browser follows the policy for every dialog kind', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  fire(rig, tabId, 'confirm', 'Delete this account?');
  fire(rig, tabId, 'prompt', 'Your name', 'Ana');
  fire(rig, tabId, 'beforeunload', 'Leave?');
  fire(rig, tabId, 'alert', 'Saved');
  assert.deepEqual(answers(rig, tabId), [
    { accept: false, promptText: '' },
    { accept: true, promptText: 'Ana' },
    { accept: false, promptText: '' },
    { accept: true, promptText: '' },
  ]);
});

test('S3 a destructive prompt is cancelled, never filled with the page default', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  fire(rig, tabId, 'prompt', 'Type DELETE to permanently delete the repo', 'DELETE');
  assert.deepEqual(answers(rig, tabId), [{ accept: false, promptText: '' }]);
});

test('D2 a beforeunload during Companion\'s own navigation is accepted; during anything else the page stays', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  rig.ports[0].receive(call(300, 'browser_navigate', { tab: tabId, url: 'https://a.example/next' }));
  await settle();
  fire(rig, tabId, 'beforeunload', 'Leave site?');
  assert.deepEqual(answers(rig, tabId), [{ accept: true, promptText: '' }]);
  mock.timers.tick(5000);
  await settle();
  fire(rig, tabId, 'beforeunload', 'Leave site?');
  assert.deepEqual(answers(rig, tabId).at(-1), { accept: false, promptText: '' }, 'after navigate ended the page stays');
  rig.state.page = clickablePage();
  const read = await readTab(rig, tabId);
  assert.equal(read.dialogs.length, 1, 'only the stay is reported to the model');
});

test('D2 a navigation the page refused to leave says so instead of still loading', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  rig.state.refuseAccept = true;
  rig.ports[0].receive(call(301, 'browser_navigate', { tab: tabId, url: 'https://a.example/next' }));
  await settle();
  fire(rig, tabId, 'beforeunload', 'Leave site?');
  await settle();
  mock.timers.tick(5000);
  await settle();
  const reply = rig.ports[0].sent.filter((m) => m.id === 301).at(-1);
  assert.equal(reply.result.done, 'the page asked to stay; Companion stayed');
});

test('D2 a slow navigation with no dialog still says still loading', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  rig.ports[0].receive(call(302, 'browser_navigate', { tab: tabId, url: 'https://a.example/next' }));
  await settle();
  mock.timers.tick(5000);
  await settle();
  assert.equal(rig.ports[0].sent.filter((m) => m.id === 302).at(-1).result.done, 'still loading');
});

test('S1 a dialog travels in its own field and never touches done or the page text', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  rig.state.page = clickablePage();
  const read = await readTab(rig, tabId);
  fire(rig, tabId, 'confirm', 'Delete this account?');
  const reply = await clickTab(rig, tabId, read.page.generation);
  assert.equal(reply.result.done, 'clicked');
  assert.deepEqual(reply.result.dialogs, [{ kind: 'confirm', answer: 'no', destructive: true, message: 'Delete this account?' }]);
  assert.equal(reply.result.more, 0);
  const again = await clickTab(rig, tabId, read.page.generation);
  assert.equal(again.result.dialogs, undefined, 'drained');
});

test('S1 T2 a read after navigation carries the dialog and the page text stays untouched', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  await ask(rig.ports[0], 310, 'browser_navigate', { tab: tabId, url: 'https://a.example/y' }).catch(() => {});
  rig.state.page = clickablePage('page body');
  fire(rig, tabId, 'confirm', 'Stay?');
  const read = await readTab(rig, tabId);
  assert.equal(read.page.text, 'page body');
  assert.equal(read.dialogs[0].message, 'Stay?');
  assert.equal(answers(rig, tabId).at(-1).accept, false);
});

test('an alert is answered but never reported', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  rig.state.page = clickablePage();
  const read = await readTab(rig, tabId);
  fire(rig, tabId, 'alert', 'Saved');
  assert.equal(answers(rig, tabId).at(-1).accept, true);
  assert.equal((await clickTab(rig, tabId, read.page.generation)).result.dialogs, undefined);
});

test('T3 hostile characters never reach the reported message', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  rig.state.page = clickablePage();
  const read = await readTab(rig, tabId);
  fire(rig, tabId, 'confirm', 'a‮b⁦c\u0085d؜e­f\u{E0041}g᠎h￹i');
  const { dialogs } = (await clickTab(rig, tabId, read.page.generation)).result;
  assert.equal(dialogs[0].message, 'abc defghi');
  assert.doesNotMatch(dialogs[0].message, /[\p{Cc}\p{Cf}\p{Co}\p{Cn}\p{Zl}\p{Zp}]/u);
});

test('T4 fifty dialogs on one tab report five and count the rest, then the next result is clean', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  rig.state.page = clickablePage();
  const read = await readTab(rig, tabId);
  for (let i = 0; i < 50; i++) fire(rig, tabId, 'confirm', `question ${i}`);
  assert.equal(answers(rig, tabId).length, 50, 'every dialog is answered');
  const { dialogs, more } = (await clickTab(rig, tabId, read.page.generation)).result;
  assert.equal(dialogs.length, 5);
  assert.equal(more, 45);
  assert.equal((await clickTab(rig, tabId, read.page.generation)).result.dialogs, undefined);
});

test('T5 a tab that is removed and reseeded starts without the old dialogs', async () => {
  const rig = await boot({ tabs: [...userTabs(), { id: 40, index: 3 }] });
  await ask(rig.ports[0], 320, 'browser_take', { tab: 40 });
  fire(rig, 40, 'confirm', 'old question');
  rig.fireRemoved(40);
  rig.state.tabs.push({ windowId: 1, groupId: -1, active: false, title: '', url: 'https://x.example/', id: 40, index: 3 });
  await ask(rig.ports[0], 321, 'browser_take', { tab: 40 });
  rig.state.page = clickablePage();
  const read = await readTab(rig, 40);
  assert.equal(read.dialogs, undefined);
});

test('releasing a tab drops what it had not reported yet', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  fire(rig, tabId, 'confirm', 'before release');
  await ask(rig.ports[0], 330, 'browser_release', { tab: tabId });
  await ask(rig.ports[0], 331, 'browser_take', { tab: tabId });
  rig.state.page = clickablePage();
  assert.equal((await readTab(rig, tabId)).dialogs, undefined);
});

test('T6 an empty page still carries the dialog and an error reply keeps it queued', async () => {
  const rig = await boot({ tabs: userTabs() });
  const tabId = await openAndTake(rig, 'https://a.example/');
  rig.state.page = clickablePage('');
  fire(rig, tabId, 'confirm', 'Stay?');
  const failed = await ask(rig.ports[0], 340, 'browser_click', { tab: tabId, generation: 1, element: 99 });
  assert.ok(failed.error, 'the click fails on a stale id');
  const read = await readTab(rig, tabId);
  assert.equal(read.page.text, '');
  assert.deepEqual(read.dialogs.map((d) => d.message), ['Stay?']);
});

test('S5 nothing is injected into the page world', async () => {
  const rig = await boot({ tabs: userTabs() });
  await openAndTake(rig, 'https://a.example/');
  assert.deepEqual(rig.state.mainScripts, []);
});
