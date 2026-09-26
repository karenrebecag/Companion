# Incredible — tipografía, espaciado, retícula y escala (medido)

Fecha: 2026-09-25. Fuente: Incredible 0.2.36 (`one.incredible.new`, Tauri + Vite + Tailwind v4),
CSS embebido en el binario (brotli), extraído en solo lectura. Aquí van **valores**, no código:
nada de su CSS se copia al repo.

Ventanas y hojas de estilo:

| Ventana | CSS | Papel |
|---|---|---|
| Principal (chat, ajustes) | `index-*.css` (131 KB) | tokens `@theme` de Tailwind |
| Isla / overlay del notch | `overlay-*.css` (1 MB, incluye Tailwind) | `html[data-window=overlay]` |
| Bienvenida | `firstRun-*.css` | pantallas de primer arranque |
| Widgets | `styles-*.css` | switch, select |

## 1. Familias

| Contexto | Sans | Mono |
|---|---|---|
| Ventana principal | **fuente del sistema** (`-apple-system` → SF Pro) | Geist Mono |
| Isla (overlay) | **Geist Sans**, cuerpo 13 px | Geist Mono |
| Bienvenida | Geist | `ui-monospace` (SF Mono) |

- Geist y Geist Mono se cargan como **variables** (eje `wght` 100–900), subconjuntos latin y
  latin-ext. Sin itálicas.
- Montserrat no aparece en ninguna hoja.
- Consecuencia para Companion: la wave 16c puso Geist en toda la app. Incredible solo la usa en
  la isla y en la bienvenida; la ventana principal habla en SF Pro.

## 2. Pesos

| Token | Valor |
|---|---|
| `font-weight-normal` | 400 |
| `font-weight-medium` | 500 |
| `font-weight-semibold` | 600 |
| `font-weight-bold` | 700 |

## 3. Escala tipográfica (por papel)

| Token | Tamaño | Interlineado |
|---|---|---|
| `text-micro` | 11 px | 1.35 |
| `text-caption` | 12 px | 1.4 |
| `text-body` | 13 px | 1.5 |
| `text-row-title` | 14 px | 1.4 |
| `text-hero-body` | 15 px | 1.5 |
| `text-section-title` | 16 px | 1.3 |
| `text-dialog-title` | 20 px | 1.2 |
| `text-banner-title` | 22 px | 1.2 |
| `text-page-title` | 30 px | 1.2 |
| `text-display` | `clamp(30px, 3.2vw, 42px)` | 1.06 |

Tamaños sueltos en la isla, por frecuencia: 13 (7), 14 (2), 12 (2), 10 (2), 15, 12.5, 11.

Interlineados con nombre: tight 1.25 · snug 1.375 · normal 1.5 · relaxed 1.625.

Tracking con nombre: tight −0.025em · wide 0.025em. Usados además: −0.03, −0.02, −0.015,
−0.011, −0.01, −0.005, 0.04, 0.06, 0.07, 0.08 em (los positivos en etiquetas en mayúsculas).

Color de texto (claro): primary `#1c1c1e` · secondary `#6c6c70` · muted `#727276` ·
faint `#8e8e93`.

## 4. Escala del usuario (scaling)

- **No hay control de tamaño de texto.** Ni en la interfaz ni en la configuración aparece un
  ajuste de tamaño. El binario lleva el comando `webview_zoom` de Tauri, pero ningún fragmento
  del frontend lo llama.
- Todo va en px fijos. Lo único fluido es `text-display`, que crece con el ancho de la ventana
  (3.2vw entre 30 y 42 px).
- Consecuencia: el `TypeScale` de Companion (pasos ×1.08, de −1 a +3) no tiene equivalente.

## 5. Espaciado

Base: `--spacing: 4px` (Tailwind). Múltiplos más usados en la ventana principal:

| ×4 | ×6 | ×2 | ×1.5 | ×5 | ×3 | ×8 | ×3.5 | ×2.5 | ×7 | ×10 | ×9 | ×12 | ×0.5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 16 | 24 | 8 | 6 | 20 | 12 | 32 | 14 | 10 | 28 | 40 | 36 | 48 | 2 |

Menos frecuentes: 44, 56, 64, 80, 96, 192 px.

Espaciados con nombre:

| Token | Valor | Uso |
|---|---|---|
| `spacing-gutter` | 56 px | margen lateral de página |
| `spacing-section` | 40 px | entre secciones |
| `spacing-card-end` | 24 px | cierre de tarjeta |
| `spacing-indent` | 18 px | sangría de filas anidadas |

En la isla los paddings y gaps son más apretados: 8 (6), 4 (4), 12 (4), 7 (3), 3 (3), 6 (2),
16 (2).

## 6. Retícula y contenedores

| Token | Valor |
|---|---|
| `container-sm` | 384 px |
| `container-md` | 448 px |
| `container-xl` | 576 px |
| `container-4xl` | 896 px |
| `container-content` | 960 px (columna de contenido) |
| `container-5xl` | 1024 px |
| `container-6xl` | 1152 px |

Anchos fijos que se repiten: 220, 280, 380 (paneles y barras laterales), 440, 520, 560, 720,
980.

## 7. Radios

| Token | Valor |
|---|---|
| `radius-sm` | 4 |
| `radius-md` | 6 |
| `radius-badge` | 8 |
| `radius` (base) | 10 |
| `radius-chip` | 10 |
| `radius-control` | 14 |
| `radius-lg` / `2xl` | 16 |
| `radius-card-sm` | 18 |
| `radius-dialog` / `xl` | 20 |
| `radius-card` | 22 |
| `radius-panel` | 28 |

## 8. Medidas de controles

| Control | Medidas |
|---|---|
| Switch md | 38 × 23, pulgar 19, padding 2 |
| Switch sm | 28 × 16, pulgar 12, padding 2 |
| Select sm | alto 34, texto 12 px |

## 9. Diferencias con Companion hoy

| Eje | Companion | Incredible |
|---|---|---|
| Sans en ventana principal | Geist | SF Pro (sistema) |
| Sans en la isla | Geist | Geist Sans |
| Escalones | 11 · 13 · 16 · 22 · 29 | 11 · 12 · 13 · 14 · 15 · 16 · 20 · 22 · 30 · 30–42 |
| Interlineado | solo `bodyLead` 0.3 y `codeLead` 0.15 | uno por escalón (1.06–1.5) |
| Tracking tight | −0.02em | −0.025em |
| Escala del usuario | ×1.08 por paso, −1…+3 | ninguna |
| Espaciado | 0, 4, 8, 12, 16, 20, 24, 32 | base 4, más 2, 6, 10, 14, 28, 36, 40, 48, 56 y cuatro semánticos |
| Radios | 4, 8, 12, 16, 20 | 4, 6, 8, 10, 14, 16, 18, 20, 22, 28 |
| Columna | `Container.sheet` 520 | `container-content` 960 |
