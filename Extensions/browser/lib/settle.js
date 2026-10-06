// Post-action observer. `observe` runs in the page (ISOLATED world), armed before the action; the
// background then waits until the page is quiet or a cap passes and turns the before/after diff into
// a small structured fact. Nothing page-derived leaves here: no text, no title, no URL, only flags
// and counts, so there is nothing for a page to inject through it.

export const QUIET_MS = 300;
export const CAP_MS = 1500;
export const POLL_MS = 50;

// Serialised by Chrome into the page, so it must not reach for anything outside its own body.
export function observe(mode) {
  const WATCHED = ['aria-expanded', 'aria-selected', 'aria-checked', 'open', 'hidden', 'class', 'value'];
  const OVERLAYS = {
    dialog: ['dialog[open]', '[aria-modal="true"]', '[role="dialog"]', '[role="alertdialog"]', ':popover-open'],
    menu: ['[role="menu"]'],
    listbox: ['[role="listbox"]'],
  };
  const shown = (el) => (typeof el.checkVisibility === 'function' ? el.checkVisibility() : true);
  const look = () => {
    const overlays = {};
    for (const [kind, selectors] of Object.entries(OVERLAYS)) {
      const seen = new Set();
      for (const selector of selectors) {
        // An engine without :popover-open rejects only that selector, not the others.
        try { for (const el of document.querySelectorAll(selector)) if (shown(el)) seen.add(el); } catch { /* unsupported */ }
      }
      overlays[kind] = seen.size;
    }
    return { url: location.href, overlays };
  };
  const state = globalThis.__companionSettle;
  if (mode === 'arm') {
    if (state?.observer) state.observer.disconnect();
    const next = { before: look(), count: 0, observer: null };
    next.observer = new MutationObserver((records) => { next.count += records.length; });
    next.observer.observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: WATCHED });
    globalThis.__companionSettle = next;
    return true;
  }
  // A new document has no state: the old one, observer included, went away with the navigation.
  if (!state) return null;
  const out = { before: state.before, after: look(), count: state.count };
  if (mode === 'end') {
    state.observer.disconnect();
    delete globalThis.__companionSettle;
  }
  return out;
}

const OPENED = ['dialog', 'menu', 'listbox'];

// Pure. Null when there is nothing to say (the page could not be observed).
export function summarise({ navigated = false, before = null, after = null, count = 0, fieldChars = null } = {}) {
  const field = Number.isInteger(fieldChars) && fieldChars >= 0 ? fieldChars : null;
  if (navigated) return { navigated: true, urlChanged: true, opened: null, changed: true, fieldChars: field };
  if (!before || !after) return field === null ? null : { navigated: false, urlChanged: false, opened: null, changed: false, fieldChars: field };
  const urlChanged = before.url !== after.url;
  const opened = OPENED.find((kind) => (after.overlays?.[kind] ?? 0) > (before.overlays?.[kind] ?? 0)) ?? null;
  const changed = urlChanged || opened !== null || count > 0;
  return { navigated: false, urlChanged, opened, changed, fieldChars: field };
}

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Arms the observer. A page that refuses injection (chrome://, a store page) just yields no summary:
// the action itself is what was asked for.
export async function startSettle(exec, target) {
  try {
    return (await exec(target, observe, ['arm'])) === true;
  } catch {
    return false;
  }
}

// Waits for QUIET_MS without a new mutation, never past CAP_MS, then reads the final diff. A thrown
// injection, or a document that lost our state, means the page navigated.
export async function finishSettle(exec, target, { now = () => Date.now(), sleep = defaultSleep, quietMs = QUIET_MS, capMs = CAP_MS, pollMs = POLL_MS, fieldChars = null } = {}) {
  const start = now();
  let seen = 0;
  let quietFrom = start;
  try {
    for (;;) {
      const elapsed = now() - start;
      if (elapsed >= capMs) break;
      await sleep(Math.min(pollMs, capMs - elapsed));
      const peek = await exec(target, observe, ['peek']);
      if (!peek) return summarise({ navigated: true, fieldChars });
      if (peek.count !== seen) { seen = peek.count; quietFrom = now(); }
      if (now() - quietFrom >= quietMs) break;
    }
    const last = await exec(target, observe, ['end']);
    if (!last) return summarise({ navigated: true, fieldChars });
    return summarise({ ...last, fieldChars });
  } catch {
    return summarise({ navigated: true, fieldChars });
  }
}
