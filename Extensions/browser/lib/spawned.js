// Helpers for tabs the site opens in response to a Companion action.
// Pure logic (matchesAction, shouldRestore, spawnedField) plus a small stateful
// watcher that listens to chrome.tabs.onCreated and arms/awaits per action.

// The five tools that can cause a page to open a new tab (click, double click,
// press, type, select). Other tools (hover, scroll, drag, navigate) are ignored
// because they cannot create a tab on their own.
export const SPAWN_TOOLS = Object.freeze(new Set([
  'browser_click',
  'browser_double_click',
  'browser_press',
  'browser_type',
  'browser_select',
]));

export const SPAWN_WINDOW_MS = 2000;

export function isSpawnTool(name) {
  return SPAWN_TOOLS.has(name);
}

const isInt = Number.isInteger;

// Snapshot of "what the user was looking at" before it changed: the tab they
// had active, in the window where the action will land.
export function armWatch({ tabId, windowId, prevActiveId = null, now }) {
  return {
    tabId: isInt(tabId) ? tabId : null,
    windowId: isInt(windowId) ? windowId : null,
    prevActiveId: isInt(prevActiveId) ? prevActiveId : null,
    startTime: isInt(now) ? now : null,
  };
}

// Is this onCreated event the action's own spawn? Same opener and inside the
// 2 s window. Outside the window we forget the watch so a late birth from the
// user (a Ctrl+T they pressed later) is never blamed on us.
export function matchesAction({ watch, spawn, now }) {
  if (!watch || !spawn) return false;
  if (!isInt(watch.tabId) || !isInt(watch.startTime)) return false;
  if (spawn.openerTabId !== watch.tabId) return false;
  if (!isInt(now)) return false;
  return now - watch.startTime <= SPAWN_WINDOW_MS;
}

// Should we put the previous active tab back in front? Only when the new tab
// is active in the same window AND we recorded a tab to restore. Anything else
// (background tab, other window, no recorded prev) is left alone.
export function shouldRestore({ watch, spawned }) {
  if (!watch || !spawned) return false;
  if (!isInt(watch.windowId) || spawned.windowId !== watch.windowId) return false;
  if (spawned.active !== true) return false;
  if (!isInt(watch.prevActiveId)) return false;
  return true;
}

export const SPAWN_TITLE_MAX = 80;

// The title is page text, so it is one short line; the host cleans it again before the model sees it.
export function spawnedField({ id, title }) {
  const line = String(title ?? '').replace(/\s+/g, ' ').trim();
  return { tab: id, title: line.slice(0, SPAWN_TITLE_MAX) };
}

// STATEFUL: a per-call watcher that listens to onCreated for a short window.
// One onCreated listener is shared across all watches; per-call state is held
// in the returned watcher, which background.js calls from the dispatch path.
export function createSpawnWatcher({ chrome }) {
  const watches = new Map();
  let listener = null;

  const fire = (tab) => {
    for (const watch of watches.values()) {
      if (matchesAction({ watch, spawn: tab, now: Date.now() })) {
        watch.spawn = tab;
        const waiters = watch.waiters;
        watch.waiters = null;
        if (waiters) for (const resolve of waiters) resolve(tab);
        return;
      }
    }
  };

  return {
    attach() {
      if (listener || !chrome?.tabs?.onCreated?.addListener) return;
      listener = fire;
      chrome.tabs.onCreated.addListener(listener);
    },

    // Build a watch for this call: capture the prev active tab BEFORE the click,
    // so even a click that takes a frame to settle knows what to put back.
    async arm(callId, tabId) {
      if (!Number.isInteger(tabId)) return null;
      let tab = null;
      try { tab = await chrome.tabs.get(tabId); } catch { return null; }
      if (!tab) return null;
      let active = [];
      try { active = await chrome.tabs.query({ active: true, windowId: tab.windowId }); } catch { active = []; }
      const watch = armWatch({
        tabId: tab.id, windowId: tab.windowId, prevActiveId: active[0]?.id ?? null, now: Date.now(),
      });
      watches.set(callId, watch);
      this.attach();
      return watch;
    },

    // Wait up to maxMs for a spawn matching the watch. Resolves with the
    // spawned tab (if any) so the caller can amend its reply.
    awaitSpawn(callId, maxMs) {
      const watch = watches.get(callId);
      if (!watch) return Promise.resolve(null);
      if (watch.spawn) return Promise.resolve(watch.spawn);
      return new Promise((resolve) => {
        watch.waiters = watch.waiters || [];
        watch.waiters.push(resolve);
        watch.timer = setTimeout(() => {
          const w = watches.get(callId);
          if (!w || !w.waiters) return;
          const waiters = w.waiters;
          const spawn = w.spawn || null;
          w.waiters = null;
          for (const r of waiters) r(spawn);
        }, maxMs);
      });
    },

    // Drop the watch: the reply has gone out, no spawn listener should fire.
    release(callId) {
      const watch = watches.get(callId);
      if (!watch) return;
      watches.delete(callId);
      if (watch.timer) clearTimeout(watch.timer);
      if (watch.waiters) {
        const waiters = watch.waiters;
        watch.waiters = null;
        for (const r of waiters) r(null);
      }
    },
  };
}

// STATEFUL: do the actual restore + group, returning the new reply or null.
// Why this is here and not inline in background.js: keeping every chrome side
// effect in one module means the watcher in test/spawned.test.js can call it
// against a fake chrome without reaching into background.js's internals.
export async function applySpawnRestore({ watch, spawned, chrome, group }) {
  if (!shouldRestore({ watch, spawned })) return null;
  // Only the tab is re-activated, never the window: the person may be in another app.
  if (Number.isInteger(watch.prevActiveId)) {
    try { await chrome.tabs.update(watch.prevActiveId, { active: true }); }
    catch (error) { console.warn('companion: could not restore previous tab', error?.message); }
  }
  // Group the new tab so the agent can pick it up; failures here are logged,
  // not raised, because the user already saw the restore happen.
  try { await group({ id: spawned.id, windowId: spawned.windowId, index: -1, groupId: -1 }); }
  catch (error) { console.warn('companion: could not group spawned tab', error?.message); }
  return { spawned: spawnedField(spawned) };
}