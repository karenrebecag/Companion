# Design system — port fiel (atomico)

**Estado: BORRADOR.** Karen aprueba UN spec y se construye ese. El siguiente
no arranca sin OK. Criterio de done de cada pieza: su ojo con las dos
apps abiertas, no los tests.

W5-5 (stagger + `docs/design-system.md`) queda **congelado**. No cierra la
foto. Este programa la cierra, componente a componente, contra
`../companion`.

## Por que atomico, y por que este orden

Las piezas W5-2..4 fueron moleculas sin chasis: un dropdown en Ajustes, un
orb Canvas, syntax. El prototipo se reconoce por la **ventana**, el
**header**, el **orb de metasidd** y la **barra de control**. Los atomos
salen justo antes del organismo que los necesita, no como un catalogo
invisible.

Simplificar un control propio por uno del sistema esta prohibido. SpriteKit
en UI esta permitido (el prototipo lo usa en particulas). Rive no (ADR 003).
Pow no: blur nativo. Fuentes propietarias siguen solo-local.

1 grid del prototipo = `Space.x1` (4 pt).

## Errores del prototipo: no se copian

El original no es la fuente de bugs; es la fuente de **cicatrices** — el
arreglo que ya pagaron. Cada spec, antes de codear, lista:

1. Que se porta (craft, composicion, el arreglo).
2. Que se deja fuera (bug, atajo, Hermes/.env, Rive, Pow).
3. Que se reescribe a este repo (async/await, tokens `Space`/`Semantic`,
   sin `Tokens.*` ni literales).

Si un comentario del prototipo dice "sin esto X se rompe", se porta el
arreglo, no el estado anterior. Si el prototipo mezcla `.grid` suelto con
tokens, aqui solo tokens. Si compara `Color == .bg2` y el comentario dice
que mentia, se usa el flag `bordered` que ya inventaron.

No hay "paridad con el defecto". Hay paridad visual con el producto que
quisieron, en el patron de este repo.

Cicatrices de front ya identificadas (van al spec que las toca):

| Cicatriz | Donde | Que hacemos |
|---|---|---|
| SwiftUI infla la ventana | ConversationWindow `sizingOptions = []` | Portar el arreglo (DS-01) |
| Titlebar come el logo | `fullSizeContentView` + hidden | Portar el arreglo (DS-01) |
| Esc mata el turno al cerrar un menu | cascada confirm → sheet → menu → stop | Portar el arreglo (DS-05/12) |
| Overlay de dropdown recortado por ScrollView | portal en la raiz | Portar el arreglo (DS-04) |
| `background == .bg2` miente | `bordered:` explicito | Portar el arreglo (DS-08) |
| Rojo de sistema en dark es claro | `destructive` + `onDestructive` | Portar el arreglo (DS-08) |
| Rive en idle | ADR 003 | No se porta (DS-09) |
| Pow para blur | 6b | Blur nativo, mismo gesto (todos) |
| Ajustes leen `~/.hermes` | ADR 001 | No se porta (DS-12) |
| Menu nativo no se anima | Dropdown propio | Ya es el principio rector |

Hallazgo nuevo en un spec → se anota ahi, se re-aprueba esa linea, no se
calla "para avanzar". Sin las tres listas el spec sigue BORRADOR: no se
codea.


## Secuencia

| # | Spec | Capa | Que cambia en la foto |
|---|---|---|---|
| 01 | [Ventana](01-window.md) | template | Proporcion, titlebar, fondo |
| 02 | [Press / hover](02-press-hover.md) | atomo | Clic y hover de toda la UI |
| 03 | [IconGlyph](03-icons.md) | atomo | Trazo fino de la casa |
| 04 | [Dropdown](04-dropdown.md) | molecula | Panel del header, no solo Ajustes |
| 05 | [Header](05-header.md) | organismo | Logo, choice, modo, historial, gear |
| 06 | [OrbView](06-orb.md) | organismo | Identidad visual de voz |
| 07 | [ShimmerRing](07-shimmer-ring.md) | atomo | Anillo del orb |
| 08 | [ControlBar](08-control-bar.md) | organismo | Orb + mute rojo + colgar |
| 09 | [Chat](09-chat.md) | organismo | Idle, lista invertida, burbujas |
| 10 | [Composer](10-composer.md) | molecula | Input de texto; modo voz lo oculta |
| 11 | [Status y adjuntos](11-status-attach.md) | molecula | Linea de estado, tira, drop |
| 12 | [Ajustes overlay](12-settings-overlay.md) | organismo | Sheet propia, no `.sheet` de macOS |

## Como se despacha

1. Kickoff: el spec lista **Portar / Fuera / Reescribir**. Sin esas
   cabezas sigue BORRADOR.
2. Karen marca **APROBADO** (incluye esas listas).
3. Un agente, TDD, solo esos archivos. No recorta callado.
4. Hallazgo nuevo → se anota en el spec, esa linea vuelve a BORRADOR,
   se re-aprueba. No se avanza.
5. `scripts/gates.sh` + bundle + reabrir.
6. Veredicto visual. Si no, se itera el mismo spec. No se avanza.

## Ya heredado (no rehacer)

Tokens `Semantic` / `Space` / `Radius` / `Elevation`, Inter, syntax en
fences, gate de spacing. El dropdown de Ajustes se **reusa** en 04, no se
inventa otro.
