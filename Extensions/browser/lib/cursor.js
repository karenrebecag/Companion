// Classic script, injected like page.js. CDP input moves no real pointer, so without this a person
// watching sees fields fill with no idea where Companion is acting. Presentation only: it never
// dispatches events and is pointer-events:none, so it cannot change what a click hits.
// The host sits on <html>, outside <body>, in a closed shadow root: page reads walk the body and
// cannot enter a closed root, so the cursor never shows up in what the model reads.
(function () {
  if (globalThis.__companionCursor) return;
  const GLIDE_MIN_MS = 350;
  const GLIDE_MAX_MS = 800;
  const ACCENT = '#2563eb';

  let host = null;
  let parts = null;
  let at = null;

  function mount() {
    if (host && host.isConnected) return parts;
    host = document.createElement('companion-cursor');
    const root = host.attachShadow({ mode: 'closed' });
    root.innerHTML = `
      <style>
        :host { all: initial; }
        .glow { position: fixed; inset: 0; pointer-events: none; z-index: 2147483646;
                box-shadow: inset 0 0 0 3px ${ACCENT}, inset 0 0 24px rgba(37,99,235,.35); }
        .cursor { position: fixed; left: 0; top: 0; pointer-events: none; z-index: 2147483647;
                  transition-property: transform; transition-timing-function: cubic-bezier(.22,.8,.26,1); }
        .arrow { width: 22px; height: 22px; filter: drop-shadow(0 1px 2px rgba(0,0,0,.45)); }
        .label { position: absolute; left: 22px; top: 16px; white-space: nowrap; max-width: 280px;
                 overflow: hidden; text-overflow: ellipsis; background: #111; color: #fff;
                 font: 600 12px/1.2 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                 padding: 5px 9px; border-radius: 999px; border: 1px solid ${ACCENT}; }
        .ripple { position: absolute; left: -14px; top: -14px; width: 28px; height: 28px; border-radius: 50%;
                  border: 2px solid ${ACCENT}; opacity: 0; }
        .ripple.on { animation: ripple .45s ease-out; }
        @keyframes ripple { from { transform: scale(.3); opacity: 1; } to { transform: scale(1.6); opacity: 0; } }
      </style>
      <div class="glow"></div>
      <div class="cursor">
        <div class="ripple"></div>
        <svg class="arrow" viewBox="0 0 22 22"><path d="M2 2 L2 18 L6.5 13.8 L9.6 20.5 L12.6 19.2 L9.6 12.6 L16 12.6 Z"
          fill="${ACCENT}" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/></svg>
        <div class="label"></div>
      </div>`;
    document.documentElement.appendChild(host);
    parts = {
      cursor: root.querySelector('.cursor'),
      label: root.querySelector('.label'),
      ripple: root.querySelector('.ripple'),
    };
    return parts;
  }

  const clampX = (x) => Math.max(4, Math.min(x, window.innerWidth - 8));
  const clampY = (y) => Math.max(4, Math.min(y, window.innerHeight - 8));

  // Resolves after the glide, by timer and not transitionend: a background tab never paints, and
  // the action must not wait on an animation nobody can see.
  function moveTo(x, y, label) {
    const p = mount();
    const tx = clampX(x);
    const ty = clampY(y);
    const from = at ?? { x: window.innerWidth / 2, y: window.innerHeight / 2 };
    const distance = Math.hypot(tx - from.x, ty - from.y);
    const ms = at ? Math.round(Math.min(GLIDE_MAX_MS, Math.max(GLIDE_MIN_MS, distance * 0.9))) : 0;
    p.label.textContent = label || '';
    p.cursor.style.transitionDuration = ms + 'ms';
    p.cursor.style.transform = `translate(${tx}px, ${ty}px)`;
    at = { x: tx, y: ty };
    return new Promise((resolve) => setTimeout(resolve, ms + 60));
  }

  function press() {
    const p = mount();
    p.ripple.classList.remove('on');
    void p.ripple.offsetWidth;
    p.ripple.classList.add('on');
  }

  function destroy() {
    if (host) host.remove();
    host = null;
    parts = null;
    at = null;
  }

  globalThis.__companionCursor = { moveTo, press, destroy, mount };
})();
