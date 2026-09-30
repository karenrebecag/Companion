// Chrome DevTools Protocol on the tabs Companion controls, and only those. Synthetic DOM events
// never reach a background tab the way a person's input does (isTrusted is false, focus does not
// move, and Chrome freezes the page), which is why the first version could not render a Lightning
// list or finish a search. Same mechanism Incredible uses.
//
// A factory, not module state: each worker (and each test) gets its own view of what is attached.

const VERSION = '1.3';
const ALREADY_ATTACHED = 'Another debugger is already attached';

export class RevokedError extends Error {
  constructor(tabId) {
    super('the user stopped Companion from controlling this tab (Cancel on the debugging banner)');
    this.code = 'debugger_revoked';
    this.tabId = tabId;
  }
}

const REVOKED_KEY = 'companionRevoked';

// `onDetached(tabId)` runs whenever Companion stops controlling a tab through the debugger, so the
// cursor never outlives the control it stands for.
export function createCdp(api = globalThis.chrome, { onDetached = () => {} } = {}) {
  const attached = new Set();
  const inflight = new Map();
  // The user's Cancel on Chrome's banner is a revocation that lasts as long as the tab: taking it
  // again needs no sheet in the chat, so letting a take lift it would let the model undo the user.
  // Session storage, not memory: a suspended worker must not forget it.
  const revoked = new Set();
  const store = api.storage?.session;
  const loaded = (async () => {
    const saved = store ? (await store.get(REVOKED_KEY).catch(() => ({})))[REVOKED_KEY] : null;
    for (const tabId of Array.isArray(saved) ? saved : []) revoked.add(tabId);
  })();
  const persist = () => store?.set({ [REVOKED_KEY]: [...revoked] }).catch(() => {});
  // One command at a time per tab: a mouse press and a key event from two calls must never interleave.
  const queues = new Map();

  const call = (fn) => new Promise((resolve, reject) => {
    fn((result) => {
      const error = api.runtime.lastError;
      if (error) reject(new Error(error.message));
      else resolve(result);
    });
  });

  const send = (tabId, method, params = {}) => call((cb) => api.debugger.sendCommand({ tabId }, method, params, cb));

  // A worker that was suspended loses its memory but not its attachments; those are ours to keep using.
  async function ourTargets() {
    const targets = await call((cb) => api.debugger.getTargets(cb)).catch(() => []);
    return (targets ?? []).filter((t) => Number.isInteger(t.tabId) && t.attached && t.extensionId === api.runtime.id)
      .map((t) => t.tabId);
  }

  async function ownedByUs(tabId) {
    return (await ourTargets()).includes(tabId);
  }

  async function isRevoked(tabId) {
    await loaded;
    return revoked.has(tabId);
  }

  async function ensureAttached(tabId) {
    if (await isRevoked(tabId)) throw new RevokedError(tabId);
    if (attached.has(tabId)) return;
    const running = inflight.get(tabId);
    if (running) return running;
    const task = (async () => {
      try {
        await call((cb) => api.debugger.attach({ tabId }, VERSION, cb));
      } catch (error) {
        if (!String(error?.message).includes(ALREADY_ATTACHED) || !(await ownedByUs(tabId))) throw error;
      }
      attached.add(tabId);
      await send(tabId, 'Page.enable').catch(() => {});
      // A background tab is frozen and its timers clamped; that stalls the page's own app logic
      // (Lightning renders one row, a search stays on "Loading"). Active keeps it running unseen.
      await send(tabId, 'Page.setWebLifecycleState', { state: 'active' }).catch(() => {});
    })().finally(() => inflight.delete(tabId));
    inflight.set(tabId, task);
    return task;
  }

  // An attachment a suspended worker left behind is not in memory, so Chrome is asked too; otherwise
  // its banner would stay up on a tab nobody controls.
  async function detach(tabId) {
    onDetached(tabId);
    const known = attached.delete(tabId);
    if (!known && !(await ownedByUs(tabId))) return;
    await call((cb) => api.debugger.detach({ tabId }, cb)).catch(() => {});
  }

  async function detachAll() {
    const tabIds = new Set([...attached, ...(await ourTargets())]);
    await Promise.all([...tabIds].map((tabId) => detach(tabId)));
  }

  function forget(tabId) {
    attached.delete(tabId);
    if (revoked.delete(tabId)) persist();
  }

  // Focus emulation lets trusted input land in a tab that is not the focused one.
  function withInput(tabId, fn) {
    const previous = queues.get(tabId) ?? Promise.resolve();
    const run = previous.catch(() => {}).then(async () => {
      await ensureAttached(tabId);
      await send(tabId, 'Emulation.setFocusEmulationEnabled', { enabled: true }).catch(() => {});
      try {
        return await fn();
      } finally {
        await send(tabId, 'Emulation.setFocusEmulationEnabled', { enabled: false }).catch(() => {});
      }
    });
    const settled = run.catch(() => {});
    queues.set(tabId, settled);
    settled.then(() => { if (queues.get(tabId) === settled) queues.delete(tabId); });
    return run;
  }

  async function mouseClick(tabId, x, y) {
    await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none', buttons: 0 });
    await send(tabId, 'Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', buttons: 1, clickCount: 1 });
    await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', buttons: 0, clickCount: 1 });
  }

  // keyDown/char/keyUp per character: live search, autocomplete and validation hear real keys.
  // Control characters are dropped: a real Return submits and Escape or Backspace edit, and none of
  // that is what typing was approved for.
  async function typeText(tabId, text) {
    for (const ch of Array.from(text)) {
      if (isControl(ch)) continue;
      await send(tabId, 'Input.dispatchKeyEvent', { type: 'keyDown', key: ch });
      await send(tabId, 'Input.dispatchKeyEvent', { type: 'char', text: ch });
      await send(tabId, 'Input.dispatchKeyEvent', { type: 'keyUp', key: ch });
    }
  }

  api.debugger?.onDetach?.addListener((source, reason) => {
    if (!Number.isInteger(source.tabId)) return;
    attached.delete(source.tabId);
    onDetached(source.tabId);
    if (reason === 'canceled_by_user') {
      revoked.add(source.tabId);
      persist();
    }
  });

  return { ensureAttached, detach, detachAll, forget, withInput, mouseClick, typeText, isRevoked };
}

export function isControl(ch) {
  const code = ch.codePointAt(0);
  return code < 0x20 || code === 0x7f;
}
