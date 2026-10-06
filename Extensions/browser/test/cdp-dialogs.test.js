import test from 'node:test';
import assert from 'node:assert/strict';
import { createCdp } from '../lib/cdp.js';

// A debugger that records every command, exposes an onEvent bucket the test fires itself,
// and a runtime with a clearable lastError.
function fakeDebugger() {
  const sent = [];
  const events = [];
  const runtime = { id: 'ext', lastError: undefined };
  const control = { failNext: 0 };
  const api = {
    runtime,
    debugger: {
      sendCommand: (target, method, params, cb) => {
        sent.push([target.tabId, method, params]);
        if (control.failNext > 0) {
          control.failNext--;
          runtime.lastError = { message: 'send failed' };
          cb();
          runtime.lastError = undefined;
          return;
        }
        if (runtime.lastError) {
          const err = new Error(runtime.lastError.message);
          runtime.lastError = undefined;
          cb();
          throw err;
        }
        cb({});
      },
      onEvent: { addListener: (fn) => events.push(fn) },
      onDetach: { addListener: () => {} },
    },
  };
  return { api, sent, events, runtime, control };
}

const dialog = (overrides = {}) => ({
  type: 'confirm',
  message: 'Delete this?',
  defaultPrompt: '',
  hasBrowserHandler: false,
  url: 'https://x.example/',
  ...overrides,
});

test('cdp: a javascriptDialogOpening event is answered with the policy and Page.handleJavaScriptDialog', () => {
  const { api, sent, events } = fakeDebugger();
  const cdp = createCdp(api);
  cdp.onJavaScriptDialog((d) => {
    // Test policy: confirm -> false, escalated, destructive on the keyword.
    const destructive = /delete|remove|discard|pay|buy|send|transfer|irreversible|eliminar|borrar|descartar|pagar|comprar|enviar|transferir|excluir|apagar/i.test(d.message);
    return { accept: false, destructive, escalate: true };
  });
  events[0]({ tabId: 7 }, 'Page.javascriptDialogOpening', dialog());
  const handle = sent.find(([, m]) => m === 'Page.handleJavaScriptDialog');
  assert.ok(handle, 'sent Page.handleJavaScriptDialog');
  assert.equal(handle[0], 7);
  assert.equal(handle[2].accept, false);
  assert.equal(handle[2].promptText, '');
});

test('cdp: a prompt is answered with the defaultPrompt as promptText, accept true', () => {
  const { api, sent, events } = fakeDebugger();
  const cdp = createCdp(api);
  cdp.onJavaScriptDialog((d) => ({ accept: true, promptText: d.defaultValue }));
  events[0]({ tabId: 8 }, 'Page.javascriptDialogOpening', dialog({ type: 'prompt', defaultPrompt: 'Ana' }));
  const handle = sent.find(([, m]) => m === 'Page.handleJavaScriptDialog');
  assert.ok(handle);
  assert.equal(handle[2].accept, true);
  assert.equal(handle[2].promptText, 'Ana');
});

test('cdp: an alert is answered with accept true and never escalates', () => {
  const { api, sent, events } = fakeDebugger();
  const cdp = createCdp(api);
  cdp.onJavaScriptDialog((d) => ({ accept: d.kind === 'alert' }));
  events[0]({ tabId: 9 }, 'Page.javascriptDialogOpening', dialog({ type: 'alert' }));
  const handle = sent.find(([, m]) => m === 'Page.handleJavaScriptDialog');
  assert.ok(handle);
  assert.equal(handle[2].accept, true);
});

test('cdp: a beforeunload is answered with accept false, the page stays', () => {
  const { api, sent, events } = fakeDebugger();
  const cdp = createCdp(api);
  cdp.onJavaScriptDialog((d) => ({ accept: d.kind !== 'beforeunload' }));
  events[0]({ tabId: 10 }, 'Page.javascriptDialogOpening', dialog({ type: 'beforeunload' }));
  const handle = sent.find(([, m]) => m === 'Page.handleJavaScriptDialog');
  assert.equal(handle[2].accept, false);
});

test('cdp: events on an unknown tab (no tabId) are ignored, no command sent', () => {
  const { api, sent, events } = fakeDebugger();
  const cdp = createCdp(api);
  cdp.onJavaScriptDialog(() => ({ accept: false }));
  events[0]({ url: 'https://x.example/' }, 'Page.javascriptDialogOpening', dialog());
  assert.equal(sent.find(([, m]) => m === 'Page.handleJavaScriptDialog'), undefined);
});

test('cdp: events other than javascriptDialogOpening pass through, no command sent', () => {
  const { api, sent, events } = fakeDebugger();
  const cdp = createCdp(api);
  cdp.onJavaScriptDialog(() => ({ accept: false }));
  events[0]({ tabId: 7 }, 'Page.frameNavigated', { url: 'https://x.example/' });
  assert.equal(sent.find(([, m]) => m === 'Page.handleJavaScriptDialog'), undefined);
});

test('cdp: with no callback registered, the event is a no-op (no command sent, no throw)', () => {
  const { api, sent, events } = fakeDebugger();
  const cdp = createCdp(api);
  events[0]({ tabId: 7 }, 'Page.javascriptDialogOpening', dialog());
  assert.equal(sent.find(([, m]) => m === 'Page.handleJavaScriptDialog'), undefined);
});

test('cdp: a failing sendCommand does not throw out of the event handler', () => {
  const { api, sent, events, runtime } = fakeDebugger();
  const cdp = createCdp(api);
  cdp.onJavaScriptDialog(() => ({ accept: false }));
  // Make the next sendCommand fail. sendCommand is invoked synchronously, so we set lastError before firing.
  runtime.lastError = { message: 'send failed' };
  assert.doesNotThrow(() => events[0]({ tabId: 7 }, 'Page.javascriptDialogOpening', dialog()));
  assert.equal(sent.find(([, m]) => m === 'Page.handleJavaScriptDialog')?.[2].accept, false);
});

test('cdp: onJavaScriptDialog replaces the previous callback (one registered handler at a time)', () => {
  const { api, events } = fakeDebugger();
  const cdp = createCdp(api);
  let a = 0;
  let b = 0;
  cdp.onJavaScriptDialog(() => { a++; return { accept: false }; });
  cdp.onJavaScriptDialog(() => { b++; return { accept: false }; });
  events[0]({ tabId: 7 }, 'Page.javascriptDialogOpening', dialog());
  assert.equal(a, 0, 'the first callback is no longer in effect');
  assert.equal(b, 1);
});

const flush = () => new Promise((resolve) => setImmediate(resolve));
const handled = (sent) => sent.filter(([, m]) => m === 'Page.handleJavaScriptDialog').map(([, , p]) => p);

test('F4 a policy that throws falls back to staying put and warns', async (t) => {
  const warn = t.mock.method(console, 'warn', () => {});
  const { api, sent, events } = fakeDebugger();
  const cdp = createCdp(api);
  cdp.onJavaScriptDialog(() => { throw new Error('boom'); });
  events[0]({ tabId: 7 }, 'Page.javascriptDialogOpening', dialog());
  await flush();
  assert.deepEqual(handled(sent), [{ accept: false, promptText: '' }]);
  assert.ok(warn.mock.calls.length >= 1);
});

test('F4 an answer the browser rejects is retried once as no, with a warning', async (t) => {
  const warn = t.mock.method(console, 'warn', () => {});
  const { api, sent, events, control } = fakeDebugger();
  const cdp = createCdp(api);
  cdp.onJavaScriptDialog(() => ({ accept: true, promptText: 'x' }));
  control.failNext = 1;
  events[0]({ tabId: 7 }, 'Page.javascriptDialogOpening', dialog({ type: 'prompt' }));
  await flush();
  assert.deepEqual(handled(sent), [{ accept: true, promptText: 'x' }, { accept: false, promptText: '' }]);
  assert.ok(warn.mock.calls.length >= 1);
});

test('F4 the callback learns what was finally answered', async () => {
  const { api, events, control } = fakeDebugger();
  const cdp = createCdp(api);
  const seen = [];
  cdp.onJavaScriptDialog(() => ({ accept: true }), (tabId, kind, accept) => seen.push([tabId, kind, accept]));
  events[0]({ tabId: 7 }, 'Page.javascriptDialogOpening', dialog({ type: 'beforeunload' }));
  await flush();
  control.failNext = 1;
  events[0]({ tabId: 8 }, 'Page.javascriptDialogOpening', dialog({ type: 'beforeunload' }));
  await flush();
  assert.deepEqual(seen, [[7, 'beforeunload', true], [8, 'beforeunload', false]]);
});
