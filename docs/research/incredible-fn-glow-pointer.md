# Incredible.app (v0.2.36) — glow de pantalla, puntero y tooltips/dropdowns del island

Investigación de solo lectura sobre los assets ya extraídos (`.css`/`.js` de Tauri/Vite, Tailwind v4
con `--spacing: 4px`), el bundle de la app (`Info.plist`, `Contents/Resources`, `strings` del
binario) y `~/.incredible/overlay.json` (claves/forma, sin tocar `auth.json` ni `bridge-secret`).
Se documentan VALORES y COMPORTAMIENTO, no código — donde el origen es un shader GLSL o una función
JS, se describe en prosa (fórmula, constantes, unidades) en vez de copiar el código fuente.

Metadata de la app: `CFBundleShortVersionString` 0.2.36, bundle id `one.incredible.new`, URL scheme
`incredible://`. `Contents/Resources` solo trae `_up_` (updater), `ffmpeg-runtime`,
`python-runtime` y el `.icns` — no hay un `tauri.conf.json` legible aparte ni una lista de ventanas
en texto plano; el `strings` del binario no reveló labels de ventana adicionales (glow/cursor/menu)
como cadenas sueltas, así que el layout de ventanas de Tauri no pudo confirmarse por esa vía (ver
sección de límites al final).

---

## 1. Glow de pantalla al mantener fn

**Hallazgo clave**: hay DOS implementaciones en el bundle, y no son intercambiables al azar — una es
la que realmente se manda a producción hoy, la otra es la que documentan los comentarios de dev.

| | Método | Estado |
|---|---|---|
| A | `gl-waves` — shader WebGL (canvas `position:fixed;inset:0`) | **Producción actual** (`bC` array en `main-BL-DABKy.js`: `{value:"gl-waves",label:"Production (shader: waves)"}`; el resto (`gl-aurora`, `gl-liquid`, `og-spec-b`) aparecen en el mismo array de opciones, con `og-spec-b` etiquetado literalmente `"CSS strips (previous)"`) |
| B | `og-spec-b` / familia `.sg-glow` — CSS puro (conic-gradients + máscaras SVG) | Método anterior, sigue en el CSS pero ya no es el default |

El setting persistido en `~/.incredible/overlay.json` es un solo booleano: `"screen_glow_enabled": true`
(no hay una clave de método persistida — el selector de método visto en `main-BL-DABKy.js` parece un
control interno/dev, no expuesto de forma normal). También existe `"fn_screenshots_enabled": false`
(feature separada, screenshots al soltar fn).

### 1.A — Shader de producción (`gl-waves`)

Fuente: `js/overlay-DstkIEbM.js`, bloque de shaders GLSL embebidos (vertex + fragment, con un
diccionario de 3 variantes: `gl-liquid`, `gl-aurora`, `gl-waves`). Un `canvas` WebGL a pantalla
completa (`position:fixed;inset:0`), `devicePixelRatio` limitado a `min(dpr,1.25)` para el backing
store.

| Valor | Detalle | Confianza |
|---|---|---|
| Paleta de color | 4 tonos en rueda continua: azul `vec3(0.110,0.412,0.941)` ≈ `#1C69F0`, teal `vec3(0.039,0.706,0.686)` ≈ `#0AB4AF`, violeta `vec3(0.549,0.275,0.902)` ≈ `#8C46E6`, cian `vec3(0.078,0.588,0.863)` ≈ `#1496DC`. Interpolación lineal por cuartos de círculo (mismos 4 stops que el gradiente legacy `.sg-paint` — ver 1.B) | Alta |
| Distribución del color | El color depende del ÁNGULO alrededor del centro de pantalla (barrido tipo rueda, no una franja fija) más una deriva lenta en el tiempo | Alta |
| Velocidad de deriva | La fase se desplaza `tiempo_seg × 0.014`; una vuelta completa de la paleta tarda ≈ 71 s | Alta |
| Fase/semilla por activación | Cada vez que se activa (cada hold de fn) se sortea una fase y una semilla de ruido nuevas — el arreglo visual no se repite igual dos veces | Alta |
| Grosor / alcance hacia adentro | Perfil de caída ("reach") con base 120 px (unidades del canvas WebGL, es decir px físicos con el DPR ya aplicado, tope 1.25×) + una ondulación de ±~20 px que varía con el método: `gl-waves` combina dos ondas viajeras (frecuencias 0.016 y 0.041, velocidades 1.5 y 0.9) más ruido fractal de baja amplitud — el borde queda ondulado, no una franja recta | Alta |
| Esquinas | El SDF usado es un rectángulo con radio de esquina **0.0 fijo** (no configurable) — el glow sigue el rectángulo de pantalla con esquinas totalmente cuadradas, NO sigue la curvatura física del bisel del display | Alta |
| Opacidad máxima | `alpha = perfil(0..1) × 0.5 × u_dim × u_fill` → techo real de opacidad ≈ 0.5 (50%), distinto del `0.66` del método CSS legacy | Alta |
| Fade in | `u_fill` sube linealmente a razón de `Δms/260` por frame → fade-in completo en ≈260 ms | Alta |
| Fade out | `u_fill` baja a razón de `Δms/900` → fade-out en ≈900 ms (bastante más lento que el in) | Alta |
| Estado "waiting" (a media espera) | `u_dim` interpola hacia 0.5 (vs. 1.0 normal) con un lerp de constante de tiempo ≈250 ms — la pantalla se atenúa a la mitad mientras "espera" | Alta |
| Reactividad a audio/mic | **No encontrada.** No hay ningún uniform tipo `u_level`/`u_amp` ligado al nivel de voz en este shader; el módulo de audio (`js/audioLevelsSource-DSOQLR23.js`, eventos Tauri `audio:mic-level` / `audio:tts-bands`) existe pero no se referencia desde este archivo. El pulso que sí tiene el glow es puramente temporal (la deriva de fase de 71 s) y de estado (`off/waiting/activo`), no de amplitud de voz | Media-alta (ausencia negativa, no se puede probar 100%) |
| Variantes alternativas en el mismo shader | `gl-liquid` (desplazamiento por ruido fbm de doble octava, amplitud ×20, sin variación de brillo) y `gl-aurora` (ruido "warpeado" doble, amplitud ×24, brillo modulado 0.78–1.23 con otro fbm) — ninguna es la de producción | Alta |

### 1.B — Método CSS legacy (`.sg-glow` / familia `og-*`, archivo `overlay-CkZPSNkG.css`)

Presente en el CSS pero ya no es el default (ver tabla arriba). Documentado porque los comentarios
de dev en `js/first-run-stage-jWP7PI3J.js` (una demo/tour que porta el mismo efecto a nivel de
página web) explican con mucho detalle el diseño original, y puede ser la referencia si el usuario
llegó a ver esta versión en builds anteriores.

| Valor | Detalle | Fuente / confianza |
|---|---|---|
| Grosor de banda (franja del método "strip") | `--sg-t: 96px` (variable CSS `.sg-glow`) | Alta (CSS) |
| Grosor de banda real del anillo de producción anterior (ventana, no display completo) | 112 px arriba/abajo, 122 px izquierda/derecha (`GLOW_BAND_H`/`GLOW_BAND_V`), con radio de esquina fijo de **18 px** (`GLOW_CORNER_RADIUS`) | Alta (comentario de dev muy explícito, con changelog de por qué 18 y no el grosor de banda) |
| Opacidad | `--sg-o: .66` (66%) | Alta (CSS) |
| Colores base (gradiente "sway"/aurora) | `linear-gradient(135deg, #1c69f0 15%, #0ab4af 40%, #8c46e6 60%, #1496dc 85%)` — mismos 4 tonos que el shader de producción | Alta (CSS) |
| Colores del método "og-spectrum" (producción legacy, `og-spec-b`) | Dos paints conic-gradient contrarrotantes: A = `conic-gradient(from 0deg, rgb(24,68,215) 0deg, rgb(150,200,255) 38deg, rgb(60,115,238) 74deg, rgb(10,42,175) 118deg, rgb(125,185,252) 152deg, rgb(35,85,225) 195deg, rgb(160,205,255) 238deg, rgb(15,52,190) 275deg, rgb(90,150,245) 315deg, rgb(24,68,215) 360deg)`, rotando 18 s lineal; B = arcos claros translúcidos (highlights), rotando 29 s lineal en sentido contrario (137°→‑223°) — TODO azul, sin el violeta/teal del método "sway" | Alta (comentario de dev + JS de la demo) |
| Respiración del marco ("breathe") | `scale(1)` → `scale(1.012)` → `scale(1)`, 6.5 s ease-in-out infinito | Alta (CSS + JS) |
| Transición de aparición/desaparición | `opacity .7s var(--ease-settle) .8s` (delay 0.8 s); `--ease-settle: cubic-bezier(.32,.72,0,1)` | Alta (CSS) |
| Ripple de activación | `scale(.05)→scale(2.3)`, opacity `0→.55→0`, 0.85 s `cubic-bezier(.25,.55,.35,1)` (variante suave: `.7s cubic-bezier(.2,.65,.3,1)`) | Alta (CSS) |
| Setting que lo desactiva | `screen_glow_enabled` (booleano; función `setScreenGlowEnabled` en `main-BL-DABKy.js`, default `true`) | Alta |

**No se encontró** ninguna evidencia (en ninguno de los dos métodos) de que el glow reaccione al
nivel de audio/mic en tiempo real — ni uniform de shader, ni variable CSS, ni listener cruzado con
`audioLevelsSource`.

---

## 2. Puntero / selección de elemento al mantener fn

### 2.A — Rastro de tinta ("comet"), implementación real de escritorio

Fuente: `js/overlay-DstkIEbM.js`, componente que monta `<canvas class="ov-cshow-trail">` dentro de
`<div class="ov-cshow" data-testid="cursor-show-layer">`. Las posiciones NO vienen de eventos DOM de
mouse normales: se reciben vía un `CustomEvent("ov-cursor", {detail:{x,y}})` despachado en el
`document` — es decir, la posición real del cursor llega desde el lado nativo (Tauri) y se
redistribuye como evento de página. El rastro solo se dibuja/graba mientras una prop `listening`
es verdadera (gate ligado al estado de hold, compartido con el "companion orb" de 2.B).

| Valor | Detalle | Confianza |
|---|---|---|
| Color del trazo | `rgb(70, 120, 245)` (azul, sólido, sin gradiente) | Alta |
| Ancho máximo del trazo | 16 px | Alta |
| Vida de un punto del rastro | 620 ms (puntos más viejos se descartan) | Alta |
| Adelgazamiento de cola | En el último 20% de vida del punto, el ancho interpola linealmente de 16 px a 0 (por debajo de 0.5 px el segmento no se dibuja) — o sea el rastro se afina y desaparece en la cola, no aparece cortado de golpe | Alta |
| Suavizado de posición | La posición usada para el rastro es un lerp de la posición cruda del cursor, factor 0.3 por frame (30%) — no seguimiento 1:1 exacto, hay un pequeño "arrastre" | Alta |
| Distancia mínima entre puntos grabados | 1.5 px (evita graduar puntos redundantes cuando el cursor casi no se mueve) | Alta |
| Opacidad de composición | La capa de rastro completa se compone sobre el canvas visible con `globalAlpha = 0.3` | Alta |
| Corte de rastro en saltos | Si el cursor "teletransporta" más de 260 px entre eventos (cambio de pantalla, warp), se inserta un punto de "quiebre" que corta la línea en vez de conectar con un trazo largo | Alta |
| Render | Doble canvas (uno de trabajo fuera de pantalla + composición con `globalAlpha`), con recorte a un "dirty rect" (bounding box de los puntos vivos + 20 px de margen) por rendimiento | Alta |

### 2.B — "Companion orb" cerca del cursor (no es un highlight del elemento)

**No se encontró** ningún outline/caja/relleno que resalte el elemento de UI bajo el cursor (nada de
`highlight`, `outline`, `ax-element`, `elementRect` ligado a fn en los bundles JS/CSS revisados). Lo
que sí existe, y probablemente es lo que el usuario recuerda como "algo se resalta", es un orbe
pequeño que sigue al cursor durante el hold:

| Valor | Detalle | Confianza |
|---|---|---|
| Tamaño | Círculo de 32×32 px (`.ov-hold-orb`), con un "pill" contenedor de 46 px de alto | Alta (CSS) |
| Offset respecto a la punta del cursor | +14 px en x, +17 px en y | Alta (JS) |
| Suavizado de seguimiento | Lerp 0.16 por frame (más suave/perezoso que el rastro de tinta, que usa 0.3) | Alta |
| Aparición/desaparición | `opacity 0→1` + `scale .85→1`, 0.18 s con `--ease-standard` (`cubic-bezier(.4,0,.2,1)`) | Alta |
| Chips de "captura" (`ov-hold-collect`) | Cuando el sistema captura algo (archivo, texto seleccionado, texto copiado — kinds `file` / `selected-text` / `copied`), aparece una píldora de 26 px alto, fondo `#17171a`, radio 999px (pill), texto blanco 13px/500, con icono; entra con spring (`.46s`, `--ease-bounce` = `cubic-bezier(.34,1.56,.64,1)`) y sale acelerando hacia arriba (`.26s cubic-bezier(.55,0,1,.45)`), apiladas con 31 px de separación vertical | Alta |
| Qué se captura | Solo se confirmaron 3 tipos de "kind" en el código: `file`, `selected-text`, `copied` (ninguna mención a un tamaño de crop de screenshot ni a estructura de nodo AX en el JS) | Media (lista de kinds confirmada; el mecanismo de captura en sí es nativo/Rust, fuera de alcance de los bundles JS) |

**Cursor personalizado**: no se encontró un cursor de sistema reemplazado a nivel SwiftUI/AppKit en
los bundles — el único "cursor SVG a medida" que aparece en los assets (path de Lucide
`mouse-pointer-2`, colores por acción: azul `#2563eb` click, verde `#16a34a` type, rosa `#db2777`
screenshot, violeta `#7c3aed` scroll, cian `#0891b2` navigate, teal `#0d9488` select, índigo
`#4f46e5` spinner...) vive en `js/first-run-stage-jWP7PI3J.js`, que por su contenido (comentarios
fechados "Emil, 2026-08-19/20/22", lógica de hotspot/banking de SVG en un DOM de página) es una
**demo/tour de un cursor inyectado en páginas web** (para cuando el agente conduce un navegador),
no necesariamente el cursor nativo de macOS que se ve al mantener fn en escritorio. Se cita aquí
solo como referencia de paleta de colores por "modo", no como comportamiento confirmado del
puntero de escritorio.

**Captura de pantalla / recorte AX**: no se encontró tamaño de crop, ni estructura de nodo AX, en
ninguno de los archivos JS/CSS revisados — esa lógica vive del lado nativo (Rust) y no está
expuesta en el bundle web.

---

## 3. Tooltips y dropdowns del island/notch

Fuente principal: `firstRun-BOTAwJJ8.css` (a pesar del nombre del chunk, contiene también las clases
`.ov-island-*` compartidas — Vite duplicó/incluyó el CSS del island ahí). El menú/dropdown usa
convenciones de atributo (`data-starting-style`, `data-ending-style`, `data-side`) típicas de un
componente de popup sin estilos tipo Base UI / Floating UI.

### Tooltip (`.ov-island-tooltip`)

| Valor | Detalle | Confianza |
|---|---|---|
| Posición por defecto | ARRIBA del trigger: `bottom: calc(100% + 4px)`, centrado horizontal (`left:50%; transform:translateX(-50%)`) | Alta |
| Variante "abajo" | Con atributo `[data-below]`: `top: calc(100% + 6px)` | Alta |
| Variante dentro del island (con separación dinámica) | `top: calc(100% + var(--isl-tooltip-clearance, var(--isl-gap)))`, donde `--isl-tooltip-clearance = calc(altura-de-la-fila-de-chat + sp-4)` — es decir, el offset se ajusta para no tapar la barra de chat activa | Alta |
| Tamaño / forma | Alto 40 px, padding `0 18px`, `border-radius: 9999px` (pill) | Alta |
| Fondo (variante base) | `var(--overlay-surface-pill)` = `rgb(10,10,12)` (casi negro), borde `var(--overlay-border-pill)` = `rgba(255,255,255,.15)` | Alta |
| Fondo (variante oscura alternativa) | `#17181b`, borde `#ffffff24` (~14% alpha), sombra `0 1px 2px rgba(0,0,0,.75), 0 6px 18px rgba(0,0,0,.50)` | Alta |
| Tipografía | 14px, weight 500, line-height 1, color blanco, `white-space:nowrap` | Alta |
| Animación | Solo opacity (`0→1`), `var(--overlay-duration-snap)` = **0.15s**, easing `var(--ease-standard)` = `cubic-bezier(.4,0,.2,1)` — sin escala ni traslado, aparece/desaparece con fade puro | Alta |
| Render | Se posiciona con `position:absolute` respecto a su contenedor (no hay evidencia de una ventana nativa separada ni de `data-testid` de ventana adicional) — mecanismo de portal DOM dentro de la MISMA ventana overlay, no una ventana Tauri nueva | Media-alta (ausencia de labels de ventana adicionales en `strings`, pero no se pudo confirmar el `tauri.conf.json` directamente) |

### Dropdown / menú (`.ov-menu`, clase base de librería `.ui-menu-popup`)

| Valor | Detalle | Confianza |
|---|---|---|
| Ancho | 230 px (variantes: `--volume` 244 px, `--shortcuts` 224 px) | Alta |
| Padding / radio | Padding 6px, `border-radius: 16px` (override; el radio base de la librería es `var(--radius-card-sm, 18px)`) | Alta |
| Fondo / borde / sombra (capa base de librería, tema claro) | `background: var(--color-surface-primary, #fff)`, borde `1px solid var(--color-popup-border, transparent)`, `box-shadow: 0 16px 48px rgba(0,0,0,.14)` | Alta |
| Popover hermano (`.ui-popover-popup`) | Radio 16px, fondo `#fff`, sombra `0 16px 48px rgba(0,0,0,.14)` (alpha exacto `#00000024`), transición 0.18s | Alta |
| Ítems de menú | Padding 10px, `border-radius: 8px`, gap 10px, fuente 13px/500, transición de fondo 0.14s con `--ease-settle` (`cubic-bezier(.32,.72,0,1)`) | Alta |
| Posicionamiento | Vía atributo `data-side` (`bottom` confirmado; el patrón de la librería sugiere que también soporta `top`/`left`/`right` según espacio disponible — no se pudo confirmar todas las variantes en el CSS extraído) | Media |
| Animación de apertura/cierre | Base librería: `opacity 0→1` + `scale(.98→1)`, 0.2s `--ease-standard`. Variante `ov-menu` (con `data-side`): en vez de escala, usa `translateY(4px→0)` (o `-4px→0` si `data-side=bottom`) — es decir, un pequeño deslizamiento vertical de 4px combinado con fade, 0.2s `--ease-settle` | Alta |
| Backdrop | `.ov-menu-backdrop`: `position:fixed;inset:0;z-index:9998;background:transparent` — captura clics fuera para cerrar, pero es invisible (no oscurece detrás) | Alta |
| Z-index / capas | Positioner del menú `z-index:9999`, por encima del backdrop (9998) y muy por encima del contenido normal del island | Alta |
| Render fuera de la forma del island | El menú/tooltip usan `position:fixed`/`absolute` con z-index alto y no aparecen recortados por ningún `overflow:hidden` del contenedor "pill" del island en las reglas revisadas — consistente con un portal DOM que escapa visualmente la forma redondeada del island, pero dentro de la MISMA ventana (no se encontró un label de ventana Tauri nuevo para menús/tooltips en `strings` del binario) | Media |

**Popover de "stack" de tarjetas** (`.ov-cap-stack-popover`, ej. para mostrar detalle al hacer hover
sobre una pila de tarjetas): posición fija arriba del trigger (`bottom:100%`, centrado), aparece con
`opacity 0→1` + `translateY(4px→0)`, 0.18s `--ease-settle`, cierre más rápido y lineal (0.1s).

---

## Notas / lo que NO se pudo confirmar

- **Lista real de ventanas Tauri** (labels de overlay/glow/cursor/menú) — no se encontró un
  `tauri.conf.json` legible ni labels de ventana en `strings` del binario más allá de genéricos de
  librería (SQLite, símbolos matemáticos de Mermaid). No se puede confirmar si tooltips/dropdowns
  son de verdad una ventana Tauri aparte o un portal DOM (la evidencia indirecta —z-index, falta de
  labels— apunta a portal DOM, no ventana nueva).
- **Reactividad del glow a nivel de audio/mic**: no encontrada en ningún shader ni CSS revisado.
- **Highlight visual del elemento bajo el cursor** (outline/caja/relleno): no encontrado. Solo existe
  el "companion orb" (2.B), que no dibuja el elemento en sí.
- **Estructura exacta del nodo AX capturado y tamaño de crop de screenshot**: vive del lado nativo
  (Rust), fuera del alcance de los bundles JS/CSS.
- El shader de producción (`gl-waves`) fue confirmado por el array de opciones en `main-BL-DABKy.js`
  y por su presencia activa en `overlay-DstkIEbM.js`; no se pudo verificar con un pantallazo en vivo
  (investigación 100% estática sobre los assets ya extraídos).

## Archivos fuente citados

- `<scratchpad>/inc/overlay-CkZPSNkG.css`
- `<scratchpad>/inc/firstRun-BOTAwJJ8.css`
- `<scratchpad>/inc/js/overlay-DstkIEbM.js`
- `<scratchpad>/inc/js/main-BL-DABKy.js`
- `<scratchpad>/inc/js/first-run-stage-jWP7PI3J.js` (demo/tour, citado con salvedad)
- `<scratchpad>/inc/js/audioLevelsSource-DSOQLR23.js`
- `<scratchpad>/inc/js/EventsTab-CRHuKw96.js`
- `/Applications/Incredible.app/Contents/Info.plist`
- `~/.incredible/overlay.json` (solo claves/valores de configuración, sin secretos)
