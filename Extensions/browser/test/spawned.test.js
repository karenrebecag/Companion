import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SPAWN_TOOLS, SPAWN_WINDOW_MS, SPAWN_TITLE_MAX, isSpawnTool, armWatch, matchesAction, shouldRestore, spawnedField,
  createSpawnWatcher, applySpawnRestore,
} from '../lib/spawned.js';

test('SPAWN_TOOLS lists the five actions that can open a tab', () => {
  assert.deepEqual([...SPAWN_TOOLS].sort(),
    ['browser_click', 'browser_double_click', 'browser_press', 'browser_select', 'browser_type'].sort());
  assert.equal(SPAWN_WINDOW_MS, 2000, '2 s window matches the spec');
});

test('isSpawnTool accepts the five and rejects the rest', () => {
  for (const name of ['browser_click', 'browser_double_click', 'browser_press', 'browser_type', 'browser_select']) {
    assert.equal(isSpawnTool(name), true, name);
  }
  for (const name of ['browser_tabs', 'browser_read', 'browser_hover', 'browser_scroll', 'browser_drag', 'browser_right_click']) {
    assert.equal(isSpawnTool(name), false, name);
  }
});

test('armWatch stores the snapshot of what the user was looking at before the action', () => {
  const watch = armWatch({ tabId: 5, windowId: 9, prevActiveId: 5, now: 1000 });
  assert.deepEqual(watch, { tabId: 5, windowId: 9, prevActiveId: 5, startTime: 1000 });
});

test('armWatch leaves prevActiveId null when the user was not looking at any tab', () => {
  const watch = armWatch({ tabId: 5, windowId: 9, now: 1000 });
  assert.equal(watch.prevActiveId, null);
});

test('matchesAction says yes only when openerTabId equals the acted tab and the time is inside the window', () => {
  const watch = armWatch({ tabId: 5, windowId: 9, prevActiveId: 5, now: 1000 });
  assert.equal(matchesAction({ watch, spawn: { openerTabId: 5 }, now: 1500 }), true);
  assert.equal(matchesAction({ watch, spawn: { openerTabId: 5 }, now: 1000 + SPAWN_WINDOW_MS }), true, 'on the edge');
  assert.equal(matchesAction({ watch, spawn: { openerTabId: 5 }, now: 1000 + SPAWN_WINDOW_MS + 1 }), false, 'just past');
  assert.equal(matchesAction({ watch, spawn: { openerTabId: 7 }, now: 1500 }), false, 'other opener');
  assert.equal(matchesAction({ watch, spawn: {}, now: 1500 }), false, 'no opener at all');
  assert.equal(matchesAction({ watch, spawn: { openerTabId: 5 }, now: undefined }), false, 'no clock');
  assert.equal(matchesAction({ watch: null, spawn: { openerTabId: 5 }, now: 1500 }), false, 'no watch');
});

test('shouldRestore says yes only when the new tab is active in the same window and we know what to put back', () => {
  const watch = armWatch({ tabId: 5, windowId: 9, prevActiveId: 7, now: 1000 });
  assert.equal(shouldRestore({ watch, spawned: { id: 12, windowId: 9, active: true } }), true);
  assert.equal(shouldRestore({ watch, spawned: { id: 12, windowId: 9, active: false } }), false, 'in the background');
  assert.equal(shouldRestore({ watch, spawned: { id: 12, windowId: 8, active: true } }), false, 'other window');
  assert.equal(shouldRestore({ watch, spawned: { id: 12, windowId: 9, active: true, openerTabId: 5 } }), true, 'openerTabId does not gate restore');
  const noPrev = armWatch({ tabId: 5, windowId: 9, now: 1000 });
  assert.equal(shouldRestore({ watch: noPrev, spawned: { id: 12, windowId: 9, active: true } }), false, 'no prev to put back');
  assert.equal(shouldRestore({ watch, spawned: null }), false);
  assert.equal(shouldRestore({ watch: null, spawned: { id: 12, windowId: 9, active: true } }), false);
});

test('spawnedField carries the tab id and a one-line title capped for the model', () => {
  assert.deepEqual(spawnedField({ id: 12, title: 'Receipt' }), { tab: 12, title: 'Receipt' });
  assert.deepEqual(spawnedField({ id: 12 }), { tab: 12, title: '' }, 'no title is an empty one');
  assert.equal(spawnedField({ id: 12, title: 'a\nb\t  c' }).title, 'a b c', 'breaks collapse');
  assert.equal(spawnedField({ id: 12, title: 'x'.repeat(500) }).title.length, SPAWN_TITLE_MAX);
});

// --- stateful helpers ---------------------------------------------------------

// Tiny chrome stand-in: enough to arm, fire, and restore. The watcher only
// needs onCreated, tabs.get, tabs.query, tabs.update.
function makeChrome() {
  const createdListeners = [];
  const updates = [];
  const grouped = [];
  const tabs = new Map();
  let nextId = 1;
  return {
    updates,
    grouped,
    addTab(tab) { tabs.set(tab.id, tab); return tab; },
    fireCreated(tab) { for (const fn of [...createdListeners]) fn(tab); },
    chrome: {
      tabs: {
        onCreated: { addListener: (fn) => createdListeners.push(fn) },
        get: async (id) => {
          const t = tabs.get(id);
          if (!t) throw new Error('no tab ' + id);
          return { ...t };
        },
        query: async (filter) => {
          const out = [];
          for (const t of tabs.values()) {
            if (filter.windowId !== undefined && t.windowId !== filter.windowId) continue;
            if (filter.active !== undefined && Boolean(t.active) !== Boolean(filter.active)) continue;
            out.push({ ...t });
          }
          return out;
        },
        update: async (id, props) => {
          updates.push([id, props]);
          const t = tabs.get(id);
          if (!t) throw new Error('no tab ' + id);
          Object.assign(t, props);
          return { ...t };
        },
      },
    },
  };
}

test('arm captures the tab the user had active before the click, awaitSpawn resolves on a matching onCreated', async () => {
  const rig = makeChrome();
  rig.addTab({ id: 5, windowId: 9, groupId: -1, active: true });
  rig.addTab({ id: 7, windowId: 9, groupId: -1, active: false });
  const watcher = createSpawnWatcher({ chrome: rig.chrome });
  const watch = await watcher.arm(11, 5);
  assert.equal(watch.tabId, 5);
  assert.equal(watch.windowId, 9);
  assert.equal(watch.prevActiveId, 5);
  const pending = watcher.awaitSpawn(11, 1000);
  rig.fireCreated({ id: 12, windowId: 9, openerTabId: 5, active: true, title: 'Receipt' });
  const spawn = await pending;
  assert.equal(spawn.id, 12);
  assert.equal(spawn.openerTabId, 5);
  assert.equal(spawn.title, 'Receipt');
  watcher.release(11);
});

test('awaitSpawn resolves with null when no spawn arrives within the window', async () => {
  const rig = makeChrome();
  rig.addTab({ id: 5, windowId: 9, groupId: -1, active: true });
  const watcher = createSpawnWatcher({ chrome: rig.chrome });
  await watcher.arm(11, 5);
  const spawn = await watcher.awaitSpawn(11, 20);
  assert.equal(spawn, null);
  watcher.release(11);
});

test('awaitSpawn ignores an onCreated with a different openerTabId, and one outside the window', async () => {
  const rig = makeChrome();
  rig.addTab({ id: 5, windowId: 9, groupId: -1, active: true });
  const watcher = createSpawnWatcher({ chrome: rig.chrome });
  await watcher.arm(11, 5);
  // Different opener.
  const a = watcher.awaitSpawn(11, 1000);
  rig.fireCreated({ id: 100, windowId: 9, openerTabId: 7, active: true });
  assert.deepEqual(rig.updates, [], 'restored nothing yet');
  // No opener at all (the user opened it).
  rig.fireCreated({ id: 101, windowId: 9, active: true });
  assert.deepEqual(rig.updates, [], 'no opener: not the action\'s spawn');
  // Outside the window.
  await new Promise((r) => setTimeout(r, SPAWN_WINDOW_MS + 5));
  rig.fireCreated({ id: 102, windowId: 9, openerTabId: 5, active: true });
  const spawn = await a;
  assert.equal(spawn, null);
  watcher.release(11);
});

test('awaitSpawn fires only once even if two spawns match the same watch', async () => {
  const rig = makeChrome();
  rig.addTab({ id: 5, windowId: 9, groupId: -1, active: true });
  const watcher = createSpawnWatcher({ chrome: rig.chrome });
  await watcher.arm(11, 5);
  const pending = watcher.awaitSpawn(11, 200);
  rig.fireCreated({ id: 12, windowId: 9, openerTabId: 5, active: true });
  rig.fireCreated({ id: 13, windowId: 9, openerTabId: 5, active: true });
  const spawn = await pending;
  assert.equal(spawn.id, 12);
  watcher.release(11);
});

test('release stops a pending awaitSpawn and clears the timer', async () => {
  const rig = makeChrome();
  rig.addTab({ id: 5, windowId: 9, groupId: -1, active: true });
  const watcher = createSpawnWatcher({ chrome: rig.chrome });
  await watcher.arm(11, 5);
  const pending = watcher.awaitSpawn(11, 1000);
  watcher.release(11);
  const spawn = await pending;
  assert.equal(spawn, null);
});

test('applySpawnRestore updates the prev active tab, groups the new tab, and returns the reply', async () => {
  const rig = makeChrome();
  rig.addTab({ id: 7, windowId: 9, groupId: -1, active: false });
  rig.addTab({ id: 12, windowId: 9, groupId: -1, active: true });
  const watch = armWatch({ tabId: 5, windowId: 9, prevActiveId: 7, now: Date.now() });
  const spawned = { id: 12, windowId: 9, openerTabId: 5, active: true, title: 'Receipt' };
  const group = async (tab) => rig.grouped.push(tab);
  const reply = await applySpawnRestore({ watch, spawned, chrome: rig.chrome, group });
  assert.deepEqual(reply, { spawned: { tab: 12, title: 'Receipt' } });
  assert.deepEqual(rig.updates, [[7, { active: true }]], 're-activates prev, no focused:true');
  assert.deepEqual(rig.grouped.map((t) => [t.id, t.windowId]), [[12, 9]], 'new tab added to group');
});

test('applySpawnRestore does nothing when the new tab is not active in the same window', async () => {
  const rig = makeChrome();
  rig.addTab({ id: 12, windowId: 9, groupId: -1, active: false });
  const watch = armWatch({ tabId: 5, windowId: 9, prevActiveId: 7, now: Date.now() });
  const reply = await applySpawnRestore({
    watch, spawned: { id: 12, windowId: 9, active: false }, chrome: rig.chrome, group: async () => {},
  });
  assert.equal(reply, null);
  assert.deepEqual(rig.updates, []);
});

test('applySpawnRestore returns null when shouldRestore says no', async () => {
  const rig = makeChrome();
  const watch = armWatch({ tabId: 5, windowId: 9, prevActiveId: 7, now: Date.now() });
  for (const spawned of [null, { id: 12, windowId: 8, active: true }, { id: 12, windowId: 9, active: false }]) {
    const reply = await applySpawnRestore({ watch, spawned, chrome: rig.chrome, group: async () => {} });
    assert.equal(reply, null, JSON.stringify(spawned));
  }
  // No prev to put back: still null even with a perfect match otherwise.
  const noPrev = armWatch({ tabId: 5, windowId: 9, now: Date.now() });
  const reply = await applySpawnRestore({
    watch: noPrev, spawned: { id: 12, windowId: 9, active: true }, chrome: rig.chrome, group: async () => {},
  });
  assert.equal(reply, null);
});