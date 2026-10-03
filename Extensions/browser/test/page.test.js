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
function fake({ tag, attrs = {}, text = '', value = '', ctx = '', execWorks = true, editable = false, labels = null, hidden = false, display = 'block', masked = false, parent = null, visibility = 'visible' }) {
  const events = [];
  const doc = {
    execCalls: [],
    defaultView: {
      PointerEvent: class { constructor(type, init) { this.type = type; this.init = init; } },
      MouseEvent: class { constructor(type, init) { this.type = type; this.init = init; } },
      Event: class { constructor(type, init) { this.type = type; this.init = init; } },
      HTMLInputElement: { prototype: {} },
      HTMLTextAreaElement: { prototype: {} },
      getComputedStyle: () => ({ display, visibility, webkitTextSecurity: masked ? 'disc' : 'none' }),
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
    querySelectorAll: () => [],
    dispatchEvent(e) { events.push(e); return true; },
  });
  Object.defineProperty(el, 'type', { get: () => attrs.type ?? 'text' });
  if (tag === 'input' || tag === 'textarea') el.value = value;
  el.parentElement = parent;
  el.ownDisplay = display;
  el.ownVisibility = visibility;
  el.checkVisibility = (options) => fakeCheckVisibility(el, options);
  el.contains = (node) => {
    for (let at = node; at; at = at.parentElement) if (at === el) return true;
    return false;
  };
  return el;
}

// Same rule as Element.checkVisibility for what these tests build: no box when
// the element or an ancestor is `hidden` or `display:none`, and a closed
// `details` renders only its own `summary`. `visibility:hidden` counts only
// when asked, as in the real API.
function fakeCheckVisibility(el, options = {}) {
  const asksVisibility = options.visibilityProperty === true || options.checkVisibilityCSS === true;
  if (asksVisibility && el.ownVisibility === 'hidden') return false;
  let child = null;
  for (let node = el; node; child = node, node = node.parentElement) {
    if (node.hidden || node.ownDisplay === 'none') return false;
    const closedDetails = node.tag === 'details' && !node.hasAttribute('open');
    if (closedDetails && child && child.tag !== 'summary') return false;
  }
  return true;
}

// ---- Wave 18 review fixes ----

const SURROGATE = /[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/;

// Shared fixture: keep identical to `sensitiveFixtures` in Tests/CompanionCoreTests/BrowserReviewTests.swift.
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

// S4 (brief navegador-mejoras-agentes, H-4b): the element's own style missed
// a control hidden by an ancestor, so the model was offered buttons it could
// not see or click.
test('the fake checkVisibility follows ancestors and closed details', () => {
  const box = fake({ tag: 'div', display: 'none' });
  assert.equal(fake({ tag: 'button', parent: box }).checkVisibility(), false);
  assert.equal(fake({ tag: 'button', parent: fake({ tag: 'div', hidden: true }) }).checkVisibility(), false);
  assert.equal(fake({ tag: 'button', parent: fake({ tag: 'div', parent: box }) }).checkVisibility(), false);
  const closed = fake({ tag: 'details' });
  assert.equal(fake({ tag: 'summary', parent: closed }).checkVisibility(), true);
  assert.equal(fake({ tag: 'button', parent: fake({ tag: 'summary', parent: closed }) }).checkVisibility(), true);
  assert.equal(fake({ tag: 'button', parent: closed }).checkVisibility(), false);
  assert.equal(fake({ tag: 'button', parent: fake({ tag: 'details', attrs: { open: '' } }) }).checkVisibility(), true);
});

test('a control hidden by an ancestor is not listed, with or without a selector', () => {
  const shown = fake({ tag: 'button', text: 'Shown' });
  const underNone = fake({ tag: 'button', text: 'UnderNone', parent: fake({ tag: 'div', display: 'none' }) });
  const closed = fake({ tag: 'details' });
  const inClosed = fake({ tag: 'button', text: 'InClosed', parent: closed });
  const inSummary = fake({ tag: 'button', text: 'InSummary', parent: fake({ tag: 'summary', parent: closed }) });
  const invisible = fake({ tag: 'button', text: 'Invisible', visibility: 'hidden' });
  const nodes = [shown, underNone, inClosed, inSummary, invisible];
  globalThis.document = { querySelectorAll: () => nodes, body: { innerText: '' } };
  assert.deepEqual(page.read(1, 'button', 0).elements.map((e) => e.label), ['Shown', 'InSummary']);
  assert.deepEqual(page.read(2, null, 0).elements.map((e) => e.label), ['Shown', 'InSummary']);
  delete globalThis.document;
});

test('without checkVisibility the read falls back to the element own style', () => {
  const bare = (opts) => { const el = fake(opts); delete el.checkVisibility; return el; };
  const nodes = [
    bare({ tag: 'button', text: 'Shown' }),
    bare({ tag: 'button', text: 'None', display: 'none' }),
    bare({ tag: 'button', text: 'Invisible', visibility: 'hidden' }),
  ];
  globalThis.document = { querySelectorAll: () => nodes, body: { innerText: '' } };
  assert.deepEqual(page.read(1, 'button', 0).elements.map((e) => e.label), ['Shown']);
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
  assert.equal(page.typeIntoElement(div, 'x').error.code, 'not_typable');
  assert.equal(div.textContent, 'keep me');
  const sel = fake({ tag: 'select', text: 'opts' });
  assert.equal(page.typeIntoElement(sel, 'x').error.code, 'not_typable');
  const file = fake({ tag: 'input', attrs: { type: 'file' } });
  assert.equal(page.typeIntoElement(file, 'x').error.code, 'not_typable');
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

test('the point under the cursor hits the target when it is the target or inside it', () => {
  const button = fake({ tag: 'button', text: 'Go' });
  const icon = fake({ tag: 'span' });
  icon.parentNode = button;
  const overlay = fake({ tag: 'div' });
  assert.equal(page.hitsTarget(button, button), true);
  assert.equal(page.hitsTarget(button, icon), true);
  assert.equal(page.hitsTarget(button, overlay), false);
  assert.equal(page.hitsTarget(button, null), false);
});

test('a hit inside a shadow root counts through its host', () => {
  const host = fake({ tag: 'my-button' });
  const shadowRoot = { host, parentNode: null };
  const inner = fake({ tag: 'span' });
  inner.parentNode = shadowRoot;
  assert.equal(page.hitsTarget(host, inner), true);
});

test('a hit on another control inside the target is not the target', () => {
  const row = fake({ tag: 'a', attrs: { href: '/item' } });
  const del = fake({ tag: 'button', text: 'Delete' });
  del.parentNode = row;
  assert.equal(page.hitsTarget(row, del), false);
});

test('a hit on something that contains the target is not the target', () => {
  const overlay = fake({ tag: 'div' });
  const button = fake({ tag: 'button', text: 'Go' });
  button.parentNode = overlay;
  assert.equal(page.hitsTarget(button, overlay), false);
});

// prepareType and typedValue look elements up in the page state, as after a read.
function armed(el) {
  globalThis.__companionState = { generation: 1, elements: new Map([[1, el]]) };
  return el;
}

test('prepareType refuses a password or card field before focusing or selecting it', () => {
  for (const attrs of [{ type: 'password' }, { type: 'text', autocomplete: 'cc-number' }]) {
    const el = armed(fake({ tag: 'input', attrs }));
    let selected = 0;
    el.select = () => { selected++; };
    assert.equal(page.prepareType(1, 1).error.code, 'secure_field', JSON.stringify(attrs));
    assert.equal(el.focused, false);
    assert.equal(selected, 0);
  }
});

test('prepareType refuses a file input and an element that takes no text', () => {
  armed(fake({ tag: 'input', attrs: { type: 'file' } }));
  assert.equal(page.prepareType(1, 1).error.code, 'not_typable');
  armed(fake({ tag: 'div' }));
  assert.equal(page.prepareType(1, 1).error.code, 'not_typable');
  armed(fake({ tag: 'select', text: 'opts' }));
  assert.equal(page.prepareType(1, 1).error.code, 'not_typable');
});

test('prepareType focuses a text field and selects its content so the keys replace it', () => {
  const el = armed(fake({ tag: 'input', attrs: { type: 'text' }, value: 'old' }));
  let selected = 0;
  el.select = () => { selected++; };
  assert.deepEqual(page.prepareType(1, 1), { ready: true, multiline: false });
  assert.equal(el.focused, true);
  assert.equal(selected, 1);
});

test('typedValue reads an input by value and an editable by its text', () => {
  armed(fake({ tag: 'input', attrs: { type: 'text' }, value: 'Ana' }));
  assert.deepEqual(page.typedValue(1, 1), { value: 'Ana' });
  armed(fake({ tag: 'div', attrs: { contenteditable: 'true' }, text: 'Hola', editable: true }));
  assert.deepEqual(page.typedValue(1, 1), { value: 'Hola' });
});

// ---- A selector read over an open menu or listbox ----

// A [role=menu]/[role=listbox] container whose descendants are `items`; it is not listable itself.
function container({ role = 'menu', items = [], innerText = '', display = 'block', visible = undefined, shadow = null }) {
  const box = fake({ tag: 'div', attrs: { role }, display });
  box.querySelectorAll = (s) => (s === '*' ? items : []);
  box.innerText = innerText;
  box.contains = (other) => other === box || items.includes(other);
  if (visible !== undefined) box.checkVisibility = () => visible;
  if (shadow) box.shadowRoot = { querySelectorAll: (s) => (s === '*' ? shadow : []) };
  return box;
}

function readWith(matches, selector = '[role=menu]') {
  globalThis.document = { querySelectorAll: () => matches, body: { innerText: 'whole page' } };
  try {
    return page.read(1, selector, 0);
  } finally {
    delete globalThis.document;
  }
}

test('a selector on an open menu lists its items and its text', () => {
  const one = fake({ tag: 'div', attrs: { role: 'menuitem' }, text: 'Uno' });
  const two = fake({ tag: 'div', attrs: { role: 'menuitem' }, text: 'Dos' });
  const out = readWith([container({ items: [one, two], innerText: 'Uno\nDos' })]);
  assert.deepEqual(out.elements.map((e) => e.label), ['Uno', 'Dos']);
  assert.deepEqual(out.elements.map((e) => e.id), [1, 2]);
  assert.equal(out.text, 'Uno\nDos');
});

test('a selector matching both the menu and its items lists each item once', () => {
  const one = fake({ tag: 'div', attrs: { role: 'menuitem' }, text: 'Uno' });
  const two = fake({ tag: 'div', attrs: { role: 'menuitem' }, text: 'Dos' });
  const menu = container({ items: [one, two], innerText: 'Uno\nDos' });
  const out = readWith([menu, one, two], '[role=menu], [role=menuitem]');
  assert.deepEqual(out.elements.map((e) => e.label), ['Uno', 'Dos']);
  assert.deepEqual(out.elements.map((e) => e.id), [1, 2]);
  assert.equal(out.text, 'Uno\nDos');
});

test('a closed menu next to an open one gives neither its items nor its text', () => {
  const hiddenItem = fake({ tag: 'div', attrs: { role: 'menuitem' }, text: 'x' });
  const shownItem = fake({ tag: 'div', attrs: { role: 'menuitem' }, text: 'A' });
  const closed = container({ items: [hiddenItem], innerText: 'SECRET', visible: false });
  const open = container({ items: [shownItem], innerText: 'A' });
  const out = readWith([closed, open]);
  assert.deepEqual(out.elements.map((e) => e.label), ['A']);
  assert.equal(out.text, 'A');
});

test('an open menu with nothing listable is an empty menu, not an error', () => {
  const out = readWith([container({ innerText: 'No hay opciones' })]);
  assert.equal(out.error, undefined);
  assert.deepEqual(out.elements, []);
  assert.equal(out.text, 'No hay opciones');
});

// A broad selector on a hostile page matches tens of thousands of nodes; comparing every pair hangs the tab.
test('finding the outermost matches stays linear in the number of matches', () => {
  let calls = 0;
  const matches = Array.from({ length: 2000 }, () => {
    const box = container({ innerText: 'm' });
    box.contains = (other) => { calls += 1; return other === box; };
    return box;
  });
  readWith(matches, 'div');
  assert.ok(calls <= matches.length * 2, `contains called ${calls} times for ${matches.length} matches`);
});

test('a listbox that is a shadow host lists the options in its own shadow root', () => {
  const opt = fake({ tag: 'div', attrs: { role: 'option' }, text: 'Mexico' });
  const out = readWith([container({ role: 'listbox', shadow: [opt], innerText: 'Mexico' })], '[role=listbox]');
  assert.deepEqual(out.elements.map((e) => e.label), ['Mexico']);
});

test('a container nested in another matched container adds no text twice', () => {
  const opt = fake({ tag: 'div', attrs: { role: 'option' }, text: 'A' });
  const inner = container({ role: 'listbox', items: [opt], innerText: 'A' });
  const outer = container({ role: 'listbox', items: [inner, opt], innerText: 'Pick\nA' });
  const out = readWith([outer, inner], '[role=listbox]');
  assert.equal(out.text, 'Pick\nA');
  assert.deepEqual(out.elements.map((e) => e.label), ['A']);
});

test('the text of a matched container is cut to the page text limit', () => {
  const out = readWith([container({ innerText: 'x'.repeat(250000) })]);
  assert.equal(out.text.length, 200000);
});

test('nothing matching the selector is an error that names the next step, not an empty page', () => {
  const out = readWith([]);
  assert.equal(out.error.code, 'selector_no_match');
  assert.equal(out.elements, undefined);
});

test('a closed menu (only hidden matches) is its own error', () => {
  const one = fake({ tag: 'div', attrs: { role: 'menuitem' }, text: 'Uno' });
  assert.equal(readWith([container({ items: [one], display: 'none' })]).error.code, 'selector_hidden');
  assert.equal(readWith([container({ items: [one], visible: false })]).error.code, 'selector_hidden');
  const hiddenItem = fake({ tag: 'button', text: 'Hidden', hidden: true });
  assert.equal(readWith([hiddenItem], 'button').error.code, 'selector_hidden');
});

test('prepareType tells the background whether the field keeps line breaks', () => {
  armed(fake({ tag: 'textarea' }));
  assert.equal(page.prepareType(1, 1).multiline, true);
  armed(fake({ tag: 'input', attrs: { type: 'text' } }));
  assert.equal(page.prepareType(1, 1).multiline, false);
});

// H-4(a): menus, dialogs and popovers mount in portals at the end of <body>, so a cut in DOM order
// drops exactly what the user just opened.
function pageWithMenuAtTheEnd(linkCount) {
  const links = Array.from({ length: linkCount }, (_, i) => fake({ tag: 'a', text: `Link ${i}`, attrs: { href: `/l${i}` } }));
  const menu = fake({ tag: 'div', attrs: { role: 'menu' } });
  const items = ['Perfil', 'Cerrar sesion'].map((label) => fake({ tag: 'button', text: label, parent: menu }));
  menu.innerText = 'Perfil\nCerrar sesion';
  const body = links.map((l) => l.textContent).join('\n') + '\n' + menu.innerText;
  globalThis.document = {
    querySelectorAll: (selector) => (selector === '*' ? [...links, menu, ...items] : [menu]),
    body: { innerText: body },
  };
  return { links, items };
}

test('an open menu at the end of the page is listed and read first', () => {
  pageWithMenuAtTheEnd(3);
  try {
    const out = page.read(1, null, 0);
    assert.deepEqual(out.elements.slice(0, 2).map((e) => e.label), ['Perfil', 'Cerrar sesion']);
    assert.equal(out.elements.length, 5, 'nothing dropped, only reordered');
    assert.equal(out.elements[0].id, 1, 'ids follow the new order');
    assert.ok(out.text.startsWith('Perfil\nCerrar sesion'), 'the menu text comes first');
    assert.equal(out.text.split('Cerrar sesion').length, 2, 'the menu text is not repeated');
    assert.equal(page.lookup(globalThis.__companionState, 1, 1).element.textContent, 'Perfil');
  } finally {
    delete globalThis.document;
  }
});

test('the open menu survives the wire cut on a page with 1,500 links', async () => {
  const { trimMessage } = await import('../lib/wire.js');
  pageWithMenuAtTheEnd(1500);
  try {
    const read = page.read(1, null, 0);
    const message = { id: 1, result: { page: { tab: 3, url: 'https://x.test', title: 'T', generation: 1, truncated: false, ...read } } };
    const sent = trimMessage(message);
    assert.equal(sent.result.page.truncated, true, 'the page really was cut');
    const labels = sent.result.page.elements.map((e) => e.label);
    assert.ok(labels.includes('Cerrar sesion'), 'the menu item made it');
    assert.ok(sent.result.page.text.includes('Cerrar sesion'), 'so did its text');
  } finally {
    delete globalThis.document;
  }
});

test('a page with no open overlay keeps document order', () => {
  const a = fake({ tag: 'button', text: 'A' });
  const b = fake({ tag: 'button', text: 'B' });
  globalThis.document = { querySelectorAll: (s) => (s === '*' ? [a, b] : []), body: { innerText: 'A B' } };
  try {
    const out = page.read(1, null, 0);
    assert.deepEqual(out.elements.map((e) => e.label), ['A', 'B']);
    assert.equal(out.text, 'A B');
  } finally {
    delete globalThis.document;
  }
});

// Builds a page whose overlay query answers with exactly `overlays`, as the real selector would.
function pageWith({ before = [], overlays = [], after = [], body }) {
  const all = [...before, ...overlays.flatMap((o) => [o.node, ...o.items]), ...after];
  for (const o of overlays) o.node.innerText = o.text;
  globalThis.document = {
    querySelectorAll: (selector) => (selector === '*' ? all : selector === 'button' ? all.filter((n) => n.tag === 'button') : overlays.map((o) => o.node)),
    body: { innerText: body },
  };
}

function overlay(role, labels, { parent = null, display = 'block' } = {}) {
  const node = fake({ tag: 'div', attrs: { role }, parent, display });
  return { node, items: labels.map((label) => fake({ tag: 'button', text: label, parent: node })), text: labels.join('\n') };
}

test('a closed menu is not promoted, and its text stays where it was', () => {
  const link = fake({ tag: 'a', text: 'Inicio', attrs: { href: '/' } });
  const closed = overlay('menu', ['Oculto'], { display: 'none' });
  const open = overlay('dialog', ['Aceptar']);
  pageWith({ before: [link], overlays: [closed, open], body: 'Inicio\nAceptar' });
  try {
    const out = page.read(1, null, 0);
    assert.deepEqual(out.elements.map((e) => e.label), ['Aceptar', 'Inicio']);
    assert.ok(out.text.startsWith('Aceptar'));
    assert.ok(!out.text.includes('Oculto'));
  } finally {
    delete globalThis.document;
  }
});

test('two open overlays are each promoted once, in page order', () => {
  const link = fake({ tag: 'a', text: 'Inicio', attrs: { href: '/' } });
  const first = overlay('menu', ['Uno']);
  const second = overlay('dialog', ['Dos']);
  pageWith({ before: [link], overlays: [first, second], body: 'Inicio\nUno\nDos' });
  try {
    const out = page.read(1, null, 0);
    assert.deepEqual(out.elements.map((e) => e.label), ['Uno', 'Dos', 'Inicio']);
    assert.equal(out.text.split('Uno').length, 2);
    assert.equal(out.text.split('Dos').length, 2);
    assert.ok(out.text.indexOf('Uno') < out.text.indexOf('Dos'));
  } finally {
    delete globalThis.document;
  }
});

test('a listbox inside an open dialog is read once, through the dialog', () => {
  const dialog = overlay('dialog', ['Guardar']);
  const list = overlay('listbox', ['Opcion'], { parent: dialog.node });
  dialog.text = 'Guardar\nOpcion';
  pageWith({ before: [fake({ tag: 'a', text: 'Inicio', attrs: { href: '/' } })], overlays: [dialog, list], body: 'Inicio\nGuardar\nOpcion' });
  try {
    const out = page.read(1, null, 0);
    assert.deepEqual(out.elements.map((e) => e.label), ['Guardar', 'Opcion', 'Inicio']);
    assert.equal(out.text.split('Opcion').length, 2, 'the inner text is not repeated');
  } finally {
    delete globalThis.document;
  }
});

test('overlay text missing from the body is still put first and the body is left whole', () => {
  const open = overlay('dialog', ['Aceptar']);
  pageWith({ overlays: [open], body: 'Cuerpo de la pagina' });
  try {
    assert.equal(page.read(1, null, 0).text, 'Aceptar\n\nCuerpo de la pagina');
  } finally {
    delete globalThis.document;
  }
});

test('a selector read is not reordered', () => {
  const first = fake({ tag: 'button', text: 'Antes' });
  const open = overlay('menu', ['Menu']);
  pageWith({ before: [first], overlays: [open], body: 'Antes\nMenu' });
  try {
    assert.deepEqual(page.read(1, 'button', 0).elements.map((e) => e.label), ['Antes', 'Menu']);
  } finally {
    delete globalThis.document;
  }
});
