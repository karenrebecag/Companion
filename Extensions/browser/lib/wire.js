export const MAX_BYTES = 56 * 1024;
export const BACKOFF_START_MS = 1000;
export const BACKOFF_MAX_MS = 30000;
const FIELD_MAX = 500;

const encoder = new TextEncoder();
const byteLength = (value) => encoder.encode(JSON.stringify(value)).length;

// Code points, not UTF-16 units: a cut inside an emoji leaves a lone surrogate that JSON cannot carry.
export function clipPoints(value, n) {
  const text = String(value ?? '');
  return Array.from(typeof text.toWellFormed === 'function' ? text.toWellFormed() : text).slice(0, n).join('');
}

// The reason is a fixed word naming which check refused; only a string goes out, the host allowlists it.
export function errorReply(id, code, message, reason) {
  return typeof reason === 'string' ? { id, error: { code, message, reason } } : { id, error: { code, message } };
}

export function detectBrowser(nav) {
  const brands = nav?.userAgentData?.brands ?? [];
  if (brands.some((b) => /comet/i.test(b?.brand ?? ''))) return 'comet';
  if (/comet/i.test(nav?.userAgent ?? '')) return 'comet';
  return 'chrome';
}

const isInt = (v) => Number.isInteger(v);
const isText = (v) => typeof v === 'string';
// A blank finder would match every control: refused here too, for a caller that skips the app.
const isSearch = (v) => typeof v === 'string' && v.trim() !== '';
const isBool = (v) => typeof v === 'boolean';
const isCount = (v) => Number.isInteger(v) && v > 0;
const optional = (v, check) => v == null || check(v);

// Shape only: Core owns the path policy. A NUL or a newline would not be one path, and the native
// frame will not carry more than this.
const PATH_MAX = 4096;

function isAbsolutePath(raw) {
  if (typeof raw !== 'string' || raw.length === 0 || raw.length > PATH_MAX) return false;
  if (raw.includes('\0') || raw.includes('\n') || raw.includes('\r')) return false;
  return raw.startsWith('/');
}

// Core polices origins, but a scheme other than http(s) must never reach chrome.tabs.update.
function isHttpURL(raw) {
  if (typeof raw !== 'string') return false;
  try {
    const u = new URL(raw);
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch {
    return false;
  }
}

// Pixels per axis in one scroll; the host refuses more, this only keeps a forged call from flinging the page.
const SCROLL_LIMIT = 20000;
const isPixels = (v) => isInt(v) && Math.abs(v) <= SCROLL_LIMIT;
// Kept in step with BrowserTool.pressKeys on the host.
export const PRESS_KEYS = Object.freeze([
  'Enter', 'Escape', 'Tab', 'Shift+Tab', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
  'Space', 'Backspace', 'Delete', 'Home', 'End', 'PageUp', 'PageDown',
]);
export const PRESS_MAX_TIMES = 10;
// The gate judged one activation; a second Enter lands wherever the first one left the focus.
const PRESS_ONCE = Object.freeze(['Enter', 'Space']);

const pressTimes = (a) => isInt(a.times) && a.times >= 1
  && a.times <= (PRESS_ONCE.includes(a.key) ? 1 : PRESS_MAX_TIMES);
const pressTarget = (a) => (a.generation === null && a.element === null) || (isInt(a.generation) && isInt(a.element));
// A viewport coordinate: no screen is wider than this, so a bigger number is a forged or broken call.
const isPoint = (v) => isInt(v) && v >= 0 && v <= SCROLL_LIMIT;

const SHAPES = {
  browser_tabs: () => true,
  browser_read: (a) => isInt(a.tab) && optional(a.selector, isText) && optional(a.text, isSearch)
    && optional(a.exact, isBool) && optional(a.role, isSearch) && optional(a.name, isSearch)
    && (a.name == null || a.role != null)
    && optional(a.max, isCount) && optional(a.maxChars, isCount)
    // A non-boolean must not widen the read. Absent keeps the visible list.
    && optional(a.hidden, isBool)
    // within names an element of one read, so it means nothing without that read's generation.
    && (a.within == null ? true : isInt(a.within) && isInt(a.generation)),
  browser_click: (a) => isInt(a.tab) && isInt(a.generation) && isInt(a.element),
  browser_double_click: (a) => isInt(a.tab) && isInt(a.generation) && isInt(a.element),
  browser_right_click: (a) => isInt(a.tab) && isInt(a.generation) && isInt(a.element),
  browser_hover: (a) => isInt(a.tab) && isInt(a.generation) && isInt(a.element),
  // Either an element of the last read or an offset, never both.
  browser_scroll: (a) => isInt(a.tab) && (a.element != null
    ? isInt(a.generation) && isInt(a.element) && a.dx == null && a.dy == null
    : isPixels(a.dx) && isPixels(a.dy)),
  browser_press: (a) => isInt(a.tab) && PRESS_KEYS.includes(a.key) && pressTimes(a) && pressTarget(a),
  // Onto another element of the read, or by an offset that goes somewhere; never both.
  browser_drag: (a) => isInt(a.tab) && isInt(a.generation) && isInt(a.element) && (a.to != null
    ? isInt(a.to) && a.to !== a.element && a.dx == null && a.dy == null
    : isPixels(a.dx) && isPixels(a.dy) && (a.dx !== 0 || a.dy !== 0)),
  browser_click_at: (a) => isInt(a.tab) && isInt(a.generation) && isPoint(a.x) && isPoint(a.y),
  browser_type: (a) => isInt(a.tab) && isInt(a.generation) && isInt(a.element) && typeof a.text === 'string',
  browser_select: (a) => isInt(a.tab) && isInt(a.generation) && isInt(a.element) && typeof a.option === 'string',
  browser_set_files: (a) => isInt(a.tab) && isInt(a.generation) && isInt(a.element) && isAbsolutePath(a.path),
  browser_navigate: (a) => isInt(a.tab) && isHttpURL(a.url),
  browser_open: (a) => isHttpURL(a.url),
  browser_take: (a) => isInt(a.tab),
  browser_release: (a) => isInt(a.tab),
};

export function validateCall(params) {
  const bad = (message) => ({ ok: false, error: { code: 'invalid_args', message } });
  if (!params || typeof params !== 'object' || typeof params.name !== 'string') return bad('missing call name');
  const shape = Object.hasOwn(SHAPES, params.name) ? SHAPES[params.name] : null;
  if (!shape) return bad('unknown tool');
  const args = params.arguments && typeof params.arguments === 'object' ? params.arguments : {};
  if (!shape(args)) return bad('invalid arguments for ' + params.name);
  return { ok: true, name: params.name, args };
}

function largest(max, fits) {
  let lo = 0;
  let hi = max;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (fits(mid)) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

function trimPage(message, budget) {
  const source = message.result.page;
  // Title and url are page-controlled and unbounded; they must not be able to eat the whole budget.
  const page = { ...source, title: clipPoints(source.title, FIELD_MAX), url: clipPoints(source.url, FIELD_MAX), origin: clipPoints(source.origin, FIELD_MAX) };
  const build = (elementCount, text) => ({
    ...message,
    result: { ...message.result, page: { ...page, elements: page.elements.slice(0, elementCount), text, truncated: true } },
  });
  // Elements are what the model acts on, so they get first claim on 60% of the budget; text takes the rest.
  const keep = largest(page.elements.length, (n) => byteLength(build(n, '')) <= budget * 0.6);
  const points = Array.from(page.text);
  const kept = largest(points.length, (n) => byteLength(build(keep, points.slice(0, n).join(''))) <= budget);
  return build(keep, points.slice(0, kept).join(''));
}

function trimTabs(message, budget) {
  const tabs = message.result.tabs;
  const build = (n) => ({ ...message, result: { ...message.result, tabs: tabs.slice(0, n) } });
  return build(largest(tabs.length, (n) => byteLength(build(n)) <= budget));
}

export function trimMessage(message, budget = MAX_BYTES) {
  if (byteLength(message) <= budget) return message;
  let out = message;
  if (message?.result?.page) out = trimPage(message, budget);
  else if (Array.isArray(message?.result?.tabs)) out = trimTabs(message, budget);
  if (byteLength(out) <= budget) return out;
  return errorReply(message?.id ?? null, 'frame_too_large', 'the reply does not fit in one frame');
}

// A tab url can carry tokens in its query or fragment, and browser_tabs lists every tab, not just the one in use.
export function sanitizeTab(tab, { controlled = false, createdAt = null } = {}) {
  let url = '';
  try {
    const u = new URL(tab?.url ?? '');
    u.search = '';
    u.hash = '';
    u.username = '';
    u.password = '';
    url = clipPoints(u.href, FIELD_MAX);
  } catch {
    url = '';
  }
  return {
    id: tab?.id,
    title: clipPoints(tab?.title, FIELD_MAX),
    url,
    active: Boolean(tab?.active),
    controlled: controlled === true,
    opener: isInt(tab?.openerTabId) ? tab.openerTabId : null,
    createdAt: isInt(createdAt) ? createdAt : null,
  };
}

const originOf = (url) => {
  try {
    return new URL(url).origin;
  } catch {
    return '';
  }
};

// Frame 0 is first-party text; every other frame goes under its own header so a third-party frame
// cannot pass its words off as the page's.
// Page text can carry a line that looks like a frame header; prefixing it keeps only our own headers authentic.
const neutralizeFrameHeaders = (text) => String(text).replace(/^\[frame /gm, '> [frame ');

// A scoped read (a selector, or inside one element) runs in one frame, so its failure is the answer.
export function buildPage(tab, tabId, generation, scoped, frames, { max = null, maxChars = null } = {}) {
  const failed = frames.find((f) => f.result.error);
  if (failed && scoped) return { error: failed.result.error };
  const pageOrigin = originOf(tab.url ?? '');
  const map = new Map();
  const elements = [];
  const texts = [];
  for (const { frameId, result } of frames) {
    if (result.error) continue;
    const frameOrigin = frameId === 0 || result.origin === pageOrigin ? null : String(result.origin ?? 'null');
    if (result.text) texts.push(frameId === 0 ? neutralizeFrameHeaders(result.text) : '[frame ' + clipPoints(result.origin, FIELD_MAX) + ']\n' + neutralizeFrameHeaders(result.text));
    for (const el of result.elements) {
      if (max != null && elements.length >= max) break;
      const id = elements.length + 1;
      map.set(id, { frameId, localId: el.id });
      elements.push({ ...el, id, frame: frameId, frameOrigin });
    }
  }
  return {
    map,
    page: {
      tab: tabId,
      origin: pageOrigin,
      url: clipPoints(tab.url, FIELD_MAX),
      title: clipPoints(tab.title, FIELD_MAX),
      text: maxChars == null ? texts.join('\n') : clipPoints(texts.join('\n'), maxChars),
      generation,
      elements,
      truncated: false,
    },
  };
}

// Only a hello ack proves the link works, so only it resets the backoff. A refusal (bad token, second
// extension) stops reconnecting until the next alarm tick instead of respawning the host in a loop.
export function reconnectPlan(state, event) {
  switch (event) {
    case 'hello_ok': return { backoff: BACKOFF_START_MS, hold: false, delay: null };
    case 'refused': return { backoff: state.backoff, hold: true, delay: null };
    case 'tick': return { backoff: state.backoff, hold: false, delay: null };
    case 'disconnect':
      if (state.hold) return { backoff: state.backoff, hold: true, delay: null };
      return { backoff: Math.min(state.backoff * 2, BACKOFF_MAX_MS), hold: false, delay: state.backoff };
    default: return { backoff: state.backoff, hold: state.hold, delay: null };
  }
}

export function classifyInbound(message) {
  if (!message || typeof message !== 'object' || message.method !== undefined) return 'other_message';
  if (message.result?.ok === true) return 'hello_ok';
  const code = message.error?.code;
  return code === 'bad_token' || code === 'busy' ? 'refused' : 'other_message';
}

// Seeded from the clock so ids stay monotonic when the service worker restarts and its counter is lost.
export function nextGeneration(previous, now) {
  return Math.max(previous + 1, now);
}

// Whoever claims an id first answers it. A timeout claims it, so a dispatch that finishes later finds
// the id gone and stays silent.
export function makeReplyGuard() {
  const open = new Set();
  return {
    open: (id) => open.add(id),
    claim: (id) => open.delete(id),
  };
}
