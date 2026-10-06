import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const PINNED_ID = 'gaipfdnbliibnfchgcnamnjpfgkilnll';
const manifest = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url), 'utf8'));

// Chrome's extension id: first 16 bytes of sha256(DER public key), each hex digit mapped 0-f to a-p.
const idFromKey = (key) => createHash('sha256')
  .update(Buffer.from(key, 'base64'))
  .digest('hex')
  .slice(0, 32)
  .replace(/[0-9a-f]/g, (digit) => String.fromCharCode('a'.charCodeAt(0) + parseInt(digit, 16)));

// debugger since step 1 of the Incredible-style redesign (authorized by Karen 2026-09-29): trusted
// input and an active lifecycle on background tabs are impossible without it. Only Companion's tabs attach.
test('the permissions are exactly nativeMessaging, scripting, alarms, tabGroups, storage and debugger', () => {
  assert.deepEqual([...manifest.permissions].sort(), ['alarms', 'debugger', 'nativeMessaging', 'scripting', 'storage', 'tabGroups']);
});

test('tabs is not requested in any permission list', () => {
  for (const list of [manifest.permissions, manifest.optional_permissions ?? []]) {
    assert.ok(!list.includes('tabs'));
  }
});

test('host permissions are <all_urls> only', () => {
  assert.deepEqual(manifest.host_permissions, ['<all_urls>']);
});

test('no other extension can connect from outside', () => {
  assert.deepEqual(manifest.externally_connectable, { ids: [] });
});

test('the manifest carries the public key so the id survives moving the folder', () => {
  assert.equal(typeof manifest.key, 'string');
  assert.ok(manifest.key.length > 100);
});

test('the id derived from the key is the one Companion pins', () => {
  assert.equal(idFromKey(manifest.key), PINNED_ID);
});

test('the Swift side pins the same id', () => {
  const policy = readFileSync(new URL('../../../Sources/CompanionCore/Browser/BrowserPolicy.swift', import.meta.url), 'utf8');
  assert.ok(policy.includes(PINNED_ID), 'BrowserPolicy.pinnedOrigins names the id the key produces');
});

test('the derivation is sensitive to the key (a different key gives a different id)', () => {
  const other = Buffer.from(manifest.key, 'base64');
  other[other.length - 10] ^= 1;
  assert.notEqual(idFromKey(other.toString('base64')), PINNED_ID);
});

// The app logs a stale reason only if it is on its allowlist; a reason added here but not there would show
// up in the log as "other" and hide the cause it was added to name.
test('every stale reason the extension sends is on the app allowlist', () => {
  const source = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
  const background = source('../background.js');
  const page = source('../lib/page.js');
  const sent = new Set([
    ...[...background.matchAll(/stale\('([a-z_]+)'/g)].map((m) => m[1]),
    ...[...page.matchAll(/stale\('(?:[^'\\]|\\.)*',\s*'([a-z_]+)'\)/g)].map((m) => m[1]),
  ]);
  assert.ok(sent.size >= 15, `found ${sent.size} reasons`);
  const swift = source('../../../Sources/CompanionCore/Browser/BrowserSanitize.swift');
  const block = swift.slice(swift.indexOf('allowedReasons'), swift.indexOf(']', swift.indexOf('allowedReasons')));
  const allowed = new Set([...block.matchAll(/"([a-z_]+)"/g)].map((m) => m[1]));
  for (const reason of sent) assert.ok(allowed.has(reason), `${reason} is missing from allowedReasons`);
});
