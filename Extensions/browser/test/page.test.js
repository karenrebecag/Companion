import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

// page.js is a classic script (executeScript `files` cannot be a module), so it is loaded as CJS.
const page = createRequire(import.meta.url)('../lib/page.js');

test('classifier marks the sensitive input types and autocomplete tokens', () => {
  assert.equal(page.isSensitive({ type: 'password', autocomplete: null }), true);
  for (const ac of ['cc-number', 'cc-exp', 'cc-csc', 'cc-name', 'one-time-code', 'current-password', 'new-password']) {
    assert.equal(page.isSensitive({ type: 'text', autocomplete: ac }), true, ac);
  }
  assert.equal(page.isSensitive({ type: 'text', autocomplete: 'section-a shipping CC-Number' }), true);
  assert.equal(page.isSensitive({ type: 'PASSWORD', autocomplete: '' }), true);
});

test('classifier leaves ordinary fields alone and tolerates null', () => {
  assert.equal(page.isSensitive({ type: 'text', autocomplete: 'email' }), false);
  assert.equal(page.isSensitive({ type: null, autocomplete: null }), false);
  assert.equal(page.isSensitive({}), false);
  assert.equal(page.isSensitive(null), false);
  assert.equal(page.isSensitive({ type: 'text', autocomplete: 'accept' }), false);
});

test('hidden inputs are never listed', () => {
  assert.equal(page.isListable(fake({ tag: 'input', attrs: { type: 'hidden' } })), false);
  assert.equal(page.isListable(fake({ tag: 'input', attrs: { type: 'text' } })), true);
  assert.equal(page.isListable(fake({ tag: 'button', text: 'Go' })), true);
  assert.equal(page.isListable(fake({ tag: 'div' })), false);
  assert.equal(page.isListable(fake({ tag: 'div', attrs: { role: 'option' } })), true);
});

test('a >>> b gives two segments, trimmed', () => {
  assert.deepEqual(page.parseSelector('a >>> b'), ['a', 'b']);
  assert.deepEqual(page.parseSelector('  x-app>>>  .list   >>>li:nth-child(2) '), ['x-app', '.list', 'li:nth-child(2)']);
  assert.deepEqual(page.parseSelector('div > p'), ['div > p']);
});

test('parseSelector rejects empty input and empty segments', () => {
  assert.equal(page.parseSelector(''), null);
  assert.equal(page.parseSelector('   '), null);
  assert.equal(page.parseSelector(null), null);
  assert.equal(page.parseSelector(42), null);
  assert.equal(page.parseSelector('a >>> '), null);
  assert.equal(page.parseSelector('>>> a'), null);
  assert.equal(page.parseSelector('a >>>  >>> b'), null);
});

test('resolveSelector walks shadow roots and same-origin iframes', () => {
  const inner = fake({ tag: 'button', text: 'Save' });
  const iframeDoc = { querySelectorAll: (s) => (s === 'button' ? [inner] : []) };
  const iframe = fake({ tag: 'iframe' });
  iframe.contentDocument = iframeDoc;
  const host = fake({ tag: 'x-app' });
  host.shadowRoot = { querySelectorAll: (s) => (s === 'iframe' ? [iframe] : []) };
  const root = { querySelectorAll: (s) => (s === 'x-app' ? [host] : []) };
  assert.deepEqual(page.resolveSelector(root, ['x-app', 'iframe', 'button']), [inner]);
  assert.deepEqual(page.resolveSelector(root, ['x-app', 'nope']), []);
});

test('resolveSelector skips a cross-origin iframe (null contentDocument)', () => {
  const iframe = fake({ tag: 'iframe' });
  iframe.contentDocument = null;
  const root = { querySelectorAll: (s) => (s === 'iframe' ? [iframe] : []) };
  assert.deepEqual(page.resolveSelector(root, ['iframe', 'button']), []);
});

test('serializer emits exactly the wire shape', () => {
  const el = fake({ tag: 'input', attrs: { type: 'email', autocomplete: 'email', 'aria-label': 'Correo' }, value: 'a@b.c' });
  const out = page.serializeElement(el, 3, 0);
  assert.deepEqual(Object.keys(out), ['id', 'frame', 'role', 'label', 'context', 'inputType', 'autocomplete', 'value', 'frameOrigin', 'href', 'fieldName', 'fieldId']);
  assert.deepEqual(out, { id: 3, frame: 0, role: 'textbox', label: 'Correo', context: '', inputType: 'email', autocomplete: 'email', value: 'a@b.c', frameOrigin: null, href: null, fieldName: null, fieldId: null });
});

test('serializer drops the value of sensitive fields and nulls non-inputs', () => {
  const pw = page.serializeElement(fake({ tag: 'input', attrs: { type: 'password' }, value: 'hunter2' }), 1, 0);
  assert.equal(pw.value, null);
  assert.equal(pw.inputType, 'password');
  const cc = page.serializeElement(fake({ tag: 'input', attrs: { type: 'text', autocomplete: 'cc-number' }, value: '4111' }), 2, 1);
  assert.equal(cc.value, null);
  assert.equal(cc.frame, 1);
  const btn = page.serializeElement(fake({ tag: 'button', text: '  Guardar ', ctx: 'Perfil' }), 4, 0);
  assert.deepEqual(btn, { id: 4, frame: 0, role: 'button', label: 'Guardar', context: 'Perfil', inputType: null, autocomplete: null, value: null, frameOrigin: null, href: null, fieldName: null, fieldId: null });
});

test('serializer caps label length and never emits undefined', () => {
  const out = page.serializeElement(fake({ tag: 'button', text: 'x'.repeat(1000) }), 1, 0);
  assert.ok(out.label.length <= 200);
  assert.ok(!Object.values(out).includes(undefined));
});

test('stale generation or unknown id is stale_id', () => {
  const state = { generation: 3, elements: new Map([[1, fake({ tag: 'button' })]]) };
  assert.equal(page.lookup(state, 3, 1).element.tag, 'button');
  assert.equal(page.lookup(state, 2, 1).error.code, 'stale_id');
  assert.equal(page.lookup(state, 3, 99).error.code, 'stale_id');
  assert.equal(page.lookup(null, 3, 1).error.code, 'stale_id');
  const gone = fake({ tag: 'button' });
  gone.isConnected = false;
  const s2 = { generation: 1, elements: new Map([[1, gone]]) };
  assert.equal(page.lookup(s2, 1, 1).error.code, 'stale_id');
});

test('click dispatches the full sequence with bubbles and composed', () => {
  const el = fake({ tag: 'button' });
  const out = page.clickElement(el);
  assert.deepEqual(out, { done: 'clicked' });
  assert.deepEqual(el.events.map((e) => e.type), ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']);
  for (const e of el.events) {
    assert.equal(e.init.bubbles, true);
    assert.equal(e.init.composed, true);
  }
});

test('type refuses secure_field on sensitive elements without touching them', () => {
  const el = fake({ tag: 'input', attrs: { type: 'password' } });
  const out = page.typeIntoElement(el, 'x');
  assert.equal(out.error.code, 'secure_field');
  assert.equal(el.focused, false);
  assert.equal(el.value, '');
  const cc = fake({ tag: 'input', attrs: { autocomplete: 'one-time-code' } });
  assert.equal(page.typeIntoElement(cc, 'x').error.code, 'secure_field');
});

test('type uses insertText, and falls back to the native setter with input+change', () => {
  const ok = fake({ tag: 'input', attrs: { type: 'text' }, execWorks: true });
  assert.deepEqual(page.typeIntoElement(ok, 'hola'), { done: 'typed' });
  assert.equal(ok.focused, true);
  assert.equal(ok.value, 'hola');
  assert.ok(ok.ownerDocument.execCalls.includes('insertText'));

  const bad = fake({ tag: 'input', attrs: { type: 'text' }, execWorks: false });
  assert.deepEqual(page.typeIntoElement(bad, 'ñ 😀'), { done: 'typed' });
  assert.equal(bad.value, 'ñ 😀');
  assert.deepEqual(bad.events.map((e) => e.type), ['input', 'change']);
  assert.ok(bad.events.every((e) => e.init.bubbles && e.init.composed));
});

// Minimal fake element: only what page.js touches.
function fake({ tag, attrs = {}, text = '', value = '', ctx = '', execWorks = true, editable = false, labels = null, hidden = false, display = 'block', masked = false }) {
  const events = [];
  const doc = {
    execCalls: [],
    defaultView: {
      PointerEvent: class { constructor(type, init) { this.type = type; this.init = init; } },
      MouseEvent: class { constructor(type, init) { this.type = type; this.init = init; } },
      Event: class { constructor(type, init) { this.type = type; this.init = init; } },
      HTMLInputElement: { prototype: {} },
      HTMLTextAreaElement: { prototype: {} },
      getComputedStyle: () => ({ display, visibility: 'visible', webkitTextSecurity: masked ? 'disc' : 'none' }),
    },
    baseURI: 'https://page.test/dir/',
    execCommand(cmd, _ui, arg) {
      this.execCalls.push(cmd);
      if (cmd === 'insertText' && execWorks) { el.value = arg; return true; }
      return cmd === 'selectAll';
    },
  };
  const accessor = {
    configurable: true,
    set(v) { this._v = v; },
    get() { return this._v ?? ''; },
  };
  Object.defineProperty(doc.defaultView.HTMLInputElement.prototype, 'value', accessor);
  Object.defineProperty(doc.defaultView.HTMLTextAreaElement.prototype, 'value', accessor);
  const proto = tag === 'textarea' ? doc.defaultView.HTMLTextAreaElement.prototype
    : tag === 'input' ? doc.defaultView.HTMLInputElement.prototype : Object.prototype;
  const el = Object.create(proto);
  Object.assign(el, {
    tag,
    tagName: tag.toUpperCase(),
    ownerDocument: doc,
    isConnected: true,
    focused: false,
    events,
    textContent: text,
    hidden,
    ...(editable ? { isContentEditable: true } : {}),
    ...(labels ? { labels } : {}),
    closest: () => (ctx ? { getAttribute: (n) => (n === 'aria-label' ? ctx : null), querySelector: () => null } : null),
    getAttribute: (n) => (n in attrs ? attrs[n] : null),
    hasAttribute: (n) => n in attrs,
    focus() { el.focused = true; },
    select() {},
    dispatchEvent(e) { events.push(e); return true; },
  });
  Object.defineProperty(el, 'type', { get: () => attrs.type ?? 'text' });
  if (tag === 'input' || tag === 'textarea') el.value = value;
  return el;
}

// ---- Wave 18 review fixes ----

const SURROGATE = /[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/;

// Shared fixture: keep identical to `sensitiveFixtures` in Tests/CompanionTests/BrowserPolicyTests.swift.
const SENSITIVE_FIXTURES = [
  [{ type: 'text', autocomplete: 'cc-' }, true],
  [{ type: 'text', autocomplete: 'cc-number' }, true],
  [{ type: 'text', name: 'otp' }, true],
  [{ type: 'text', name: 'user_pin' }, true],
  [{ type: 'text', name: 'pin-code' }, true],
  [{ type: 'text', name: 'CVV' }, true],
  [{ type: 'text', name: 'card-cvc' }, true],
  [{ type: 'text', name: 'ssn' }, true],
  [{ type: 'text', name: 'password' }, true],
  [{ type: 'text', name: 'passwd_confirm' }, true],
  [{ type: 'text', id: 'login-otp' }, true],
  [{ type: 'text', name: 'spinner' }, false],
  [{ type: 'text', name: 'pinterest' }, false],
  [{ type: 'text', name: 'mypin' }, false],
  [{ type: 'text', name: 'passwordless' }, false],
  [{ type: 'text', name: 'email', id: 'mail' }, false],
  [{ type: 'text', autocomplete: 'accept' }, false],
];

test('classifier fixture list (parity with Swift)', () => {
  for (const [field, want] of SENSITIVE_FIXTURES) {
    assert.equal(page.isSensitive({ autocomplete: null, name: null, id: null, ...field }), want, JSON.stringify(field));
  }
});

test('masked (-webkit-text-security) inputs are sensitive and lose their value', () => {
  assert.equal(page.isSensitive({ type: 'text', masked: true }), true);
  const el = fake({ tag: 'input', attrs: { type: 'text' }, value: 'secret-pin', masked: true });
  const out = page.serializeElement(el, 1, 0);
  assert.equal(out.value, null);
  assert.equal(page.typeIntoElement(el, 'x').error.code, 'secure_field');
});

test('contenteditable content never reaches the label', () => {
  const el = fake({ tag: 'div', attrs: { contenteditable: 'true' }, text: '123456', editable: true });
  assert.ok(!JSON.stringify(page.serializeElement(el, 1, 0)).includes('123456'));
  const box = fake({ tag: 'div', attrs: { role: 'textbox' }, text: '123456' });
  assert.ok(!JSON.stringify(page.serializeElement(box, 1, 0)).includes('123456'));
  const named = fake({ tag: 'div', attrs: { role: 'searchbox', 'aria-label': 'Buscar' }, text: '123456' });
  assert.equal(page.serializeElement(named, 1, 0).label, 'Buscar');
  const holder = fake({ tag: 'div', attrs: { role: 'combobox', placeholder: 'Elige' }, text: '123456' });
  assert.equal(page.serializeElement(holder, 1, 0).label, 'Elige');
});

test('a sensitive textarea with default text never emits it', () => {
  const el = fake({ tag: 'textarea', attrs: { autocomplete: 'one-time-code' }, text: '884211', value: '884211' });
  assert.ok(!JSON.stringify(page.serializeElement(el, 1, 0)).includes('884211'));
  const plain = fake({ tag: 'textarea', text: 'draft text', value: 'draft text' });
  assert.equal(page.serializeElement(plain, 1, 0).label, '');
});

test('a wrapping <label> that contains the textarea does not leak its text', () => {
  const el = fake({ tag: 'textarea', text: 'secret body', value: 'secret body' });
  el.labels = [{ textContent: 'Notes secret body', contains: (n) => n === el }];
  assert.ok(!page.serializeElement(el, 1, 0).label.includes('secret'));
});

test('selectors that reach for value or autofill state are rejected', () => {
  for (const bad of ['input[value^="4"]', 'INPUT[VALUE="x"]', 'input:autofill', 'input:-webkit-autofill',
    'input:-WEBKIT-AUTOFILL', 'input[val\\75e^=a]', 'a >>> input[value=x]', 'x\\:autofill']) {
    assert.equal(page.parseSelector(bad), null, bad);
  }
  assert.deepEqual(page.parseSelector('button.primary'), ['button.primary']);
});

test('read with a hostile selector returns invalid_args', () => {
  globalThis.document = { querySelectorAll: () => [], body: { innerText: '' } };
  assert.equal(page.read(1, 'input[value^="4"]', null).error.code, 'invalid_args');
  delete globalThis.document;
});

test('the selector branch skips invisible elements', () => {
  const shown = fake({ tag: 'button', text: 'Shown' });
  const hiddenEl = fake({ tag: 'button', text: 'Hidden', hidden: true });
  const none = fake({ tag: 'button', text: 'None', display: 'none' });
  globalThis.document = { querySelectorAll: () => [shown, hiddenEl, none], body: { innerText: '' } };
  const out = page.read(1, 'button', 0);
  assert.deepEqual(out.elements.map((e) => e.label), ['Shown']);
  delete globalThis.document;
});

test('read reports the frame origin from inside the frame', () => {
  globalThis.document = { querySelectorAll: () => [], body: { innerText: 'hi' } };
  globalThis.location = { origin: 'https://ads.test' };
  assert.equal(page.read(1, null, 0).origin, 'https://ads.test');
  delete globalThis.document;
  delete globalThis.location;
});

test('links carry an absolute http(s) href, anything else is null', () => {
  const rel = page.serializeElement(fake({ tag: 'a', attrs: { href: '../x?q=1' }, text: 'go' }), 1, 0);
  assert.equal(rel.href, 'https://page.test/x?q=1');
  const abs = page.serializeElement(fake({ tag: 'a', attrs: { href: 'https://evil.test/a' }, text: 'go' }), 1, 0);
  assert.equal(abs.href, 'https://evil.test/a');
  for (const bad of ['javascript:alert(1)', 'mailto:a@b.c', 'data:text/html,x']) {
    assert.equal(page.serializeElement(fake({ tag: 'a', attrs: { href: bad }, text: 'go' }), 1, 0).href, null, bad);
  }
  assert.equal(page.serializeElement(fake({ tag: 'button', text: 'go' }), 1, 0).href, null);
});

test('field name and id travel for Core to classify', () => {
  const out = page.serializeElement(fake({ tag: 'input', attrs: { type: 'text', name: 'otp_code', id: 'f1' } }), 1, 0);
  assert.equal(out.fieldName, 'otp_code');
  assert.equal(out.fieldId, 'f1');
});

test('type refuses non-editable elements and file inputs without touching the DOM', () => {
  const div = fake({ tag: 'div', text: 'keep me' });
  assert.equal(page.typeIntoElement(div, 'x').error.code, 'invalid_args');
  assert.equal(div.textContent, 'keep me');
  const sel = fake({ tag: 'select', text: 'opts' });
  assert.equal(page.typeIntoElement(sel, 'x').error.code, 'invalid_args');
  const file = fake({ tag: 'input', attrs: { type: 'file' } });
  assert.equal(page.typeIntoElement(file, 'x').error.code, 'invalid_args');
  assert.equal(file.focused, false);
});

test('type still fills a contenteditable through the textContent fallback', () => {
  const el = fake({ tag: 'div', attrs: { contenteditable: 'true' }, editable: true, execWorks: false });
  assert.deepEqual(page.typeIntoElement(el, 'hola'), { done: 'typed' });
  assert.equal(el.textContent, 'hola');
});

test('an emoji straddling the label limit never leaves a lone surrogate', () => {
  const text = 'a'.repeat(199) + '😀' + 'tail';
  const out = page.serializeElement(fake({ tag: 'button', text }), 1, 0);
  assert.ok(!SURROGATE.test(out.label), 'label');
  assert.ok(out.label.startsWith('a'.repeat(199)));
  const ctx = page.serializeElement(fake({ tag: 'button', text: 'x', ctx: 'b'.repeat(119) + '😀' }), 1, 0);
  assert.ok(!SURROGATE.test(ctx.context), 'context');
});

test('read cuts page text on a code point and keeps it well formed', () => {
  const body = 'z'.repeat(199_999) + '😀' + 'end';
  globalThis.document = { querySelectorAll: () => [], body: { innerText: body } };
  const out = page.read(1, null, 0);
  assert.ok(!SURROGATE.test(out.text));
  assert.ok(out.text.length <= 200_000);
  delete globalThis.document;
});

test('the serialized value is clipped to 200 code points', () => {
  const out = page.serializeElement(fake({ tag: 'input', attrs: { type: 'text' }, value: 'v'.repeat(199) + '😀😀' }), 1, 0);
  assert.equal(Array.from(out.value).length, 200);
  assert.ok(!SURROGATE.test(out.value));
});
