# Wave 6b — Design systems engineering

**Estado: BORRADOR** — pendiente de aprobacion de Karen.

## Principio rector (decision de producto, 2026-08-21)

La UI es central en este producto y se trabaja con disciplina de design
systems engineering, no como capa decorativa. **La simplificacion solo es
valida donde no haya perdida visual**: la paridad con el prototipo es el
piso, no el techo. Donde el rebuild simplifico sacrificando craft (dropdowns
del sistema, bloques de codigo sin resaltar, orb plano), esta wave lo revierte.
La unica restriccion que se mantiene intacta es cero dependencias externas —
todo el craft del prototipo que vale la pena ya era SwiftUI/AppKit puro.

## Objetivo

Elevar el sistema de diseno a la altura del prototipo y por encima:
fundaciones completas, componentes con estados, motion coreografiado, y
documentacion viva del sistema.

## Alcance

### 1. Fundaciones (Tokens)
| Pieza | Contenido | Referencia |
|---|---|---|
| Tipografia | Fuentes del producto empaquetadas y registradas (bundle.sh las copia; la app las registra al arrancar; fallback limpio a system). La eleccion de tipografia de Ajustes deja de ser cosmetica: cambia la rampa completa. | prototipo `Tokens.swift` + Assets/Fonts + build.sh |
| Elevacion y profundidad | Escala de sombras/elevacion tokenizada (reposo, hover, hoja, popover), radios y strokes como escalas nombradas — hoy hay valores sueltos en las vistas. | prototipo `Theme.swift` |
| Densidad y layout | Escala de espaciado auditada: ninguna vista con paddings magicos fuera de tokens. Gate nuevo: grep de literales de spacing en CompanionUI falla el build. | — |
| Estados de color | Variantes hover/pressed/disabled/focus derivadas de los roles semanticos, no colores ad hoc por componente. Contraste AA verificado en claro y oscuro (test que calcula ratios de los pares rol/fondo). | — |

### 2. Componentes con estados
| Componente | Contenido | Referencia |
|---|---|---|
| `Dropdown` propio | El selector del prototipo, no `Menu` del sistema: panel anclado con motion, hover states, check del activo. Reemplaza los `SettingsItem` actuales. Se revierte aqui la simplificacion del kickoff de 5a. | prototipo `Dropdown.swift` |
| Botones | Jerarquia primaria/secundaria/destructiva/ghost con los 4 estados + focus ring visible para navegacion por teclado. | — |
| Campos | TextField estilizado con estados y mensajes de error integrados (hoy onboarding y ajustes usan `.roundedBorder` del sistema). | — |
| `Shimmer` | El brillo de "pensando" sobre texto/estado. | prototipo `Shimmer.swift` |
| `Halftone` | La textura de identidad del prototipo donde aplique (fondos de tarjeta, onboarding). | prototipo `Halftone.swift` |
| Iconografia | Set consistente: SF Symbols con pesos/escalas tokenizados + los iconos propios del prototipo que definan identidad. | prototipo `Icons.swift` |

### 3. Resaltado de sintaxis
Portar `Syntax.swift` del prototipo (tokenizador propio por familia de
lenguaje, sin dependencias) con paleta desde tokens semanticos, temas claro y
oscuro. Sus tests del prototipo se portan como caracterizacion.

### 4. Orb a nivel de producto
El orb actual es funcional pero plano. Portar el enfoque del vendor del
prototipo — que ya era SwiftUI puro (MIT, atribuir en NOTICE.md): capas de
blob ondulante, glow rotatorio, particulas y sombra realista, moduladas por
los mismos estados y niveles que ya recibe. ADR 003 se mantiene: esto no
requiere Rive. La interactividad del tap ya existe; anadir microrespuesta al
press (spring del sistema de motion).

### 5. Motion coreografiado
Las duraciones existen (5a); esta pieza las usa con intencion: stagger en la
aparicion de mensajes y tarjetas, transiciones de la hoja y los popovers,
microinteracciones de botones. Todo respetando reduce-motion (ya hay patron).

### 6. Documentacion viva del sistema
`docs/design-system.md` generable/mantenible: fundaciones, componentes con
sus estados y donde se usan. El prototipo tenia `design-system.html` (47k);
aqui es markdown en el repo, revisable en PRs. Regla en CONTRIBUTING: un
componente nuevo entra con su seccion.

## Tests

Todo lo que sea decision pura: mapeo de estados a variantes de color,
ratios de contraste AA de los pares semanticos, tokenizador de sintaxis
(caracterizacion del prototipo), escala de elevacion ordenada, apariencia del
orb por estado (ya existe patron en OrbAppearanceTests: ampliar). Las vistas
no se instancian: la revision visual es la prueba manual de Karen, que en
esta wave es la definitiva.

## Definicion de done

Ajustes y onboarding sin un solo control del sistema sin estilo propio;
bloques de codigo resaltados en ambos temas; orb con la riqueza del
prototipo; documento del sistema al dia; gate de spacing en verde; y el
veredicto visual de Karen — en esta wave su revision manual ES el criterio.

## Riesgos

- Craft sin fin: el alcance es paridad con el prototipo + los estados que le
  faltaban; nada que el prototipo no tuviera salvo lo listado.
- Las fuentes del producto necesitan licencia clara antes de empaquetarse en
  un repo publico: si alguna no la tiene, se documenta y queda solo local.
