# Wave 6b — Ordenes restantes (W5-2 a W5-5)

**Estado: listo para ejecucion.** W5-1 (fundaciones) esta CERRADA en
`9fc56fd`. No la rehagas. Cada orden de aqui es un prompt autocontenido:
reglas compartidas + UNA orden, espera el reporte, corre los greps de
"Verificacion" antes de dar la siguiente.

Las cuatro van EN SERIE. Comparten `Sources/CompanionUI/` (sobre todo
Settings, MarkdownView, Orb, ThreadView). Paralelizarlas se pisan.

Criterio de done de W5: el veredicto VISUAL de Karen con la app abierta.
Ningun reporte de agente lo sustituye.

## Reglas que TODO agente recibe (copiar en cada prompt)

- Proyecto: Swift 6 strict concurrency. Tests con Swift Testing
  (`swift test`), helpers `expect`/`expectEq` de TestKit, suites
  `@Test @MainActor func xxxTests()`. TDD estricto: test primero, verifica
  ROJO, implementacion minima, VERDE, con evidencia en el reporte.
- Sin `try?` en Core/Services; sin print (usar `Log`); archivos ≤400 lineas
  (si crece, archivo nuevo); comentarios WHY en ingles; sin emojis en codigo
  ni en UI. Core no importa nada de Apple salvo Foundation.
- Tests: JAMAS audio real, jamas red viva, jamas dormir tiempos reales
  largos ni bloquear el main actor (suite < 3 s). No instanciar SwiftUI
  Views en tests: lo puro se prueba; el ojo de Karen cubre lo visual.
- GIT: hay VARIAS sesiones en el mismo arbol. Commit por pieza cerrada con
  `git add` de archivos EXPLICITOS — `git add -A` esta PROHIBIDO. Antes de
  empezar: `git pull`. No toques archivos fuera de tu orden.
- ANTES DE REPORTAR "terminado": grep de que el flujo real invoca cada
  capacidad nueva. Si difieres del alcance, dilo con todas sus letras.
- Lectura obligatoria: `docs/ARCHITECTURE.md`. Prototipo `../companion` es
  SOLO LECTURA: se porta comportamiento, no se copia estilo ni se vendoran
  Pow ni Rive.
- Un solo sistema de tokens (`Semantic` / `Space` / `Radius` / `Stroke` /
  `Elevation`). El shim `Tokens.*` ya no existe. El gate de spacing esta
  activo: literales de `padding`/`spacing`/`cornerRadius(` fallan el build.
  Valvula `// token-exempt:` con WHY.
- Simplificar un control propio por uno del sistema para "avanzar" esta
  prohibido. Fue el error de 5a con el dropdown. Esta wave lo revierte.

## Lo que W5-1 ya dejo (no repetir)

- Inter Regular + `OFL.txt` en `Sources/CompanionUI/Fonts/`.
  `Fonts.register()` al arrancar; propietarias desde `~/Library/Fonts` o
  Application Support; si faltan, Inter y luego el sistema (`FontFallback`).
- `Elevation` rest < hover < panel < sheet < popover.
- Contraste AA sobre hex de `Swatch` (`Contrast` en Core).
- Shim `Tokens.*` borrado. Gate de spacing en `scripts/gates.sh`.
- `Semantic.hover` / `Semantic.pressed` existen. **No** existe todavia
  `ControlState` ni focus ring ni campos/botones propios: eso es W5-2.

## Deuda de criterio (5a)

En el kickoff de 5a se acepto cambiar el selector propio del prototipo por
`Menu` de SwiftUI "para avanzar". Es exactamente la simplificacion con
perdida visual que el principio rector de 6b prohibe. W5-2 la revierte.
No es una mejora: es devolver lo que se quito.

---

## W5-2 — Componentes (revierte 5a)

Referencias: prototipo `../companion/Sources/{Dropdown,Shimmer,Halftone}.swift`
y `ActionButton` en `Tokens.swift`. Blur nativo (`.blur` + scale) — no Pow
(decision de kickoff).

Alcance:
1. `ControlState`: `normal, hover, pressed, disabled, focused`. Mapeo puro
   a color/opacidad/stroke desde `Semantic` + `Elevation`. Test del mapeo
   y de que focused tiene anillo visible (token, no magia).
2. `Dropdown` propio: panel anclado al disparador (portal por
   `anchorPreference`, como el prototipo: un overlay dentro de ScrollView
   se recorta). Motion de entrada/salida nativa. Hover en filas, check en
   el activo, cierre por click fuera y Escape, flechas + Return.
   **Reemplaza `Menu` en `SettingsItem`**. Todos los usos actuales
   (apariencia, tipografia, voz, fin de turno, eagerness, ejecutor) deben
   abrir este panel. No dejes un `Menu {` en Settings.
3. Botones `AppButton` (nombre libre, uno): primaria / secundaria /
   destructiva / ghost, los cinco `ControlState`, focus ring. Cablear
   onboarding (CTA), ApprovalSheet (Permitir / No permitir), y el Enviar
   del hilo. No hace falta rediseñar el boton del engranaje.
4. Campos: dejar `.roundedBorder`. Estilo propio con estados y mensaje de
   error debajo. Cablear onboarding (clave), Ajustes (nombre) y el campo
   de tono en VOZ.
5. Toggle y slider: restyle para que no desentonen. Si el nativo con
   tint de `Semantic.accent` se ve al nivel, anotalo; no inventes un
   control peor. Criterio: Ajustes no debe leerse como Preferences.app.
6. `Shimmer`: brillo sobre texto de estado / orb ring mientras
   thinking/connecting. Reloj inyectable en tests del ciclo; sin
   `Task.sleep` real.
7. `HalftoneOverlay`: textura sutil (opacidad ~0.035 como el prototipo)
   en onboarding y, si no pelea, fondo de Ajustes. Canvas, sin blend
   modes raros.

Tests: mapeo `ControlState` → tokens; cierre del dropdown (fuera / Escape
/ elegir); navegacion por indice de flechas (puro, sin View);
Shimmer avanza con reloj fake.

Verificacion (grep en el reporte):
- `Menu {` en `Sources/CompanionUI` = ninguno en Settings*.
- `SettingsItem` construye `Dropdown`, no `Menu`.
- `.roundedBorder` = ninguno en Onboarding/Settings.
- Shimmer se aplica en un camino real (estado thinking o texto de
  status), no solo en Preview.
- CompanionUI sigue sin `import AVFoundation`.

Fuera: ThreadView chrome ("Nueva conversacion") puede quedar texto plano;
W5-5 lo anima. No toques Orb.swift (W5-4) ni MarkdownView fences (W5-3).

---

## W5-3 — Resaltado de sintaxis

Referencias: prototipo `../companion/Sources/Syntax.swift` (el diseno; no
hay tests alla — se escriben aqui, correccion de kickoff). Tokenizador en
**Core**. Paleta + `AttributedString` en UI.

Alcance:
1. Core `SyntaxTokenizer.tokenize(_:language:) -> [SyntaxToken]` con
   `Kind`: text, keyword, string, comment, number, typeName, attr.
   Familias: Swift, Python, JS/TS, JSON, shell, markdown. Lenguaje
   desconocido o vacio → un solo token `.text` (o todo `.text` por
   caracter, pero el test pide degradacion a plano: un token o todos
   `.text` sin kinds de keyword).
2. Casos TDD obligatorios: entrada vacia; lenguaje desconocido → plano;
   comentario/string sin cerrar no cuelga y pinta el resto como comment/
   string; `3.14` es UN `.number`; keywords de la familia; escapes en
   string (`\"` no cierra).
3. UI: paleta claro/oscuro desde roles (no hex sueltos).
   `SyntaxHighlighter.attributed(_:language:)` arma el `AttributedString`.
4. Cablear `MarkdownView.codeBlock`: el fence usa highlighter +
   `Font.uiCode`. `RoundedRectangle(cornerRadius: 8)` pasa a `Radius.md`
   (el gate actual no caza el label `cornerRadius:`; no lo dejes).

Tests en CompanionTests, sin vistas.

Verificacion:
- `MarkdownView` llama al highlighter en `codeBlock`.
- Core no importa SwiftUI.
- Familias cubiertas: grep de `swift`/`python`/`json` en el tokenizador.

Fuera: no resaltes prose ni headings. No toques Settings ni Orb.

---

## W5-4 — Orb rico

Referencias: prototipo `../companion/Sources/vendor/{OrbView,WavyBlobView,
RotatingGlowView,ParticlesView,RealisticShadows,OrbConfiguration}.swift`
(metasidd/Orb, MIT). ADR 003 intacto: SwiftUI, cero Rive.

Alcance:
1. Atribuir en `NOTICE.md` (hoy Inter OFL ya esta; anadir el orb MIT y
  matizar "no third-party code").
2. Funciones puras nuevas en `OrbAppearance` (el patron que ya funciona):
   `glowOpacity(for:)`, `particleCount(for:reduceMotion:)`,
   `pressScale(_:)`. Tests ampliando `OrbAppearanceTests`.
3. Capas: blob ondulante, glow rotatorio, particulas, sombra. Moduladas
   por estado + `VoiceLevels`. Reduce-motion: capas que se mueven se
   apagan o pasan a estatico (ya hay helpers; no los rompas).
4. Microrespuesta al press con spring de `Motion.swift`.
5. Partir `Orb.swift` si pasa de 400 (p.ej. `OrbLayers.swift`).
6. Coste: nada de timers a 120 Hz ni blur apilados caros. El hilo de
   chat tiene que seguir fluido.

Verificacion:
- NOTICE menciona metasidd/Orb y MIT.
- `Orb.swift` (o layers) llama `glowOpacity` / `particleCount`.
- `OrbAppearanceTests` cubre las tres funciones nuevas.
- `VoiceSession.swift` no se toca.

Fuera: no cambies el contrato `Orb(state:levels:accentColor:)`. No toques
Settings.

---

## W5-5 — Motion coreografiado + doc viva

Referencias: `Sources/CompanionUI/Motion.swift` (`staggered` YA existe y
respeta reduce-motion; hoy nadie lo llama).

Alcance:
1. Stagger en aparicion de mensajes del hilo y de tarjetas
   (Map/Gallery/Sources). `staggered(index)`.
2. Transicion de la hoja de Ajustes y del panel del Dropdown (si W5-2
   dejo un hueco). Microinteraccion press/release en `AppButton`.
3. Todo con `MotionTime` / springs existentes. Reduce-motion: sin
   stagger ni scale de entrada.
4. `docs/design-system.md`: fundaciones (color, tipo, espacio, elevacion,
   motion) y catalogo de componentes con estados y **donde se usan**.
5. `CONTRIBUTING.md`: un componente nuevo entra con su seccion en
   `design-system.md`.

Tests: helper puro "stagger delay(index, reduceMotion) -> TimeInterval"
si no esta ya testeado. No instanciar la lista.

Verificacion:
- `staggered(` aparece en ThreadView o en las cards, no solo en Motion.swift.
- Existe `docs/design-system.md` y CONTRIBUTING lo menciona.
- Reduce-motion: grep de `accessibilityReduceMotion` en las vistas nuevas.

Fuera: no anadas duraciones magicas. No reabras el dropdown ni el orb.

---

## Cierre de cada orden

Gates verdes + commit scoped + push + CHANGELOG si es visible. Al cerrar
W5-5: marcar `docs/specs/wave-6b-design-system.md` CERRADO, ROADMAP, y
parar. Entonces Karen abre la app: su veredicto visual es el done. Si
algo no llega, se anota y se itera.
