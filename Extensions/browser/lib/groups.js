export const GROUP_TITLE = 'Companion';

const NO_GROUP = -1;
const isInt = Number.isInteger;

// Where a tab goes and what to remember so release can put it back. A tab already in our group keeps its
// earlier record: overwriting it would remember the Companion slot as the "original" place.
export function groupPlan({ tab, ourGroupIds }) {
  if (ourGroupIds.includes(tab.groupId)) return { noop: true, target: tab.groupId, record: null };
  return {
    noop: false,
    target: ourGroupIds.length > 0 ? ourGroupIds[0] : null,
    record: { index: tab.index, groupId: tab.groupId > NO_GROUP ? tab.groupId : null, windowId: tab.windowId },
  };
}

// Restore only what is still ours to restore: a tab the user already moved out of the group is theirs now.
export function releasePlan({ record, tab, ourGroupIds, groupExists }) {
  const nothing = { act: false, moveTo: null, regroup: null };
  if (!tab || !ourGroupIds.includes(tab.groupId)) return nothing;
  if (!record || record.windowId !== tab.windowId) return { act: true, moveTo: null, regroup: null };
  if (record.groupId !== null && groupExists(record.groupId)) return { act: true, moveTo: null, regroup: record.groupId };
  return { act: true, moveTo: record.index, regroup: null };
}

// Storage is only a hint of which ids we made; the title check stops a recycled id from dissolving a user group.
export function cleanupPlan({ stored, groups }) {
  if (!Array.isArray(stored) || !Array.isArray(groups)) return [];
  return stored.filter((id) => groups.some((g) => g.id === id && g.title === GROUP_TITLE));
}

export function recordCreated(map, tab, now) {
  const next = new Map(map);
  if (isInt(tab?.id) && !next.has(tab.id)) next.set(tab.id, now);
  return next;
}
