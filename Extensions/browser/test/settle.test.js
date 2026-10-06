import test, { afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { observe, summarise, startSettle, finishSettle, QUIET_MS, CAP_MS, POLL_MS } from '../lib/settle.js';

const look = (url, overlays = {}) => ({ url, overlays: { dialog: 0, menu: 0, listbox: 0, ...overlays } });
const same = look('https://page.test/list?token=secret');

// A clock the test owns: sleep advances it, so no real time passes.
function clock() {
  let t = 0;
  return { now: () => t, sleep: async (ms) => { t += ms; }, at: () => t };
}

// --- summarise: one case per field of the structured fact -------------------

test('summarise reports a changed address as a flag, never as text', () => {
  const out = summarise({ before: same, after: look('https://page.test/orders?token=new'), count: 0 });
  assert.deepEqual(out, { navigated: false, urlChanged: true, opened: null, changed: true, fieldChars: null });
  assert.equal(JSON.stringify(out).includes('orders'), false);
  assert.equal(JSON.stringify(out).includes('token'), false);
});

test('summarise names which overlay kind newly opened', () => {
  for (const kind of ['dialog', 'menu', 'listbox']) {
    const out = summarise({ before: same, after: look(same.url, { [kind]: 1 }), count: 2 });
    assert.equal(out.opened, kind);
    assert.equal(out.changed, true);
  }
});

test('summarise does not call an overlay that was already open a new one', () => {
  const open = look(same.url, { dialog: 1 });
  assert.equal(summarise({ before: open, after: open, count: 0 }).opened, null);
});

test('summarise says nothing changed when the page was quiet', () => {
  assert.deepEqual(summarise({ before: same, after: same, count: 0 }),
    { navigated: false, urlChanged: false, opened: null, changed: false, fieldChars: null });
});

test('summarise marks changed when only mutations were seen', () => {
  const out = summarise({ before: same, after: same, count: 3 });
  assert.equal(out.changed, true);
  assert.equal(out.opened, null);
  assert.equal(out.urlChanged, false);
});

test('summarise carries the field length, which is a number and never the value', () => {
  const out = summarise({ before: same, after: same, count: 0, fieldChars: 8 });
  assert.equal(out.fieldChars, 8);
  assert.deepEqual(Object.keys(out).sort(), ['changed', 'fieldChars', 'navigated', 'opened', 'urlChanged']);
  assert.equal(summarise({ before: same, after: same, fieldChars: 'hunter2' }).fieldChars, null);
  assert.equal(summarise({ before: same, after: same, fieldChars: -1 }).fieldChars, null);
});

test('summarise on a navigation reports the page navigated', () => {
  assert.deepEqual(summarise({ navigated: true }),
    { navigated: true, urlChanged: true, opened: null, changed: true, fieldChars: null });
});

test('summarise has nothing to say when the page could not be observed', () => {
  assert.equal(summarise({ before: null, after: null }), null);
  assert.equal(summarise(), null);
  assert.equal(summarise({ fieldChars: 4 }).fieldChars, 4);
});

// --- settle timing with an injected clock ------------------------------------

const quietExec = (extra = {}) => async (_target, _fn, [mode]) => {
  if (mode === 'arm') return true;
  return { before: same, after: same, count: 0, ...extra };
};

test('the production budget is 300 ms quiet, 1500 ms cap, 50 ms poll', () => {
  assert.deepEqual([QUIET_MS, CAP_MS, POLL_MS], [300, 1500, 50]);
});

test('a page that stays quiet ends at the quiet window, far below the cap', async () => {
  const c = clock();
  const out = await finishSettle(quietExec(), null, { now: c.now, sleep: c.sleep });
  assert.equal(out.changed, false);
  assert.ok(c.at() >= QUIET_MS, 'waited the quiet window');
  assert.ok(c.at() <= QUIET_MS + POLL_MS, 'no-op latency stays near 350 ms');
});

test('mutations that keep arriving end at the cap and never later', async () => {
  const c = clock();
  let count = 0;
  const exec = async (_t, _f, [mode]) => {
    if (mode === 'peek') count += 1;
    return { before: same, after: same, count };
  };
  const out = await finishSettle(exec, null, { now: c.now, sleep: c.sleep });
  assert.equal(out.changed, true);
  assert.equal(c.at(), CAP_MS);
});

test('the quiet window restarts from the last mutation', async () => {
  const c = clock();
  const exec = async (_t, _f, [mode]) => ({ before: same, after: same, count: c.at() < 200 ? Math.floor(c.at() / 50) + 1 : 5, mode });
  const out = await finishSettle(exec, null, { now: c.now, sleep: c.sleep });
  assert.equal(out.changed, true);
  assert.ok(c.at() >= 200 + QUIET_MS - POLL_MS, 'quiet counted from the last change, not from the start');
  assert.ok(c.at() < CAP_MS);
});

test('an injection that throws mid-settle reports a navigation instead of throwing', async () => {
  const c = clock();
  const exec = async () => { throw new Error('Frame with ID 0 was removed.'); };
  const out = await finishSettle(exec, null, { now: c.now, sleep: c.sleep });
  assert.equal(out.navigated, true);
});

test('a new document that lost the armed state reports a navigation', async () => {
  const c = clock();
  const out = await finishSettle(async () => null, null, { now: c.now, sleep: c.sleep, fieldChars: 3 });
  assert.equal(out.navigated, true);
  assert.equal(out.fieldChars, 3);
});

test('startSettle is false, not a throw, when the page refuses injection', async () => {
  assert.equal(await startSettle(async () => { throw new Error('Cannot access a chrome:// URL'); }, null), false);
  assert.equal(await startSettle(async () => true, null), true);
});

// --- observe: the in-page half against a stand-in DOM -------------------------

let observers = [];
function installDom({ url = 'https://page.test/a', overlays = {} } = {}) {
  const dom = { url, overlays };
  const el = () => ({ checkVisibility: () => true });
  globalThis.location = { get href() { return dom.url; } };
  globalThis.document = {
    documentElement: {},
    querySelectorAll: (selector) => {
      if (selector === ':popover-open') throw new SyntaxError('unsupported');
      const kind = { '[role="dialog"]': 'dialog', '[role="menu"]': 'menu', '[role="listbox"]': 'listbox' }[selector];
      return Array.from({ length: kind ? dom.overlays[kind] ?? 0 : 0 }, el);
    },
  };
  globalThis.MutationObserver = class {
    constructor(cb) { this.cb = cb; this.live = true; observers.push(this); }
    observe(_node, options) { this.options = options; }
    disconnect() { this.live = false; }
  };
  return dom;
}
afterEach(() => {
  observers = [];
  for (const k of ['location', 'document', 'MutationObserver', '__companionSettle']) delete globalThis[k];
});

test('observe watches only the short attribute list and counts mutations', () => {
  installDom();
  assert.equal(observe('arm'), true);
  const [o] = observers;
  assert.deepEqual(o.options.attributeFilter, ['aria-expanded', 'aria-selected', 'aria-checked', 'open', 'hidden', 'class', 'value']);
  assert.equal(o.options.subtree, true);
  o.cb([{}, {}]);
  assert.equal(observe('peek').count, 2);
});

test('observe sees an overlay that appeared and survives an engine without :popover-open', () => {
  const dom = installDom();
  observe('arm');
  dom.overlays = { menu: 1 };
  const out = observe('end');
  assert.deepEqual(summarise(out), { navigated: false, urlChanged: false, opened: 'menu', changed: true, fieldChars: null });
});

test('observe end disconnects and clears, and a later read finds no state', () => {
  installDom();
  observe('arm');
  observe('end');
  assert.equal(observers[0].live, false);
  assert.equal(observe('peek'), null);
});

test('observe peek reports an address change made by the page', () => {
  const dom = installDom();
  observe('arm');
  dom.url = 'https://page.test/b';
  assert.equal(summarise(observe('peek')).urlChanged, true);
});
