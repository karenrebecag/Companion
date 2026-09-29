# Wave 16p — Cerrar la brecha de UI con Incredible

**Estado: APROBADO (2026-09-29).** Firmado por delegación de Karen: "podemos igualar? trabaja
sobre un worktree especifico para estos fixes... todo en loop. tu eres el orquestador, delega
subagentes en loop para cerrar toda esta brecha". Evidencia:
`docs/research/audit-ui-companion-vs-incredible.md` (conteos con archivo:línea).

## 1. Qué cierra

El audit encontró que la ingeniería de la UI ya supera a Incredible (tokens con enforcement,
máquina de estados, motion presupuestado, i18n) y que la brecha restante es de **consolidación**
y de **catálogo**. El catálogo lo cubren 16m-3..7 y 16h (firmadas). Esta wave cubre lo demás.

## 2. Programa y orden

Dos carriles en worktrees propios, integrados en la rama `feat/ui-gap`. Un solo PR
`feat/ui-gap → main` al final, que Karen lee antes del merge (regla de ritmo: nada llega a
`main` sin que lo lea).

| Carril | Orden | Sesión |
|---|---|---|
| UI (`companion-next-ui-gap`) | 1 | 16p-1 quick wins |
| | 2 | 16p-2 consolidación (antes de 16m-3: parte `IslandView` por familias) |
| | 3-7 | 16m-3 adjuntos, 16m-4 dictado y avisos, 16m-5 gráficas y Mermaid, 16m-6 pregunta con opciones y rejilla de avisos, 16m-7 menciones y comentarios |
| | 8 | 16p-3 tipografía y pins |
| Conversación (`companion-next-ui-gap-h`) | 1-3 | 16h-1 filtro de voz, espacios, "listo" con prueba, compuestos; 16h-2 acuse y delegación en segundo plano; 16h-3 dónde estás e isla→modelo |

Cada sesión: test en rojo → implementación → code-reviewer y security-reviewer en paralelo →
hallazgos aplicados test-first → `scripts/gates.sh` verde → PR a `feat/ui-gap` con bitácora.

## 3. 16p-1 — Quick wins

1. **Errores visibles.** `ChatViewModel.errorText` hoy solo lo pinta `ThreadView`, que nadie
   instancia. Se pinta en la isla (aviso con salida, patrón `IslandNoticeCard`) y en Home.
   Test: un `errorText` no nulo produce estado visible en la proyección de la isla.
2. **reduceMotion** en `CompanionRootView`, `SettingsView`, `Dropdown`, `MainSidebar`: sus
   animaciones leen `accessibilityReduceMotion` y caen a opacidad/instantáneo. Test por la
   función pura que elige la animación.
3. **i18n fuera del catálogo**: labels de `Highlight` (`TokensChoices`), `ShortcutAction`
   (`Shortcuts`), tema (`UserPreferences`), "Opening/Abriendo" (`IslandAnswerPieces`) pasan a
   `Localizable.strings` es/en. Test: cada label resuelve a una clave existente en ambos idiomas.
4. **Semántica de botón** en los 11 `onTapGesture` interactivos (patrón `AppsPage:374`:
   `accessibilityAddTraits(.isButton)` + `accessibilityAction`, o `Button` con estilo plano).

## 4. 16p-2 — Consolidación

1. **Una primitiva por papel**: un keycap (sm/lg, con `.elevation`), un estilo de chip en
   cápsula parametrizado por tinta, un botón cerrar (ventana e isla por variante), botones de
   icono reducidos a `IconButton` + variante de isla. Métricas pinneadas a los valores medidos.
2. **Retirar código muerto** (0 instancias verificadas por grep al empezar la sesión):
   `HeaderView` (salvo `ChoiceDropdown`/`HistoryOverlay`, que se mueven), `ControlBar`,
   `ThreadView` (su helper `visible` se muda), `ChatInputView`, `StatusLine`, `AttachmentStrip`,
   `Badge` si sigue sin uso, vista `PermissionRow`, `ShortcutCaptureField`, `VoiceControlsView`,
   `OrbLayers`, `UI.swift`, `IslandHandsChip`, y los huérfanos por arrastre. **`OnboardingView`
   se retira**: la bienvenida `Welcome*` es el único flujo (Karen, 2026-09-29, "cerrar toda
   esta brecha"; recuperable del historial). El baseline de conformance baja con cada borrado.
3. **Paletas locales**: `DataCardInk`, `AttachmentLook`, `ControlFill/Ink/Stroke` se funden en
   `Semantic` o quedan documentadas con su porqué como `IslandInk`/`AnswerInk` (isla siempre
   negra, ovx medido).
4. **`IslandView` por familias**: carpetas `Island/Data`, `Island/Work`, `Island/Attach`,
   `Island/Notices` (riesgo §4 de 16m). `IslandView.swift` queda como composición < 400 líneas.
5. **Fugas de TypeScale**: los 16 `.system(size:)` con expresión pasan por `Fonts`/`GeistFont`;
   `MenuMetrics.duration` usa `MotionTime.base`. Regla nueva del contrato que los detecte.

## 5. 16p-3 — Tipografía y pins

1. Interlineado por escalón en `TypeScale` (valores medidos: 11/1.35, 12/1.4, 13/1.5, 14/1.4,
   15/1.5, 16/1.3, 20/1.2, 22/1.2, 30/1.2, display 1.06) y roles que lo usan.
2. Pins para `MainWindowMetrics`, `AppsMetrics`, `AppPanelMetrics`, `ConnectingSheetMetrics`,
   `IslandAttachMetrics`, `IslandDropMetrics`.

## 6. Criterio de done

Gates verdes; baseline de conformance ≤ al de hoy en cada archivo tocado; cero vistas con 0
instancias en `Sources/`; `IslandView.swift` < 400 líneas; galería de snapshots regenerada con
cada familia nueva; PR final con bitácora por sesión.

## 7. Riesgos

- Borrar `ThreadView` y `HeaderView` arrastra helpers vivos: se mudan antes de borrar, con grep.
- Dos carriles tocan la isla (16h-2 añade la tarjeta de recibo): el carril de conversación
  rebasa sobre `feat/ui-gap` antes de su PR.
- Mermaid (16m-5) es la única dependencia nueva: vendoreada con versión y hash fijados, sin red,
  CSP cerrada, revisión de seguridad propia.

## 8. Seguimiento de 16p-2 (anotado, no bloqueante)

- **Rive — HECHO 2026-09-29** (Karen: "quita rive"): fuera el binaryTarget, `vendor/`,
  `hello.riv` y su paso en `bundle.sh`; `Mascot/` conserva solo `claude.svg` (hoja de
  aprobación). ADR 003 retirada.
- **`ExecutorChoice` — HECHO 2026-09-29** (Karen: "retira executor choice"): fuera
  `ExecutorPicker.swift` y el campo de App. Su `refresh` reescribía la misma selección (no-op);
  el probe de CLIs al arrancar se conserva porque `WorkRouting` depende de él.
- **`AnswerOption` retirada** por no tener instancias; 16m-6 (pregunta con opciones) la
  reconstruye desde el historial con su dato.
- **Pantallas de base local (Ollama / Apple)** se fueron con `OnboardingView`; el camino sin clave
  sigue vivo en la bienvenida (`acceptLocalBase`, paso de claves).

## 9. 16p-3: alcance real (2026-09-29)

Lo que ya existía al abrir la sesión: `Leading` (los 10 interlineados por escalón, wave 16k-1) y
sus pins; `IslandAttachMetrics` con pins de 16m-3 para lo medido. Lo que faltaba era que algún papel
**usara** el interlineado (solo lo hacía el hero de Home) y los pins de las métricas de ventana.

**Interlineado por papel.** `TypeRole` (Typography.swift) une tamaño e interlineado de cada escalón
(`micro` 11/1.35 … `display` 30/1.06). `View.typeRole(_:)` pone fuente e interlineado juntos (para
que un texto no reciba el tamaño de un papel con el interlineado de otro) y `typeLeading(_:)` solo
el interlineado. `SwiftUI.lineSpacing` se SUMA a la altura natural de la fuente (en SF ~1.2x el
tamaño), así que el hueco no es `size*(ratio-1)` sino `max(0, ratio*size - natural)`, con
`natural` = `NSAttributedString.size().height` de la fuente (coincide con SwiftUI a la unidad; ni
`NSLayoutManager` ni las métricas de CoreText lo hacen en varios tamaños). `TypeRole.lineSpacing()`
aplica `TypeScale.apply(size)` por dentro, así el hueco sigue la escala del usuario.

Altura de línea renderizada (delta 0, 21 líneas menos 1, entre 20), esperada = ratio x tamaño,
tolerancia 0.5 pt (`testRenderedLineHeightIsTheMeasuredRatio`):

| Papel | Medida | Esperada |
|---|---|---|
| micro 11 | 14.85 | 14.85 |
| caption 12 | 16.85 | 16.80 |
| body 13 | 19.50 | 19.50 |
| rowTitle 14 | 19.65 | 19.60 |
| heroBody 15 | 22.50 | 22.50 |
| sectionTitle 16 | 20.85 | 20.80 |
| dialogTitle 20 | 24.00 | 24.00 |
| bannerTitle 22 | 26.40 | 26.40 |
| pageTitle 30 | 36.00 | 36.00 |
| display 30 | 35.00 | 31.80 |

`display` (1.06) es más apretado que la línea propia de SF (35 pt) y SwiftUI ignora un
`lineSpacing` negativo (medido: -3 no cambia nada), así que se queda en 35: techo conocido, se
resuelve solo si el display se compone con `NSTextView`/`kerning` propio.

Lo usan 21 textos de varias líneas de Home (hero, pasos), Apps, panel de app y hoja de conexión:
cuerpo `.body` (13/1.5), avisos y notas `.micro`. Trampa de nombres: `Font.uiCaption` es el
escalón de 11 pt (`.micro`); `TypeRole.caption` es de 12 pt. `TypeLeadingConformanceTests` exige que
todo `Text` con `.fixedSize(horizontal: false` de esos cuatro archivos lleve `typeRole` (o
`typeLeading` con la fuente del mismo papel) y falla al quitarlo o cruzarlo. Excepciones explícitas
con motivo en `TypeLeadingLint.exempt`: isla, Ajustes, Bienvenida, ApprovalSheet, OwnMCPSheet,
ChatErrorSurface, Controls.

**Pins nuevos** (`Tests/CompanionTests/Pins16p3Tests.swift`):

| Métrica | Origen del valor |
|---|---|
| `AppPanelMetrics` 1000 x 700, columna izquierda 430, icono 44 | medido: spec 16k §9.5 D1 (auditoría del binario, no está en `docs/research`) |
| `ConnectingSheetMetrics.icon` 72 | medido: captura en vivo 2026-09-28 (16k-2d) |
| `IslandDropMetrics.litFill` / `litStroke` | medido: grabación 18:11 de NotchNook |
| `IslandDropMetrics` alto 36, padding 16, filete 1.5, 28 %, radio 12, texto 12 | medido, ya pinneado en 16m-3 |
| `IslandDropMetrics.dash` [6, 4] | propio: el CSS deja el trazo al navegador |
| `AppsMetrics` icono 40, tarjeta 132, gap 16, formulario 460 | propio: la rejilla de Incredible se leyó por estructura, no por píxeles |
| `ConnectingSheetMetrics` hoja 520, carril 120, punto 8 | propio |
| `MainWindowMetrics` detalle 860 x 620, columna 220 | propio: el detalle de tarea de Incredible no se midió |
| `IslandAttachMetrics` desvanecido 20, pila 3 x 2 capas, icono de respaldo 22, miniatura 204 (2x del lado largo), caché 64 | propio, cada uno anotado en su archivo |

**Divergencias corregidas.** `MainWindowMetrics` traía `sidebar` = 220, cuando la barra medida es
248 (`SidebarMetrics.width`, pinneada en 16n), más `avatar`, `heroHeight`, `startWidth` y
`pageMaxWidth` sin un solo consumidor (grep en `Sources/` y `Tests/`: 0). Se borran: la medida vive en
`SidebarMetrics` y una segunda copia con otro número era una trampa.

**Contrato de conformance.** Baseline sin cambios: ninguno de los archivos tocados figura en él y
la sesión no añade infracciones (las cinco reglas de literales quedan a cero en ellos).

**Galería.** `Window16p3SnapshotTests` añade Home, panel de app y hoja de conexión, que no tenían
entrada (Home va por un hosting view: `ImageRenderer` pinta un `ScrollView` en blanco). Es una
galería para leer a ojo; la medida está en `testRenderedLineHeightIsTheMeasuredRatio`. Antes/después
con la altura de línea corregida: cambian solo los párrafos de varias líneas (hero de Home, pasos,
descripción y notas del panel, cuerpo de la hoja); la hoja "failed" casi no se mueve porque el
interlineado por defecto de SwiftUI ya andaba cerca de 1.35 a 11 pt. Las galerías de isla, Ajustes y
Bienvenida solo difieren en el ruido de animación en vivo (decenas de píxeles en el orbe y el punto
de escucha; ningún código de esas pantallas cambió).
