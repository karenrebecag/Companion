import test from 'node:test';
import assert from 'node:assert/strict';
import { GROUP_TITLE, groupPlan, releasePlan, cleanupPlan, recordCreated } from '../lib/groups.js';

test('the group title is Companion', () => assert.equal(GROUP_TITLE, 'Companion'));

test('groupPlan creates the group when the window has none and records where the tab was', () => {
  const plan = groupPlan({ tab: { id: 5, index: 3, groupId: -1, windowId: 9 }, ourGroupIds: [] });
  assert.deepEqual(plan, { noop: false, target: null, record: { index: 3, groupId: null, windowId: 9 } });
});

test('groupPlan joins our existing group and remembers the user group it left', () => {
  const plan = groupPlan({ tab: { id: 5, index: 3, groupId: 40, windowId: 9 }, ourGroupIds: [77] });
  assert.deepEqual(plan, { noop: false, target: 77, record: { index: 3, groupId: 40, windowId: 9 } });
});

test('groupPlan is a no-op with no new record when the tab is already in our group', () => {
  const plan = groupPlan({ tab: { id: 5, index: 0, groupId: 77, windowId: 9 }, ourGroupIds: [77] });
  assert.deepEqual(plan, { noop: true, target: 77, record: null });
});

const rec = { index: 4, groupId: null, windowId: 9 };

test('releasePlan restores the index when the tab is still in our group', () => {
  const plan = releasePlan({ record: rec, tab: { id: 5, groupId: 77, windowId: 9 }, ourGroupIds: [77], groupExists: () => false });
  assert.deepEqual(plan, { act: true, moveTo: 4, regroup: null });
});

test('releasePlan restores the original user group when it still exists, instead of an index', () => {
  const plan = releasePlan({ record: { ...rec, groupId: 40 }, tab: { id: 5, groupId: 77, windowId: 9 }, ourGroupIds: [77], groupExists: (id) => id === 40 });
  assert.deepEqual(plan, { act: true, moveTo: null, regroup: 40 });
});

test('releasePlan falls back to the index when the original user group is gone', () => {
  const plan = releasePlan({ record: { ...rec, groupId: 40 }, tab: { id: 5, groupId: 77, windowId: 9 }, ourGroupIds: [77], groupExists: () => false });
  assert.deepEqual(plan, { act: true, moveTo: 4, regroup: null });
});

test('releasePlan does nothing when the user already moved the tab out of our group', () => {
  assert.deepEqual(
    releasePlan({ record: rec, tab: { id: 5, groupId: -1, windowId: 9 }, ourGroupIds: [77], groupExists: () => false }),
    { act: false, moveTo: null, regroup: null },
  );
});

test('releasePlan does nothing for a tab in someone else group, or one that no longer exists', () => {
  assert.equal(releasePlan({ record: rec, tab: { id: 5, groupId: 12, windowId: 9 }, ourGroupIds: [77], groupExists: () => true }).act, false);
  assert.equal(releasePlan({ record: rec, tab: null, ourGroupIds: [77], groupExists: () => true }).act, false);
});

test('releasePlan without a record (worker restarted) still ungroups but restores nothing', () => {
  assert.deepEqual(
    releasePlan({ record: null, tab: { id: 5, groupId: 77, windowId: 9 }, ourGroupIds: [77], groupExists: () => true }),
    { act: true, moveTo: null, regroup: null },
  );
});

test('releasePlan does not move the tab across windows', () => {
  const plan = releasePlan({ record: { ...rec, windowId: 1 }, tab: { id: 5, groupId: 77, windowId: 9 }, ourGroupIds: [77], groupExists: () => false });
  assert.deepEqual(plan, { act: true, moveTo: null, regroup: null });
});

test('cleanupPlan dissolves only stored ids that still exist and are titled Companion', () => {
  const groups = [
    { id: 1, title: 'Companion' }, { id: 2, title: 'Companion' }, { id: 3, title: 'Work' }, { id: 4, title: 'Companion' },
  ];
  assert.deepEqual(cleanupPlan({ stored: [1, 3, 99], groups }), [1]);
});

test('cleanupPlan tolerates junk storage', () => {
  for (const stored of [undefined, null, 'x', {}, []]) assert.deepEqual(cleanupPlan({ stored, groups: [{ id: 1, title: 'Companion' }] }), []);
  assert.deepEqual(cleanupPlan({ stored: [1], groups: undefined }), []);
});

test('recordCreated returns a new map with the stamp and does not mutate the old one', () => {
  const before = new Map();
  const after = recordCreated(before, { id: 8 }, 1234);
  assert.equal(before.size, 0);
  assert.equal(after.get(8), 1234);
  assert.equal(recordCreated(after, { id: 8 }, 9999).get(8), 1234, 'first stamp wins');
  assert.equal(recordCreated(after, { id: 'x' }, 1).size, 1, 'non-integer id ignored');
});
