import test from 'node:test';
import assert from 'node:assert/strict';
import { changedOf } from '../lib/effect.js';

const at = (url, title, textHash) => ({ url, title, textHash });

test('changedOf names only the categories that differ', () => {
  assert.deepEqual(changedOf(at('a', 't', 1), at('a', 't', 1)), []);
  assert.deepEqual(changedOf(at('a', 't', 1), at('b', 't', 1)), ['url']);
  assert.deepEqual(changedOf(at('a', 't', 1), at('b', 'u', 2)), ['url', 'title', 'text']);
});

test('changedOf cannot tell when a digest is missing and nothing else moved', () => {
  assert.equal(changedOf(at('a', 't', 1), at('a', 't', null)), null);
  assert.deepEqual(changedOf(at('a', 't', 1), at('b', 't', null)), ['url']);
  assert.equal(changedOf(null, at('a', 't', 1)), null);
});
