# Wave 16l — Componentes como Incredible

**Estado: CERRADO EN CÓDIGO (2026-09-25), sin commit; code-reviewer y security-reviewer APPROVE; falta la revisión visual de Karen. Aprobado con "vamos con todo, en loop sobre la spec hasta que finalices".**
Karen: "que componentes debemos replicar sobre companion? quiero que se vea exactamente igual".

Evidencia: `docs/research/incredible-componentes.md` (medidas de su CSS y de sus variantes de
componente, sin copiar código). Base: 16k (escala, espaciado, radios).

## 1. Decisiones

- **El acento no cambia.** El botón que Incredible usa es negro; el `btn-primary` azul es una
  clase heredada casi sin uso. El lima sigue siendo el énfasis elegible de Companion.
- **Tema claro exacto, oscuro derivado.** Incredible no tiene tema oscuro en la ventana; Companion
  conserva el suyo y solo el claro toma los valores medidos.
- **Disabled = 50 % de opacidad**, como Incredible (antes Companion tenía un look propio).
- **Sombras de una capa.** `shadow-card` tiene dos capas en CSS; SwiftUI apila sombras con coste,
  así que se usa la capa dominante.
- **Mismo componente, mismas medidas en todas partes:** los sitios que hoy usan piezas nativas
  (Toggle, Picker, menú del sistema) pasan a piezas propias.

## 2. Sesiones

| Sesión | Qué | Archivos |
|---|---|---|
| 16l-1 | Colores (claro), estados, sombras, curvas; botón (solid, ghost, danger, hero), botón de icono, cerrar, badge, keycap sm/lg | `TokensChoices`, `ControlChrome`, `Controls`, `SettingsPieces`, `Pressable` + test |
| 16l-2 | Switch y select propios; menú (ventana e isla) con las medidas de `ui-menu` | `IncredibleControls` (nuevo), `SettingsPieces`, `Dropdown`, `IslandPopover`, `SettingsPages` |
| 16l-3 | Action card con halo que sigue al cursor, glow card, status dot, tarjeta elevada | `IncredibleCards` (nuevo), `HomePage`, `GalleryCard` |
| 16l-4 | Isla: opción de respuesta, chip de referencia, tira de capturas, popup de respuesta rica | `IslandAnswerPieces` (nuevo), uno o dos puntos de uso en la isla |

## 3. TDD

Cada sesión fija sus medidas en `IncredibleComponentsTests.swift` (valores de la investigación)
antes de tocar las vistas. Lo visual se verifica con snapshots (`COMPANION_SNAPSHOTS=<dir>`).

## 4. Riesgos

- La otra sesión (16j) edita `MarkdownView`, `HomePage`, `ChatViewModel`: los componentes nuevos
  van en archivos nuevos y los puntos de uso se tocan al final de cada sesión.
- Cambiar `AppButton` mueve sus 11 usos a la vez: es lo buscado.

## 5. Cierre por sesión (2026-09-25, sin commit)

- **16l-1** Paleta clara medida (`Palette.swift`), estados (`StateAlpha`), roles `wash`,
  `hoverSubtle`, `popupBorder`, estado y peligro; sombras = card / raised / popup / modal;
  curvas standard / settle / glide / bounce. `AppButton` = botón de Incredible (negro, píldora,
  40 × 20, 14 pt semibold, crece 3 %, disabled 50 %; `.pill` = botón de bienvenida 46 × 30,
  15 pt). `SettingsPill` con las mismas medidas; `IconButton`, `Badge`, `Keycap` nuevos
  (`IncredibleChrome.swift`); la tecla de Ajustes y la de bienvenida los usan.
- **16l-2** `IncredibleSwitch` dibujado (38 × 23, pulgar 19) sustituye al `Toggle` nativo;
  el selector de Ajustes toma las medidas de `ui-select` (42, radio 14, lavado 5 %); el
  `Picker` segmentado de Apariencia pasa a ese selector; menú de la ventana y de la isla con
  las medidas de `ui-menu` (`IncredibleControls.swift`).
- **16l-3** `cardSurface` = tarjeta elevada (radio 16, borde `#eee`); `ActionCard` con halo
  que sigue al cursor (Get Started de Home); `glowRow` + `GlowChip` en las filas de tareas;
  `StatusDot` (`IncredibleCards.swift`).
- **16l-4** Tinta de la isla = blancos de Incredible (95 / 64 / 42 / 6 / 12 / 9 / 7 %), acento
  `#78aaff`, error `#ff7a64`, verde `#78d6a8`, enviar 30, radio 28. Chip de referencia
  conectado a "Abriendo …". `AnswerOption`, `CaptureCard` y `AnswerPopup` construidos y
  medidos, **sin conectar**: hoy Companion no pregunta con opciones, los adjuntos viven en la
  ventana y la respuesta rica no llega a la isla (`IslandAnswerPieces.swift`).

Pendiente: la "x" de `TaskDetailSheet` (archivo de 16j) al botón de cerrar de 32; conectar
las tres piezas de la isla cuando exista su dato (16h / 16i).
