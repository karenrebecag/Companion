import test, { mock, afterEach } from 'node:test';
import assert from 'node:assert/strict';

const EXTENSION_ID = 'gaipfdnbliibnfchgcnamnjpfgkilnll';
let importCount = 0;

// A stand-in for the pieces of `chrome` that background.js touches. Every registration is recorded so a test
// can also assert what was NOT registered.
function makeChrome({ query = async () => [] } = {}) {
  const ports = [];
  const registered = { alarm: [], startup: [], installed: [], removed: [], forbidden: [] };
  const listener = (bucket) => ({ addListener: (fn) => bucket.push(fn) });
  const chrome = {
    runtime: {
      id: EXTENSION_ID,
      lastError: undefined,
      getManifest: () => ({ version: '0.1.0' }),
      connectNative(host) {
        const port = {
          host,
          sent: [],
          messageListeners: [],
          disconnectListeners: [],
          onMessage: { addListener(fn) { port.messageListeners.push(fn); } },
          onDisconnect: { addListener(fn) { port.disconnectListeners.push(fn); } },
          postMessage(message) { port.sent.push(message); },
          receive(message) { for (const fn of port.messageListeners) fn(message); },
          hangUp() { for (const fn of port.disconnectListeners) fn(); },
        };
        ports.push(port);
        return port;
      },
      onStartup: listener(registered.startup),
      onInstalled: listener(registered.installed),
      onMessageExternal: listener(registered.forbidden),
      onConnectExternal: listener(registered.forbidden),
      onMessage: listener(registered.forbidden),
      onConnect: listener(registered.forbidden),
    },
    alarms: { create() {}, onAlarm: listener(registered.alarm) },
    tabs: { query, get: async (id) => ({ id }), update: async () => ({}), onRemoved: listener(registered.removed) },
    scripting: { executeScript: async () => [] },
  };
  return { chrome, ports, registered };
}

// A fresh module instance per test: background.js keeps its state at module level.
async function boot(options) {
  mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  const rig = makeChrome(options);
  globalThis.chrome = rig.chrome;
  await import(`../background.js?case=${importCount++}`);
  return rig;
}

const settle = () => new Promise((resolve) => setImmediate(resolve));
const call = (id, name = 'browser_tabs', args = {}) => ({ id, method: 'call', params: { name, arguments: args } });
const answersTo = (port, id) => port.sent.filter((m) => m.id === id);

afterEach(() => {
  mock.timers.reset();
  delete globalThis.chrome;
});

test('the first message on a new port is a hello that carries no token', async () => {
  const { ports } = await boot();
  assert.equal(ports.length, 1);
  assert.equal(ports[0].host, 'com.karen.companion.browser');
  const [hello] = ports[0].sent;
  assert.equal(hello.method, 'hello');
  assert.equal(hello.id, 1);
  assert.equal(hello.params.extension, EXTENSION_ID);
  assert.equal(hello.params.protocol, 1);
  assert.equal(hello.params.version, '0.1.0');
  assert.ok(!('token' in hello.params), 'the relay adds the token; the extension never holds one');
  assert.equal(JSON.stringify(hello).includes('token'), false);
});

test('after a disconnect it reconnects on the backoff schedule, doubling while nothing answers', async () => {
  const { ports } = await boot();
  ports[0].hangUp();
  mock.timers.tick(999);
  assert.equal(ports.length, 1, 'not before the first delay (1000 ms)');
  mock.timers.tick(1);
  assert.equal(ports.length, 2);
  ports[1].hangUp();
  mock.timers.tick(1999);
  assert.equal(ports.length, 2, 'the second delay doubled to 2000 ms');
  mock.timers.tick(1);
  assert.equal(ports.length, 3);
});

test('a hello ack resets the backoff to the start', async () => {
  const { ports } = await boot();
  ports[0].hangUp();
  mock.timers.tick(1000);
  ports[1].hangUp();
  mock.timers.tick(2000);
  assert.equal(ports.length, 3);
  ports[2].receive({ id: 1, result: { ok: true } });
  ports[2].hangUp();
  mock.timers.tick(1000);
  assert.equal(ports.length, 4, 'back to 1000 ms after a proven link');
});

for (const code of ['bad_token', 'busy']) {
  test(`${code} stops reconnecting until the next alarm`, async () => {
    const { ports, registered } = await boot();
    ports[0].receive({ id: 1, error: { code, message: 'no' } });
    ports[0].hangUp();
    mock.timers.tick(10 * 60 * 1000);
    assert.equal(ports.length, 1, 'no respawn loop after a refusal');
    assert.equal(registered.alarm.length, 1);
    registered.alarm[0]();
    assert.equal(ports.length, 2, 'the alarm tick tries again');
  });
}

test('an ordinary error frame does not put the reconnect on hold', async () => {
  const { ports } = await boot();
  ports[0].receive({ id: 5, error: { code: 'stale_id', message: 'x' } });
  ports[0].hangUp();
  mock.timers.tick(1000);
  assert.equal(ports.length, 2);
});

test('a call whose timeout fires first is answered once, with timeout, and the late result stays silent', async () => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const { ports } = await boot({ query: () => gate });
  ports[0].receive(call(7));
  mock.timers.tick(12000);
  await settle();
  release([{ id: 3, title: 't', url: 'https://x.example/', active: true }]);
  await settle();
  const replies = answersTo(ports[0], 7);
  assert.equal(replies.length, 1);
  assert.equal(replies[0].error.code, 'timeout');
});

test('a call whose result lands first is answered once and its timer no longer fires an error', async () => {
  const { ports } = await boot({ query: async () => [{ id: 3, title: 't', url: 'https://x.example/', active: true }] });
  ports[0].receive(call(8));
  await settle();
  mock.timers.tick(12000);
  await settle();
  const replies = answersTo(ports[0], 8);
  assert.equal(replies.length, 1);
  assert.ok(replies[0].result.tabs, 'the result, not a timeout');
});

test('the result and the timeout in the same turn still answer once', async () => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const { ports } = await boot({ query: () => gate });
  ports[0].receive(call(9));
  release([]);
  mock.timers.tick(12000);
  await settle();
  assert.equal(answersTo(ports[0], 9).length, 1);
});

test('an invalid call gets invalid_args and nothing is dispatched', async () => {
  const { ports } = await boot();
  ports[0].receive(call(4, 'browser_delete_everything'));
  await settle();
  const [reply] = answersTo(ports[0], 4);
  assert.equal(reply.error.code, 'invalid_args');
});

test('nothing but the native port is a way in: no external, internal or window message listener', async () => {
  const windowListeners = [];
  globalThis.addEventListener = (type) => windowListeners.push(type);
  try {
    const { registered } = await boot();
    assert.deepEqual(registered.forbidden, []);
    assert.deepEqual(windowListeners, []);
  } finally {
    delete globalThis.addEventListener;
  }
});
