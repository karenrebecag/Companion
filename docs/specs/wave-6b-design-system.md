# Wave 6b — Design systems engineering

**Estado: BORRADOR** — kickoff 2026-08-21 (planner + architect). Pendiente de
aprobacion de Karen. Depende de 6a cerrada.

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

### 7. Tipografia empaquetada (bloqueada por assets)

Si Karen autoriza las fuentes: `bundle.sh` las copia a Resources/Fonts,
`main.swift` llama `Fonts.register()` al arrancar. Verificar nombres
PostScript (`Hypodermic.otf` vs `"Hypodermic-Regular"`). Si alguna no tiene
licencia clara para repo publico: documentar y dejar solo local, fallback a
system (ya existe).

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
