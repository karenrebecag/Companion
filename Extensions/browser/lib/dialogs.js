// Policy and bookkeeping for the native dialogs a page opens in a tab Companion controls. Chrome answers
// them through CDP (cdp.js); here lives what the answer is and what the model is told about it.

// A substring match on purpose: a page can frame a destructive question around any word, so the keyword
// anywhere in the text is enough to ask the person.
const DESTRUCTIVE = /(delete|remove|discard|pay|buy|send|transfer|irreversible|eliminar|borrar|descartar|pagar|comprar|enviar|transferir|excluir|apagar)/i;

// A beforeunload during Companion's own navigation is the page checking that the agent meant to leave,
// and it did, so it is accepted; any other one means the page is protecting unsaved work.
export function dialogPolicy({ kind, message = '', defaultValue = '', leaving = false } = {}) {
  const destructive = DESTRUCTIVE.test(message);
  switch (kind) {
    case 'confirm':
      return { accept: false, answer: 'no', escalate: true, destructive };
    case 'prompt':
      // Filling a "type DELETE" box with the page's own default would confirm for the model.
      if (destructive) return { accept: false, promptText: '', answer: 'no', escalate: true, destructive };
      return { accept: true, promptText: defaultValue, answer: 'default', escalate: true, destructive };
    case 'beforeunload':
      if (leaving) return { accept: true, answer: 'yes', escalate: false, destructive: false };
      return { accept: false, answer: 'no', escalate: true, destructive: false };
    default:
      return { accept: true, answer: 'dismissed', escalate: false, destructive: false };
  }
}

// Same classes the host strips from page text: controls and line separators become a space, format
// (bidi, zero-width, tag block), private-use, unassigned and surrogate scalars vanish.
const AS_BLANK = /[\p{Cc}\p{Zl}\p{Zp}]/gu;
const DROPPED = /[\p{Cf}\p{Co}\p{Cn}\p{Cs}︀-️]/gu;

export function sanitizeDialogMessage(message, max = 120) {
  if (typeof message !== 'string') return '';
  const cleaned = message.replace(DROPPED, '').replace(AS_BLANK, ' ').replace(/\s+/g, ' ').trim();
  return Array.from(cleaned).slice(0, max).join('');
}

// Per tab: the last few answered dialogs and a count of the rest. A page can open dialogs faster than
// anyone reads, so past a burst only the counter grows and memory stays flat.
export function createDialogReports({ maxEntries = 5, burst = 20, windowMs = 1000, now = () => Date.now() } = {}) {
  const tabs = new Map();
  const blank = (at) => ({ entries: [], more: 0, windowStart: at, seen: 0 });

  function record(tabId, entry) {
    if (!Number.isInteger(tabId)) return;
    const at = now();
    const prev = tabs.get(tabId) ?? blank(at);
    const fresh = at - prev.windowStart >= windowMs;
    const base = { ...prev, windowStart: fresh ? at : prev.windowStart, seen: (fresh ? 0 : prev.seen) + 1 };
    if (base.seen > burst) return void tabs.set(tabId, { ...base, more: base.more + 1 });
    const all = [...base.entries, entry];
    const overflow = Math.max(0, all.length - maxEntries);
    tabs.set(tabId, { ...base, entries: all.slice(overflow), more: base.more + overflow });
  }

  // Only a reply that carries a done text or a page can hold the report; any other keeps it queued.
  function attach(result, tabId) {
    const holds = typeof result?.done === 'string' || (result?.page && typeof result.page === 'object');
    const held = holds && Number.isInteger(tabId) ? tabs.get(tabId) : null;
    if (!held || held.entries.length === 0) return result;
    tabs.delete(tabId);
    return { ...result, dialogs: held.entries, more: held.more };
  }

  return { record, attach, clear: (tabId) => void tabs.delete(tabId), size: () => tabs.size };
}
