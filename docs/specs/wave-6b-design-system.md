# Wave 6b — Design systems engineering

**Estado: EN CURSO** — pieza 1 (fundaciones) despachada 2026-08-21.
Ejecucion por piezas: ver "Ordenes W5-1 a W5-5" al final. — 2026-08-21. 6a y 6c cerradas. Pieza 1: fundaciones.

## Principio rector (decision de producto, 2026-08-21)

La UI es central y se trabaja con disciplina de design systems engineering.
**La simplificacion solo es valida donde no haya perdida visual**: la paridad
con el prototipo es el piso, no el techo. Donde el rebuild simplifico
sacrificando craft (dropdowns del sistema, bloques de codigo sin resaltar,
orb plano), esta wave lo revierte. Cero dependencias externas.

## Objetivo

Elevar el sistema de diseno a la altura del prototipo y por encima:
fundaciones completas, componentes con estados, motion coreografiado, y
documentacion viva. **El veredicto visual de Karen ES el criterio de done.**

## Correcciones de kickoff

- El tokenizador de `Syntax.swift` del prototipo **no tiene tests**. Se
  porta el diseno; los tests se escriben nuevos (no hay caracterizacion).
- La rampa tipografica YA lee `AppTypeface.stored`. Lo que falta: no existe
  `Assets/` en el rebuild, `Fonts.register()` no lo llama nadie, `bundle.sh`
  no copia fuentes. Hoy `Font.custom("Hypodermic-Regular")` cae al sistema.
- Elevacion ya tokenizada a medias (`elevationChip/Panel/Sheet`). La deuda
  real: **dos sistemas de tokens** — shim `Tokens.*` (ThreadView, Markdown,
  cards) contra `Semantic/Space/Radius` (Settings). El ledger lo prohibe.
  `Tokens.swift` termina en un doc-comment colgante.
- El orb del prototipo es de Siddhant Mehta (`metasidd/Orb`, MIT). NOTICE.md
  hoy dice "no third-party code": atribuir y matizar.
- Blur del dropdown: **nativo** (`.blur` + scale). No vendorar Pow. Mantiene
  cero dependencias.
- **Assets (Karen 2026-08-21):** Inter se empaqueta con su texto OFL (SIL).
  Gadey, Hypodermic y TBJ Interval son All Rights Reserved — solo local; el
  repo publico degrada Inter → sistema. WAVs: sintesis, no se copian.
- `staggered(_:step:)` ya existe en `Motion.swift` y respeta reduce-motion:
  usarlo, no reinventarlo.

## Alcance

Secuencia: 6b-1 (tokens, tres slices) bloquea el resto. 6b-3/4/5/6 en
paralelo tras 6b-1. 6b-2 (Dropdown) bloquea 6c-2. 6b-7 bloqueado por assets.
6b-8 al final. `SettingsView.swift` lo tocan varias slices: serializar.

### 1. Fundaciones (Tokens) — 6b-1a/b/c

| Pieza | Contenido |
|---|---|
| Elevacion | Escala `rest/hover/panel/sheet/popover` + radios y strokes nombrados. Test: escala monotona |
| Migracion | ThreadView, MarkdownView, cards, ApprovalSheet → `Semantic/Space/Radius` |
| Un solo sistema | Borrar shim `Tokens.*` y el `enum Tokens` vacio; limpiar doc-comment colgante |
| Gate | Literales de `padding/spacing/cornerRadius` en CompanionUI fallan el build; valvula `// token-exempt:` |

```swift
public enum Elevation: Sendable, CaseIterable, Comparable {
    case rest, hover, panel, sheet, popover
}
```

### 2. Componentes con estados

| Componente | Contenido |
|---|---|
| `Dropdown` propio | Panel anclado con motion nativo, hover, check del activo. Reemplaza `Menu` en SettingsItem. Revierte la simplificacion de 5a |
| Botones | Primaria/secundaria/destructiva/ghost con 4 estados + focus ring |
| Campos | TextField estilizado con estados y mensaje de error (fuera `.roundedBorder`) |
| `Shimmer` / `Halftone` / iconografia | Craft del prototipo, SwiftUI puro |

```swift
public enum ControlState: Sendable, CaseIterable {
    case normal, hover, pressed, disabled, focused
}
```

Contraste AA: calcular ratios sobre los `Swatch` (hex) puros, no sobre
`NSColor` dinamico resuelto — mas estable bajo `swift test`.

### 3. Resaltado de sintaxis

Tokenizador en **Core** (puro, testeable sin vistas). Paleta +
`AttributedString` en UI, temas claro y oscuro.

```swift
public enum SyntaxTokenizer: Sendable {
    public static func tokenize(_ source: String, language: String) -> [SyntaxToken]
}
```

Casos TDD: entrada vacia, lenguaje desconocido → todo `.text`, UTF-8
invalido, comentario/string sin cerrar, `3.14` es un solo `.number`.

### 4. Orb a nivel de producto

ADR 003 intacto: SwiftUI, cero Rive. Partir `Orb.swift` / `OrbLayers.swift`
antes del warn de 400 lineas. Decisiones nuevas = funciones puras en
`OrbAppearance` (patron que ya funciona):

```swift
extension OrbAppearance {
    nonisolated public static func glowOpacity(for state: TurnState) -> Double
    nonisolated public static func particleCount(for state: TurnState, reduceMotion: Bool) -> Int
    nonisolated public static func pressScale(_ pressed: Bool) -> Double
}
```

Atribuir `metasidd/Orb` (MIT) en NOTICE.md.

### 5. Motion coreografiado

Usar `staggered` existente en mensajes y tarjetas; transiciones de hoja y
popover; microinteracciones. Todo respeta reduce-motion.

### 6. Documentacion viva

`docs/design-system.md`: fundaciones, componentes con estados y donde se
usan. Regla en CONTRIBUTING: un componente nuevo entra con su seccion.

### 7. Tipografia empaquetada

Inter (OFL) entra al bundle con su licencia. Las propietarias se cargan si
estan en disco; si no, Inter → sistema. `Fonts.register()` al arrancar.
Verificar nombres PostScript. WAVs no se copian (sintesis, 6a-5b).

Tocar `bundle.sh`, `gates.sh` o anadir binarios a `Assets/` requiere OK
explicito.

## Tests

Decisiones puras: mapeo estado→color, ratios AA sobre Swatch, tokenizador
(casos de arriba), escala de elevacion ordenada, apariencia del orb por
estado (ampliar `OrbAppearanceTests`). Las vistas no se instancian: la
revision visual de Karen es la prueba.

## Definicion de done

Ajustes y onboarding sin un solo control del sistema sin estilo propio;
bloques de codigo resaltados en ambos temas; orb con la riqueza del
prototipo; un solo sistema de tokens (shim borrado); gate de spacing en
verde; `docs/design-system.md` al dia; veredicto visual de Karen.

## Riesgos

- Craft sin fin: alcance = paridad con el prototipo + los estados que le
  faltaban. Nada extra salvo lo listado.
- Gate de spacing: acotar a `padding/spacing/cornerRadius`.
- Fuentes: 6b-7 no arranca sin respuesta de Karen.

## Desviaciones respecto al borrador original

1. Tests de Syntax se escriben, no se portan.
2. Item de tipografia reescrito: el problema es registro/bundle, no la rampa.
3. Deuda de tokens = dos sistemas conviviendo, no falta de elevacion.
4. Dropdown blur nativo, no Pow.
5. Tokenizador en Core, paleta en UI.
6. NOTICE atribuye el orb.

---

# Ordenes W5-1 a W5-5 (ejecutables por agentes)

Cada orden = un prompt. Se dan EN ORDEN: todas tocan `Sources/CompanionUI/`
y pisarse seria peor que ir en serie. Entre orden y orden: verificar los
greps del reporte, gates verdes, commit scoped, push.

## Estado medido antes de empezar (2026-08-21)

| Aspecto | Hoy | Objetivo |
|---|---|---|
| Controles del sistema sin estilo | 12 | 0 en Ajustes y onboarding |
| Dropdown propio | no existe (5a lo simplifico) | de vuelta, con motion |
| Resaltado de sintaxis | no existe | portado, dos temas |
| Tipografias | ni carpeta Assets | Inter empaquetada + locales |
| Elevacion | 1 sombra suelta | escala tokenizada claro/oscuro |
| Orb | 161 lineas planas | cuatro capas del prototipo |
| Paddings magicos | 0 | 0, con gate que lo garantice |

## Deuda de criterio que estas ordenes revierten

En el kickoff de 5a se acepto cambiar el selector propio del prototipo por
`Menu` del sistema "para avanzar". Fue exactamente la simplificacion con
perdida visual que el principio rector prohibe. W5-2 la revierte; queda
anotado para que no se repita el patron de cambiar craft por velocidad.

## W5-1 — Fundaciones (EN CURSO)

Tipografia empaquetada y registrada al arrancar (Inter con su OFL; las
propietarias solo si estan instaladas, con degradacion), elevacion/radios/
strokes tokenizados con variante oscura, estados derivados de los roles,
contraste AA verificado por test que FALLA bajo 4.5:1, y gate de spacing.

## W5-2 — Componentes con craft

Referencias: prototipo `Sources/{Dropdown,Shimmer,Halftone,Icons}.swift`.

- **Dropdown propio**: panel anclado con motion de entrada/salida, hover
  states, check en el activo, cierre por click fuera y por Escape,
  navegacion con flechas. Reemplaza `SettingsItem` en TODOS sus usos
  (apariencia, voz, ejecutor).
- **Botones**: jerarquia primaria / secundaria / destructiva / ghost, con
  los cuatro estados de W5-1 y focus ring visible (accesibilidad por
  teclado).
- **Campos de texto**: estilo propio con estados y error integrado; hoy
  onboarding y ajustes usan `.roundedBorder` del sistema.
- **Toggles y sliders**: envoltura propia consistente con lo anterior (o
  restyle del nativo si se ve igual de bien — criterio: que no desentonen).
- **Shimmer**: brillo sobre el texto de estado mientras piensa.
- **Halftone**: la textura de identidad donde aporte (onboarding, fondo de
  tarjeta), sutil, sin robar protagonismo.
- **Iconografia**: SF Symbols con pesos y escalas tokenizados.

Tests: lo puro (estado -> variante, decision de cierre del dropdown,
navegacion por teclado). Las vistas no se instancian.

## W5-3 — Resaltado de sintaxis

Portar `../companion/Sources/Syntax.swift`: tokenizador propio por familia de
lenguaje (Swift, Python, JS, JSON, shell, markdown), SIN dependencias, a
**Core** (puro y testeable). La paleta y el `AttributedString` quedan en UI,
con colores desde los roles semanticos y ambos temas. Los tests del
prototipo (`testSyntax*` si existen) se portan como caracterizacion; si no,
escribir casos por familia: keywords, strings con escapes, comentarios de
linea y bloque, numeros, y texto sin lenguaje conocido (degrada a plano).
Cablear en `MarkdownView` donde hoy el bloque de codigo va gris.

## W5-4 — Orb rico

Portar el enfoque de `../companion/Sources/vendor/` (MIT, atribuir en
NOTICE.md; es SwiftUI puro — el ADR 003 se mantiene, nada de Rive):
capas de blob ondulante, glow rotatorio, particulas y sombra realista,
moduladas por el estado y los niveles que `OrbAppearance` ya decide. Anadir
microrespuesta al press con el spring del sistema de motion. Mantener el
respeto a reduce-motion y ampliar `OrbAppearanceTests` con las capas nuevas.
Cuidar el coste: el orb no puede costar frames en una ventana con el hilo
corriendo.

## W5-5 — Motion coreografiado + documentacion viva

- Stagger en la aparicion de mensajes y tarjetas; transicion de la hoja de
  ajustes y de los popovers; microinteracciones de boton (press/release).
  Todo con las duraciones de `Motion.swift`, respetando reduce-motion.
- `docs/design-system.md`: fundaciones (color, tipografia, espaciado,
  elevacion, motion) y catalogo de componentes con sus estados y donde se
  usan. Regla en CONTRIBUTING: componente nuevo entra con su seccion.

## Cierre de W5

Gates verdes + CHANGELOG + spec 6b CERRADA + ROADMAP. Y entonces la unica
prueba que importa aqui: **Karen abre la app y da su veredicto visual**. Si
algo no esta al nivel, se anota y se itera — el criterio es su ojo, no los
tests.
