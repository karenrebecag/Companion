import test from 'node:test';
import assert from 'node:assert/strict';
import { createCdp } from '../lib/cdp.js';

// A debugger that answers every command, except it fails the move that is the `failAt`-th one.
function fakeDebugger({ failAt = Infinity, failRelease = false } = {}) {
  const sent = [];
  const runtime = { id: 'ext', lastError: undefined };
  let moves = 0;
  const api = {
    runtime,
    debugger: {
      sendCommand: (target, method, params, cb) => {
        sent.push(params.type);
        const fails = (params.type === 'mouseMoved' && params.buttons === 1 && ++moves === failAt)
          || (params.type === 'mouseReleased' && failRelease);
        runtime.lastError = fails ? { message: `${params.type} failed` } : undefined;
        cb({});
        runtime.lastError = undefined;
      },
    },
  };
  return { api, sent };
}

test('a drag presses, moves in steps and releases on the target', async () => {
  const { api, sent } = fakeDebugger();
  await createCdp(api).mouseDrag(7, { x: 0, y: 0 }, { x: 100, y: 50 });
  assert.deepEqual(sent, ['mouseMoved', 'mousePressed', ...Array(10).fill('mouseMoved'), 'mouseReleased']);
});

test('a drag that fails mid-move still lets go of the button, and the original error propagates', async () => {
  const { api, sent } = fakeDebugger({ failAt: 4 });
  await assert.rejects(createCdp(api).mouseDrag(7, { x: 0, y: 0 }, { x: 100, y: 50 }), /mouseMoved failed/);
  assert.equal(sent.filter((type) => type === 'mousePressed').length, 1);
  assert.equal(sent.at(-1), 'mouseReleased', 'a button left down would stay down in the page');
  assert.equal(sent.filter((type) => type === 'mouseReleased').length, 1);
});

test('a failed press sends no release: nothing was held', async () => {
  const { api, sent } = fakeDebugger();
  api.debugger.sendCommand = (target, method, params, cb) => {
    sent.push(params.type);
    api.runtime.lastError = params.type === 'mousePressed' ? { message: 'press failed' } : undefined;
    cb({});
    api.runtime.lastError = undefined;
  };
  await assert.rejects(createCdp(api).mouseDrag(7, { x: 0, y: 0 }, { x: 1, y: 1 }), /press failed/);
  assert.ok(!sent.includes('mouseReleased'));
});

test('when the release itself fails, that is the error', async () => {
  const { api } = fakeDebugger({ failRelease: true });
  await assert.rejects(createCdp(api).mouseDrag(7, { x: 0, y: 0 }, { x: 100, y: 50 }), /mouseReleased failed/);
});

test('when the move and the best-effort release both fail, the move is the error', async () => {
  const { api, sent } = fakeDebugger({ failAt: 2, failRelease: true });
  await assert.rejects(createCdp(api).mouseDrag(7, { x: 0, y: 0 }, { x: 100, y: 50 }), /mouseMoved failed/);
  assert.equal(sent.at(-1), 'mouseReleased');
});
