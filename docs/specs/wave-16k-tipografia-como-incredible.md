# Wave 16k — Tipografía, espaciado y retícula como Incredible

**Estado: APROBADO (2026-09-25, "dale"); 16k-1 HECHA (tokens, gates en verde, sin commit).
D1 conservar el control con paso 0 = Incredible · D2 SF Pro en la ventana principal · D3 960 solo
en el chat, ajustes con sus anchos.** Karen: "todo exactamente igual a como lo
hace incredible, incluso su spacing, reticula, padding, font size y scaling".

Evidencia: `docs/research/incredible-tipografia.md` (valores medidos en su CSS, sin copiar código).

## 1. Objetivo

Que los tokens de Companion tengan los mismos valores que Incredible: familias por contexto, escala
por papel con su interlineado, tracking, espaciado, radios, contenedores y escala del usuario.

## 2. Tokens nuevos

### Familias

| Rol | Ventana principal | Isla | Bienvenida |
|---|---|---|---|
| sans | sistema (SF Pro) | Geist | Geist |
| mono | Geist Mono | Geist Mono | SF Mono |

`Fonts.sans` recibe el contexto (`.window`, `.island`, `.welcome`); por defecto `.window`.

### `TypeSize` y `Leading` (por papel)

| Token | pt | Interlineado |
|---|---|---|
| `micro` | 11 | 1.35 |
| `caption` | 12 | 1.4 |
| `body` | 13 | 1.5 |
| `rowTitle` | 14 | 1.4 |
| `heroBody` | 15 | 1.5 |
| `sectionTitle` | 16 | 1.3 |
| `dialogTitle` | 20 | 1.2 |
| `bannerTitle` | 22 | 1.2 |
| `pageTitle` | 30 | 1.2 |
| `display` | 30…42 según ancho (3.2 % del ancho de ventana) | 1.06 |

Los nombres de hoy se mantienen como alias mientras migran las vistas: `base` = `body`,
`strong` = `sectionTitle`, `title` = `bannerTitle`. `display` pasa de 29 a 30…42.

### `Tracking`

tight −0.025 · wide 0.025, más los usados: −0.03, −0.02, −0.015, −0.01, 0.04, 0.06, 0.08.

### `Space`

Base 4. Se añaden x0_5 = 2, x1_5 = 6, x2_5 = 10, x3_5 = 14, x7 = 28, x9 = 36, x10 = 40, x12 = 48,
x14 = 56. Semánticos: `gutter` 56, `section` 40 (hoy 24), `cardEnd` 24, `indent` 18.

### `Radius`

sm 4 · md 6 (hoy 8) · badge 8 · chip 10 · control 14 · lg 16 (hoy 12) · cardSm 18 · dialog 20 ·
card 22 (hoy 20) · panel 28.

### `Container`

content 960 (columna del chat), narrow 384, medium 448, wide 576. `sheet` 520 se queda para ajustes (D3).

### Controles

Switch md 38 × 23 (pulgar 19), sm 28 × 16 (pulgar 12). Select sm alto 34 con texto 12.

## 3. Archivos (máx. 5 por sesión)

- **Sesión 1, tokens (HECHA):** `TokensChoices.swift`, `Typography.swift`,
  `IncredibleTokensTests.swift` (nuevo) y la rampa de `DesignFoundationTests.swift`. Solo valores y
  tokens nuevos; ninguna vista cambia de token. `TypeScale.bodyLead` sale ahora de
  `Leading.body` (6.5 pt de hueco a 13 pt).
- **Sesión 2, familias por contexto (D2):** `Fonts.sans` recibe el contexto; la ventana principal
  pasa a SF Pro y la isla y la bienvenida piden `.island` / `.welcome` para seguir en Geist. Va en
  una sola sesión con las vistas de la isla para que la isla nunca quede en SF Pro entre sesiones.
- **Sesión 3, vistas de ajustes y chat:** cada fila y título pasa a su papel (`rowTitle`,
  `dialogTitle`, `pageTitle`).

## 4. Restricciones

- Sin dependencias nuevas. Geist ya está en `Fonts/` en OTF estático (4 pesos + Mono 2). Los TTF
  variables de tus zips no hacen falta. Montserrat no entra porque Incredible no la usa.
- Cambiar radios y espaciados mueve ~450 usos existentes: verificar con snapshots
  (`COMPANION_SNAPSHOTS=<dir>`) antes y después de cada sesión.
- La retícula de `docs/specs/reticula/` (escala 01, radio 06) queda sustituida por esta spec; se
  marca así en su README.

## 5. Decisiones que necesito firmadas

- **D1 — Control de tamaño de texto.** Incredible no tiene ninguno. Paridad exacta = quitar el
  control de Ajustes. **Recomendación: conservarlo**, con el paso 0 dando exactamente los valores de
  Incredible. Quitarlo es una regresión de accesibilidad y no cuesta nada mantenerlo.
- **D2 — SF Pro en la ventana principal.** Es lo que hace Incredible, pero contradice la wave 16c
  ("Geist es la fuente del producto"). Paridad exacta = SF Pro.
- **D3 — Columna de 960.** La hoja de Ajustes de hoy mide 520 y con 960 cambia la composición. La
  alternativa es 960 solo en la ventana de chat y en los ajustes el ancho de sus propios paneles
  (380 / 560).

## 6. Criterios de aceptación

1. Test de tokens: cada valor de §2 coincide con la investigación.
2. Snapshots de isla, Ajustes y bienvenida en paso 0 comparados lado a lado con capturas de
   Incredible del mismo estado.
3. `gates.sh` en verde.
