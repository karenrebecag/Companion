# Companion Browser extension (Chromium, MV3)

Lets Companion read and operate tabs in Chrome or Comet through native messaging.
Native host name: `com.karen.companion.browser`. Extension id: `gaipfdnbliibnfchgcnamnjpfgkilnll`
(stable because `manifest.json` carries the public `key`).

## Load it

1. Open `chrome://extensions` (or the Comet equivalent) and enable Developer mode.
2. Load unpacked and pick this folder.
3. Confirm the id shown matches the one above; Companion pins that id in its native host manifest.

The extension holds no secret: the native relay adds the auth token to the first `hello` frame.

## Private key

Only the public key is in the repo. The matching private key is not stored here and must never be
committed; it is needed only to pack a `.crx`, not to load unpacked.

## Tests

```
node --test Extensions/browser/test/*.test.js
```

No dependencies. Pass the file path; a directory argument fails on Node 22.
