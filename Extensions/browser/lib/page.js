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

  // Implicit submission presses the form's default button, so that button's label is what an Enter in
  // the field would do. '' is a form with no submit button; null is a field outside any form.
  // The default is the first submit control the form owns in tree order: form.elements includes the
  // ones tied in by form="id", and .type reports an invalid or missing button type as submit. A
  // disabled default still is the default (Enter then submits nothing), so it is not skipped.
  function submitOf(el, field) {
    if (field.type === null || field.type === 'select' || !el.form) return null;
    const button = Array.from(el.form.elements ?? []).find((node) => {
      const tag = tagOf(node);
      const type = String(node.type ?? '').toLowerCase();
      return (tag === 'button' || tag === 'input') && (type === 'submit' || type === 'image');
    });
    return button ? buttonLabel(button) : '';
  }

  // labelOf treats every <input> as a field; a submit or image input shows its value or alt instead,
  // and with neither the browser shows "Submit", which is what it does.
  function buttonLabel(button) {
    const own = labelOf(button);
    if (own || tagOf(button) !== 'input') return own;
    const shown = attr(button, 'value') || attr(button, 'alt');
    return shown ? clip(shown, LABEL_MAX) : String(button.type ?? '').toLowerCase() === 'submit' ? 'Submit' : '';
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
      submit: submitOf(el, field),
    };
  }

  // One code for the model, a reason for the logs: a live stale_id has to say which check refused it.
  const stale = (message, reason) => ({ error: { code: 'stale_id', message, reason } });

  // What the read showed and the gate judged (label, context, link). The value is left out: typing
  // changes it on purpose; a sensitive field is re-checked live before any key.
  function identityOf(el) {
    return [roleOf(el), labelOf(el), contextOf(el), hrefOf(el) ?? ''].join('\u0000');
  }

  // As in Incredible, a few recent reads stay usable: a read the host never saw (one that timed out, or
  // finished after a newer one) must not void the ids the host is still pointing at.
  const READS_KEPT = 20;

  function readOf(state, generation) {
    if (!state) return null;
    if (state.generation === generation) return state;
    return state.reads?.get(generation) ?? null;
  }

  function lookupIn(read, id) {
    if (!read) return stale('generation is out of date, read the page again', 'generation_mismatch');
    const element = read.elements.get(id);
    if (!element) return stale('element is gone, read the page again', 'unknown_element');
    if (element.isConnected === false) return stale('element is gone, read the page again', 'element_gone');
    // A reused or rewritten node keeps its id and stays connected; acting on it would press what nobody approved.
    const seen = read.identities?.get(id);
    if (seen !== undefined && identityOf(element) !== seen) {
      return stale('element changed since the read, read the page again', 'identity_changed');
    }
    return { element };
  }

  function lookup(state, generation, id) {
    return lookupIn(readOf(state, generation), id);
  }

  // within narrows the next read to a part of the page the model is looking at now, so only the last read counts.
  function lookupLatest(state, generation, id) {
    return lookupIn(state && state.generation === generation ? state : null, id);
  }

  // Every press and insert goes through here: a menu that closed after the read keeps its items in
  // the map, and acting on one would report a click or text that landed on nothing.
  function lookupShown(state, generation, id) {
    const found = lookup(state, generation, id);
    if (found.error || isShown(found.element)) return found;
    return stale('element is hidden now, read the page again', 'hidden');
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

  const OPTION_MAX = 60;
  // Under the host's 300-character cap on an extension message, so the last label arrives whole.
  const OPTIONS_BUDGET = 280;
  const collapse = (s) => String(s ?? '').replace(/\s+/g, ' ').trim();
  const optionLabel = (o) => collapse(typeof o.label === 'string' ? o.label : o.textContent);

  // By label only: the read never shows an option's value, and the gate judged the words the model
  // sent, so a value would choose an option whose label nobody judged.
  function selectOption(el, wanted) {
    if (tagOf(el) !== 'select') return { error: { code: 'not_selectable', message: 'this element is not a list of options' } };
    if (isSensitive(fieldOf(el))) return { error: { code: 'secure_field', message: 'sensitive field, choosing refused' } };
    // A disabled fieldset disables its controls without setting their own flag.
    if (el.disabled === true || (typeof el.matches === 'function' && el.matches(':disabled'))) {
      return { error: { code: 'not_selectable', message: 'this list is disabled' } };
    }
    const all = Array.from(el.options ?? []);
    // A disabled <optgroup> disables its options without setting their own flag.
    const usable = all.filter((o) => !o.disabled && !(typeof o.matches === 'function' && o.matches(':disabled')));
    const want = collapse(wanted);
    const match = usable.find((o) => optionLabel(o) === want)
      ?? usable.find((o) => optionLabel(o).toLowerCase() === want.toLowerCase());
    if (!match) {
      const listed = [];
      let used = 0;
      for (const o of usable) {
        const label = clip(optionLabel(o), OPTION_MAX);
        const cost = Array.from(label).length + (listed.length ? 3 : 0);
        if (used + cost > OPTIONS_BUDGET) break;
        listed.push(label);
        used += cost;
      }
      return { error: { code: 'option_not_found', message: listed.join(' | ') } };
    }
    // A real choice of the same option fires nothing, and a change handler may act on every event.
    // A multi-select keeps what the user already chose there.
    if (el.multiple ? match.selected : all.every((o) => o.selected === (o === match))) return { done: 'selected' };
    if (el.multiple) match.selected = true;
    else for (const o of all) o.selected = o === match;
    const win = el.ownerDocument.defaultView;
    const init = { bubbles: true, composed: true };
    el.dispatchEvent(new win.Event('input', init));
    el.dispatchEvent(new win.Event('change', init));
    return { done: 'selected' };
  }

  // Open shadow roots keep their own activeElement; the document only sees the host.
  function deepActive(doc) {
    let node = doc.activeElement ?? null;
    while (node && node.shadowRoot && node.shadowRoot.activeElement) node = node.shadowRoot.activeElement;
    return node;
  }

  // A trusted key lands on whatever holds the focus, so it only goes out once the element holds it.
  function focusElement(el) {
    if (typeof el.focus === 'function') el.focus({ preventScroll: false });
    return { focused: deepActive(el.ownerDocument) === el };
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

  // innerText of a body that is not rendered (a frame inside a hidden preview) is its textContent: every
  // script and config blob in it, none of which the user can see.
  function bodyText(doc) {
    const body = doc.body;
    if (!body) return '';
    if (typeof body.checkVisibility === 'function' && !body.checkVisibility()) return '';
    return String(body.innerText ?? '');
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
    const body = bodyText(doc);
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


  // Incredible's finders: by text, by role and name, inside an element. Names and lines compare
  // without case or runs of spacing, since the model types what it read, not the markup.
  const squash = (value) => String(value ?? '').replace(/\s+/g, ' ').trim().toLowerCase();
  const says = (value, wanted, exact) => (exact ? squash(value) === squash(wanted) : squash(value).includes(squash(wanted)));
  const hasFinder = (q) => q.text != null || q.role != null;

  function fits(node, q) {
    if (q.role != null && roleOf(node) !== String(q.role).toLowerCase()) return false;
    if (q.name != null && !says(labelOf(node), q.name, q.exact)) return false;
    // textContent, not innerText: innerText lays the page out again for every control tested.
    // HACK: only the first 4 KB of a control's text is searched, so nested wrappers stay linear. Raise it
    // when a real control's name sits deeper than that.
    if (q.text != null && !says(labelOf(node), q.text, q.exact) && !says(String(node.textContent ?? '').slice(0, 4096), q.text, q.exact)) return false;
    return true;
  }

  // An empty answer must say why, as a selector's does: "nothing here" and "only hidden here" lead
  // the model to different next steps.
  function find(nodes, text, q, scopes) {
    const matched = nodes.filter((node) => fits(node, q));
    const lines = q.text == null ? [] : text.split('\n').filter((line) => line.trim() && says(line, q.text, q.exact));
    if (matched.length > 0 || lines.length > 0) {
      const own = q.text == null ? matched.map((node) => String(node.innerText ?? node.textContent ?? '').trim()).filter(Boolean) : lines;
      return { nodes: matched, text: own.join('\n') };
    }
    // Only the part searched counts: a hidden control elsewhere would wrongly say "it is here, hidden".
    const anyHidden = scopes.some((root) => [root, ...Array.from(root.querySelectorAll('*'))]
      .some((node) => node.tagName && isListable(node) && !isVisible(node) && fits(node, q)));
    return anyHidden
      ? { error: { code: 'selector_hidden', message: 'everything the search matches is hidden' } }
      : { error: { code: 'selector_no_match', message: 'nothing matches the search' } };
  }

  function scopeOf(q, state) {
    if (q.withinLocal == null) return { root: document };
    const found = lookupLatest(state, q.withinGeneration, q.withinLocal);
    return found.error ? found : { root: found.element };
  }

  function read(generation, query, frame) {
    const q = query == null || typeof query === 'string' ? { selector: query ?? null } : query;
    const state = stateOf();
    const doc = document;
    const scope = scopeOf(q, state);
    if (scope.error) return scope;
    let nodes = [];
    let text = '';
    if (q.selector == null && scope.root === doc && !hasFinder(q)) {
      collect(doc, nodes);
      ({ nodes, text } = overlayFirst(doc, nodes));
    } else {
      let scoped;
      let roots = [scope.root];
      if (q.selector != null) {
        const segments = parseSelector(q.selector);
        if (!segments) return { error: { code: 'invalid_args', message: 'invalid selector' } };
        roots = resolveSelector(scope.root, segments);
        scoped = readMatches(roots);
      } else if (scope.root !== doc) {
        scoped = readMatches([scope.root]);
      } else {
        const all = [];
        collect(doc, all);
        scoped = { nodes: all, text: bodyText(doc) };
      }
      if (scoped.error) return scoped;
      if (hasFinder(q)) scoped = find(scoped.nodes, scoped.text, q, roots);
      if (scoped.error) return scoped;
      ({ nodes, text } = scoped);
    }
    if (Number.isInteger(q.max) && q.max > 0) nodes = nodes.slice(0, q.max);
    text = cutUnits(text, Number.isInteger(q.maxChars) && q.maxChars > 0 ? Math.min(q.maxChars, TEXT_MAX) : TEXT_MAX);
    const kept = new Map(state.reads ?? []);
    kept.set(generation, {
      elements: new Map(nodes.map((node, i) => [i + 1, node])),
      identities: new Map(nodes.map((node, i) => [i + 1, identityOf(node)])),
    });
    const reads = new Map([...kept].sort(([a], [b]) => a - b).slice(-READS_KEPT));
    // Generations only grow, so a read that finishes after a newer one never becomes the frame's latest.
    // HACK: ordering trusts the background's wall-clock-seeded generations; a worker restart after the clock
    // went back leaves an older read as latest. Report the highest held generation to seed the counter once
    // within or click_at are seen refusing fresh reads after a restart.
    const latest = Math.max(...reads.keys());
    Object.assign(state, { reads, generation: latest, ...reads.get(latest) });
    const elements = nodes.map((node, i) => serializeElement(node, i + 1, frame));
    // Each frame reports its own origin so the app can tell third-party frames from the page.
    return { origin: String(globalThis.location?.origin ?? ''), text, elements };
  }

  function act(generation, id, run) {
    const found = lookupShown(stateOf(), generation, id);
    return found.error ? found : run(found.element);
  }

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const STABLE_TRIES = 10;
  const STABLE_STEP_MS = 40;

  // A popover that re-renders between measure and press makes a trusted click land on nothing,
  // so the box has to hold still across two reads before its center is handed to CDP.
  async function locate(generation, id, token, landingEvent = 'click') {
    const found = lookupShown(stateOf(), generation, id);
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

  // A closed root hides from the page but not from an extension. Only the frame test opens it: a read cannot
  // list what is inside a closed root, so a click hit test that went in would refuse the host it read.
  function shadowOf(node, closed) {
    if (node.shadowRoot) return node.shadowRoot;
    if (!closed) return null;
    try {
      return globalThis.chrome?.dom?.openOrClosedShadowRoot?.(node) ?? null;
    } catch {
      return null;
    }
  }

  function deepElementFromPoint(doc, x, y, { closed = false } = {}) {
    let node = doc.elementFromPoint(x, y);
    for (let root = node && shadowOf(node, closed); root; root = node && shadowOf(node, closed)) {
      const inner = root.elementFromPoint(x, y);
      if (!inner || inner === node) break;
      node = inner;
    }
    return node;
  }

  const covered = () => stale('something covers this element (a dialog or banner); read the page again', 'covered');

  // A styled checkbox or radio hides the input and draws its label on top: the label is how a person
  // presses it, so being under its own label is not being covered.
  function reachable(el, topmost) {
    return hitsTarget(el, topmost) || Array.from(el.labels ?? []).some((label) => hitsTarget(label, topmost));
  }

  // The synthetic click is dispatched on the element itself, so an overlay never stops it; inside
  // frames and in the trusted path's fallback it is the only click, and it must refuse what the user
  // could not have pressed. Each same-origin frame up the chain is checked in its parent's coordinates.
  // HACK: a cross-origin parent hides its frameElement, so every cross-origin frame (ads, payments,
  // sign-in) is unchecked against overlays in the page around it. Hit-test the frame's box from the
  // top document in the background before the synthetic click once the agent acts in such frames.
  function isCovered(el) {
    el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
    const r = el.getBoundingClientRect();
    let win = el.ownerDocument.defaultView;
    // Only the part on screen is tested: a centre pushed just off screen must not skip the check.
    const left = Math.max(r.left, 0);
    const top = Math.max(r.top, 0);
    const right = Math.min(r.left + r.width, win.innerWidth);
    const bottom = Math.min(r.top + r.height, win.innerHeight);
    // Nothing on screen leaves nothing to hit-test; that case keeps the click it always had.
    if (!(right > left && bottom > top)) return false;
    let x = (left + right) / 2;
    let y = (top + bottom) / 2;
    let target = el;
    for (;;) {
      if (!reachable(target, deepElementFromPoint(target.ownerDocument, x, y))) return true;
      const frame = win.frameElement;
      if (!frame) return false;
      // The frame's document starts inside its border and padding, and a CSS transform scales it.
      const box = frame.getBoundingClientRect();
      const style = frame.ownerDocument.defaultView.getComputedStyle(frame);
      const scale = frame.offsetWidth > 0 ? box.width / frame.offsetWidth : 1;
      x = box.left + ((frame.clientLeft || 0) + (parseFloat(style.paddingLeft) || 0) + x) * scale;
      y = box.top + ((frame.clientTop || 0) + (parseFloat(style.paddingTop) || 0) + y) * scale;
      target = frame;
      win = frame.ownerDocument.defaultView;
    }
  }

  function clickUncovered(el) {
    return isCovered(el) ? covered() : clickElement(el);
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

  const EMBEDS = new Set(['iframe', 'frame', 'object', 'embed', 'fencedframe', 'portal']);
  // What each press saw at its point before the cursor glide, by token; weak, so a gone node is not kept alive.
  const pointMarks = new Map();
  const POINT_MARKS_MAX = 16;

  // A press at a bare point goes to the innermost node there, so the frame test walks out from it through
  // shadow hosts: an embedded frame, or anything inside one, belongs to a page nobody read. The token pairs the
  // look before the glide ('mark') with the one right before the press ('check'), so a node that slid in
  // between is caught; a check with no mark fails closed, and each check spends its mark.
  function pointAt(x, y, token, phase) {
    const node = deepElementFromPoint(document, x, y, { closed: true });
    let frame = false;
    for (let at = node; at; at = at.parentNode ?? at.parentElement ?? at.host ?? null) {
      if (at.tagName && EMBEDS.has(tagOf(at))) { frame = true; break; }
    }
    if (token == null) return { frame, same: true };
    if (phase === 'mark') {
      if (pointMarks.size >= POINT_MARKS_MAX) pointMarks.clear();
      pointMarks.set(token, node ? new WeakRef(node) : null);
      return { frame, same: true };
    }
    if (!pointMarks.has(token)) return { frame, same: false };
    const seen = pointMarks.get(token);
    pointMarks.delete(token);
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
    const found = lookupShown(stateOf(), generation, id);
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
    clickElement, doubleClickElement, contextClickElement, hoverElement, scrollToElement, typeIntoElement, armLanding, read, locate, landed, prepareType, typedValue, hitsTarget, hitsAt, selectOption, boxOf, pointAt, focusElement,
    click: (generation, id) => act(generation, id, clickUncovered),
    doubleClick: (generation, id) => act(generation, id, doubleClickElement),
    contextClick: (generation, id) => act(generation, id, contextClickElement),
    hover: (generation, id) => act(generation, id, hoverElement),
    scrollTo: (generation, id) => act(generation, id, scrollToElement),
    viewport: () => ({ w: window.innerWidth, h: window.innerHeight }),
    type: (generation, id, text) => act(generation, id, (el) => typeIntoElement(el, text)),
    select: (generation, id, option) => act(generation, id, (el) => selectOption(el, option)),
    focus: (generation, id) => act(generation, id, focusElement),
  };
  globalThis.__companionPage = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
