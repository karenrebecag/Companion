// Postcondition of an action: what visibly differs between two glances at the tab. Only category names
// leave this file, never a url, a title or text, so nothing page-controlled rides the reply.
export const SETTLE_QUIET_MS = 300;
export const SETTLE_CAP_MS = 1500;

// null means "cannot tell": a page that did not answer its second glance, with the address and title
// unchanged, is not evidence that nothing happened.
export function changedOf(before, after) {
  if (!before || !after) return null;
  const changed = [];
  if (before.url !== after.url) changed.push('url');
  if (before.title !== after.title) changed.push('title');
  const known = before.textHash != null && after.textHash != null;
  if (known && before.textHash !== after.textHash) changed.push('text');
  return changed.length > 0 || known ? changed : null;
}
