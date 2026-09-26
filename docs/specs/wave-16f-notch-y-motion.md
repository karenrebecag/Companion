# Wave 16f — La isla nace del notch, con el motion de Incredible

**Estado: CERRADO EN CÓDIGO (2026-09-25); falta la verificación en vivo de Karen (§8). Aprobado con "vamos, entonces confirmado"; NotchNook lo desactiva Karen.** Karen: "el diseño de notch de incredible y su motion, animaciones
son muchísimo mejores. ¿Puedes replicarlas?"

Criterio de done (medible):
- En una Mac con notch, el borde superior de la isla coincide con el borde de la pantalla y su ancho
  en reposo es el ancho del notch: en reposo no se distingue del hardware.
- Ningún cambio de tamaño mueve la ventana: la ventana es fija y lo que se anima es la forma. Cero
  `setFrame` animados.
- Cada transición medida contra la grabación de Incredible (§4) con una tolerancia de ±40 ms de
  duración y el mismo orden: primero la forma, después el contenido.
- 60 fps sin caídas en un MacBook con ProMotion (Instruments, 10 transiciones seguidas).

## 1. Qué hace Incredible y qué hacemos hoy

| | Incredible | Companion hoy |
|---|---|---|
| Ancla | El notch físico: arriba del todo, encima de la barra de menús | Debajo de la barra de menús (`visibleFrame.maxY`) |
| Forma | Una sola silueta negra que continúa el notch; hombros cóncavos arriba, radio grande abajo | Un rectángulo redondeado con borde gris y sombra, separado de todo |
| Crecer | La silueta se estira hacia abajo y a los lados con un resorte; la ventana no se mueve | `NSAnimationContext` anima el marco de la ventana (expoOut 0,32 s); el contenido se redibuja a cada paso |
| Contenido | Aparece cuando la forma ya casi llegó (fundido + desenfoque que se aclara) | Aparece a la vez que el marco, cortado mientras crece |
| Cerrar | La forma se recoge al notch; el contenido se va antes | Salto a 0 s entre pebble y nudge (se desactivó por bucles de hover) |
| Hover | Una franja en el borde superior abre la barra | Tracking del NSView sobre el pebble |
| Escucha | Barras de onda que siguen la voz + anillo | Barras (16e) sin curva propia |

## 2. Diseño

1. **Ventana fija.** `IslandPanel` ocupa una sola vez el rectángulo máximo (ancho de la tarjeta ×
   alto máximo) anclado a `screen.frame.maxY` (no `visibleFrame`), nivel por encima de la barra de
   menús. Transparente, sin sombra de ventana. Los clics en la zona transparente atraviesan (hit
   test por alfa); si no bastara, `ignoresMouseEvents` sigue a la forma (riesgo §5).
2. **Notch medido, no supuesto.** `NotchGeometry` (Core, puro) recibe `screen.frame`,
   `safeAreaInsets.top` y `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` y devuelve ancho y alto
   del notch. Sin notch (monitor externo, Mac sin muesca), una píldora negra de alto de barra de
   menús pegada arriba.
3. **Una silueta.** `NotchShape` (SwiftUI `Shape` con `animatableData` de ancho, alto y radios):
   hombros cóncavos arriba (la curva que une con el borde de la pantalla) y radio inferior que crece
   con el tamaño. Negro puro, sin borde ni sombra en reposo; una sombra suave solo al abrirse.
4. **Motion por tokens.** `IslandMotion` (UI): un resorte para abrir, otro más seco para cerrar, un
   retardo de contenido y el desenfoque de entrada. Los valores salen de la grabación (§4), no se
   inventan. Reducir movimiento: fundido corto sin resorte ni desenfoque.
5. **Coreografía.** Abrir: forma primero → contenido con fundido y desenfoque a los N ms. Cerrar:
   contenido fuera primero → forma de vuelta al notch. Cambio de estado dentro de la barra (escucha →
   pensando → tarjeta): la forma interpola tamaño y el contenido hace un fundido cruzado, sin cortes.
6. **Hover como el suyo.** Una franja fina en el borde superior sobre el notch abre la barra; la
   isla abierta sigue abierta mientras el puntero está dentro de la forma, con un margen de salida.
   Se elimina el bucle de hover que obligó a animar a 0 s (la ventana ya no cambia de tamaño).
7. **Escucha.** Barras con suavizado de subida rápida y bajada lenta (ataque/relajación) para que
   sigan la voz sin temblar; el anillo respira con el nivel.

## 3. TDD

- `NotchGeometry`: con notch, sin notch, pantalla escalada, notch descentrado imposible → centrado.
- `NotchShape`: el borde superior toca y = 0 en toda la anchura; los hombros son cóncavos; los radios
  nunca superan la mitad del alto.
- `IslandMotion`: el contenido de abrir empieza después de la forma; cerrar al revés; reduce motion
  sin resorte.
- `IslandChrome`: la ventana no cambia de marco al pasar de pebble a tarjeta (el test viejo de
  `visibleFrame` cambia a `screen.frame`).
- Revisión visual: grabación de la nuestra junto a la de Incredible, cuadro a cuadro.

## 4. Referencia de motion (medida, grabación de Karen 2026-09-25, 120 fps)

Medido cuadro a cuadro sobre `CleanShot 2026-09-25 at 2.03.25 PM.mp4` (1236×424 px a 2×, 40 s): ancho
de la silueta negra en cada cuadro y hojas de 25 ms. Nada de su código.

| Momento | Qué pasa | Tiempo | Curva |
|---|---|---|---|
| Abrir, fase 1 | Del notch a una píldora ancha y baja (51 → 241 pt de ancho) | 0–135 ms | resorte sin rebote: 51 % del camino en 17 ms, 90 % en 67 ms |
| Pausa | La píldora se sostiene | ~25 ms | — |
| Abrir, fase 2 | Se estira a panel (241 → 492 pt) y baja a ~118 pt de alto | 160–300 ms | resorte con rebote leve: 25 % a 17 ms, 65 % a 50 ms, 92 % a 100 ms, sobrepasa ~1,6 % y asienta en ~150 ms |
| Contenido | Entra cuando la forma va al ~90 %: aparece atenuado y se aclara | +125 ms, fundido ~40 ms | ease-out |
| Crecer con contenido (adjunto) | El panel crece en alto y ancho a la vez, sobrepasa (500 pt) y vuelve (492) | ~200 ms | mismo resorte de fase 2 |
| Cerrar | Primero se va el contenido; la silueta se recoge a una píldora y desaparece en el notch | ~35 ms contenido + ~180 ms forma | ease-in-out, sin rebote |

Silueta: negro puro; borde superior al ras de la pantalla con **hombros cóncavos** (se abre hacia
fuera al tocar arriba); radio inferior ~20 pt; sin borde gris; sombra solo en el panel abierto.

Arranque en tokens (`IslandMotion`), ajustados a esos números:
- fase 1: `spring(response: 0.14, dampingFraction: 1.0)`;
- fase 2 y cambios de tamaño: `spring(response: 0.18, dampingFraction: 0.82)`, con inicio a +160 ms;
- contenido: retardo 125 ms, fundido 40 ms (opacidad 0 → 1, desenfoque 6 → 0);
- cerrar: contenido 35 ms; forma `spring(response: 0.18, dampingFraction: 1.0)`.
La verificación es grabar la nuestra igual y comparar curvas con el mismo script (±40 ms).

Detalles de la barra que también salen en la grabación (entran en 16f): icono de volumen arriba a
la izquierda con un deslizador emergente; tres círculos punteados arriba a la derecha (espacios de
tareas); el orb pasa a botón rojo de parar mientras habla ("Stop talking"); tooltip "Talk fn" sobre
el orb y "Send ↵" sobre enviar; el clip abre "Add files" con ⌥C Capture Text y ⌥X Screenshot; los
adjuntos son una tarjeta bajo el campo; una píldora "Cancelled" aparece bajo el panel; al arrastrar
un archivo se oscurece la pantalla como zona de soltar.

Captura de Karen 2026-09-25 17:22 (panel abierto, en reposo tras responder), también entra:
- **Sin tarjeta ni burbuja:** la respuesta es texto blanco grande (~22 pt) directo sobre el negro,
  alineado a la izquierda bajo el campo, a todo el ancho.
- **Palabras que entran:** las últimas palabras de la respuesta aparecen en gris y se aclaran a
  blanco al llegar (el texto "se revela" mientras habla), no aparecen de golpe.
- **Orb a la izquierda del campo:** esfera de ~40 pt con degradado de cielo; el campo es una
  píldora gris oscura "Pregúntale a Companion…" con clip y un botón circular de enviar.
- **Cabecera:** altavoz arriba a la izquierda y los tres círculos punteados a la derecha, sobre el
  mismo negro; esquinas inferiores muy redondas (~40 pt a 2×) y hombros arriba que se funden con el
  borde de la pantalla, como NotchNook.

## 5. Riesgos

- **NotchNook está instalada** y ocupa el mismo notch: dos apps compitiendo por el hover. Opción:
  detectarla y avisar, o anclarnos igual y que Karen decida cuál queda.
- **Clics que atraviesan:** si el hit test por alfa falla en algún macOS, alternar
  `ignoresMouseEvents` según la forma (más código, mismo resultado).
- **Pantalla completa:** en apps a pantalla completa el notch se esconde con la barra; la isla debe
  seguir la barra (como Incredible con `data-macos-fullscreen`).
- **Multimonitor:** la isla vive en la pantalla con notch; en externas, la píldora.

## 6. Archivos

Core: `NotchGeometry.swift` (nuevo). UI: `NotchShape.swift`, `IslandMotion.swift` (nuevos),
`IslandChrome.swift`, `IslandView.swift`, `IslandPieces.swift`. App: `CompanionMain.swift` (anclaje y
nivel). Tests: `NotchGeometryTests`, `NotchShapeTests`, `IslandMotionTests`, `IslandChromeTests`.

## 7. Aprobación

Pendiente de Karen: esta spec y qué hacer con NotchNook (§5). La grabación ya está medida (§4).

## 8. Cierre (2026-09-25)

| Criterio | Resultado |
|---|---|
| En reposo es la muesca | `NotchGeometry` mide ancho y alto desde `safeAreaInsets` y las zonas auxiliares; en reposo la forma es exactamente eso. Sin muesca: píldora de 190 pt del alto de la barra |
| La ventana no se mueve | Un lienzo fijo de 560×620 pt colgado del borde; solo se recoloca al cambiar de pantalla, sin animar. Test: el mismo marco para todos los tamaños |
| Orden y tiempos de la grabación | `IslandMotion`: píldora con resorte 0,14/1,0, panel a +160 ms con 0,18/0,82, contenido +125 ms con fundido 40 ms y desenfoque 6→0; cerrar: contenido 35 ms y luego resorte 0,18/1,0. Reducir movimiento: fundido sin resorte |
| ±40 ms contra la grabación, 60 fps en Instruments | **Pendiente**: hay que grabar la nuestra; desde esta sesión no hay permiso de captura de pantalla |
| Clics | Pasan por todo el lienzo salvo por la forma (monitores de ratón global y local; `ignoresMouseEvents` sigue a la forma) |
| Respuesta en grande | Texto claro sobre negro; las palabras entran en gris y se aclaran a 3 por segundo mientras habla; tres huecos de tareas arriba a la derecha |

Desviaciones:
- **No entraron** los detalles de §4 que no tienen función detrás todavía: el altavoz con deslizador
  de volumen (la app no expone volumen a la UI), el orb rojo de "parar de hablar", los tooltips, el
  menú del clip con Capturar texto / Captura, la tarjeta de adjuntos bajo el campo, la píldora
  "Cancelado" y el oscurecido al arrastrar. Van a una 16f-2 si Karen los quiere.
- **Pantalla completa:** la isla sigue arriba sobre la app a pantalla completa (nivel de barra de
  estado con `fullScreenAuxiliary`); no se esconde con la barra.
- Un cambio de alto dentro del panel puede lanzar dos resortes seguidos (el primero con el alto
  anterior); SwiftUI los encadena con velocidad continua. Se mira en la prueba en vivo.

Revisión:
- Seguridad (HIGH): con el campo enfocado, todo el lienzo tomaba clics (barra de menús y app de
  atrás). Arreglado: solo la forma los toma. MEDIUM: miles de enlaces en la respuesta hacían el
  análisis cuadrático en el hilo principal; ahora se corta antes. Nota convertida en test: la forma
  se asienta antes de que "Permitir" acepte un clic.
- Código (HIGH, además del de arriba): al cerrar, el área de clic saltaba a la muesca mientras el
  panel seguía visible; ahora se achica cuando la forma llegó. MEDIUM: un "[" suelto frenaba los
  enlaces; la revelación de palabras redibujaba por cuadro y ahora por palabra. Re-revisión (MEDIUM):
  ocultar la isla con una encogida pendiente dejaba un área de clic fantasma; ahora se cancela y se
  pone a cero. Cada fix con su test en rojo antes.

## 9. Criterio de smooth motion (2026-09-25, desde transitions.dev)

Fuente: el catálogo de transitions.dev (18 transiciones, `~/.claude/skills/transitions-dev`), tomado
como vocabulario de valores y reglas, traducido a SwiftUI. No se copia su CSS: la app es nativa. Un
cambio de UI de la isla cumple si pasa las ocho reglas; cada una es medible.

### 9.1 Reglas

| # | Regla | Medida | De dónde sale |
|---|---|---|---|
| M1 | **Nada salta.** Todo cambio visible de tamaño, posición, opacidad, color o texto tiene transición (salvo reducir movimiento). Un resorte que cambia de destino a medio camino conserva la velocidad; nunca reinicia desde cero | Grabación a 120 fps: ningún cuadro con un cambio de más del 25 % del recorrido total | card resize, tabs sliding ("primera posición sin transición, luego restaurar") |
| M2 | **Entrar despacio, salir rápido.** Cerrar dura ~0,6× lo que abrir; la salida es un fundido quieto, sin rebobinar la entrada | Abrir ≤ 400 ms hasta asentarse; cerrar ≤ 250 ms; un tooltip sale en 50 ms | dropdown 250/150, modal 250/150, tooltip 150/50, texts reveal (salida 200 ms sin retorno en Y) |
| M3 | **Una curva de entrada.** Entrar es ease-out fuerte (`0.22, 1, 0.36, 1`) o un resorte críticamente amortiguado; nunca ease-in al entrar; lineal solo en bucles (shimmer, giro de tarea) | Revisión de tokens: cada `Animation` de la isla sale de `IslandMotion` o `MotionTime`, con test | todo el catálogo usa esa curva; shimmer lineal 2 s |
| M4 | **Rebote solo donde significa algo.** Sobrepaso ≤ 2 % y solo en la forma (el panel que se asienta) y en la confirmación de "hecho"; el texto nunca rebota | Grabación: sobrepaso medido | success check (bob), la grabación de Incredible (1,6 %) |
| M5 | **Amplitudes chicas.** Desenfoque ≤ 3 pt en texto, desplazamiento ≤ 12 pt, escala de superficies ≥ 0,96 | Test sobre los tokens | text swap 4 px / 2 px, texts reveal 12 px / 3 px, modal 0,96, dropdown 0,97 |
| M6 | **Coreografía.** La forma primero, el contenido cuando la forma va al ~90 %; varias líneas entran escalonadas 40 ms (máx. 5); al salir, todo a la vez | `IslandMotion.contentStart`, test de escalonado | texts reveal (40 ms), panel reveal (cross-blur) |
| M7 | **60 fps reales.** Cero cuadros perdidos seguidos y hitch ratio < 5 ms/s en 10 aperturas y cierres seguidos, en ProMotion (120 Hz) | Instruments › Animation Hitches | criterio de done de 16f |
| M8 | **Reducir movimiento.** Todo pasa a fundido ≤ 150 ms o instantáneo: sin resorte, sin desenfoque, sin desplazamiento, sin escalonado | Test por cada transición con `reduceMotion = true` | cada snippet trae su guard de `prefers-reduced-motion` |

Ninguna animación bloquea la entrada: se puede escribir, hacer clic o mantener fn mientras algo se
mueve (M1 + la guarda de "Permitir", que sí espera a que la forma se asiente).

### 9.2 Cada momento de la isla con su transición

| Momento | Patrón de transitions.dev | Valores en SwiftUI | Hoy |
|---|---|---|---|
| Abrir / cerrar la forma | card resize + la grabación | resortes de §4 | Cumple M1–M4 |
| Contenido entra | panel reveal (cross-blur) | 150 ms ease-out, desenfoque 3→0, +4 pt en Y | **No cumple M5:** desenfoque 6 y fundido de 40 ms (casi un corte) |
| Contenido sale | texts reveal (salida quieta) | 35 ms fundido, sin Y | Cumple |
| Línea de estado (escucho → pienso → hablo) | text states swap | 150 ms ease-in-out, sale 4 pt arriba con 2 pt de desenfoque, entra desde abajo | **No cumple M1:** el texto cambia de golpe |
| Palabras de la respuesta | texts reveal por palabra | cada palabra pasa de gris a blanco en 150 ms | **No cumple M1:** cambia a saltos de 3 por segundo |
| Tarjetas de resultado | texts reveal | escalonado 40 ms, 12 pt, desenfoque 3 | **No cumple M6:** entran de golpe |
| "Pensando" | shimmer text | banda lineal de 2 s | Cumple (ya existe) |
| Hueco de tarea girando | bucle lineal | lineal | Cumple |
| Luz verde / recibo de "hecho" | success check | fundido + giro + bob ≤ 2 %, trazo 550 ms | **Falta** (la luz aparece de golpe) |
| Menú del campo | menu dropdown | 250 ms abrir / 150 ms cerrar, desde 0,97, anclado al botón | **Falta revisar** |
| Hoja de aprobación | panel reveal | 400 ms / 350 ms, desenfoque 2 | **Falta revisar** |
| Icono que cambia (enviar ↔ parar) | icon swap | 200 ms, escala desde 0,25, desenfoque 2 | Llega con el orb de parar (16f-2) |
| Tooltips (futuro) | tooltip | entra a los 80 ms en 150 ms, sale en 50 ms | 16f-2 |

### 9.3 Cómo se hace cumplir

- **Tokens con test:** una `IslandMotionBudget` (UI) declara duraciones, curvas y amplitudes; un test
  comprueba M2, M3, M5, M6 y M8 sobre esos valores. El contrato `conformance/ui-contract.json` ya
  prohíbe duraciones literales en vistas, así que todo pasa por ahí.
- **Grabación:** el mismo script de medición de la grabación de Incredible corre sobre la nuestra
  (M1, M4, ±40 ms).
- **Instruments:** Animation Hitches en 10 aperturas y cierres (M7). Lo corre Karen o una sesión con
  permiso de captura.

### 9.4 Lo que falta para cumplir (propuesto como 16f-2, espera aprobación)

Seis cambios en la isla, todos en UI:
1. contenido entra en 150 ms con desenfoque 3;
2. la línea de estado cambia con text states swap;
3. las palabras se aclaran con un fundido de 150 ms cada una;
4. las tarjetas entran escalonadas;
5. la luz verde y los recibos con success check;
6. revisar el menú y la hoja de aprobación contra dropdown y panel reveal.

Más el test de presupuesto (`IslandMotionBudget`) primero, en rojo.

## 10. Cierre de 16f-2: smooth motion (2026-09-25)

Aprobada con "bien mejora todos los easings para que sean smooth, y dale a la spec". Hecho:

| Regla / momento | Antes | Ahora |
|---|---|---|
| M3 en toda la app | 13 curvas sueltas (`easeOut`, `snappy`, `osmo` que arranca lento) | Una curva de entrada (`MotionCurve.enter`, 0.22/1/0.36/1) vía `.expoOut`; regla de contrato `soft-easing` que prohíbe escribir curvas en las vistas |
| M4 resortes | hover/select/press con amortiguación 0,8 (rebote 1,5 %) | 0,9 (rebote 0,1 %); hoja 0,86; el panel conserva el 1,1 % medido; solo "hecho" rebota (`MotionSpring.success`) |
| Contenido entra | 40 ms, desenfoque 6 | 130 ms ease-out, desenfoque 3, sube 4 pt; todo dentro en 390 ms |
| Línea de estado | cambiaba de golpe | text states swap 150 ms (sale arriba, entra de abajo, desenfoque 2); un paso más de un encargo se actualiza en su sitio |
| Palabras | a saltos de 3 por segundo | cada palabra se aclara en 150 ms desde su momento (30 fps) |
| Tarjetas | de golpe | texts reveal: escalonado 40 ms, 12 pt, desenfoque 3, máx. 5 |
| Luz verde / ámbar | de golpe | success check: entra con escala y el único rebote permitido |
| Hoja de aprobación | de golpe | panel reveal 300 ms, desenfoque 2, sale con un fundido quieto |
| Reducir movimiento | parcial | todo a fundido ≤ 150 ms sin desenfoque ni desplazamiento |

Cómo se hace cumplir: `MotionBudgetTests` (M2–M6, M8 sobre los tokens), la regla `soft-easing` del
contrato, y `IslandMotion.swift` como archivo de tokens exento (solo números; las vistas que los
aplican viven en `IslandMotionViews.swift`, bajo todas las reglas).

Revisión (código, 3 HIGH, todos con test en rojo antes o arreglo en la vista): la línea se
reanimaba en cada paso de un encargo (llave por tipo de línea); las tarjetas heredaban el estado
"ya mostrada" de la que empujaban (llave por mensaje); dos animaciones de contenedor competían con
el resorte de la luz (cada animación en lo que mueve). MEDIUM: exención del contrato demasiado ancha
(archivo partido). LOW: el tiempo de asentado omitía el término de la envolvente.

Pendiente: M7 (Instruments) y la grabación comparada, en la prueba en vivo. El menú del campo es un
menú nativo de macOS: su animación es la del sistema.
