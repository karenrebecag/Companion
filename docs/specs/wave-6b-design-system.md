# Wave 6b — Design systems engineering

**Estado: CERRADA** — 2026-08-21. Fundaciones, componentes propios,
sintaxis, orb por capas y documentacion viva. Falta solo el veredicto visual
de Karen con la app abierta. W5-1..4 entregaron tokens, dropdown de
Ajustes, syntax y un orb Canvas que **no** es paridad. W5-5 congelado.
Port fiel por componente: `docs/specs/ds/README.md`.

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
  **Abierto (W5-3).**
- Tipografia: **resuelto en W5-1.** `Fonts.register()` al arrancar; Inter
  empaquetada con OFL; propietarias solo si estan en disco.
- Dos sistemas de tokens: **resuelto en W5-1.** Shim `Tokens.*` borrado;
  gate de spacing activo. Queda `RoundedRectangle(cornerRadius: 8)` en
  `MarkdownView.codeBlock` (el gate no caza el label; W5-3 al tocar el fence).
- NOTICE.md y el orb: **abierto (W5-4).** Inter OFL ya esta; falta
  metasidd/Orb MIT.
- Blur del dropdown: **nativo** (`.blur` + scale). No vendorar Pow.
- `staggered(_:step:)` ya existe y respeta reduce-motion; **nadie lo llama
  todavia (W5-5).**
- Dropdown propio sustituido por `Menu` en 5a: **abierto (W5-2).** Es
  reversion, no mejora.

## Alcance

W5-1 hecha. W5-2 → W5-3 → W5-4 → W5-5 en ese orden, una pieza por agente.
Detalle ejecutable en `docs/specs/wave-6b-remaining.md`. El contrato de
API de cada pieza sigue abajo.

### 1. Fundaciones (Tokens) — CERRADO (W5-1)

Entregado: escala `Elevation`, migracion a `Semantic/Space/Radius`, shim
`Tokens.*` borrado, gate de spacing.

```swift
public enum Elevation: Sendable, CaseIterable, Comparable {
    case rest, hover, panel, sheet, popover
}
```

### 2. Componentes con estados

| Componente | Contenido |
|---|---|
| `Dropdown` propio | Panel anclado con motion nativo, hover, check del activo. Reemplaza `Menu` en SettingsItem. Revierte la simplificacion de 5a |
| Botones | Primaria/secundaria/destructiva/ghost con 5 `ControlState` + focus ring |
| Campos | TextField estilizado con estados y mensaje de error (fuera `.roundedBorder`) |
| `Shimmer` / `Halftone` / iconografia | Craft del prototipo, SwiftUI puro |

```swift
public enum ControlState: Sendable, CaseIterable {
    case normal, hover, pressed, disabled, focused
}
```

Contraste AA: **resuelto en W5-1** sobre hex de `Swatch`. W5-2 usa esos
roles para `ControlState`; no reabre la formula.

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

### 7. Tipografia empaquetada — CERRADO (W5-1)

Inter (OFL) en el bundle. Propietarias solo local. `Fonts.register()` al
arrancar. WAVs no se copian. No reabrir `bundle.sh` ni meter binarios de
fuentes propietarias.

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
- Fuentes: W5-1 cerrado. Propietarias siguen fuera del repo.

## Desviaciones respecto al borrador original

1. Tests de Syntax se escriben, no se portan.
2. Item de tipografia reescrito: el problema era registro/bundle, no la rampa.
3. Deuda de tokens = dos sistemas conviviendo, no falta de elevacion.
4. Dropdown blur nativo, no Pow.
5. Tokenizador en Core, paleta en UI.
6. NOTICE atribuye el orb (W5-4) e Inter OFL (W5-1).
7. 6c-2 ya no espera al Dropdown: 6c cerro antes. El Dropdown sigue
   siendo reversion de 5a, no bloqueo de voz.

---

# Ordenes ejecutables

Viven en `docs/specs/wave-6b-remaining.md` (W5-2 a W5-5). No duplicar aqui:
este archivo es el contrato; aquel es el prompt.
