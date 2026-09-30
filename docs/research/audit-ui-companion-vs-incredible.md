# Audit comparativo de UI: Companion vs Incredible

**2026-09-29. Documento de trabajo (no es spec).** Fuentes: lectura completa de
`Sources/CompanionUI` (114 archivos, 18 428 líneas, inventario por agente con
conteos verificables) contra la evidencia ya medida de Incredible 0.2.36 en
`docs/research/` (tokens, tipografía, componentes, medidas, capturas, docs
públicas). **El código de Incredible nunca se lee ni entra al repo: solo
valores medidos y comportamiento observado.** Donde su lado no se pudo medir
(tests, accesibilidad interna), se dice "no comparable" en vez de inventarlo.

---

## 0. Veredicto en una frase

Companion tiene hoy **mejor ingeniería de frontend** (tokens con enforcement
mecánico, máquina de estados con un solo escritor, motion presupuestado y
testeado, i18n con paridad exacta) e Incredible tiene todavía **mejor producto
visual terminado**: catálogo de componentes más completo (16m-3..7 pendientes),
una sola familia de primitivas en vez de dos kits paralelos, y cero código
muerto visible. La brecha de calidad percibida ya no está en los estilos —
paridad lograda en 16c-16o/16m-1/2 — sino en **cobertura del catálogo y
consolidación**.

| Dimensión | Companion | Incredible | Gana |
|---|---|---|---|
| Sistema de tokens | ★★★★★ (enforcement mecánico) | ★★★★ (Tailwind @theme, sin ratchet visible) | Companion |
| Tipografía | ★★★★ (2 interlineados con nombre) | ★★★★★ (uno por escalón, 10 pasos) | Incredible |
| Componentización | ★★★ (2 kits paralelos, duplicados) | ★★★★★ (un kit cva por superficie) | Incredible |
| Atomic design | ★★★ (primitivas reales, sin capas) | ★★★★ (átomos btn/badge/keycap consistentes) | Incredible |
| Estados (arquitectura) | ★★★★★ (reducer, proyección de solo lectura) | ★★★★ (spine/task_projection, inferido) | Companion |
| Estados (cobertura visual) | ★★★★ (carga/error/vacío con huecos) | ★★★★★ (todo estado tiene superficie) | Incredible |
| Motion | ★★★★★ (budgets testeados M1-M8) | ★★★★ (4 curvas nombradas, resto no medible) | Companion |
| UX de flujos | ★★★★ (bienvenida 7, isla como app) | ★★★★★ (tour, primera orden guiada, pasivo) | Incredible |
| Accesibilidad | ★★★ (53 labels, huecos contados) | no comparable (webview; DOM da parte gratis) | — |
| i18n | ★★★★ (551×2 claves, paridad exacta) | ★★ (en observación: UI solo inglés) | Companion |
| Higiene | ★★★ (~1 200 líneas muertas, 4 archivos >400) | no comparable | — |
| Testabilidad de UI | ★★★★ (81 archivos de test importan UI) | no comparable | — |

---

## 1. Sistema de diseño y tokens

**Companion.** Tokens en 4 archivos (`Tokens`, `Palette`, `TokensChoices`,
`Typography`): rampa neutral de 17 pasos, ~40 roles semánticos claro/oscuro
(`NSColor(name:)` dinámico), `Space` base 4 con alias semánticos, 12 radios,
`TypeSize` 11→42 con display fluido, `Stroke`, `Elevation`, y **escala del
usuario** (×1.08, −1…+3) que Incredible no tiene. Consumo real: 526 usos de
`Space.`, 447 de `Semantic.`. Lo que Incredible no puede enseñar: el
**enforcement**. `conformance/ui-contract.json` (10 reglas regex con baseline
ratchet por archivo), `gates.sh` (padding/spacing/cornerRadius/copy literales
bloqueados), y tests de fundamento (`DesignFoundationTests`: contraste AA,
rampa, ratios de escala). Un literal nuevo no compila la suite.

**Incredible.** Tailwind v4 `@theme` con tokens completos y bien nombrados
(`radius-control` 14, `spacing-gutter` 56, sombras por elevación, 4 curvas).
Sin evidencia de ratchet ni de tests de fundamento (no medible desde fuera).
Todo en px fijos; **cero escala de usuario** (el `webview_zoom` de Tauri existe
y nadie lo llama).

**Deuda nuestra, contada:** 43 infracciones en baseline (AttachmentViews 12,
HeaderView 11 — muerta, ThreadView 8 — muerta); 16 `.system(size:)` con
expresión que esquivan `TypeScale` y la fuente del usuario
(`MainSidebar:91,138`, `HomePage:151`, `IslandPieces:228,240`); 26
`opacity(0.x)` literales; `MenuMetrics.duration = 0.2` duplica
`MotionTime.base` fuera del catálogo; y **8 paletas de tinta locales**
paralelas a `Semantic` (`IslandInk`, `AnswerInk`, `DataCardInk`,
`AttachmentLook`, `SyntaxPalette`, `BrandKeycap`, `Monogram`, `ControlFill`).
Las de la isla son decisión documentada (la isla es siempre negra); las demás
son fragmentación.

**Veredicto:** ganamos en gobernanza, ellos en economía (una sola fuente de
tokens por superficie). Nuestra fragmentación de tintas es el equivalente del
`btn-primary` azul heredado de ellos: capas históricas sin retirar.

---

## 2. Componentización y atomic design

**Incredible (medido).** Un kit por superficie con variantes cva: botón
(solid/ghost/danger/icon en 2 tamaños), badge (6 tonos), keycap (sm/lg),
switch (md/sm), select, menú, tarjeta elevada / action card / glow card. La
isla (`ov-*`, `ci-*`, `ovx-*`, `wf-*`) reusa la misma lógica con tinta oscura.
Su único fósil visible: `btn-primary` azul (8 apariciones, heredado).

**Companion.** 157 vistas en 114 archivos, planas (solo `Orb/` tiene carpeta).
Hay reuso real de primitivas — `AppButton` 33 usos, `SettingsRow` 21,
`SettingsPill` 18, `SettingsCard` 14, `AppField` 13 — pero conviven **dos kits
paralelos**: el "kit Incredible" (`Incredible*.swift`: IconButton, Badge,
Keycap, Switch, ActionCard) casi sin adoptar fuera de Ajustes (`IconButton`,
`Keycap`, `IncredibleSwitch`: 1 uso cada uno; `Badge` y `HoverChip`: 0), y las
piezas por familia que cada pantalla se fabrica. Duplicación contada:

- **Keycaps ×4**: `Keycap`, `SettingsKeycap`, `WelcomeKeycap` (con sombra a
  mano en vez de `.elevation`), `BrandKeycapView`.
- **Chips de cápsula ×2**: `IslandChipStyle` y `WelcomeChipStyle`, casi
  idénticos salvo tinta.
- **Botón cerrar "xmark" ×7**: 4 copias literales en ventana
  (`AppPanel:50`, `ConnectingSheet:63`, `OwnMCPSheet:130`,
  `TaskDetailSheet:51`) + 3 variantes en isla.
- **Botones de icono ×6 tipos**: IconButton, HoverIconButton, RoundIconButton,
  IslandHeaderIcon, IslandPopoverRow, OrbButton.
- **Onboarding ×2 flujos completos** (`OnboardingView` 373 líneas +
  `Welcome*`), ambos con campo de API key propio.

**Veredicto:** Incredible gana claro. Nuestro patrón bueno ya existe (enum de
métricas por componente + primitiva compartida); lo que falta es **adoptar el
kit en vez de fabricarlo por pantalla** y retirar los duplicados. Es trabajo de
consolidación, no de diseño.

---

## 3. Estados

**Arquitectura (ganamos).** `SessionModel` es el único objeto que muta la
proyección (regla de contrato `session-kind-write` lo hace incumplible desde
una vista); `SessionMachine` vive en Core puro y la isla deriva su estado con
`IslandState.from(...)` — funciones puras testeadas (SessionMachineTests,
TurnMachine*, HUDContractTests con libro de 11 puertas que falla si una puerta
cita un test inexistente). 15 `@Observable` por dominio, ningún ViewModel-dios
(el ChatViewModel de 777 líneas ya se partió en 7 extensiones). El `spine`
de Incredible (task_projection, work_ledger en jsonl) es el mismo patrón;
lo suyo no es inspeccionable más allá de nombres de módulo.

**Cobertura visual (gana Incredible).** Ellos: cada estado tiene superficie y
ningún estado tiene texto de estado (barras, brillo, tarjetas que se
auto-cierran, luz ámbar/verde). Nosotros ya tenemos el equivalente en la isla
(16f/16i/16m-2: transcripción viva/fija, carrete, runcard, checklist, barras
de agentes, luz, "no te oí" 6 s, aviso con salida) pero quedan huecos
medidos:

- `ChatViewModel.errorText` (persistencia y chat genérico:
  `ChatViewModel:171,228,239`, `Persistence:51`) **solo se pinta en
  `ThreadView`, que nadie instancia**. En Home y en la isla no se lee. Los
  fallos de turno sí persisten como línea de estado desde PR #18 — el hueco
  es la otra familia de errores.
- Estados de carga/vacío bien cubiertos en Apps (fases `.failed` con copy
  localizado) y Ajustes; `home.empty` existe.

**Pendiente de catálogo (16m-3..7):** adjuntos en isla (tarjetas 84×102, pila
de capturas, drop zone), dictado como tarjeta, contenedor visual
(gráfica/Mermaid), answer-card con rejilla de avisos (límite, actualización,
consentimiento, sesión, diagnóstico), menciones y comentarios.

---

## 4. Motion

**Companion.** Centralizado y **presupuestado**: `MotionTime` (6 tiempos),
`MotionCurve` (standard/settle/glide/bounce — las mismas 4 curvas medidas de
Incredible), 9 muelles nombrados con overshoot/settle calculados,
`IslandMotionBudget` por movimiento (duración, blur, offset y variante
reducida), coreografía de isla en fases con `steps()` puro, y
`MotionBudgetTests` que verifica las reglas M1-M8. Solo 3 curvas literales en
todo el árbol (2 son `MotionTime × k`, 1 en baseline); `easeIn/easeOut`: 0,
bloqueado por regla. reduceMotion: 93 referencias en 18 archivos.

**Incredible.** 4 curvas nombradas y morphs finos observados (isla 0.26 s,
settle 0.2 s, halo que sigue al cursor 0.9 s). No medible si tienen
presupuesto o tests.

**Huecos nuestros:** `CompanionRootView` (13 `withAnimation`), `SettingsView`
(4), `Dropdown` y `MainSidebar` animan sin leer `accessibilityReduceMotion`
(muelles suaves, pero los paneles se desplazan). El halo de `ActionCard` que
sigue al cursor existe en el kit y casi no se usa (1 instancia).

**Veredicto:** ganamos en sistema; nos falta cerrar los 4 archivos sin
reduceMotion.

---

## 5. UX y flujos

**Bienvenida.** La nuestra (15e/16c: 7 pantallas — portada, hola con voz,
claves verificadas en vivo, permisos en una pantalla de 4 filas con estado,
tecla, micrófono con nivel en vivo, "tu turno" que no termina sin un hold
real) adoptó deliberadamente el esqueleto del stepper de Incredible. Lo que
ellos tienen y nosotros no (decisión, no descuido): el tour ilustrado que toma
la pantalla, la investigación de tu empresa mientras esperas, y el PDF de
despedida. Lo que nosotros tenemos y ellos no: las claves son del usuario y se
verifican de frente (ellos ocultan la IA en su servidor — opción que no
existe para un producto sin backend).

**La isla como app.** Paridad estructural lograda (15g/16i/16m-1/2): campo con
orb y clip en hover, tarjetas de resultado con "Ver →", popup rico ovx
completo (tablas, callouts, código con copiar/plegar, tareas, chips, stats y
gráficas Swift Charts), estados de trabajo, menú, luz ámbar/verde, errores con
frase y salida. Diferencias que quedan: su clip adjunta en la isla (nuestro
16m-3), su historial apilado en el panel es más profundo, y el modo pasivo a
los 10 min es producto suyo (nuestro rollover de 5 min es equivalente parcial).

**Aprobaciones.** Nuestra hoja muestra el comando completo, auto-deny 60 s,
"Permitir" sin atajo de teclado (hallazgo de seguridad propio: Return no
aprueba sin leer). Su `action-gate` puntúa riesgo por acción (leer no
pregunta, crear confirma, borrar exige aprobación) — la nuestra es equivalente
por política de tools, no por puntuación.

**Tono.** El gap del asistente técnico se cerró en PR #22 (grounding:
términos de la usuaria, efecto siempre, mecanismo opcional). Queda 16h
(implementación de conversación) firmada y sin arrancar.

---

## 6. Tipografía y estilo visual

Paridad decidida y aplicada (16k-2/16n): **SF Pro en ventana, Geist variable
en isla y bienvenida** — exactamente su reparto. Radios y medidas de
componentes pinneados a los valores medidos (`IncredibleComponentsTests`,
`IncredibleWindowTests`, `AnswerPopupRichTests`, `Island16m2Tests`). Cuando el
CSS y la captura difieren, gana la captura (regla establecida en 16n).

Donde ellos siguen delante: **interlineado por escalón** (10 pasos, 1.06-1.5)
contra nuestros 2 con nombre (`bodyLead`, `codeLead`) + los del popup ovx;
su escala de 10 tamaños con papel nombrado contra nuestros 5 + micro-pasos.
Donde nosotros: escala del usuario (ellos: ninguna), tema claro/oscuro
completo por roles semánticos (su isla es solo oscura, su ventana solo clara
en lo observado).

---

## 7. Accesibilidad e i18n

**A11y (no comparable con ellos; lo nuestro, medido):** 53
`accessibilityLabel` en 28 archivos, 27 hidden, contraste AA testeado.
Huecos contados: **11 `onTapGesture` sin semántica de botón**
(`IslandView:442` abrir resultado, `MapCard:30`, Root ×4, Settings ×2,
AppsPage ×2), `accessibilityHint/Value/Identifier` y rotores: 0,
`keyboardShortcut` solo en ApprovalSheet. Los labels en español fijo están
todos en código muerto.

**i18n (ganamos con claridad):** 551 claves × 2 idiomas con paridad exacta de
claves, lookup por sub-bundle del idioma elegido (no el del sistema), seam
task-local para tests. Incredible en lo observado es solo inglés. Fugas
nuestras fuera del catálogo (el gate no ve switches): labels de `Highlight`
(`TokensChoices:15-22`), 5/7 de `ShortcutAction` (`Shortcuts:16-22`),
"Claro/Oscuro/Sistema" (`UserPreferences:88-90`), "Opening/Abriendo"
(`IslandAnswerPieces:102-103`).

---

## 8. Higiene y testabilidad

**Muerto de hecho (~1 200+ líneas, 0 instancias):** `HeaderView` (212),
`ControlBar` (158), `ThreadView` (235, solo se usa su helper estático),
`ChatInputView`, `StatusLine`, `AttachmentStrip`, `Badge`, `PermissionRow`
(vista), `ShortcutCaptureField`, y huérfanos por arrastre (`JobCardView`,
`TypewriterView`, `MascotView`, `MessageAttachments`). Borrar es decisión de
Karen (anotado desde 16n); mientras vivan, inflan el baseline de conformance
(19 de las 43 infracciones están en muertos) y los conteos de a11y/i18n.
**>400 líneas:** `IslandView` 759 (a 41 del tope duro), `AppsModel` 536,
`AppsPage` 469, `UserPreferences` 454.

**Tests:** 81 archivos de test importan la UI; pins de métricas por familia,
máquina y contratos (HUD gates, conformance ratchet), 512 tests en verde.
Huecos: vistas de ventana principal sin ningún test que las nombre
(`HomePage`, `AppsPage` vista, `AppPanel`, `MainSidebar`, Root;
`MainWindowMetrics`/`AppsMetrics`/`AppPanelMetrics` sin pin), snapshots
opt-in **sin baseline** (documentan, no validan), cero test interactivo
(decisión: la lógica vive en enums puros y eso es lo que se prueba).

---

## 9. Plan accionable (orden propuesto)

**Quick wins (una sesión, sin spec por tamaño):**
1. Pintar `chat.errorText` donde se ve (isla o Home): hoy muere en una vista
   muerta.
2. reduceMotion en Root, Settings, Dropdown, MainSidebar (4 archivos).
3. Localizar las 4 fugas de i18n fuera de catálogo.
4. `accessibilityAction`/trait de botón en los 11 `onTapGesture` (el patrón ya
   existe en `AppsPage:374`).

**Consolidación (spec corta, tipo 16p):**
5. Un solo keycap, un solo chip, un solo botón-cerrar, adoptar
   `IconButton`/`Badge` del kit o retirarlos; retirar `OnboardingView` (con OK
   de Karen) y el muerto de §8 — baja ~19 infracciones del baseline y
   ~1 200 líneas.
6. Fundir las paletas de tinta no-isla en `Semantic` o documentarlas como la
   de la isla.
7. Partir `IslandView` (759) antes de que 16m-3..7 lo crucen del tope.

**Catálogo (ya especificado, 16m-3..7 + 16h):** adjuntos en isla, dictado,
visual/Mermaid, avisos con rejilla, menciones; conversación 16h. Es la mitad
de la brecha de producto restante.

**Deuda de sistema (cuando toque):** pin de métricas de ventana principal,
snapshots con baseline comparable, interlineado por escalón en `TypeScale`.
