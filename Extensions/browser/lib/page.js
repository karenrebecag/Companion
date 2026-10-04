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

  // An open dropdown trigger and a closed one read the same without these, so the model cannot
  // tell whether its click opened anything, and a disabled control looks pressable.
  function statesOf(el) {
    const aria = (name) => el.getAttribute(name);
    const tag = tagOf(el);
    const out = [];
    // :disabled also covers a control inside <fieldset disabled>, which its own property does not.
    if (el.disabled === true || el.matches?.(':disabled') || aria('aria-disabled') === 'true') out.push('disabled');
    const expanded = tag === 'summary' && tagOf(el.parentElement ?? {}) === 'details'
      ? String(el.parentElement.hasAttribute('open'))
      : aria('aria-expanded');
    if (expanded === 'true') out.push('expanded');
    if (expanded === 'false') out.push('collapsed');
    const type = String(el.type || '').toLowerCase();
    const checked = tag === 'input' && (type === 'checkbox' || type === 'radio')
      ? (el.indeterminate ? 'mixed' : String(el.checked === true))
      : aria('aria-checked');
    if (checked === 'true') out.push('checked');
    if (checked === 'false') out.push('unchecked');
    if (checked === 'mixed') out.push('mixed');
    if (aria('aria-pressed') === 'true') out.push('pressed');
    if (aria('aria-selected') === 'true' || (tag === 'option' && el.selected === true)) out.push('selected');
    const popup = aria('aria-haspopup');
    if (popup && popup !== 'false') out.push('haspopup');
    return out;
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
      states: statesOf(el),
    };
  }

  const stale = (message) => ({ error: { code: 'stale_id', message } });

  // What the read showed and the gate judged (label, context, link). The value is left out: typing
  // changes it on purpose; a sensitive field is re-checked live before any key.
  function identityOf(el) {
    return [roleOf(el), labelOf(el), contextOf(el), hrefOf(el) ?? ''].join('\u0000');
  }

  function lookup(state, generation, id) {
    if (!state || state.generation !== generation) return stale('generation is out of date, read the page again');
    const element = state.elements.get(id);
    if (!element || element.isConnected === false) return stale('element is gone, read the page again');
    // A reused or rewritten node keeps its id and stays connected; acting on it would press what nobody approved.
    const seen = state.identities?.get(id);
    if (seen !== undefined && identityOf(element) !== seen) return stale('element changed since the read, read the page again');
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

  function doubleClickElement(el) {
    const win = el.ownerDocument.defaultView;
    // Pages tell a double click by the click count on the second click and on dblclick, not by timing.
    for (const detail of [1, 2]) {
      const init = { bubbles: true, cancelable: true, composed: true, view: win, button: 0, detail };
      for (const [Ctor, type] of [
        [win.PointerEvent, 'pointerdown'], [win.MouseEvent, 'mousedown'],
        [win.PointerEvent, 'pointerup'], [win.MouseEvent, 'mouseup'], [win.MouseEvent, 'click'],
      ]) {
        el.dispatchEvent(new Ctor(type, init));
      }
    }
    el.dispatchEvent(new win.MouseEvent('dblclick', { bubbles: true, cancelable: true, composed: true, view: win, button: 0, detail: 2 }));
    return { done: 'double-clicked' };
  }

  // A right button press fires contextmenu, not click: a page's own menu opens, and nothing it binds to click runs.
  function contextClickElement(el) {
    const win = el.ownerDocument.defaultView;
    const base = { bubbles: true, cancelable: true, composed: true, view: win, button: 2 };
    for (const [Ctor, type, buttons] of [
      [win.PointerEvent, 'pointerdown', 2], [win.MouseEvent, 'mousedown', 2],
      [win.PointerEvent, 'pointerup', 0], [win.MouseEvent, 'mouseup', 0], [win.MouseEvent, 'contextmenu', 0],
    ]) {
      el.dispatchEvent(new Ctor(type, { ...base, buttons }));
    }
    return { done: 'right-clicked' };
  }

  // Enter, then move: menus that open on hover listen to either, and nothing is pressed.
  function hoverElement(el) {
    const win = el.ownerDocument.defaultView;
    const init = { bubbles: true, cancelable: true, composed: true, view: win, button: 0, buttons: 0 };
    for (const [Ctor, type] of [
      [win.PointerEvent, 'pointerover'], [win.PointerEvent, 'pointerenter'],
      [win.MouseEvent, 'mouseover'], [win.MouseEvent, 'mouseenter'],
      [win.PointerEvent, 'pointermove'], [win.MouseEvent, 'mousemove'],
    ]) {
      el.dispatchEvent(new Ctor(type, init));
    }
    return { done: 'hovered' };
  }

  function scrollToElement(el) {
    el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
    return { done: 'scrolled' };
  }

  function typeIntoElement(el, text) {
    if (isSensitive(fieldOf(el))) return { error: { code: 'secure_field', message: 'sensitive field, typing refused' } };
    const doc = el.ownerDocument;
    const win = doc.defaultView;
    const tag = tagOf(el);
    const isText = tag === 'input' || tag === 'textarea';
    const unfit = !isText && !isContentEditableEl(el);
    if (unfit || (tag === 'input' && String(el.type || '').toLowerCase() === 'file')) {
      return { error: { code: 'not_typable', message: 'this element cannot take typed text' } };
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

  // checkVisibility also sees an ancestor's display:none, a closed details and
  // content-visibility, which the element's own style misses. Opacity is not
  // checked: hover-revealed controls are transparent until hovered.
  // HACK: a control with display:contents has no box, so it is not listed.
  // Ask its children when a real page loses a control that way.
  function isVisible(el) {
    if (el.hidden) return false;
    if (typeof el.checkVisibility === 'function') {
      return el.checkVisibility({ checkVisibilityCSS: true, visibilityProperty: true });
    }
    const win = el.ownerDocument.defaultView;
    const style = win.getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden';
  }

  // checkVisibility also sees an ancestor's display:none or a closed <details>; the guard keeps older
  // engines and the node test fakes on the element's own style.
  function isShown(el) {
    if (!isVisible(el)) return false;
    return typeof el.checkVisibility === 'function' ? el.checkVisibility() : true;
  }

  // A selector usually names the open menu or listbox, not its items, so a match stands for its whole
  // subtree. An empty result must say why, or the model reads "nothing" as "nothing is there".
  function readMatches(matches) {
    if (matches.length === 0) {
      return { error: { code: 'selector_no_match', message: 'nothing matches the selector' } };
    }
    const shown = matches.filter(isShown);
    if (shown.length === 0) {
      return { error: { code: 'selector_hidden', message: 'everything the selector matches is hidden' } };
    }
    const seen = new Set();
    const nodes = [];
    const add = (node) => {
      if (seen.has(node)) return;
      seen.add(node);
      nodes.push(node);
    };
    for (const match of shown) {
      if (isListable(match)) add(match);
      const inside = [];
      // collect enters the shadow roots of descendants only, so the match's own root is walked here.
      if (match.shadowRoot) collect(match.shadowRoot, inside);
      collect(match, inside);
      inside.forEach(add);
    }
    // A match inside another match already gave its text through the outer one's innerText. Matches come
    // in document order, so a descendant always follows its ancestor: one comparison with the last kept
    // match suffices, where checking every pair hangs the tab on a broad selector.
    const outermost = [];
    for (const match of shown) {
      const last = outermost[outermost.length - 1];
      if (last && typeof last.contains === 'function' && last.contains(match)) continue;
      outermost.push(match);
    }
    const text = cutUnits(outermost.map((m) => m.innerText ?? '').filter(Boolean).join('\n'), TEXT_MAX);
    return { nodes, text };
  }

  // Ids are local to this document; the background renumbers them across frames and tracks the frame.
  const OVERLAY = 'dialog[open], [aria-modal="true"], [role="dialog"], [role="alertdialog"], [role="menu"], '
    + '[role="listbox"], :popover-open';

  // A page with a menu per row would otherwise make every element test against every overlay.
  const MAX_OVERLAYS = 20;

  // Menus, dialogs and popovers mount in portals at the end of <body>, and the wire keeps the first
  // elements and text when it cuts: in DOM order, what the user just opened is the first thing lost.
  // HACK: an overlay inside a shadow root is not found, so it keeps its DOM place. Walk the shadow
  // roots here when a real page loses an open menu that way.
  function overlayFirst(doc, nodes) {
    const body = String(doc.body?.innerText ?? '');
    const outermost = [];
    for (const candidate of doc.querySelectorAll(OVERLAY)) {
      if (outermost.length === MAX_OVERLAYS) break;
      // A listbox inside an open dialog is already in the dialog's text; keeping both reads it twice.
      if (!isVisible(candidate) || outermost.some((kept) => kept.contains(candidate))) continue;
      outermost.push(candidate);
    }
    if (outermost.length === 0) return { nodes, text: body };
    const roots = new Set(outermost);
    const insideOverlay = (node) => {
      for (let at = node.parentElement; at; at = at.parentElement) if (roots.has(at)) return true;
      return false;
    };
    const front = nodes.filter(insideOverlay);
    const rest = nodes.filter((node) => !insideOverlay(node));
    let remaining = body;
    const parts = [];
    for (const overlay of outermost) {
      const part = String(overlay.innerText ?? '');
      if (!part) continue;
      parts.push(part);
      // The portal sits at the end of the body text too, so its last copy is the one to drop.
      const at = remaining.lastIndexOf(part);
      if (at >= 0) remaining = remaining.slice(0, at) + remaining.slice(at + part.length);
    }
    return { nodes: [...front, ...rest], text: [...parts, remaining].join('\n\n') };
  }

  function read(generation, selector, frame) {
    const state = stateOf();
    const doc = document;
    let nodes = [];
    let text = '';
    if (selector == null) {
      collect(doc, nodes);
      ({ nodes, text } = overlayFirst(doc, nodes));
      text = cutUnits(text, TEXT_MAX);
    } else {
      const segments = parseSelector(selector);
      if (!segments) return { error: { code: 'invalid_args', message: 'invalid selector' } };
      const scoped = readMatches(resolveSelector(doc, segments));
      if (scoped.error) return scoped;
      ({ nodes, text } = scoped);
    }
    state.generation = generation;
    state.elements = new Map();
    state.identities = new Map();
    const elements = nodes.map((node, i) => {
      state.elements.set(i + 1, node);
      state.identities.set(i + 1, identityOf(node));
      return serializeElement(node, i + 1, frame);
    });
    // Each frame reports its own origin so the app can tell third-party frames from the page.
    return { origin: String(globalThis.location?.origin ?? ''), text, elements };
  }

  function act(generation, id, run) {
    const found = lookup(stateOf(), generation, id);
    return found.error ? found : run(found.element);
  }

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const STABLE_TRIES = 10;
  const STABLE_STEP_MS = 40;

  // A popover that re-renders between measure and press makes a trusted click land on nothing,
  // so the box has to hold still across two reads before its center is handed to CDP.
  async function locate(generation, id, token, landingEvent = 'click') {
    const found = lookup(stateOf(), generation, id);
    if (found.error) return found;
    const el = found.element;
    // A selector read reaches into same-origin iframes; their boxes are in the frame's own coordinates.
    if (el.ownerDocument !== document) return { inFrame: true, label: labelOf(el), role: roleOf(el) };
    el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
    let box = null;
    for (let i = 0; i < STABLE_TRIES; i++) {
      const r = el.getBoundingClientRect();
      const next = { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height };
      const still = box && Math.abs(box.x - next.x) < 1 && Math.abs(box.y - next.y) < 1;
      box = next;
      if (still) break;
      await sleep(STABLE_STEP_MS);
    }
    const inView = box.w > 0 && box.h > 0 && box.x >= 0 && box.y >= 0
      && box.x <= window.innerWidth && box.y <= window.innerHeight;
    // A trusted press goes to whatever is on top at that pixel, not to the element: a decoy or a
    // floating third-party frame there would receive a click nobody approved.
    const blocked = inView && !hitsTarget(el, deepElementFromPoint(document, box.x, box.y));
    // A hover passes no landing event: there is no press whose landing could be proven.
    if (inView && !blocked && landingEvent) armLanding(el, token, landingEvent);
    return { box, inView, blocked, label: labelOf(el), role: roleOf(el) };
  }

  function deepElementFromPoint(doc, x, y) {
    let node = doc.elementFromPoint(x, y);
    while (node && node.shadowRoot) {
      const inner = node.shadowRoot.elementFromPoint(x, y);
      if (!inner || inner === node) break;
      node = inner;
    }
    return node;
  }

  // A drag's drop point is measured where the page is: scrolling to the target would move the source the
  // press already holds.
  function boxOf(generation, id) {
    const found = lookup(stateOf(), generation, id);
    if (found.error) return found;
    const el = found.element;
    if (el.ownerDocument !== document) return { inFrame: true };
    const r = el.getBoundingClientRect();
    const box = { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    const inView = r.width > 0 && r.height > 0 && box.x >= 0 && box.y >= 0
      && box.x <= window.innerWidth && box.y <= window.innerHeight;
    return { box, inView };
  }

  const EMBEDS = new Set(['iframe', 'frame', 'object', 'embed']);
  // What each press saw at its point before the cursor glide, by token; weak, so a gone node is not kept alive.
  const pointMarks = new Map();
  const POINT_MARKS_MAX = 16;

  // A press at a bare point goes to the innermost node there, so the frame test walks out from it through
  // shadow hosts: an embedded frame, or anything inside one, belongs to a page nobody read. The token pairs the
  // look before the glide with the one right before the press, so a node that slid in between is caught.
  function pointAt(x, y, token) {
    const node = deepElementFromPoint(document, x, y);
    let frame = false;
    for (let at = node; at; at = at.parentNode ?? at.parentElement ?? at.host ?? null) {
      if (at.tagName && EMBEDS.has(tagOf(at))) { frame = true; break; }
    }
    if (token == null) return { frame, same: true };
    const seen = pointMarks.get(token);
    if (!seen) {
      if (pointMarks.size >= POINT_MARKS_MAX) pointMarks.clear();
      pointMarks.set(token, node ? new WeakRef(node) : null);
      return { frame, same: true };
    }
    return { frame, same: (seen?.deref() ?? null) === (node ?? null) };
  }

  // Re-checked right before the press: the page had the whole cursor glide to slip something on top.
  function hitsAt(generation, id, x, y) {
    const found = lookup(stateOf(), generation, id);
    return !found.error && hitsTarget(found.element, deepElementFromPoint(document, x, y));
  }

  // Walks up through shadow roots to their hosts, so a hit on a web component's inner span counts.
  // Another control on the way up (a Delete button inside a clickable row) is not the approved one.
  function hitsTarget(el, topmost) {
    for (let node = topmost; node; node = node.parentNode ?? node.host ?? null) {
      if (node === el) return true;
      if (node.tagName && isListable(node)) return false;
    }
    return false;
  }

  // Proof the press reached the element and not an overlay on top of it: the trusted click's path must contain it.
  function armLanding(el, token, landingEvent = 'click') {
    const state = stateOf();
    state.landing = { token, hit: false };
    const listener = (event) => {
      if (state.landing?.token !== token) return;
      const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
      state.landing = { token, hit: event.isTrusted === true && path.includes(el) };
    };
    window.addEventListener(landingEvent, listener, { capture: true, once: true });
  }

  // null means this document is not the one that was armed: the click navigated, which is a landing.
  function landed(token) {
    const landing = stateOf().landing;
    return landing && landing.token === token ? landing.hit : null;
  }

  // Runs after the trusted click focused the field; selecting first makes the keys replace, not append.
  function prepareType(generation, id) {
    const found = lookup(stateOf(), generation, id);
    if (found.error) return found;
    const el = found.element;
    if (isSensitive(fieldOf(el))) return { error: { code: 'secure_field', message: 'sensitive field, typing refused' } };
    const tag = tagOf(el);
    const isText = tag === 'input' || tag === 'textarea';
    if ((!isText && !isContentEditableEl(el)) || (tag === 'input' && String(el.type || '').toLowerCase() === 'file')) {
      return { error: { code: 'not_typable', message: 'this element cannot take typed text' } };
    }
    if (el.ownerDocument.activeElement !== el) el.focus();
    if (isText && typeof el.select === 'function') el.select();
    else el.ownerDocument.execCommand('selectAll', false);
    // Keys cannot carry a line break; a textarea can still take them in one insert.
    return { ready: true, multiline: tag === 'textarea' };
  }

  function typedValue(generation, id) {
    const found = lookup(stateOf(), generation, id);
    if (found.error) return found;
    const el = found.element;
    const tag = tagOf(el);
    return { value: tag === 'input' || tag === 'textarea' ? el.value : String(el.textContent ?? '') };
  }

  const api = {
    isSensitive, isListable, parseSelector, resolveSelector, serializeElement, lookup,
    clickElement, doubleClickElement, contextClickElement, hoverElement, scrollToElement, typeIntoElement, armLanding, read, locate, landed, prepareType, typedValue, hitsTarget, hitsAt, boxOf, pointAt,
    click: (generation, id) => act(generation, id, clickElement),
    doubleClick: (generation, id) => act(generation, id, doubleClickElement),
    contextClick: (generation, id) => act(generation, id, contextClickElement),
    hover: (generation, id) => act(generation, id, hoverElement),
    scrollTo: (generation, id) => act(generation, id, scrollToElement),
    viewport: () => ({ w: window.innerWidth, h: window.innerHeight }),
    type: (generation, id, text) => act(generation, id, (el) => typeIntoElement(el, text)),
  };
  globalThis.__companionPage = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
