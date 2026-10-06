import { dialogPolicy, sanitizeDialogMessage, createDialogReports } from './dialogs.js';

export const STAYED = 'the page asked to stay; Companion stayed';

// Connects the CDP dialog events to the per-tab reports. `navigation(tab)` brackets a navigation
// Companion started itself, which is the only time a beforeunload is accepted.
export function wireDialogs(cdp, reports = createDialogReports()) {
  const leaving = new Map();
  cdp.onJavaScriptDialog((d) => {
    const policy = dialogPolicy({ ...d, leaving: leaving.has(d.tabId) });
    if (policy.escalate) {
      reports.record(d.tabId, { kind: d.kind, answer: policy.answer, destructive: policy.destructive, message: sanitizeDialogMessage(d.message) });
    }
    return { accept: policy.accept, promptText: policy.promptText };
  }, (tabId, kind, accept) => {
    if (kind === 'beforeunload' && !accept && leaving.has(tabId)) leaving.set(tabId, { stayed: true });
  });

  function navigation(tabId) {
    const mark = { stayed: false };
    leaving.set(tabId, mark);
    return {
      stayed: () => leaving.get(tabId)?.stayed === true,
      end: () => { if (leaving.get(tabId)) leaving.delete(tabId); },
    };
  }

  return { attach: reports.attach, clear: reports.clear, navigation };
}
