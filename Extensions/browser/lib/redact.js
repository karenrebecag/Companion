// A page-controlled URL or string can carry a secret without anyone pressing one. Two
// boundaries scrub them where they leave the extension: `redactUrl` for an address,
// `cleanText` for the words around it. One rule here so the host never has to second-guess.

const REDACTED = 'redacted';
const MAX_NESTED_DEPTH = 2;

// Compared with separators removed, so api_key, api-key and apikey are one entry.
const SENSITIVE_SUFFIXES = new Set([
  'token', 'secret', 'password', 'passwd', 'pwd', 'pass', 'session', 'sessionid', 'sid', 'sig',
  'signature', 'credential', 'otp', 'jwt', 'apikey', 'key', 'auth', 'authorization', 'code',
  'codeverifier', 'state', 'ticket',
]);
// Fail closed: these are redacted wherever they sit in the name.
const SENSITIVE_SUBSTRING = /token|secret|passw|credential|signature/;
const JWT_VALUE = /^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$/;

// '+' is a space in a query string; a name that will not decode is matched as written.
function normaliseName(raw) {
  const spaced = String(raw ?? '').replace(/\+/g, ' ');
  let name;
  try {
    name = decodeURIComponent(spaced);
  } catch {
    name = spaced;
  }
  return name.trim().replace(/\[\]$/, '');
}

// Cuts at separators and at camelCase boundaries (sessionToken), so a suffix is a whole word.
function wordsOf(name) {
  return name.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase().split(/[_\-.\s]+/).filter(Boolean);
}

function isSensitiveName(raw) {
  const name = normaliseName(raw);
  if (SENSITIVE_SUBSTRING.test(name.toLowerCase())) return true;
  const words = wordsOf(name);
  return words.some((_, i) => SENSITIVE_SUFFIXES.has(words.slice(i).join('')));
}

function decodeValue(raw) {
  try {
    return decodeURIComponent(raw.replace(/\+/g, ' '));
  } catch {
    return raw;
  }
}

// A value is secret by shape (JWT) or because it is itself an address carrying a secret.
function redactValue(raw, depth) {
  const decoded = decodeValue(raw);
  if (JWT_VALUE.test(decoded)) return REDACTED;
  if (depth >= MAX_NESTED_DEPTH || !/^https?:\/\//i.test(decoded)) return raw;
  const inner = redactAt(decoded, depth + 1);
  return inner === '' || inner === decoded ? raw : encodeURIComponent(inner);
}

// Pairs split on '&' and ';'; separators are kept so the rest of the string is untouched.
function redactKeyValues(raw, depth) {
  if (typeof raw !== 'string' || raw === '') return '';
  return raw.split(/([&;])/).map((part, i) => {
    if (i % 2 === 1) return part;
    const eq = part.indexOf('=');
    if (eq < 0) return isSensitiveName(part) ? part + '=' + REDACTED : part;
    const name = part.slice(0, eq);
    if (isSensitiveName(name)) return name + '=' + REDACTED;
    return name + '=' + redactValue(part.slice(eq + 1), depth);
  }).join('');
}

// Hash routers keep their real query after a '?' inside the fragment (#/cb?token=...).
function redactFragment(fragment, depth) {
  const q = fragment.indexOf('?');
  if (q < 0) return redactKeyValues(fragment, depth);
  return fragment.slice(0, q + 1) + redactKeyValues(fragment.slice(q + 1), depth);
}

function redactAt(raw, depth) {
  if (typeof raw !== 'string' || raw === '') return '';
  let url;
  try {
    url = new URL(raw);
  } catch {
    return '';
  }
  // user:pass@ is a credential by definition.
  url.username = '';
  url.password = '';
  // Taken as text before it is cleared: URLSearchParams would re-encode and reorder what we keep.
  const search = url.search ? '?' + redactKeyValues(url.search.slice(1), depth) : '';
  const hash = url.hash ? '#' + redactFragment(url.hash.slice(1), depth) : '';
  url.search = '';
  url.hash = '';
  return url.href + search + hash;
}

// An invalid address becomes '' instead of throwing: the wire caller cannot let it bubble.
export function redactUrl(raw) {
  return redactAt(raw, 0);
}

const URL_IN_TEXT = /https?:\/\/[^\s<>"']+/g;

// Visible text can quote an address (a link whose text is its own URL); a match that does not parse stays.
export function redactUrlsIn(text) {
  if (typeof text !== 'string' || text === '') return '';
  return text.replace(URL_IN_TEXT, (match) => redactUrl(match) || match);
}

// Invisible or reordering characters let a page hide instructions from a human reading the same
// string. Same classes as the host's own sanitiser, plus the fillers and variation selectors it
// cannot see as format characters. \n and \t stay so multi-line reads remain readable.
const STRIP_INVISIBLE = new RegExp(
  '[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}\\p{Co}\\p{Cs}\\uFE00-\\uFE0F\\u{E0100}-\\u{E01EF}\\u034F\\u180B-\\u180F'
  + '\\u3164\\u115F\\u1160\\uFFA0\\u2800]',
  'gu',
);

export function cleanText(value) {
  if (typeof value !== 'string' || value === '') return '';
  return value.replace(STRIP_INVISIBLE, (ch) => (ch === '\n' || ch === '\t' ? ch : ''));
}

// What a page-derived free-text field goes through before it leaves the extension.
export const scrubText = (value) => redactUrlsIn(cleanText(value));
