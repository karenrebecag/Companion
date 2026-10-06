// Chrome DevTools Protocol on the tabs Companion controls, and only those. Synthetic DOM events
// never reach a background tab the way a person's input does (isTrusted is false, focus does not
// move, and Chrome freezes the page), which is why the first version could not render a Lightning
// list or finish a search. Same mechanism Incredible uses.
//
// A factory, not module state: each worker (and each test) gets its own view of what is attached.

const VERSION = '1.3';
const ALREADY_ATTACHED = 'Another debugger is already attached';
// Enough intermediate moves for a sortable list or a slider to follow the pointer.
const DRAG_STEPS = 10;

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

  // One stream per tab for trusted input and file setting. Interleaving a click with
  // setFileInputFiles would focus the tab and rewrite the DOM at the same time.
  function serial(tabId, fn) {
    const previous = queues.get(tabId) ?? Promise.resolve();
    const run = previous.catch(() => {}).then(fn);
    const settled = run.catch(() => {});
    queues.set(tabId, settled);
    settled.then(() => { if (queues.get(tabId) === settled) queues.delete(tabId); });
    return run;
  }

  // Focus emulation lets trusted input land in a tab that is not the focused one.
  function withInput(tabId, fn) {
    return serial(tabId, async () => {
      await ensureAttached(tabId);
      await send(tabId, 'Emulation.setFocusEmulationEnabled', { enabled: true }).catch(() => {});
      try {
        return await fn();
      } finally {
        await send(tabId, 'Emulation.setFocusEmulationEnabled', { enabled: false }).catch(() => {});
      }
    });
  }

  // The one pierced walk is the only lookup: a shortcut through the top document would let a page
  // plant a second marker inside a shadow root and have it go unseen. Frame documents are skipped,
  // since a frame is a different target from the element the read approved.
  async function markedNodes(tabId, selector, pinnedOrigin) {
    const deep = await send(tabId, 'DOM.getDocument', { depth: -1, pierce: true });
    if (originOf(deep?.root?.documentURL) !== pinnedOrigin) return [];
    const seen = new Set();
    const walk = async (node, frameDocument) => {
      if (!node || frameDocument || !Number.isInteger(node.nodeId)) return;
      if (node.nodeType === 9 || node.nodeType === 11 || node.shadowRootType) {
        for (const id of await queryAll(tabId, node.nodeId, selector)) seen.add(id);
      }
      for (const child of node.children ?? []) await walk(child, false);
      for (const shadow of node.shadowRoots ?? []) await walk(shadow, false);
      if (node.contentDocument) await walk(node.contentDocument, true);
    };
    await walk(deep?.root, false);
    return [...seen];
  }

  async function queryAll(tabId, nodeId, selector) {
    const out = await send(tabId, 'DOM.querySelectorAll', { nodeId, selector });
    return Array.isArray(out?.nodeIds) ? out.nodeIds.filter((id) => Number.isInteger(id)) : [];
  }

  async function mainFrame(tabId) {
    const tree = await send(tabId, 'Page.getFrameTree');
    const frame = tree?.frameTree?.frame;
    return { loaderId: frame?.loaderId, origin: originOf(frame?.url) };
  }

  const changed = { error: { code: 'target_changed', message: 'the file field no longer matches the read' } };

  // Only a gone debugger is the debugger's fault; a node or argument error means the field is not
  // the one that was approved, and a refused file read is the file-access toggle.
  function setFailure(error) {
    const message = String(error?.message ?? error);
    if (/detach|not attached|closed|no tab/i.test(message)) throw error;
    if (/not allowed/i.test(message)) return { error: { code: 'file_access_required', message: 'Allow access to file URLs' } };
    return changed;
  }

  // `mark` stamps the page and answers `{ marker }` or an error reply. It runs only after the pin,
  // inside the same queue slot: the page can read the marker the moment it exists, so a pin taken
  // later could already describe an attacker's document that was handed the marker in its URL.
  // `check` confirms the file landed and `clear` removes the marker; both stay in the slot so a
  // queued click cannot run against a page that still carries the marker.
  function setFileInputFiles(tabId, path, { mark, check, clear }) {
    return serial(tabId, async () => {
      try {
        await ensureAttached(tabId);
        const pinned = await mainFrame(tabId);
        if (!pinned.loaderId || !pinned.origin) return changed;
        const stamp = await mark();
        if (!stamp || stamp.error) return stamp;
        const selector = markerSelector(stamp.marker);
        if (!selector) return changed;
        const target = await locateInput(tabId, selector, pinned.origin);
        if (target.error) return target;
        const now = await mainFrame(tabId);
        if (now.loaderId !== pinned.loaderId || now.origin !== pinned.origin) return changed;
        try {
          await send(tabId, 'DOM.setFileInputFiles', { nodeId: target.nodeId, files: [path] });
        } catch (error) {
          return setFailure(error);
        }
        return await check();
      } finally {
        await clear();
      }
    });
  }

  // The one marked node, or the reply that refuses it. Walk and describe errors map like the set's.
  async function locateInput(tabId, selector, origin) {
    try {
      const ids = await markedNodes(tabId, selector, origin);
      if (ids.length !== 1) return changed;
      const described = await send(tabId, 'DOM.describeNode', { nodeId: ids[0] });
      const node = described?.node;
      const tag = String(node?.nodeName ?? '').toLowerCase();
      if (tag !== 'input' || attrValue(node, 'type').toLowerCase() !== 'file') {
        return { error: { code: 'not_file_input', message: 'the element is not a file input' } };
      }
      return { nodeId: ids[0] };
    } catch (error) {
      return setFailure(error);
    }
  }

  // Chrome reads a double click from two press pairs whose clickCount climbs 1, 2; one pair counted 2 is not one.
  // `beforeRepeat` answers whether the next press may go: false stops the gesture and the call returns false.
  async function mouseClick(tabId, x, y, { button = 'left', count = 1, beforeRepeat = null } = {}) {
    const held = button === 'right' ? 2 : 1;
    await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none', buttons: 0 });
    for (let clickCount = 1; clickCount <= count; clickCount++) {
      if (clickCount > 1 && beforeRepeat && !(await beforeRepeat())) return false;
      await send(tabId, 'Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button, buttons: held, clickCount });
      await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button, buttons: 0, clickCount });
    }
    return true;
  }

  // Press, move in steps holding the button, release: a single jump reads as a click elsewhere, not a drag.
  async function mouseDrag(tabId, from, to, steps = DRAG_STEPS) {
    await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseMoved', x: from.x, y: from.y, button: 'none', buttons: 0 });
    await send(tabId, 'Input.dispatchMouseEvent', { type: 'mousePressed', x: from.x, y: from.y, button: 'left', buttons: 1, clickCount: 1 });
    let at = from;
    try {
      for (let step = 1; step <= steps; step++) {
        at = { x: from.x + ((to.x - from.x) * step) / steps, y: from.y + ((to.y - from.y) * step) / steps };
        await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseMoved', x: at.x, y: at.y, button: 'left', buttons: 1 });
      }
    } catch (error) {
      // A button left down would stay down in the page; the move's error is the one worth reporting.
      await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseReleased', x: at.x, y: at.y, button: 'left', buttons: 0, clickCount: 1 }).catch(() => {});
      throw error;
    }
    await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseReleased', x: to.x, y: to.y, button: 'left', buttons: 0, clickCount: 1 });
  }

  async function mouseMove(tabId, x, y) {
    await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none', buttons: 0 });
  }

  // A wheel scrolls whatever is scrollable under the point, as a trackpad does, not only the document.
  // It carries its own point: moving the pointer there first would hover whatever sits at the center.
  async function mouseWheel(tabId, x, y, deltaX, deltaY) {
    await send(tabId, 'Input.dispatchMouseEvent', { type: 'mouseWheel', x, y, deltaX, deltaY });
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

  // Only Enter and Space carry text: that is what makes them submit and activate, where the
  // others reach the page as bare key presses.
  async function pressKey(tabId, name) {
    const spec = KEYS[name];
    if (!spec) throw new Error(`unknown key ${name}`);
    const base = { key: spec.key, code: spec.code, windowsVirtualKeyCode: spec.vk, modifiers: spec.modifiers ?? 0 };
    await send(tabId, 'Input.dispatchKeyEvent', spec.text
      ? { ...base, type: 'keyDown', text: spec.text }
      : { ...base, type: 'rawKeyDown' });
    await send(tabId, 'Input.dispatchKeyEvent', { ...base, type: 'keyUp' });
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

  // Native page dialogs freeze a tab until something answers, so every one gets an answer from the
  // registered policy; when the policy or the browser fails the answer is "no", never silence.
  let dialogHandler = null;
  let dialogAnswered = null;
  function onJavaScriptDialog(handler, answered = null) {
    dialogHandler = handler;
    dialogAnswered = answered;
  }
  const STAY = Object.freeze({ accept: false, promptText: '' });

  async function answerDialog(tabId, dialog) {
    let decision = STAY;
    try {
      const picked = dialogHandler(dialog);
      if (picked) decision = { accept: Boolean(picked.accept), promptText: picked.promptText == null ? '' : String(picked.promptText) };
    } catch (error) {
      console.warn('companion: dialog policy failed, answering no', error?.message);
    }
    let sent = decision;
    try {
      await send(tabId, 'Page.handleJavaScriptDialog', decision);
    } catch (error) {
      console.warn('companion: could not answer a dialog, retrying as no', error?.message);
      sent = STAY;
      if (decision.accept) await send(tabId, 'Page.handleJavaScriptDialog', STAY).catch((again) => console.warn('companion: dialog still open', again?.message));
    }
    dialogAnswered?.(tabId, dialog.kind, sent.accept);
  }

  api.debugger?.onEvent?.addListener((source, method, params) => {
    if (method !== 'Page.javascriptDialogOpening' || !Number.isInteger(source?.tabId) || typeof dialogHandler !== 'function') return;
    answerDialog(source.tabId, { tabId: source.tabId, kind: params?.type, message: params?.message, defaultValue: params?.defaultPrompt });
  });

  return { ensureAttached, detach, detachAll, forget, withInput, mouseClick, mouseDrag, mouseMove, mouseWheel, typeText, pressKey, isRevoked, setFileInputFiles, onJavaScriptDialog };
}

// The marker is a uuid we minted. Anything else would change the selector, not the attribute value.
export function markerSelector(marker) {
  if (typeof marker !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(marker)) return null;
  return `[data-companion-file="${marker}"]`;
}

// Opaque origins serialize as "null"; two of them are not the same place, so they never pin.
function originOf(url) {
  try {
    const origin = new URL(url).origin;
    return origin === 'null' ? null : origin;
  } catch {
    return null;
  }
}

function attrValue(node, name) {
  const list = node?.attributes;
  if (!Array.isArray(list)) return '';
  for (let i = 0; i + 1 < list.length; i += 2) {
    if (String(list[i]).toLowerCase() === name) return String(list[i + 1] ?? '');
  }
  return '';
}

const SHIFT = 8;
const KEYS = Object.freeze({
  Enter: { key: 'Enter', code: 'Enter', vk: 13, text: '\r' },
  Space: { key: ' ', code: 'Space', vk: 32, text: ' ' },
  Escape: { key: 'Escape', code: 'Escape', vk: 27 },
  Tab: { key: 'Tab', code: 'Tab', vk: 9 },
  'Shift+Tab': { key: 'Tab', code: 'Tab', vk: 9, modifiers: SHIFT },
  ArrowUp: { key: 'ArrowUp', code: 'ArrowUp', vk: 38 },
  ArrowDown: { key: 'ArrowDown', code: 'ArrowDown', vk: 40 },
  ArrowLeft: { key: 'ArrowLeft', code: 'ArrowLeft', vk: 37 },
  ArrowRight: { key: 'ArrowRight', code: 'ArrowRight', vk: 39 },
  Backspace: { key: 'Backspace', code: 'Backspace', vk: 8 },
  Delete: { key: 'Delete', code: 'Delete', vk: 46 },
  Home: { key: 'Home', code: 'Home', vk: 36 },
  End: { key: 'End', code: 'End', vk: 35 },
  PageUp: { key: 'PageUp', code: 'PageUp', vk: 33 },
  PageDown: { key: 'PageDown', code: 'PageDown', vk: 34 },
});

export function isControl(ch) {
  const code = ch.codePointAt(0);
  return code < 0x20 || code === 0x7f;
}
