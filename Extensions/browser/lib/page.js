// Classic script on purpose: chrome.scripting `files` injection cannot load ES modules.
// It exposes globalThis.__companionPage inside the isolated world, and module.exports for node tests.
(function () {
  const SENSITIVE_AC = /^(cc-.*|one-time-code|current-password|new-password)$/;
  // Keep identical to SENSITIVE_NAME in BrowserPolicy.swift; the shared fixture tests pin both.
  const SENSITIVE_NAME = /(^|[_-])(otp|pin|cvv|cvc|ssn|password|passwd)([_-]|$)/i;
  const LABEL_MAX = 200;
  const VALUE_MAX = 200;
  const HREF_MAX = 2000;
  const NAME_MAX = 80;
  const CONTEXT_MAX = 120;
  const TEXT_MAX = 200000;
  const INTERACTIVE = 'a[href],button,input,select,textarea,summary,[contenteditable=""],[contenteditable="true"],'
    + '[role=button],[role=link],[role=checkbox],[role=radio],[role=switch],[role=tab],[role=menuitem],'
    + '[role=menuitemcheckbox],[role=menuitemradio],[role=option],[role=combobox],[role=textbox],[role=searchbox],[role=treeitem]';

  const attr = (el, name) => (el && typeof el.getAttribute === 'function' ? el.getAttribute(name) : null);
  // Code points, not UTF-16 units: a cut inside an emoji leaves a lone surrogate that breaks JSON.stringify on the wire.
  const wellFormed = (s) => (typeof s.toWellFormed === 'function' ? s.toWellFormed() : s);
  const cutPoints = (s, n) => Array.from(wellFormed(String(s ?? ''))).slice(0, n).join('');
  const clip = (s, n) => cutPoints(String(s ?? '').replace(/\s+/g, ' ').trim(), n);
  const cutUnits = (s, n) => {
    const head = String(s ?? '').slice(0, n);
    const last = head.charCodeAt(head.length - 1);
    return wellFormed(last >= 0xd800 && last <= 0xdbff ? head.slice(0, -1) : head);
  };
  const tagOf = (el) => String(el.tagName || '').toLowerCase();

  function isSensitive(field) {
    if (!field) return false;
    if (String(field.type ?? '').toLowerCase() === 'password') return true;
    if (field.masked === true) return true;
    if (SENSITIVE_NAME.test(String(field.name ?? '')) || SENSITIVE_NAME.test(String(field.id ?? ''))) return true;
    const tokens = String(field.autocomplete ?? '').toLowerCase().split(/\s+/).filter(Boolean);
    return tokens.some((t) => SENSITIVE_AC.test(t));
  }

  function isMasked(el) {
    try {
      const style = el.ownerDocument.defaultView.getComputedStyle(el);
      const mask = style.webkitTextSecurity ?? style.getPropertyValue?.('-webkit-text-security');
      return Boolean(mask) && mask !== 'none';
    } catch {
      return false;
    }
  }

  function fieldOf(el) {
    const tag = tagOf(el);
    const isField = tag === 'input' || tag === 'textarea' || tag === 'select';
    return {
      type: tag === 'input' ? String(el.type || 'text').toLowerCase() : tag === 'textarea' ? 'textarea' : tag === 'select' ? 'select' : null,
      autocomplete: isField ? attr(el, 'autocomplete') : null,
      name: isField ? attr(el, 'name') : null,
      id: isField ? attr(el, 'id') : null,
      masked: tag === 'input' && isMasked(el),
    };
  }

  function isListable(el) {
    const tag = tagOf(el);
    if (tag === 'input' && String(el.type || '').toLowerCase() === 'hidden') return false;
    return typeof el.matches === 'function' ? el.matches(INTERACTIVE) : matchesFallback(el, tag);
  }

  // Fake nodes in tests carry no matches(); the real path above is the source of truth.
  function matchesFallback(el, tag) {
    if (['a', 'button', 'input', 'select', 'textarea', 'summary'].includes(tag)) return true;
    return /^(button|link|checkbox|radio|switch|tab|menuitem|option|combobox|textbox|searchbox|treeitem)$/.test(attr(el, 'role') || '');
  }

  function isContentEditableEl(el) {
    if (el.isContentEditable === true) return true;
    const ce = attr(el, 'contenteditable');
    return ce === '' || ce === 'true' || ce === 'plaintext-only';
  }

  // Anything the user can type into holds content in its text nodes, so its name may never come from textContent.
  function isEditable(el) {
    const tag = tagOf(el);
    if (tag === 'input' || tag === 'textarea' || isContentEditableEl(el)) return true;
    return /^(textbox|searchbox|combobox)$/.test((attr(el, 'role') || '').toLowerCase());
  }

  function parseSelector(raw) {
    if (typeof raw !== 'string' || raw.trim() === '') return null;
    // A selector is an oracle: [value^=4] or :autofill would read a field's content one character at a time.
    // Backslash escapes could spell those words past the check, so any escape is refused.
    if (raw.includes('\\') || /value|autofill/i.test(raw)) return null;
    const parts = raw.split('>>>').map((p) => p.trim());
    return parts.some((p) => p === '') ? null : parts;
  }

  function resolveSelector(root, segments) {
    let scopes = [root];
    for (let i = 0; i < segments.length; i++) {
      const next = [];
      for (const scope of scopes) {
        let found = [];
        try {
          found = Array.from(scope.querySelectorAll(segments[i]));
        } catch {
          found = [];
        }
        next.push(...found);
      }
      if (i === segments.length - 1) return next;
      scopes = next.flatMap((node) => {
        if (node.shadowRoot) return [node.shadowRoot];
        // contentDocument is null for cross-origin frames; those are covered by reading without a selector.
        if (tagOf(node) === 'iframe' && node.contentDocument) return [node.contentDocument];
        return [node];
      });
    }
    return [];
  }

  function roleOf(el) {
    const explicit = attr(el, 'role');
    if (explicit) return explicit.toLowerCase();
    if (isContentEditableEl(el)) return 'textbox';
    const tag = tagOf(el);
    if (tag === 'a') return 'link';
    if (tag === 'button' || tag === 'summary') return 'button';
    if (tag === 'select') return 'combobox';
    if (tag === 'textarea') return 'textbox';
    if (tag === 'input') {
      const t = String(el.type || 'text').toLowerCase();
      if (t === 'button' || t === 'submit' || t === 'reset' || t === 'image') return 'button';
      if (t === 'checkbox' || t === 'radio') return t;
      return 'textbox';
    }
    return 'generic';
  }

  function referencedText(el, ids, editable) {
    const doc = el.ownerDocument;
    if (!ids || !doc || typeof doc.getElementById !== 'function') return '';
    return ids.split(/\s+/).map((id) => {
      const target = doc.getElementById(id);
      if (!target) return '';
      if (editable && (target === el || (typeof target.contains === 'function' && target.contains(el)))) return '';
      return target.textContent ?? '';
    }).join(' ');
  }

  function labelOf(el) {
    const editable = isEditable(el);
    const aria = attr(el, 'aria-label');
    if (aria && aria.trim()) return clip(aria, LABEL_MAX);
    const named = referencedText(el, attr(el, 'aria-labelledby'), editable);
    if (named.trim()) return clip(named, LABEL_MAX);
    const first = el.labels && el.labels.length ? el.labels[0] : null;
    const wraps = first && typeof first.contains === 'function' && first.contains(el) && Boolean(el.textContent);
    if (first && !(editable && wraps)) return clip(first.textContent, LABEL_MAX);
    if (editable) return clip(attr(el, 'placeholder') || attr(el, 'title') || '', LABEL_MAX);
    const own = clip(el.textContent, LABEL_MAX);
    if (own) return own;
    return clip(attr(el, 'placeholder') || attr(el, 'title') || attr(el, 'alt') || '', LABEL_MAX);
  }

  function hrefOf(el) {
    const raw = tagOf(el) === 'a' ? attr(el, 'href') : null;
    if (!raw) return null;
    try {
      const url = new URL(raw, el.ownerDocument?.baseURI);
      return url.protocol === 'http:' || url.protocol === 'https:' ? cutPoints(url.href, HREF_MAX) : null;
    } catch {
      return null;
    }
  }

  function contextOf(el) {
    const box = typeof el.closest === 'function'
      ? el.closest('[role=dialog],form,fieldset,[role=group],section,li,tr')
      : null;
    if (!box) return '';
    const named = attr(box, 'aria-label');
    if (named && named.trim()) return clip(named, CONTEXT_MAX);
    const head = typeof box.querySelector === 'function' ? box.querySelector('legend,h1,h2,h3,h4') : null;
    return head ? clip(head.textContent, CONTEXT_MAX) : '';
  }

  function valueOf(el, field) {
    if (field.type === null || isSensitive(field)) return null;
    if (field.type === 'checkbox' || field.type === 'radio') return el.checked ? 'checked' : 'unchecked';
    if (field.type === 'select') {
      const opt = el.selectedOptions && el.selectedOptions[0];
      return opt ? clip(opt.textContent, LABEL_MAX) : '';
    }
    return cutPoints(el.value ?? '', VALUE_MAX);
  }

  function serializeElement(el, id, frame) {
    const field = fieldOf(el);
    return {
      id,
      frame,
      role: roleOf(el),
      label: labelOf(el),
      context: contextOf(el),
      inputType: field.type,
      autocomplete: field.autocomplete,
      value: valueOf(el, field),
      // The background fills this in for elements that live in a frame of another origin.
      frameOrigin: null,
      href: hrefOf(el),
      fieldName: field.name == null ? null : clip(field.name, NAME_MAX),
      fieldId: field.id == null ? null : clip(field.id, NAME_MAX),
    };
  }

  const stale = (message) => ({ error: { code: 'stale_id', message } });

  function lookup(state, generation, id) {
    if (!state || state.generation !== generation) return stale('generation is out of date, read the page again');
    const element = state.elements.get(id);
    if (!element || element.isConnected === false) return stale('element is gone, read the page again');
    return { element };
  }

  function clickElement(el) {
    const win = el.ownerDocument.defaultView;
    const init = { bubbles: true, cancelable: true, composed: true, view: win, button: 0 };
    for (const [Ctor, type] of [
      [win.PointerEvent, 'pointerdown'], [win.MouseEvent, 'mousedown'],
      [win.PointerEvent, 'pointerup'], [win.MouseEvent, 'mouseup'], [win.MouseEvent, 'click'],
    ]) {
      el.dispatchEvent(new Ctor(type, init));
    }
    return { done: 'clicked' };
  }

  function typeIntoElement(el, text) {
    if (isSensitive(fieldOf(el))) return { error: { code: 'secure_field', message: 'sensitive field, typing refused' } };
    const doc = el.ownerDocument;
    const win = doc.defaultView;
    const tag = tagOf(el);
    const isText = tag === 'input' || tag === 'textarea';
    const unfit = !isText && !isContentEditableEl(el);
    if (unfit || (tag === 'input' && String(el.type || '').toLowerCase() === 'file')) {
      return { error: { code: 'invalid_args', message: 'this element cannot take typed text' } };
    }
    el.focus();
    if (isText && typeof el.select === 'function') el.select();
    else doc.execCommand('selectAll', false);
    const inserted = doc.execCommand('insertText', false, text);
    if (inserted && (!isText || el.value === text)) return { done: 'typed' };
    // Frameworks that ignore execCommand still listen for input/change on the native value.
    const proto = tag === 'textarea' ? win.HTMLTextAreaElement.prototype : win.HTMLInputElement.prototype;
    const setter = isText ? Object.getOwnPropertyDescriptor(proto, 'value')?.set : null;
    if (setter) setter.call(el, text);
    else el.textContent = text;
    const init = { bubbles: true, composed: true };
    el.dispatchEvent(new win.Event('input', init));
    el.dispatchEvent(new win.Event('change', init));
    return { done: 'typed' };
  }

  function stateOf() {
    globalThis.__companionState = globalThis.__companionState || { generation: -1, elements: new Map() };
    return globalThis.__companionState;
  }

  function collect(root, out) {
    for (const node of root.querySelectorAll('*')) {
      if (node.shadowRoot) collect(node.shadowRoot, out);
      if (isListable(node) && isVisible(node)) out.push(node);
    }
  }

  function isVisible(el) {
    if (el.hidden) return false;
    const win = el.ownerDocument.defaultView;
    const style = win.getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden';
  }

  // Ids are local to this document; the background renumbers them across frames and tracks the frame.
  function read(generation, selector, frame) {
    const state = stateOf();
    const doc = document;
    let nodes = [];
    if (selector == null) {
      collect(doc, nodes);
    } else {
      const segments = parseSelector(selector);
      if (!segments) return { error: { code: 'invalid_args', message: 'invalid selector' } };
      nodes = resolveSelector(doc, segments).filter((n) => isListable(n) && isVisible(n));
    }
    state.generation = generation;
    state.elements = new Map();
    const elements = nodes.map((node, i) => {
      state.elements.set(i + 1, node);
      return serializeElement(node, i + 1, frame);
    });
    const scope = selector == null ? doc.body : null;
    const text = selector == null ? cutUnits(scope?.innerText, TEXT_MAX) : '';
    // Each frame reports its own origin so the app can tell third-party frames from the page.
    return { origin: String(globalThis.location?.origin ?? ''), text, elements };
  }

  function act(generation, id, run) {
    const found = lookup(stateOf(), generation, id);
    return found.error ? found : run(found.element);
  }

  const api = {
    isSensitive, isListable, parseSelector, resolveSelector, serializeElement, lookup,
    clickElement, typeIntoElement, read,
    click: (generation, id) => act(generation, id, clickElement),
    type: (generation, id, text) => act(generation, id, (el) => typeIntoElement(el, text)),
  };
  globalThis.__companionPage = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
