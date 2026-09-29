# mermaid.min.js (vendored)

Drawn in an isolated WKWebView by `WebKitDiagramRenderer` (wave 16m-5b). Never
fetched at runtime: the app has no network path for it.

- Package: mermaid
- Version: 11.17.2 (the one Incredible ships; latest major is 12, not adopted)
- File: `dist/mermaid.min.js` of the npm tarball (IIFE bundle, every diagram inline)
- SHA-256: 581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8
- License: MIT (see `LICENSE`, copied from the tarball)
- Approved by Karen: 2026-09-29 ("install de mermaid"); the only new third-party code of wave 16m

## How it was obtained

```bash
npm pack mermaid@11.17.2
tar xzf mermaid-11.17.2.tgz
shasum -a 256 package/dist/mermaid.min.js
cp package/dist/mermaid.min.js package/LICENSE Sources/CompanionServices/Diagram/
```

## Upgrading

Change the version and hash here AND in `DiagramPage.mermaidVersion` /
`DiagramPage.mermaidSHA256`. `diagramVendorTests` fails if any of the three
disagrees with the file, and the renderer refuses to load a script whose hash
is not the pinned one.
