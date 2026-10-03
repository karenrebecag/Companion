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
  assert.deepEqual(Object.keys(out), ['id', 'frame', 'role', 'label', 'context', 'inputType', 'autocomplete', 'value', 'frameOrigin', 'href', 'fieldName', 'fieldId', 'states']);
  assert.deepEqual(out, { id: 3, frame: 0, role: 'textbox', label: 'Correo', context: '', inputType: 'email', autocomplete: 'email', value: 'a@b.c', frameOrigin: null, href: null, fieldName: null, fieldId: null, states: [] });
});

test('serializer drops the value of sensitive fields and nulls non-inputs', () => {
  const pw = page.serializeElement(fake({ tag: 'input', attrs: { type: 'password' }, value: 'hunter2' }), 1, 0);
  assert.equal(pw.value, null);
  assert.equal(pw.inputType, 'password');
  const cc = page.serializeElement(fake({ tag: 'input', attrs: { type: 'text', autocomplete: 'cc-number' }, value: '4111' }), 2, 1);
  assert.equal(cc.value, null);
  assert.equal(cc.frame, 1);
  const btn = page.serializeElement(fake({ tag: 'button', text: '  Guardar ', ctx: 'Perfil' }), 4, 0);
  assert.deepEqual(btn, { id: 4, frame: 0, role: 'button', label: 'Guardar', context: 'Perfil', inputType: null, autocomplete: null, value: null, frameOrigin: null, href: null, fieldName: null, fieldId: null, states: [] });
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

test('a synthetic double click is two clicks counted 1 and 2, then dblclick', () => {
  const el = fake({ tag: 'button' });
  assert.deepEqual(page.doubleClickElement(el), { done: 'double-clicked' });
  const clicks = el.events.filter((e) => e.type === 'click' || e.type === 'dblclick');
  assert.deepEqual(clicks.map((e) => [e.type, e.init.detail]), [['click', 1], ['click', 2], ['dblclick', 2]]);
  assert.equal(el.events.filter((e) => e.type === 'mousedown').length, 2, 'two presses');
});

test('a synthetic right click presses the right button and asks for the context menu, never a click', () => {
  const el = fake({ tag: 'button' });
  assert.deepEqual(page.contextClickElement(el), { done: 'right-clicked' });
  assert.deepEqual(el.events.map((e) => e.type), ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'contextmenu']);
  for (const e of el.events) {
    assert.equal(e.init.button, 2, `${e.type}: the right button`);
    assert.equal(e.init.bubbles, true);
  }
  const held = Object.fromEntries(el.events.map((e) => [e.type, e.init.buttons]));
  assert.deepEqual([held.pointerdown, held.mousedown, held.pointerup, held.mouseup], [2, 2, 0, 0], 'held while down, released after');
});

test('a synthetic hover enters and moves over the element, and never presses it', () => {
  const el = fake({ tag: 'button' });
  assert.deepEqual(page.hoverElement(el), { done: 'hovered' });
  assert.deepEqual(el.events.map((e) => e.type),
    ['pointerover', 'pointerenter', 'mouseover', 'mouseenter', 'pointermove', 'mousemove']);
  for (const e of el.events) assert.equal(e.init.buttons, 0, `${e.type}: no button held`);
});

test('scrolling to an element centers it without animating', () => {
  const el = fake({ tag: 'section' });
  let asked = null;
  el.scrollIntoView = (options) => { asked = options; };
  assert.deepEqual(page.scrollToElement(el), { done: 'scrolled' });
  assert.deepEqual(asked, { block: 'center', inline: 'nearest', behavior: 'instant' });
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

test('locating for a hover arms no landing, while locating for a click does', async () => {
  const el = fake({ tag: 'button', text: 'Menu' });
  const doc = el.ownerDocument;
  el.scrollIntoView = () => {};
  el.getBoundingClientRect = () => ({ left: 10, top: 20, width: 40, height: 20 });
  const listeners = [];
  const saved = { window: globalThis.window, document: globalThis.document, state: globalThis.__companionState };
  globalThis.window = { innerWidth: 800, innerHeight: 600, addEventListener: (type) => listeners.push(type) };
  globalThis.document = doc;
  doc.elementFromPoint = () => el;
  globalThis.__companionState = { generation: 4, elements: new Map([[1, el]]) };
  try {
    const hover = await page.locate(4, 1, 'h1', null);
    assert.equal(hover.inView, true);
    assert.equal(hover.blocked, false);
    assert.deepEqual(listeners, [], 'nothing armed for a hover');
    await page.locate(4, 1, 'c1', 'click');
    assert.deepEqual(listeners, ['click'], 'a click arms its landing');
  } finally {
    globalThis.window = saved.window;
    globalThis.document = saved.document;
    globalThis.__companionState = saved.state;
  }
});

test('a right click is proven landed by its trusted contextmenu, and a click does not prove it', () => {
  const listeners = {};
  const saved = globalThis.window;
  globalThis.window = { addEventListener: (type, fn) => { listeners[type] = fn; } };
  try {
    const el = fake({ tag: 'button' });
    page.armLanding(el, 'r1', 'contextmenu');
    assert.equal(listeners.click, undefined, 'nothing listens for a click a right press never fires');
    assert.equal(page.landed('r1'), false, 'not landed before the press');
    listeners.contextmenu({ isTrusted: true, composedPath: () => [el] });
    assert.equal(page.landed('r1'), true);
    page.armLanding(el, 'r2', 'contextmenu');
    listeners.contextmenu({ isTrusted: false, composedPath: () => [el] });
    assert.equal(page.landed('r2'), false, 'a page-made event is no proof');
  } finally {
    globalThis.window = saved;
  }
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

// H-1: the gate approved the label, role and link the read showed. A page that rewrites the same node
// between the read and the action (a reused list row, a hostile swap) must not get the press.
function readOne(el) {
  globalThis.document = { querySelectorAll: () => [el], body: { innerText: '' } };
  const out = page.read(1, 'button', 0);
  delete globalThis.document;
  return out;
}

test('an element whose label changed since the read is stale, for every action', () => {
  const el = fake({ tag: 'button', text: 'Siguiente' });
  assert.equal(readOne(el).elements[0].label, 'Siguiente');
  el.textContent = 'Eliminar cuenta';
  assert.equal(page.click(1, 1).error.code, 'stale_id');
  assert.equal(el.events.length, 0, 'nothing dispatched');
  assert.equal(page.lookup(globalThis.__companionState, 1, 1).error.code, 'stale_id');
  assert.equal(page.hitsAt(1, 1, 0, 0), false);
});

test('an element whose role or link changed since the read is stale', () => {
  const button = fake({ tag: 'button', text: 'Go' });
  readOne(button);
  button.getAttribute = (n) => (n === 'role' ? 'link' : null);
  assert.equal(page.click(1, 1).error.code, 'stale_id', 'role');
  const link = fake({ tag: 'a', text: 'Docs', attrs: { href: 'https://page.test/docs' } });
  readOne(link);
  link.getAttribute = (n) => (n === 'href' ? 'https://evil.test/pay' : null);
  assert.equal(page.click(1, 1).error.code, 'stale_id', 'href');
  assert.equal(button.events.length + link.events.length, 0, 'nothing dispatched');
});

test('the trusted paths refuse a changed element before touching it', async () => {
  const button = fake({ tag: 'button', text: 'Siguiente' });
  readOne(button);
  button.textContent = 'Pagar ahora';
  const spot = await page.locate(1, 1, 't');
  assert.equal(spot.error.code, 'stale_id', 'locate');
  assert.equal(spot.box, undefined, 'no box to press');
  assert.equal(page.landed('t'), null, 'no landing armed');

  const field = fake({ tag: 'input', attrs: { placeholder: 'Nombre' } });
  let selected = 0;
  field.select = () => { selected++; };
  globalThis.document = { querySelectorAll: () => [field], body: { innerText: '' } };
  page.read(1, 'input', 0);
  delete globalThis.document;
  field.getAttribute = (n) => (n === 'placeholder' ? 'Contraseña' : null);
  assert.equal(page.prepareType(1, 1).error.code, 'stale_id', 'prepareType');
  assert.equal(field.focused, false);
  assert.equal(selected, 0);
  assert.equal(page.type(1, 1, 'x').error.code, 'stale_id', 'synthetic type');
  assert.equal(field.value, '', 'nothing typed');
  assert.equal(page.typedValue(1, 1).error.code, 'stale_id', 'typedValue');
});

test('an element inside a frame is checked too', async () => {
  const el = fake({ tag: 'button', text: 'Go' });
  readOne(el);
  // The top document is not the element's own, which is how a same-origin iframe looks to locate.
  globalThis.document = { querySelectorAll: () => [], body: { innerText: '' } };
  try {
    assert.equal((await page.locate(1, 1, 't')).inFrame, true, 'unchanged: still the frame path');
    el.textContent = 'Delete';
    assert.equal((await page.locate(1, 1, 't')).error.code, 'stale_id', 'changed: refused');
  } finally {
    delete globalThis.document;
  }
});

// H-4(b): a menu that closed after the read keeps its items in the map; pressing one must not
// report a click that landed on nothing.
function hiddenSinceRead(tag, attrs = {}) {
  const menu = fake({ tag: 'div' });
  const el = armed(fake({ tag, attrs, parent: menu }));
  menu.ownDisplay = 'none';
  return el;
}

test('a click on an element hidden since the read is refused as stale, with no events', () => {
  const el = hiddenSinceRead('button');
  const out = page.click(1, 1);
  assert.equal(out.error?.code, 'stale_id');
  assert.deepEqual(el.events, []);
});

test('typing into a field hidden since the read is refused as stale, untouched', () => {
  const el = hiddenSinceRead('input', { type: 'text' });
  assert.equal(page.type(1, 1, 'x').error?.code, 'stale_id');
  assert.equal(page.prepareType(1, 1).error?.code, 'stale_id');
  assert.equal(el.focused, false);
  assert.equal(el.value, '');
});

test('locate refuses an element hidden since the read before scrolling to it', async () => {
  const el = hiddenSinceRead('button');
  let scrolled = 0;
  el.scrollIntoView = () => { scrolled++; };
  globalThis.document = el.ownerDocument;
  try {
    const out = await page.locate(1, 1, 't');
    assert.equal(out.error?.code, 'stale_id');
    assert.equal(scrolled, 0);
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

// H-7 P1: an open dropdown trigger and a closed one read the same, so the model could not tell
// whether its click opened anything; a disabled control looked pressable.
const statesOf = (el) => page.serializeElement(el, 1, 0).states;

test('the read names disabled, expanded and collapsed controls', () => {
  const off = fake({ tag: 'button', text: 'Enviar' });
  off.disabled = true;
  assert.deepEqual(statesOf(off), ['disabled']);
  assert.deepEqual(statesOf(fake({ tag: 'button', attrs: { 'aria-disabled': 'true' } })), ['disabled']);
  assert.deepEqual(statesOf(fake({ tag: 'button', attrs: { 'aria-expanded': 'true', 'aria-haspopup': 'menu' } })), ['expanded', 'haspopup']);
  assert.deepEqual(statesOf(fake({ tag: 'button', attrs: { 'aria-expanded': 'false', 'aria-haspopup': 'true' } })), ['collapsed', 'haspopup']);
  assert.deepEqual(statesOf(fake({ tag: 'button', attrs: { 'aria-haspopup': 'false' } })), []);
});

test('the read names checked, unchecked and mixed, native or ARIA', () => {
  const box = fake({ tag: 'input', attrs: { type: 'checkbox' } });
  box.checked = true;
  assert.deepEqual(statesOf(box), ['checked']);
  box.checked = false;
  assert.deepEqual(statesOf(box), ['unchecked']);
  box.indeterminate = true;
  assert.deepEqual(statesOf(box), ['mixed']);
  assert.deepEqual(statesOf(fake({ tag: 'div', attrs: { role: 'switch', 'aria-checked': 'true' } })), ['checked']);
  assert.deepEqual(statesOf(fake({ tag: 'div', attrs: { role: 'checkbox', 'aria-checked': 'false' } })), ['unchecked']);
  assert.deepEqual(statesOf(fake({ tag: 'button', attrs: { 'aria-pressed': 'true' } })), ['pressed']);
});

test('the read names a selected tab or option', () => {
  assert.deepEqual(statesOf(fake({ tag: 'div', attrs: { role: 'tab', 'aria-selected': 'true' } })), ['selected']);
  const option = fake({ tag: 'option', text: 'Mexico' });
  option.selected = true;
  assert.deepEqual(statesOf(option), ['selected']);
});

test('a summary says whether its details are open', () => {
  const open = fake({ tag: 'details', attrs: { open: '' } });
  assert.deepEqual(statesOf(fake({ tag: 'summary', parent: open })), ['expanded']);
  assert.deepEqual(statesOf(fake({ tag: 'summary', parent: fake({ tag: 'details' }) })), ['collapsed']);
});

test('a radio reads checked or unchecked, and the native state beats a stale aria-checked', () => {
  const radio = fake({ tag: 'input', attrs: { type: 'radio' } });
  radio.checked = true;
  assert.deepEqual(statesOf(radio), ['checked']);
  radio.checked = false;
  assert.deepEqual(statesOf(radio), ['unchecked']);
  const box = fake({ tag: 'input', attrs: { type: 'checkbox', 'aria-checked': 'false' } });
  box.checked = true;
  assert.deepEqual(statesOf(box), ['checked']);
});

test('a control inside a disabled fieldset reads disabled, as the browser treats it', () => {
  const locked = fake({ tag: 'button', text: 'Enviar' });
  locked.matches = (selector) => selector === ':disabled';
  assert.deepEqual(statesOf(locked), ['disabled']);
});

test('a state built without identities still acts', () => {
  const el = fake({ tag: 'button', text: 'Go' });
  globalThis.__companionState = { generation: 1, elements: new Map([[1, el]]) };
  el.textContent = 'Changed';
  assert.equal(page.lookup(globalThis.__companionState, 1, 1).element, el);
});

test('a button that relabels itself after a press needs a fresh read for the next one', () => {
  const el = uncovered(fake({ tag: 'button', text: 'Mostrar' }));
  readOne(el);
  assert.equal(page.click(1, 1).done, 'clicked');
  el.textContent = 'Ocultar';
  assert.equal(page.click(1, 1).error.code, 'stale_id', 'chosen: the new label was never judged');
});

test('an unchanged element still acts, and typing into it does not make it stale', () => {
  const el = uncovered(fake({ tag: 'button', text: 'Siguiente' }));
  readOne(el);
  assert.equal(page.click(1, 1).done, 'clicked');
  const field = fake({ tag: 'input', attrs: { placeholder: 'Nombre' } });
  globalThis.document = { querySelectorAll: () => [field], body: { innerText: '' } };
  page.read(1, 'input', 0);
  delete globalThis.document;
  field.value = 'Ana';
  assert.equal(page.typedValue(1, 1).value, 'Ana', 'the typed value is read back, not refused as a change');
});

test('an element moved into another dialog or form since the read is stale', () => {
  const el = fake({ tag: 'button', text: 'Confirmar', ctx: 'Newsletter' });
  readOne(el);
  el.closest = () => ({ getAttribute: (n) => (n === 'aria-label' ? 'Confirmar pago' : null), querySelector: () => null });
  assert.equal(page.click(1, 1).error.code, 'stale_id', 'the gate judged the context too');
  assert.equal(el.events.length, 0);
});

test('a visible element is still clicked', () => {
  const el = onScreen(fake({ tag: 'button', parent: fake({ tag: 'div' }) }));
  assert.deepEqual(page.click(1, 1), { done: 'clicked' });
  assert.equal(el.events.length, 5);
});

// H-7 P2a: Incredible reads by finder (find_by_text, find_by_role, scoped el.find, max, max_chars)
// instead of serializing the whole page; browser_read gains the same ways in.
function finderPage(bodyText = 'Bienvenida\nTu pedido se envio\nAyuda') {
  const save = fake({ tag: 'button', text: 'Guardar' });
  const remove = fake({ tag: 'button', text: 'Borrar' });
  const help = fake({ tag: 'a', text: 'Ayuda', attrs: { href: '/ayuda' } });
  const menu = fake({ tag: 'div', attrs: { role: 'menu' } });
  const logout = fake({ tag: 'button', text: 'Cerrar sesion', parent: menu });
  menu.ownDisplay = 'none';
  const all = [save, remove, help, menu, logout];
  globalThis.document = { querySelectorAll: (s) => (s === '*' ? all : []), body: { innerText: bodyText } };
  return { save, remove, help, menu, logout };
}

function withPage(build, run) {
  const nodes = build();
  try {
    return run(nodes);
  } finally {
    delete globalThis.document;
  }
}

test('a text finder lists the controls named by it and the page lines that say it', () => {
  withPage(finderPage, () => {
    const byLabel = page.read(1, { text: 'guardar' }, 0);
    assert.deepEqual(byLabel.elements.map((e) => e.label), ['Guardar']);
    const byLine = page.read(2, { text: 'pedido' }, 0);
    assert.deepEqual(byLine.elements, []);
    assert.equal(byLine.text, 'Tu pedido se envio');
  });
});

test('exact text must match the whole name or line, ignoring case and spacing', () => {
  withPage(finderPage, () => {
    assert.deepEqual(page.read(1, { text: 'guardar', exact: true }, 0).elements.map((e) => e.label), ['Guardar']);
    assert.equal(page.read(2, { text: 'Guar', exact: true }, 0).error?.code, 'selector_no_match');
  });
});

test('a role finder with a name picks that control only', () => {
  withPage(finderPage, () => {
    const out = page.read(1, { role: 'button', name: 'borrar' }, 0);
    assert.deepEqual(out.elements.map((e) => e.label), ['Borrar']);
    assert.deepEqual(page.read(2, { role: 'link' }, 0).elements.map((e) => e.label), ['Ayuda']);
  });
});

test('a finder that only matches hidden controls says so, like a hidden selector', () => {
  withPage(finderPage, () => {
    assert.equal(page.read(1, { text: 'cerrar sesion' }, 0).error?.code, 'selector_hidden');
    assert.equal(page.read(2, { text: 'nada de esto' }, 0).error?.code, 'selector_no_match');
  });
});

test('within reads inside an element from the last read, and a stale one is refused', () => {
  withPage(() => {
    const nodes = finderPage();
    nodes.menu.ownDisplay = 'block';
    nodes.menu.querySelectorAll = () => [nodes.logout];
    nodes.menu.innerText = 'Cerrar sesion';
    globalThis.__companionState = { generation: 1, elements: new Map([[4, nodes.menu]]) };
    return nodes;
  }, () => {
    const out = page.read(2, { withinGeneration: 1, withinLocal: 4 }, 0);
    assert.deepEqual(out.elements.map((e) => e.label), ['Cerrar sesion']);
    assert.equal(out.text, 'Cerrar sesion');
    assert.equal(page.read(3, { withinGeneration: 1, withinLocal: 4 }, 0).error?.code, 'stale_id', 'the read moved on');
  });
});

test('max and maxChars cap what comes back', () => {
  withPage(finderPage, () => {
    const out = page.read(1, { max: 2, maxChars: 10 }, 0);
    assert.equal(out.elements.length, 2);
    assert.equal(out.text, 'Bienvenida');
  });
});

test('a read with no selector and no finder is the whole page, as before', () => {
  withPage(finderPage, () => {
    assert.deepEqual(page.read(1, {}, 0).elements.map((e) => e.label), ['Guardar', 'Borrar', 'Ayuda']);
    assert.deepEqual(page.read(2, null, 0).elements.map((e) => e.label), ['Guardar', 'Borrar', 'Ayuda']);
  });
});

test('a finder inside within or a selector searches only that part', () => {
  withPage(() => {
    const nodes = finderPage();
    const dialog = fake({ tag: 'div', attrs: { role: 'dialog' } });
    const close = fake({ tag: 'button', text: 'Cerrar', parent: dialog });
    const keep = fake({ tag: 'button', text: 'Seguir', parent: dialog });
    dialog.querySelectorAll = (s) => (s === '*' ? [close, keep] : s === 'button' ? [close, keep] : []);
    dialog.innerText = 'Cerrar\nSeguir';
    const base = globalThis.document.querySelectorAll;
    globalThis.document.querySelectorAll = (s) => (s === '[role=dialog]' ? [dialog] : base(s));
    return { ...nodes, dialog };
  }, ({ dialog }) => {
    const armDialog = () => { globalThis.__companionState = { generation: 1, elements: new Map([[9, dialog]]) }; };
    armDialog();
    const inside = page.read(2, { withinGeneration: 1, withinLocal: 9, role: 'button', name: 'cerrar' }, 0);
    assert.deepEqual(inside.elements.map((e) => e.label), ['Cerrar']);
    armDialog();
    assert.equal(page.read(3, { withinGeneration: 1, withinLocal: 9, text: 'Guardar' }, 0).error?.code, 'selector_no_match',
      'a control outside the element does not count');
    const bySelector = page.read(4, { selector: '[role=dialog]', text: 'seguir' }, 0);
    assert.deepEqual(bySelector.elements.map((e) => e.label), ['Seguir']);
    assert.equal(page.read(5, { selector: '[role=dialog]', text: 'cerrar sesion' }, 0).error?.code, 'selector_no_match',
      'a hidden control outside the selector is not "only hidden here"');
  });
});

test('exact applies to a role finder name too', () => {
  withPage(finderPage, () => {
    assert.equal(page.read(1, { role: 'button', name: 'Guar', exact: true }, 0).error?.code, 'selector_no_match');
    assert.deepEqual(page.read(2, { role: 'button', name: 'guardar', exact: true }, 0).elements.map((e) => e.label), ['Guardar']);
  });
});

// H-8: the synthetic click goes to the element itself, whatever sits on top; inside frames and in
// the fallback it is the only click, so it must refuse what the user could not have clicked.
function uncovered(el, { topmost = el, frame = null } = {}) {
  el.getBoundingClientRect = () => ({ left: 10, top: 10, width: 80, height: 20 });
  el.scrollIntoView = () => {};
  Object.assign(el.ownerDocument.defaultView, { innerWidth: 800, innerHeight: 600, frameElement: frame });
  el.ownerDocument.elementFromPoint = () => topmost;
  return el;
}

function onScreen(el, options) {
  return armed(uncovered(el, options));
}

function overlayNode() {
  return { tagName: 'DIV', tag: 'div', getAttribute: () => null, hasAttribute: () => false, parentNode: null };
}

test('a synthetic click on an element under an overlay is refused, with no events', () => {
  const el = onScreen(fake({ tag: 'button', text: 'Borrar' }), { topmost: overlayNode() });
  const out = page.click(1, 1);
  assert.equal(out.error?.code, 'stale_id');
  assert.match(out.error.message, /covers/);
  assert.deepEqual(el.events, []);
});

test('a synthetic click lands when the element, or a part of it, is on top', () => {
  const el = onScreen(fake({ tag: 'button', text: 'Guardar' }));
  assert.deepEqual(page.click(1, 1), { done: 'clicked' });
  const other = fake({ tag: 'button', text: 'Guardar' });
  const icon = overlayNode();
  icon.parentNode = other;
  onScreen(other, { topmost: icon });
  assert.deepEqual(page.click(1, 1), { done: 'clicked' });
  assert.equal(el.events.length, 5);
});

test('a frame covered in the page around it refuses the click inside it', () => {
  const frame = fake({ tag: 'iframe' });
  frame.getBoundingClientRect = () => ({ left: 100, top: 200, width: 400, height: 300 });
  frame.clientLeft = 0;
  frame.clientTop = 0;
  let asked = null;
  frame.ownerDocument.elementFromPoint = (x, y) => { asked = [x, y]; return overlayNode(); };
  Object.assign(frame.ownerDocument.defaultView, { frameElement: null });
  const el = onScreen(fake({ tag: 'button', text: 'Enviar' }), { frame });
  assert.equal(page.click(1, 1).error?.code, 'stale_id');
  assert.deepEqual(asked, [150, 220], 'the point is translated into the parent page');
  assert.deepEqual(el.events, []);
});

test('an element with no box on screen keeps the synthetic click', () => {
  const el = armed(fake({ tag: 'button', text: 'Oculto en scroll' }));
  el.getBoundingClientRect = () => ({ left: 0, top: 0, width: 0, height: 0 });
  el.scrollIntoView = () => {};
  Object.assign(el.ownerDocument.defaultView, { innerWidth: 800, innerHeight: 600, frameElement: null });
  assert.deepEqual(page.click(1, 1), { done: 'clicked' });
});

function frameAt(left, top, { border = [0, 0], parentFrame = null, topmost } = {}) {
  const frame = fake({ tag: 'iframe' });
  frame.getBoundingClientRect = () => ({ left, top, width: 400, height: 300 });
  [frame.clientLeft, frame.clientTop] = border;
  frame.asked = null;
  frame.ownerDocument.elementFromPoint = (x, y) => { frame.asked = [x, y]; return topmost ? topmost(frame) : frame; };
  Object.assign(frame.ownerDocument.defaultView, { frameElement: parentFrame });
  return frame;
}

test('a frame that nothing covers still clicks, whether the frame or a child is hit', () => {
  for (const topmost of [(f) => f, (f) => { const inner = overlayNode(); inner.parentNode = f; return inner; }]) {
    const frame = frameAt(100, 200, { topmost });
    const el = onScreen(fake({ tag: 'button', text: 'Enviar' }), { frame });
    assert.deepEqual(page.click(1, 1), { done: 'clicked' });
    assert.equal(el.events.length, 5);
    assert.deepEqual(frame.asked, [150, 220]);
  }
});

test('a two-level frame chain adds every offset and border on the way up', () => {
  const outer = frameAt(1000, 2000, { border: [5, 7], topmost: () => overlayNode() });
  const inner = frameAt(100, 200, { border: [2, 3], parentFrame: outer });
  const el = onScreen(fake({ tag: 'button', text: 'Enviar' }), { frame: inner });
  assert.equal(page.click(1, 1).error?.code, 'stale_id');
  assert.deepEqual(inner.asked, [152, 223], 'inner frame point, with its border');
  assert.deepEqual(outer.asked, [1157, 2230], 'outer page point, both offsets and borders');
  assert.deepEqual(el.events, []);
});

test('a centre still off screen after scrolling is not hit-tested and keeps the click', () => {
  const el = onScreen(fake({ tag: 'button', text: 'Lejos' }), { topmost: overlayNode() });
  el.getBoundingClientRect = () => ({ left: 900, top: 10, width: 80, height: 20 });
  let asked = false;
  el.ownerDocument.elementFromPoint = () => { asked = true; return overlayNode(); };
  assert.deepEqual(page.click(1, 1), { done: 'clicked' });
  assert.equal(asked, false);
});

test('a listable wrapper on top is not the element, so the click is refused', () => {
  const row = fake({ tag: 'a', text: 'Fila', attrs: { href: '/fila' } });
  row.parentNode = null;
  const el = onScreen(fake({ tag: 'button', text: 'Borrar' }), { topmost: row });
  assert.equal(page.click(1, 1).error?.code, 'stale_id');
  assert.deepEqual(el.events, []);
});

test('a hidden checkbox whose label is on top is not covered by its own label', () => {
  const label = overlayNode();
  label.tagName = 'LABEL';
  const span = overlayNode();
  span.parentNode = label;
  const box = fake({ tag: 'input', attrs: { type: 'checkbox' }, labels: [label] });
  const el = onScreen(box, { topmost: span });
  assert.deepEqual(page.click(1, 1), { done: 'clicked' });
  assert.equal(el.events.length, 5);
});

test('a label for another field on top still covers the element', () => {
  const other = overlayNode();
  other.tagName = 'LABEL';
  const box = fake({ tag: 'input', attrs: { type: 'checkbox' }, labels: [overlayNode()] });
  onScreen(box, { topmost: other });
  assert.equal(page.click(1, 1).error?.code, 'stale_id');
});

test('a padded and scaled frame maps the point through its content box', () => {
  const frame = frameAt(100, 200, { border: [2, 3], topmost: () => overlayNode() });
  frame.ownerDocument.defaultView.getComputedStyle = () => ({ paddingLeft: '10px', paddingTop: '20px' });
  frame.offsetWidth = 200;
  const el = onScreen(fake({ tag: 'button', text: 'Enviar' }), { frame });
  assert.equal(page.click(1, 1).error?.code, 'stale_id');
  // The box is drawn at twice its layout size, so every inner length doubles on the way out.
  assert.deepEqual(frame.asked, [100 + (2 + 10 + 50) * 2, 200 + (3 + 20 + 20) * 2]);
  assert.deepEqual(el.events, []);
});

test('each refusal is a fresh object the caller can change safely', () => {
  onScreen(fake({ tag: 'button', text: 'A' }), { topmost: overlayNode() });
  const first = page.click(1, 1);
  first.error.message = 'changed';
  onScreen(fake({ tag: 'button', text: 'B' }), { topmost: overlayNode() });
  assert.match(page.click(1, 1).error.message, /covers/);
});

test('an element partly on screen is hit-tested where it shows, not let through by its off-screen centre', () => {
  const el = onScreen(fake({ tag: 'button', text: 'Medio fuera' }));
  el.getBoundingClientRect = () => ({ left: 770, top: 10, width: 80, height: 20 });
  let asked = null;
  el.ownerDocument.elementFromPoint = (x, y) => { asked = [x, y]; return overlayNode(); };
  assert.equal(page.click(1, 1).error?.code, 'stale_id');
  assert.deepEqual(asked, [785, 20], 'the centre of the part inside the viewport');
  assert.deepEqual(el.events, []);
});

// ---- P3: browser_select ----

function fakeSelect(labels, { selected = 0, disabled = [], attrs = {}, off = false } = {}) {
  const el = fake({ tag: 'select', attrs });
  el.options = labels.map((label, i) => ({
    textContent: `  ${label}\n`, value: `v${i}`, disabled: disabled.includes(i), selected: i === selected,
  }));
  el.disabled = off;
  return el;
}

const picked = (el) => el.options.filter((o) => o.selected).map((o) => o.textContent.trim());

test('select picks the option by its label and fires input then change', () => {
  const el = fakeSelect(['Argentina', 'México', 'Chile']);
  assert.deepEqual(page.selectOption(el, 'México'), { done: 'selected' });
  assert.deepEqual(picked(el), ['México']);
  assert.deepEqual(el.events.map((e) => e.type), ['input', 'change']);
  assert.ok(el.events.every((e) => e.init.bubbles && e.init.composed));
});

test('select matches a label regardless of case and spacing, exact case first', () => {
  const el = fakeSelect(['Argentina', 'méxico', 'México']);
  page.selectOption(el, '  méxico  ');
  assert.deepEqual(picked(el), ['méxico']);
  const loose = fakeSelect(['Argentina', 'Costa  Rica']);
  page.selectOption(loose, 'COSTA RICA');
  assert.deepEqual(picked(loose), ['Costa  Rica']);
});

// The model only ever sees labels, and the gate judges the words it sent: a value would pick an
// option whose label nobody judged.
test('a value never selects: the miss lists the labels and touches nothing', () => {
  const el = fakeSelect(['Mantener', 'Borrar todo']);
  const out = page.selectOption(el, 'v1');
  assert.equal(out.error.code, 'option_not_found');
  assert.equal(out.error.message, 'Mantener | Borrar todo');
  assert.deepEqual(picked(el), ['Mantener']);
  assert.deepEqual(el.events, []);
});

test('a disabled option neither matches nor is listed', () => {
  const el = fakeSelect(['Uno', 'Dos', 'Tres'], { disabled: [1] });
  const out = page.selectOption(el, 'Dos');
  assert.equal(out.error.code, 'option_not_found');
  assert.equal(out.error.message, 'Uno | Tres');
  assert.deepEqual(picked(el), ['Uno']);
});

// The host cuts an extension message at 300 characters; a label cut there would miss again.
test('the listed labels fit the host cap whole, each cut to 60', () => {
  const many = Array.from({ length: 40 }, (_, i) => `Opcion ${i} ${'x'.repeat(100)}`);
  const out = page.selectOption(fakeSelect(many), 'nada');
  const listed = out.error.message.split(' | ');
  assert.ok(Array.from(out.error.message).length <= 280);
  assert.equal(listed.length, 4);
  assert.ok(listed.every((label) => Array.from(label).length === 60));
  const short = page.selectOption(fakeSelect(Array.from({ length: 50 }, (_, i) => `P${i}`)), 'nada');
  assert.ok(Array.from(short.error.message).length <= 280);
  assert.ok(short.error.message.endsWith(short.error.message.split(' | ').at(-1)));
});

test('an option inside a disabled optgroup neither matches nor is listed', () => {
  const el = fakeSelect(['Uno', 'Dos']);
  el.options[1].matches = (selector) => selector === ':disabled';
  const out = page.selectOption(el, 'Dos');
  assert.deepEqual(out.error, { code: 'option_not_found', message: 'Uno' });
});

test('select refuses what is not a usable <select> without touching it', () => {
  const input = fake({ tag: 'input', attrs: { type: 'text' } });
  assert.equal(page.selectOption(input, 'x').error.code, 'not_selectable');
  assert.deepEqual(input.events, []);
  const off = fakeSelect(['Uno', 'Dos'], { off: true });
  assert.equal(page.selectOption(off, 'Dos').error.code, 'not_selectable');
  assert.deepEqual(picked(off), ['Uno']);
  const fieldsetOff = fakeSelect(['Uno', 'Dos']);
  fieldsetOff.matches = (selector) => selector === ':disabled';
  assert.equal(page.selectOption(fieldsetOff, 'Dos').error.code, 'not_selectable');
});

test('select refuses a sensitive select, such as a card expiry month', () => {
  const el = fakeSelect(['01', '02'], { attrs: { autocomplete: 'cc-exp-month' } });
  assert.equal(page.selectOption(el, '02').error.code, 'secure_field');
  assert.deepEqual(picked(el), ['01']);
  assert.deepEqual(el.events, []);
});

test('choosing the option already selected fires nothing', () => {
  const el = fakeSelect(['Uno', 'Dos'], { selected: 1 });
  assert.deepEqual(page.selectOption(el, 'Dos'), { done: 'selected' });
  assert.deepEqual(el.events, []);
});

test('select goes through the generation check like click and type', () => {
  assert.equal(page.select(999, 1, 'x').error.code, 'stale_id');
});

// A multi-select keeps what the user already chose: choosing adds one option, it never clears the rest.
test('in a multi-select choosing adds the option and keeps the others', () => {
  const el = fakeSelect(['Rojo', 'Verde', 'Azul']);
  el.multiple = true;
  el.options[2].selected = true;
  assert.deepEqual(page.selectOption(el, 'Verde'), { done: 'selected' });
  assert.deepEqual(picked(el), ['Rojo', 'Verde', 'Azul']);
  assert.deepEqual(el.events.map((e) => e.type), ['input', 'change']);
  el.events.length = 0;
  assert.deepEqual(page.selectOption(el, 'Rojo'), { done: 'selected' });
  assert.deepEqual(el.events, []);
});

test('an option label attribute is the label, its text is not', () => {
  const el = fakeSelect(['MX', 'AR']);
  el.options[0].label = 'Mexico';
  el.options[1].label = 'Argentina';
  assert.deepEqual(page.selectOption(el, 'Argentina'), { done: 'selected' });
  assert.deepEqual(picked(el), ['AR']);
  assert.equal(page.selectOption(el, 'MX').error.code, 'option_not_found');
});

test('with two options of the same label the first is chosen, once', () => {
  const el = fakeSelect(['Uno', 'Dos', 'Dos'], { selected: 0 });
  page.selectOption(el, 'Dos');
  assert.deepEqual(el.options.map((o) => o.selected), [false, true, false]);
  assert.equal(el.events.length, 2);
});

test('a list without enabled options misses with nothing to list', () => {
  const out = page.selectOption(fakeSelect(['Uno'], { disabled: [0] }), 'Uno');
  assert.deepEqual(out.error, { code: 'option_not_found', message: '' });
});
