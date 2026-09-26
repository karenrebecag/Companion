# Incredible (macOS/Tauri) — detalle visual de UI

Extraído del bundle desempaquetado en `scratchpad/inc/` (CSS: `index-WMGzGAce.css`, `firstRun-BOTAwJJ8.css`,
`overlay-CkZPSNkG.css`, `main-BHpHk-By.css`; JS: `js/main-BL-DABKy.js`, `js/overlay-DstkIEbM.js`,
`js/firstRun-CdIWn2zA.js`). Todos los valores vienen de className/JSX literal o de variables CSS
resueltas; donde no se pudo confirmar con certeza se marca **no encontrado**.

Unidad base de espaciado Tailwind (`--spacing`): `.25rem` = 4px. Radios y tipografías por rol están
tomados de las custom properties `--radius-*` y `--text-*` en `index-WMGzGAce.css`.

---

## 1. Home — layout de página

Fuente: `home-head`, contenedor con `Welcome, {name}` en `js/main-BL-DABKy.js`.

| Propiedad | Valor | Selector/origen |
|---|---|---|
| Contenedor ancho máximo | `max-w-[1300px]` (1300px) | `.@container.mx-auto.w-full.max-w-[1300px]` |
| Padding lateral | `px-10` = 40px (`@max-[700px]:px-8` = 32px en breakpoint contenedor <700px) | mismo div |
| Padding inferior | `pb-16` = 64px | mismo div |
| Cabecera sticky — altura | **98px** (constante `oi=98`) | `style={{height:oi,paddingTop:tA}}`, `data-testid="home-head"` |
| Cabecera sticky — paddingTop | **10px** (constante `tA=10`) | idem |
| Cabecera sticky — posición | `sticky top-0 z-20`, fondo `bg-surface-canvas` (#fcfcfc) | idem |
| H1 "Welcome, {name}" tipografía | `text-dialog-title` = **20px**, line-height 1.2 | var `--text-dialog-title:20px` |
| H1 peso | `font-semibold` = 600 | `--font-weight-semibold:600` |
| H1 tracking | `tracking-[-0.02em]` | literal en className |
| H1 color | `text-text-primary` = **#1c1c1e** | `--color-text-primary` |
| Columna lateral (aside) — ancho con progreso visible | `w-[300px]` | `data-testid="home-side-column"` |
| Columna lateral — ancho colapsada | `w-[192px]` | idem |
| Columna lateral — sticky top | 98px (misma constante `oi`) | idem |
| Constante auxiliar (no visual) | `aA = 3600*1000` ms (1 hora) — umbral usado para agrupar/format de tiempos | junto a `oi`/`tA` |

---

## 2. Home — hero banner (componente `N2`)

Fuente: `function N2({keycaps:e})` y su wrapper `function fh({...})` en `main-BL-DABKy.js`.
Textos: "Hold" / keycaps / "to talk to Incredible" y "Hand off tasks wherever you are. Across your
files, your browser, and your apps."

| Propiedad | Valor | Selector/origen |
|---|---|---|
| Contenedor (`<section>`) | `relative flex w-full items-center gap-8 overflow-hidden` | `fh()` |
| Gap interno | `gap-8` = 32px | idem |
| Radio de esquina | `rounded-card` = **22px** | `--radius-card:22px` |
| Fondo base | `bg-surface-ink` = **#171310** | `--color-surface-ink` |
| Padding | `px-10 py-6` = 40px / 24px (`@max-[720px]:px-7` = 28px) | idem |
| Imagen de fondo | `hero-laptop-lap-soft-*.jpg`, `absolute right-0 top-0 h-full w-[56%] object-cover`, `object-position: 50% 26%` | rama `photo==="panel"` (modo por defecto; N2 no pasa `photo`, así que NO usa el velo oscuro de color, solo la máscara) |
| Máscara de la imagen | `mask-image: linear-gradient(90deg, transparent 0%, transparent 12%, #000 65%)` — funde la foto hacia la izquierda | idem |
| Imagen oculta en breakpoint chico | `@max-[720px]:hidden` | idem |
| Contenido — padding vertical | `py-2` (contentClassName) | `N2` |
| H2 (título) tipografía | `text-banner-title` = **22px**, line-height 1.25 (override local a `leading-[1.25]`, el token trae 1.2 pero el componente lo pisa) | `--text-banner-title:22px`; className `leading-[1.25]` |
| H2 peso | `font-semibold` = 600 | idem |
| H2 tracking | `tracking-[-0.02em]` | idem |
| H2 color | `text-white` | idem |
| Keycap inline (dentro del H2) | `inline-flex translate-y-[-2px] text-[1.25em] leading-none align-middle` (1.25× el tamaño del H2, ≈27.5px) | span que envuelve `<ds>`/keycaps |
| Párrafo (body) | `mt-2 max-w-[34ch]`, `text-hero-body` = **15px**, line-height relaxed (1.5 vía `leading-relaxed`), color `text-white/75` (blanco 75%) | `--text-hero-body:15px` |

### Keycaps — clases `brand-keycaps` / `brand-keycaps--ink`

| Propiedad | Valor | Selector |
|---|---|---|
| `.brand-keycap` (tecla) | `display:inline-flex; min-width:2.4em; height:1.8em; padding:0 .45em; margin:0 .16em; border-radius:.45em; font-size:.5em; font-weight:600; letter-spacing:-.01em; vertical-align:middle; position:relative; top:-.18em; color:#000` | `firstRun-BOTAwJJ8.css` |
| `.brand-keycap` — borde/fondo por defecto | `border:1px solid #d4d4d9; background:#fbfbfc; box-shadow:0 .14em #d6d6db, 0 .18em .3em #0000000d` | idem |
| `.brand-keycaps--ink .brand-keycap` (variante usada en el hero) | `border-color:#c9c9cf; background:linear-gradient(180deg,#fff,#f1f1f4); box-shadow:inset 0 1px #fff, 0 .16em #bdbdc4, 0 .3em .6em #00000059; font-size:.54em` | `.brand-keycaps--ink .brand-keycap` |
| `.brand-keycap-symbol` | `margin-right:.35em; opacity:.55` | idem |
| `.brand-keycap-sep` (separador "+") | `margin:0 .08em; font-size:.5em; font-weight:500; opacity:.65; vertical-align:middle; top:-.18em` | idem |
| `.brand-keycaps` animación idle | `animation: onb-key-breathe 2.6s var(--ease-settle) infinite` (puede desactivarse a `none` según contexto) | idem |

---

## 3. Home — lista Today/historial (`function gA` → filas `mA`)

Fuente: `js/main-BL-DABKy.js`, `data-testid="home-tasks"`, filas `data-testid="home-task-{id}"`.

| Propiedad | Valor | Selector/origen |
|---|---|---|
| Sección — margen/padding | `mt-10 pb-24` (40px / 96px) | `data-testid="home-tasks"` |
| Grupo — margen superior | `mt-section` = **40px** (`--spacing-section:40px`) salvo el primero (`first:mt-0`) | wrapper de cada grupo |
| Etiqueta de grupo ("Today") — sticky | `sticky z-10 bg-surface-canvas pt-1`, top = 98px (misma constante `oi`) | wrapper de label |
| Etiqueta de grupo — tipografía (segunda ocurrencia confirmada del mismo patrón; **no se pudo aislar el componente `vu` en un chunk separado, inferido con alta confianza**) | `text-body` = **13px**, `font-medium`, color `text-text-muted` (#727276) | patrón repetido junto a `children:r.label` |
| Fade debajo del label | gradiente `from-surface-canvas to-transparent`, `h-4` (16px) | div `aria-hidden` bajo el label |
| Tarjeta contenedora de la lista | radio `card` = **22px** (`radius="card"`), `overflow-hidden py-1` | componente `xe` (`data-testid="home-task-group-{label}"`) |
| Divisor entre filas | `border-t border-border-row` color **#0000000d** (~5% negro), aplicado con `mx-indent` = **18px** de margen lateral (`--spacing-indent:18px`); no aparece antes de la primera fila | componente `to`, `.border-border-row` |
| Fila — layout | `flex w-full items-center gap-4` (16px) | `function mA`, `data-testid="home-task-{id}"` |
| Fila — padding | `px-indent` (18px) `py-3.5` (14px) | idem |
| Fila — hover | `hover:bg-surface-active` = negro 5% (`--color-surface-active:#0000000d`) | idem |
| Fila — focus | `focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-current` | idem |
| Título de la tarea | `text-row-title` = **14px**, line-height 1.4, `font-medium`, color `text-text-primary`, `truncate` | `--text-row-title:14px` |
| Badge "Scheduled"/"On autopilot" | `rounded-full bg-black/[0.05] px-2 py-0.5` (8px/2px), `text-micro` = **11px**, `font-medium`, color `text-text-secondary`, icono `h-3.5 w-3.5` (14px) | `data-testid="task-badge-scheduled"` / `task-badge-autopilot` |
| Icono redondo por defecto (sin chips) — "bubble" con borde | `flex h-6 w-6` (24px) `items-center justify-center rounded-full bg-white ring-1 ring-black/10 text-text-muted` | `data-testid="task-chips-standin"` (clase compartida `cA`, misma que usan los chips de app/sitio) |
| Chip de chat/app/sitio (icono redondo con borde, mismo tamaño) | `flex h-6 w-6 shrink-0 items-center justify-center overflow-hidden rounded-full bg-white ring-1 ring-black/10`; imagen interna `h-4 w-4` (o `h-3.5 w-3.5` para "site", con `inset`) | constante `cA` en `main-BL-DABKy.js`, componente `nr` |
| Chip de archivo sin thumbnail | `h-6 min-w-6`, `rounded-chip` = **10px**, `bg-black/[0.04]`, `ring-1 ring-black/10`, `text-micro font-medium text-text-secondary` | componente `pA`, caso `file` |
| Estado "Done" (badge) | `rounded-full px-2.5 py-1` (10px/4px), `text-caption` = **12px**, tono `done`: `bg-status-green-muted` (**#34c7591f**, verde 12%) + `font-medium text-status-green` (**#34c759**) | `function xt`, `tone==="done"` |
| Punto del badge | `h-2 w-2` (8px) `rounded-full`, color según variante (`bg-status-green` en "Done") | `xt` |
| Gap interno del badge (punto↔texto) | `gap-1.5` = 6px | `xt` |
| Otros estados de badge | `Working` (azul, icono girando), `Needs you` (naranja, `loud`), `Stalled`/`Scheduled` (negro 20%), fondo por defecto `bg-black/[0.04] text-text-secondary` | `function hA` |
| Hora relativa ("2 hours ago") | Texto: `text-caption` = **12px**, `tabular-nums`, color `text-text-muted`; función formateadora `zs` (no se pudo aislar su definición en un chunk legible — no encontrado el string exacto "hours ago"/"ago", pero el umbral de 1h = constante `aA`) | span junto al badge de estado, solo si `e.state==="done"` |
| Chevron final | `ys` icono, `h-4 w-4` (16px), color `text-text-faint` (#8e8e93), hover/focus → `text-text-secondary` (#6c6c70) | idem |

---

## 4. Sidebar

Fuente: `data-testid="main-app-sidebar"`, `sidebar-logo-row`, componente de item `d0`, cuenta `sN`.

| Propiedad | Valor | Selector/origen |
|---|---|---|
| Ancho | **248px** (constante `$r`) | `style={{width:$r}}` |
| Fondo | `bg-surface-secondary` = **#f9f9f9** | `data-testid="main-app-sidebar"` |
| Borde derecho | `border-r border-border-chrome` = **#eee** | idem |
| Padding inferior del aside | `pb-2` = 8px | idem |
| Zona de traffic-lights (macOS) | altura por defecto **38px** (`titleBarSpacerHeight=38`), `WebkitAppRegion:"drag"` | prop `titleBarSpacerHeight` |
| Fila del logo | `h-[44px]`, `gap-2` (8px), `pl-[19px] pr-[14px]`, `mt-3` (12px) extra si `platform==="macos"` | `data-testid="sidebar-logo-row"` |
| Wordmark "Incredible" | ancho **132px** (SVG, componente `l0`), color `text-text-primary` | `t.jsx(l0,{width:132})` |
| Chip de plan (si existe) | `rounded-badge` = **8px**, `bg-brand-gradient-end` (**#ffe3cb**), `px-2.5 py-1` (10px/4px), `text-caption font-medium text-text-primary` | `data-testid="sidebar-plan-chip"` |
| Nav — contenedor | `mt-3 flex-1 overflow-y-auto` | `<nav>` |
| Etiqueta de sección ("Customize"/"Superpowers", generadas por arreglo, no strings sueltas) | `pl-6 pr-[19px] pb-1.5 pt-7` (24/19/6/28px), `text-caption` = **12px**, `font-medium`, color `text-text-secondary` (#6c6c70) | `data-testid="sidebar-group-{label}"` |
| **Nav item — fila exterior** | `h-[42px]`, `pl-[14px]` (o `pl-[26px]` si `item.indent`), `pr-[14px]` | `function d0` |
| **Nav item — botón** | `h-[38px] w-full flex items-center gap-3` (12px), `rounded-chip` = **10px**, `px-3` (12px) | idem |
| Nav item — tipografía | `text-row-title` = **14px**, `font-medium`, `whitespace-nowrap overflow-hidden` | idem |
| Nav item — estado normal | color `text-text-primary`, hover `hover:bg-surface-active` (negro 5%) | idem |
| Nav item — estado activo/seleccionado | `bg-black/[0.07] text-text-primary` (sin cambio de color de texto, solo fondo) | idem, `aria-current="page"` |
| Nav item — icono | `w-[18px] h-[18px]` | idem |
| Nav item — punto de notificación (dot) | `h-2 w-2` (8px) `rounded-full bg-status-orange`, posicionado `-right-0.5 -top-0.5` sobre el icono | `data-testid="sidebar-dot"` |
| Nav item — punto "pulse" (verde, con ping) | `h-2 w-2 bg-status-green`, anillo animado `opacity-60 animate-ping` detrás | `data-testid="sidebar-pulse-dot"` |
| Nav item — badge numérico | `text-caption font-medium tabular-nums text-text-faint` | `data-testid="sidebar-badge-{id}"` |
| **Rail "Use cases" (short_title) / "What people get done" (short_text)** | contenido definido en objeto de config (`short_title`/`short_text`), no strings JSX sueltas | objeto con `link_text:"Explore use cases"` |
| Rail — tarjeta contenedora | radio `card-sm` = **18px**, `mx-[14px] mb-1 mt-2`, `overflow-hidden p-0`, hover `scale-[1.03]` (150ms) | `data-testid="sidebar-promo-card"` |
| Rail — zona de imagen | `h-[84px] w-full overflow-hidden`; si no hay imagen, fondo con 2 `radial-gradient` (colores `sky`/`lilac`) + blanco | `data-testid="sidebar-promo-field"` |
| Rail — círculo del ícono (bombilla) | `h-10 w-10` (**40px**), centrado absoluto, `rounded-full bg-surface-primary` (blanco), `shadow-raised`, `ring-1 ring-black/[0.06]`; icono interno `h-[18px] w-[18px]` | idem |
| Rail — título | `px-3.5 pb-3 pt-2.5` (14/12/10px), `text-row-title` = **14px**, `font-medium`, `text-text-primary`, `truncate` | idem |
| Rail — subtítulo ("What people get done") | `mt-0.5` (2px), `text-caption` = **12px**, `text-text-muted`, `truncate` | idem |
| **Fila de cuenta (bottom)** — contenedor | `h-[54px] flex items-center px-3.5` (14px) | `function sN` |
| Cuenta — botón trigger | `h-[42px] w-full flex items-center gap-2.5` (10px), `rounded-chip` = **10px**, `pl-2 pr-2.5` (8/10px) | `data-testid="profile-trigger"` |
| Cuenta — tipografía nombre | `text-row-title` = **14px**, `font-medium text-text-primary`, `flex-1 truncate` | idem |
| Cuenta — hover/activo | `hover:bg-surface-active` / `bg-surface-active` si el menú está abierto | idem |
| **Avatar / monograma** | círculo **28px** (`size=28`), `rounded-full`; con foto → `object-cover`; sin foto (monograma) → fondo **#C8DCF1** (tono "self"/sky), texto `var(--color-text-primary)`, `font-semibold`, `font-size ≈ 11px` (28×0.38) | componente de avatar (`Rr` en main, `pS`/`HU` en `firstRun-CdIWn2zA.js`) |
| Cuenta — chip de plan | `rounded-full bg-black/[0.05] px-2 py-0.5` (8/2px), `text-micro` = **11px**, `font-medium text-text-muted` | `data-testid="profile-plan-chip"` |
| **Chevron de cuenta** | `w-[15px] h-[15px]`, color `rgba(0,0,0,.35)`, rota 180° cuando el menú está cerrado (`h?"":"rotate-180"`) | icono `ug` |
| Menú de perfil (popover) | ancho `max(calc(var(--anchor-width) + 32px), 252px)`, `side="top" align="start" sideOffset={8}` | `data-testid="profile-menu"` |

---

## 5. Island (overlay del notch) — composer

Fuente: `js/overlay-DstkIEbM.js` (`data-testid="chat-input"`), variables `--ci-*` en
`overlay-CkZPSNkG.css` (`:root`).

### Variables base `--ci-*`

| Variable | Valor por defecto (`:root`) | Valor en modo island (`.ci-shell--island`) |
|---|---|---|
| `--ci-surface` | `rgb(20, 21, 24)` | `#000` |
| `--ci-border` | `rgba(255,255,255,.09)` | `transparent` |
| `--ci-radius` | **18px** | **0** (el borde redondeado lo da el propio island, no el composer) |
| `--ci-inner-radius` | 11px | — |
| `--ci-text-primary` | `rgba(255,255,255,.95)` | — |
| `--ci-text-secondary` | `rgba(255,255,255,.64)` | — |
| `--ci-text-muted` | `rgba(255,255,255,.42)` | — |
| `--ci-divider` | `rgba(255,255,255,.07)` | — |
| `--ci-tile` / `--ci-tile-hover` | `rgba(255,255,255,.06)` / `rgba(255,255,255,.12)` | — |
| `--ci-accent` | `#78aaff` | — |
| `--ci-border-focus` | `rgba(120,170,255,.55)` | — |
| `--ci-error` | `#ff7a64` | — |
| `--ci-ease` | `cubic-bezier(.22,1,.36,1)` | — |

### Estructura y valores

| Elemento | Propiedad | Valor | Selector |
|---|---|---|---|
| `.ci-shell` | tamaño/padding | `width:100%; height:100%; padding:16px 18px 14px` | `.ci-shell` |
| `.ci-shell` | tipografía base | `font-size:14px; line-height:1.45; letter-spacing:-.005em`; familia `-apple-system, BlinkMacSystemFont, Inter, "Geist Variable", system-ui, sans-serif` | idem |
| `.ci-card` (tarjeta visible) | fondo/borde/radio | `background:var(--ci-surface); border:1px solid var(--ci-border); border-radius:var(--ci-radius)` | `.ci-card` |
| `.ci-card` | padding | `14px 14px 12px` | idem |
| `.ci-card` | sombra | `inset 0 1px #ffffff0d, 0 1px 2px #00000080, 0 3px 9px #00000052` (foco: añade `0 0 0 2px #78aaff24`) | idem, `[data-focused]` |
| `.ci-island-field` (fila del textarea) | layout | `grid-column:2; grid-row:1; display:flex; align-items:center; width:100%; min-height:var(--ci-island-textarea-h, 38px)` | `.ci-island-field` |
| **Attach/paperclip** — dónde está | primer botón del `.ci-toolbar` (fila debajo del textarea), a la izquierda, antes del texto de ayuda y el spacer | `className:"ci-tool"`, `aria-label:"Add files"` |
| `.ci-tool` (botones de la toolbar, incl. paperclip) | tamaño/forma | `width:30px; height:30px; border-radius:999px; background:transparent; color:var(--ci-text-secondary)`; hover `background:var(--ci-tile-hover); color:var(--ci-text-primary)` | `.ci-tool` |
| Icono paperclip | tamaño | `size=16, strokeWidth=2` | icono `gl` dentro de `.ci-tool` |
| `.ci-toolbar` | layout | `display:flex; gap:4px` (inferido `flex`+`gap`) | `.ci-toolbar` |
| `.ci-toolbar-hint` (texto "↑↓ history · esc to close") | tipografía | `font-size:11px; color:var(--ci-text-muted)` | `.ci-toolbar-hint` |
| `.ci-toolbar-spacer` | función | `flex:1` (empuja mic/send a la derecha) | `.ci-toolbar-spacer` |
| `.ci-mic` | tamaño/estado | igual que `.ci-tool` (30×30, radio 999px); grabando: `background:#ff5a5029; color:#ff6a5c` | `.ci-mic[data-recording]` |
| `.ci-textarea` | tamaño/padding | `padding:1px 26px 1px 2px; width:100%; min-height:26px; max-height:208px; background:transparent; border:none; color:var(--ci-text-primary)` | `.ci-textarea` |
| **Send** — dónde está | último elemento del `.ci-toolbar` (misma fila que paperclip/mic, extremo derecho) | `className:"ci-send"`, `aria-label:"Send"` |
| `.ci-send` | tamaño/forma | `width:30px; height:30px; border-radius:999px; background:var(--ci-tile); color:var(--ci-text-muted)` | `.ci-send` |
| `.ci-send[data-active]` (con texto listo para enviar) | estado | `background:#fff; color:#15161a; box-shadow:0 1px 2px #0006, 0 2px 8px #00000040`; hover `#f1f3f7`; active `#e7eaf0` | `.ci-send[data-active]` |
| Icono send | tamaño | `size=17, strokeWidth=2.25` | icono `wl` |
| `.ci-island-orb` (botón "Talk"/"Stop", solo en modo island) | tamaño | `width:38px; height:38px; padding:0; border:0; background:transparent` | `.ci-island-orb` |
| `.ci-island-orb-clip` (máscara circular del orb) | tamaño | `width:36px; height:36px; border-radius:999px; overflow:hidden` | `.ci-island-orb-clip` |
| `.ci-island-orb-clip:after` (flash rojo al detectar algo) | color/anim | `background:#ff3b30e6` con patrón de puntos (`10px 10px`), `opacity` 0→1, `transition:opacity .15s ease-out` | idem |
| `.ci-close` (botón de cerrar, "×") | tamaño | `width:24px; height:24px; border-radius:7px`; hover `background:var(--ci-tile-hover)` | `.ci-close` |
| `.ci-att-card` (adjunto) | tamaño | `width:84px; height:102px; border-radius:10px; background:var(--ci-tile); border:1px solid rgba(255,255,255,.22); padding:8px` | `.ci-att-card` |

---

## 6. Island (overlay del notch) — rim / hairline / glow / header / controles / volumen / stack

### Contenedor `.ov-island` (pill colapsado)

| Propiedad | Valor | Selector |
|---|---|---|
| Tamaño | `width:90px; height:36px` | `.ov-island` |
| Radio | `border-radius:9999px` | idem |
| Fondo/borde | `background:var(--overlay-surface-pill); border:1px solid var(--overlay-border-pill)` | idem |
| Tipografía | `color:var(--color-text-primary); font-size:12px; line-height:1` | idem |
| Ancho de línea inactiva vs. activa | `--isl-line-w:40px` (idle) → `--isl-line-w-active:90px` (con actividad) | `--isl-line-w`, `--isl-line-w-active` |
| Radios del morph completo | `--isl-radius-seed:10px` (semilla) → `--isl-radius-cue:12px` (cue) → `--isl-radius-open:28px` (abierto, = radio `panel`) | vars `--isl-radius-*` |
| `--isl-bar-h`, `--isl-notch-w`, `--isl-pad`, `--isl-paint-w`, `--isl-open-h` | **no encontrado como constante estática** — se inyectan por JS en runtime según el notch físico detectado (no hay valor fijo en el CSS) | — |
| `--isl-item-d` (diámetro de ítems de acción) | **32px** (28px en algunos contextos vía `var(--isl-item-d, 28px)`) | `--isl-item-d` |
| `--isl-icon` | **18px** por defecto, **20px** en la topline con `data-header-slots` | `--isl-icon` |
| `--isl-gap` | `var(--sp-2)` | `--isl-gap` |
| `--isl-rim-pad` | **4px** | `--isl-rim-pad` |
| `--isl-fillet-pad` | 20px | `--isl-fillet-pad` |
| `--isl-chatrow-inset` | **18px** | `--isl-chatrow-inset` |
| `--isl-body-min-h` | 66px | `--isl-body-min-h` |

### Rim / hairline / glow (halo del borde)

| Elemento | Propiedad | Valor |
|---|---|---|
| `.ov-island-rim` | posición | `absolute; inset:0 calc(-1*var(--isl-rim-pad)) 0 calc(-1*var(--isl-rim-pad))`, `z-index:-2` |
| `.ov-island-rim` | color | gradiente horizontal a partir de `--isl-rim-blue` (**#5f86ff**) en 16%/24%/30%/24%/16% de opacidad | 
| `.ov-island-rim` | visibilidad | `opacity:0` por defecto, transición `opacity var(--isl-fade)` (se activa con estados de actividad) |
| `.ov-island-hairline` | color | `background:var(--color-border-default, rgba(255,255,255,.12))`, `opacity:0→1` cuando `[data-island-window=open]` |
| `.ov-island-hairline` | z-index | `-3` (detrás del rim) |
| `.ov-island-glow` | efecto | `filter:blur(var(--isl-signal-reach, 12px)); opacity:0→1` según `data-task-signal` (`blocked`=naranja `--color-status-orange`, `completed`=verde `--color-status-green`) |
| `.ov-island-glow` | z-index | `-4` (el más al fondo) |

### Header / controles / bar-side (volumen arriba-izquierda)

| Elemento | Propiedad | Valor |
|---|---|---|
| `.ov-island-bar-topline[data-header-slots]` | layout | `display:grid; grid-template-columns:minmax(0,1fr) var(--isl-notch-w) minmax(0,1fr)`, `padding-inline:var(--isl-chatrow-inset, 18px)`, `padding-top:var(--sp-3)` |
| `.ov-island-bar-topline[data-header-slots]` | tamaños locales | `--isl-icon:20px; --isl-item-d:32px` |
| **Ubicación del control de volumen** | primer `.ov-island-bar-side` (columna izquierda del grid, antes del notch) contiene el botón de volumen (`u = actions.find(id==="volume")`) + `header.trailing`; el segundo `.ov-island-bar-side` (derecha) es `data-testid="island-bar-agents"` | `function Gp`, `data-testid="island-controls"` |
| `.ov-island-bar-side` | layout | `display:flex; align-items:center; gap:var(--sp-2)` |
| `.ov-island-header-default` | layout | `display:flex; align-items:center; gap:var(--sp-2)` |
| `.ov-island-controls` | layout | `display:inline-flex; align-items:center; gap:var(--sp-2)` |
| `.ov-island-action` | base | `position:relative; display:flex; align-items:center; justify-content:center; background:none; border:none; padding:0; color:#fff` |
| `.ov-island-action-icon` | tamaño | `width/height:var(--isl-item-d, 28px); aspect-ratio:1; border-radius:9999px` |
| `.ov-island-btn` | base | `display:inline-flex; padding:0; border:none; background:transparent; font:inherit; color:inherit` |

### Menú de volumen (popover anclado al botón)

| Elemento | Propiedad | Valor |
|---|---|---|
| Popover | posicionamiento | `side="top" align="center" sideOffset={14} collisionPadding={8}`, clase `ov-menu ov-menu--volume` | 
| `.ov-volume-head` | layout | `display:flex; align-items:baseline; justify-content:space-between; padding:6px 10px 0` |
| `.ov-volume-title` ("Volume") | tipografía | `font-size:11px; font-weight:600; color:var(--color-text-muted)` |
| `.ov-volume-value` ("Muted"/"NN%") | tipografía | `font-size:12px; font-variant-numeric:tabular-nums; color:var(--color-text-secondary)` (muted: `var(--color-text-muted)`) |
| `.ov-volume-row` | layout | `display:flex; align-items:center; gap:var(--sp-2); padding:4px 10px 10px` |
| `.ov-volume-track` | tamaño | `height:6px; border-radius:999px; background:var(--color-surface-active)` (opacidad .4 si muted) |
| `.ov-volume-fill` | color | `background:var(--color-accent)` |
| `.ov-volume-knob` | tamaño | `width:12px; height:12px; border-radius:999px; background:#fff; box-shadow:0 1px 3px #0006`, `scale(.75)` en reposo |
| `.ov-volume-slider` (hit area invisible) | tamaño | `height:24px; inset:-9px 0; opacity:0` |

### Stack de contenido (composer/conversación/card) y slots

| Elemento | Propiedad | Valor |
|---|---|---|
| `.ov-island-stack` | posición | `absolute; top:var(--isl-bar-h); left/right:var(--isl-chatrow-inset, 18px)`, `display:flex; flex-direction:column; gap:var(--sp-3); padding:var(--sp-3) 0 var(--sp-2); min-height:var(--isl-body-min-h)` |
| `.ov-island-composer-slot` | transición | `opacity/transform` con `transition: opacity .15s var(--ease-standard), transform .22s var(--ease-standard)`; `flex:none` |
| `.ov-island-conversation-slot` / `.ov-island-card-slot` | scroll | `.ov-island-card-slot{flex:0 1 auto; min-height:0; overflow-y:auto; overflow-x:clip}` |
| **"Tres círculos punteados de slots"** | — | **no encontrado**: no se localizó ningún selector con `border-style:dashed` combinado con forma circular (`border-radius:50%`/`9999px`) ni un grupo de 3 elementos repetidos que coincida con esa descripción. Los candidatos más cercanos revisados (`ov-hold-collect-slot`, `ov-cap-stack`, `ov-island-reel-item`, `ov-wf-questions-dots`) no usan `dashed`. Puede tratarse de un estado visual dinámico (placeholder de carga) no representado como regla CSS estática. |

### Otros elementos ya resueltos en investigación previa (referencia)

| Elemento | Valor destacado |
|---|---|
| `.ov-island-notice` | `padding:6px 12px; border-radius:999px; font-size:11.5px; font-weight:500`, variantes `info`/`error`/`success` con color y borde propios |
| `.ov-island-tooltip` | `height:40px; padding:0 18px; border-radius:9999px; font-size:14px; font-weight:500` |
| `.ov-cap-card` | `height:64px; border-radius:6px`, variantes por `data-kind` (`ClipboardText`, `Screenshot`, `File`, `TaskReference`) con anchos 96–140px |
| `.ov-confirm` | `padding:18px 52px 18px 18px; min-width:380px; max-width:480px; font-size:13.5px` |
| `.ovx-popup` (popup de contenido enriquecido) | `border-radius:20px (--ovx-radius); width:min(580px,76vw); padding:18px 22px 16px`; fondo `rgb(14,14,16)`; sombra `0 0 0 .5px rgba(255,255,255,.04) inset, 0 1px 2px rgba(0,0,0,.4), 0 14px 40px rgba(0,0,0,.52)` |

---

## Notas metodológicas

- Todos los tokens de radio/tipografía citados como `--radius-*` / `--text-*` están definidos una
  sola vez en `:root` de `index-WMGzGAce.css` y se reutilizan igual en toda la app (home + sidebar).
  Los tokens `--ci-*` e `--isl-*` son específicos del overlay/island y viven en
  `overlay-CkZPSNkG.css` / `firstRun-BOTAwJJ8.css`.
- Los componentes cuyo nombre en el bundle es un alias de 2 letras (`vu`, `to`, `xe`, `Rr`, etc.)
  vienen de re-exports internos del bundler (Rollup/Vite) entre "chunks"; cuando no fue posible
  rastrear la definición exacta dentro del tiempo disponible, se dejó constancia explícita en la
  fila correspondiente en lugar de adivinar el valor.
- La función que formatea "2 hours ago" (`zs`) no pudo aislarse como código legible (su
  implementación no vive en `main-BL-DABKy.js`); se documentó únicamente su estilo visual
  (`text-caption`, `tabular-nums`, `text-muted`).
