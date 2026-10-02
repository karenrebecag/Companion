# Reference Brief: motion y microinteracciones de la isla de Incredible frente a Companion

Slug: isla-motion-incredible | Nivel: standard | Fecha: 2026-10-02 | Estado: ESCALADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 ESCALATE

## 1. Pregunta y decisiones abiertas

Pregunta: que animaciones y microinteracciones tiene la isla (notch) de Incredible 0.2.36, con disparador, propiedad, duracion, retardo, curva y coreografia; cuales tiene hoy la isla de Companion; y como se expresan las curvas web en SwiftUI para pulir el motion de Companion hasta igualarlo.

Alcance: solo motion. Las medidas y el layout son del brief hermano `isla-maquetacion-incredible`; las reglas de cuando se abre, se cierra y se auto-descarta la isla son de `isla-ciclo-y-legibilidad`. El glow de fn y el puntero se reutilizan de `incredible-fn-glow-pointer.md`, sin reabrirlos.

Limite de la evidencia (leer antes que todo): `Contents/Resources` de Incredible 0.2.36 no trae CSS ni JS; el front va comprimido dentro del binario y este brief no lo descomprimio (ver seccion 9). Los valores de Incredible salen de dos fuentes de segunda mano ya en `main`: la medicion cuadro a cuadro de la grabacion de Karen (spec 16f §4) y los briefs que leyeron el CSS/JS extraido en una sesion anterior. Nueve filas del inventario quedan sin valor de Incredible y se marcan asi, no se inventan.

Directiva aplicada (relayada por el coordinador el 2026-10-02, no leida de primera mano): Incredible es el piso minimo; donde su motion choca con una decision firmada o un token de Companion, la recomendacion es igualar a Incredible y el choque se lista aqui como decision de Karen, con la regla y su archivo:linea.

Decisiones para Karen:

- D1. Curvas por rol en vez de una sola curva de entrada. Incredible usa cuatro curvas con nombre segun el rol (standard para fundidos, tooltips y el orb; settle para menus, popovers e items; glide para el campo; bounce para los chips de captura). Choca con la regla M3 "una curva de entrada" (`docs/specs/wave-16f-notch-y-motion.md:169`) y con `testOneEnterCurve` (`Tests/CompanionUITests/MotionBudgetTests.swift:24`). La regla de contrato `soft-easing` (`conformance/ui-contract.json:47`) no se toca: las cuatro curvas ya viven en `MotionCurve` (`Sources/CompanionUI/DesignSystem/Motion.swift:27`). Recomendado: igualar a Incredible y reescribir M3 como "cada rol, su curva de MotionCurve".
- D2. Rebote de los chips de captura. Incredible entra con `cubic-bezier(.34,1.56,.64,1)`, que sobrepasa cerca del 10 % del recorrido (calculado sobre la curva). Choca con M4 "sobrepaso de 2 % como maximo, solo en la forma y en hecho" (`docs/specs/wave-16f-notch-y-motion.md:170`) y con `testSpringsBarelyOvershoot` (`Tests/CompanionUITests/MotionBudgetTests.swift:29`). Recomendado: igualar, como excepcion nombrada igual que `MotionSpring.lively` (`Sources/CompanionUI/DesignSystem/Motion.swift:82`).
- D3. Tooltip. Incredible: solo opacidad, 150 ms entrar y salir, curva standard, sin espera visible en el CSS. Companion: espera 80 ms, entra en 150 ms y sale en 50 ms con glide (`Sources/CompanionUI/Island/IslandMotion.swift:166`), valores de transitions.dev fijados por M2 (`docs/specs/wave-16f-notch-y-motion.md:168`). Recomendado: igualar a Incredible (150/150 standard); la espera de 80 ms queda hasta medir si Incredible la tiene en JS.
- D4. Menu y popovers. Incredible: fundido mas 4 pt en Y, 200 ms settle (menu) y 180 ms entrar / 100 ms lineal salir (popover de pila). Companion: escala desde 0,97, 250 ms abrir y 150 ms cerrar con glide (`Sources/CompanionUI/Island/IslandMotion.swift:165`). Recomendado: igualar a Incredible.
- D5. Contenido al abrir y al cerrar. La grabacion midio fundido de ~40 ms con desenfoque 6 a 0 al entrar y ~35 ms de contenido antes de que la forma se recoja. Companion cambio a 130 ms con desenfoque 3 (`Sources/CompanionUI/Island/IslandMotion.swift:133`) por M1 y M5 (`Tests/CompanionUITests/MotionBudgetTests.swift:56`) y cierra con 80 ms a la vez que la forma (`Sources/CompanionUI/Island/IslandMotion.swift:51`). Ademas, el CSS de Incredible tiene `composer-slot` a 150 ms de opacidad y 220 ms de transform. Hay dos numeros de Incredible que no concuerdan: recomendado volver a medir antes de decidir (seccion 9) y, mientras tanto, cerrar como Incredible (contenido primero, luego la forma).
- D6. El peek al pasar el puntero. Es de NotchNook (`Sources/CompanionUI/DesignSystem/Motion.swift:76`), sobrepasa ~6,8 % y no hay evidencia de que Incredible lo tenga. No choca con el piso (es algo de mas); Karen decide si se queda.
- D7. Palabras de la respuesta. Companion pinta lo no dicho al 62 % (`Sources/CompanionUI/Island/IslandPieces.swift:31`); Incredible pinta el habla en vivo al 72 %. Recomendado: igualar a 72 %.
- D8. Anillo de auto-denegar a 1 Hz (`Sources/CompanionUI/Voice/ApprovalSheet.swift:100`): avanza a saltos, contra M1. Recomendado: la misma cadencia continua del anillo de avisos.
- D9. Autorizar una lectura primaria del front de Incredible (descomprimir los assets del binario a un scratchpad, solo lectura) o una grabacion nueva a 120 fps de los estados sin dato. Sin eso, nueve filas del inventario quedan sin valor de Incredible.

## 2. Estado actual

- Los tokens de tiempo de Companion son `MotionTime`: fast 0,15, base 0,2, panel 0,3, enter 0,6, layout 0,9 y follow 0,08 [repo:Sources/CompanionUI/DesignSystem/Motion.swift:8]
- Las cuatro curvas de Incredible ya estan declaradas como tokens: standard, settle, glide y bounce [repo:Sources/CompanionUI/DesignSystem/Motion.swift:27]
- La curva de entrada unica es glide, aplicada por `.expoOut` [repo:Sources/CompanionUI/DesignSystem/Motion.swift:31]
- `MotionCurve.bounce` esta declarada pero ningun archivo de Sources la usa; standard y settle si se usan fuera de la isla [repo:Sources/CompanionUI/DesignSystem/Controls.swift:117]
- Los resortes son `MotionSpring` con respuesta y amortiguacion, mas el calculo de sobrepaso y asentado para poder testearlos [repo:Sources/CompanionUI/DesignSystem/Motion.swift:52]
- La isla declara sus tres resortes: pill 0,14/1,0, panel 0,18/0,82 y close 0,18/1,0 [repo:Sources/CompanionUI/DesignSystem/Motion.swift:71]
- El peek de NotchNook es un resorte 0,35/0,65 y es la unica excepcion nombrada a M4 [repo:Sources/CompanionUI/DesignSystem/Motion.swift:78]
- `IslandMotion` codifica la coreografia: forma primero, contenido despues, y al cerrar el contenido primero [repo:Sources/CompanionUI/Island/IslandMotion.swift:7]
- `IslandMotionBudget` declara duracion, desenfoque y desplazamiento de cada movimiento que no es la forma [repo:Sources/CompanionUI/Island/IslandMotion.swift:115]
- La regla `raw-duration` prohibe duraciones literales en las vistas [repo:conformance/ui-contract.json:31]
- La regla `soft-easing` prohibe easeIn, easeOut, easeInOut, snappy, bouncy y smooth en las vistas [repo:conformance/ui-contract.json:47]
- `IslandMotion.swift` esta exento del contrato por ser el archivo de tokens [repo:conformance/ui-contract.json:53]
- Karen pidio replicar el notch y el motion de Incredible con sus palabras [KAREN:docs/specs/wave-16f-notch-y-motion.md:3]
- Karen aprobo suavizar todos los easings con la spec 16f-2 [KAREN:docs/specs/wave-16f-notch-y-motion.md:221]
- Los valores de forma de Incredible salen de la grabacion de Karen a 120 fps medida cuadro a cuadro [repo:docs/specs/wave-16f-notch-y-motion.md:65]
- La comparacion de la grabacion de Companion contra la de Incredible (±40 ms) sigue pendiente [repo:docs/specs/wave-16f-notch-y-motion.md:132]
- En el bundle 0.2.36 no hay CSS ni JS sueltos y el binario no contiene `cubic-bezier` en texto plano [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:3]
- El binario 0.2.36 si nombra `overlay-CkZPSNkG.css` y `overlay-DstkIEbM.js`, los mismos archivos que citan los briefs previos [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:4]
Contextos: app instalada (`/Applications/Companion.app`, build release, pantallas de 60 y 120 Hz), `swift test` (CompanionUITests: MotionBudgetTests y ControlTests prueban tokens y funciones puras sin ventana), gates (`scripts/gates.sh` y uiConformanceTests aplican `conformance/ui-contract.json` por grep sobre las vistas), espejo de autoinspeccion (pinta el estado, no los cuadros)

### Inventario de motion

| # | Momento | Incredible (valor) | Companion hoy | Brecha |
|---|---|---|---|---|
| 1 | Abrir fase 1, notch a pildora (tamano) | 0 a 135 ms, resorte sin rebote: 51 % a 17 ms, 90 % a 67 ms [repo:docs/specs/wave-16f-notch-y-motion.md:70] | `islandPill` 0,14/1,0 sin retardo [repo:Sources/CompanionUI/Island/IslandMotion.swift:61] | Sin brecha en numeros; falta la grabacion comparada [repo:docs/specs/wave-16f-notch-y-motion.md:132] |
| 2 | Pausa y fase 2, pildora a panel (tamano) | pausa ~25 ms; 160 a 300 ms, sobrepasa ~1,6 %, asienta en ~150 ms [repo:docs/specs/wave-16f-notch-y-motion.md:72] | arranca a 0,16 s con `islandPanel` 0,18/0,82, sobrepaso fijado en 1,1 % [repo:Sources/CompanionUI/Island/IslandMotion.swift:46] [repo:Tests/CompanionUITests/MotionBudgetTests.swift:34] | 1,1 % frente a 1,6 % |
| 3 | Crecer con la isla abierta (tamano) | alto y ancho a la vez, pasa a 500 y vuelve a 492, ~200 ms, resorte de fase 2 [repo:docs/specs/wave-16f-notch-y-motion.md:74] | resorte de fase 2 al cambiar el alto del contenido [repo:Sources/CompanionUI/Island/IslandView.swift:173] | Doble resorte encadenado sin medir [repo:docs/specs/wave-16f-notch-y-motion.md:143] |
| 4 | Contenido entra (opacidad, desenfoque, Y) | +125 ms, fundido ~40 ms ease-out, desenfoque 6 a 0 [repo:docs/specs/wave-16f-notch-y-motion.md:83]; CSS del slot del campo: opacidad 150 ms y transform 220 ms standard [repo:docs/research/incredible-ui-detalle.md:265] | empieza a 0,20 s, 130 ms glide, desenfoque 3, sube 4 pt [repo:Sources/CompanionUI/Island/IslandMotion.swift:133] [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:91] | D5 |
| 5 | Cerrar (opacidad y tamano) | contenido ~35 ms primero, despues la forma ~180 ms sin rebote [repo:docs/specs/wave-16f-notch-y-motion.md:75] | contenido 80 ms glide a la vez que la forma, `islandClose` 0,18/1,0 [repo:Sources/CompanionUI/Island/IslandMotion.swift:51] [repo:Sources/CompanionUI/Island/IslandMotion.swift:64] | 80 frente a 35 ms; simultaneo frente a secuencial (D5) |
| 6 | Radio de esquina | semilla 10, cue 12, abierto 28 [repo:docs/research/incredible-ui-detalle.md:210] | 10 en reposo, 22 abierto por umbral, interpolado por `animatableData` [repo:Sources/CompanionUI/Island/IslandMotionViews.swift:70] [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:37] | Radios son de `isla-maquetacion-incredible`; el motion ya interpola |
| 7 | Hover in en reposo (tamano, sombra) | una franja en el borde superior abre la barra; sin peek medido [repo:docs/specs/wave-16f-notch-y-motion.md:24] | peek inmediato con 0,35/0,65 y la sesion se entera a los 150 ms [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:46] [repo:Sources/CompanionUI/Island/IslandChrome.swift:344] | D6 |
| 8 | Hover out | sin dato: el CSS no se pudo releer [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:6] | 150 ms de gracia antes de terminar el hover [repo:Sources/CompanionUI/Island/IslandChrome.swift:352] | Sin dato de Incredible |
| 9 | Hairline y rim (opacidad) | hairline 12 % de 0 a 1 al abrir; rim azul con `opacity var(--isl-fade)` al haber actividad [repo:docs/research/incredible-ui-detalle.md:227] [repo:docs/research/incredible-ui-detalle.md:226] | hairline `resting ? 0 : 1` sin animacion propia; no hay rim [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:23] | Valor de `--isl-fade` desconocido; falta el rim |
| 10 | Senal de tarea bloqueada o hecha (opacidad, desenfoque, color) | `.ov-island-glow` desenfoque 12, opacidad 0 a 1 segun blocked (naranja) o completed (verde) [repo:docs/research/incredible-ui-detalle.md:229] | punto `IslandLight`: escala 0,4 a 1 mas opacidad con `success` 0,35/0,8 [repo:Sources/CompanionUI/Island/IslandPieces.swift:61] [repo:Sources/CompanionUI/Island/IslandPieces.swift:67] | Halo frente a punto; duracion de Incredible desconocida |
| 11 | Tooltip (opacidad) | solo opacidad, 150 ms, standard [repo:docs/research/incredible-fn-glow-pointer.md:154] | espera 80 ms, entra 150, sale 50, glide [repo:Sources/CompanionUI/Island/IslandMotion.swift:166] [repo:Sources/CompanionUI/Island/IslandPopover.swift:167] | D3 |
| 12 | Menu del header (opacidad, Y) | fundido mas 4 pt en Y, 200 ms settle; base de libreria escala 0,98 a 200 ms standard [repo:docs/research/incredible-fn-glow-pointer.md:167] | escala desde 0,97, 250 ms abrir, 150 ms cerrar, glide [repo:Sources/CompanionUI/Island/IslandPopover.swift:60] | D4 |
| 13 | Item de menu en hover (color de fondo) | 140 ms settle [repo:docs/research/incredible-fn-glow-pointer.md:165] | el menu del campo es nativo de macOS [repo:docs/specs/wave-16f-notch-y-motion.md:245] | Solo aplica a menus propios |
| 14 | Popover de pila y respuesta rica (opacidad, Y) | fundido mas 4 pt en Y, 180 ms settle; cierre 100 ms lineal [repo:docs/research/incredible-fn-glow-pointer.md:172] | la respuesta rica usa el popover de 250 ms [repo:Sources/CompanionUI/Island/Data/IslandView+Answer.swift:69] | D4 |
| 15 | Linea de estado escucho, pienso, hablo (opacidad, desenfoque, Y) | sin dato: el CSS no se pudo releer [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:6] | text swap 150 ms, desenfoque 2, 4 pt [repo:Sources/CompanionUI/Island/IslandMotion.swift:135] [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:42] | Sin dato de Incredible |
| 16 | Pensando (shimmer) | estado de 36 de alto con tinta 72 %; la animacion no esta documentada [repo:docs/research/incredible-isla-componentes.md:37] | banda lineal, periodo 1,5 s, espera 0,25 s, banda 0,35, blanco 15 % a 100 %, 30 fps [repo:Sources/CompanionUI/DesignSystem/Shimmer.swift:35] [repo:Sources/CompanionUI/DesignSystem/Shimmer.swift:43] | La spec dice 2 s y el codigo usa 1,5 s [repo:docs/specs/wave-16f-notch-y-motion.md:189] |
| 17 | Escucha (alto de barras, anillo) | eventos `audio:mic-level` y `audio:tts-bands` existen; la forma del medidor no esta documentada [repo:docs/research/incredible-fn-glow-pointer.md:52] | 5 barras de 4 a 20 pt, expoOut 80 ms simetrico; anillo shimmer de 1,15 s [repo:Sources/CompanionUI/Island/IslandPieces.swift:96] [repo:Sources/CompanionUI/DesignSystem/Shimmer.swift:19] | 16f pidio ataque rapido y relajacion lenta y no se hizo [repo:docs/specs/wave-16f-notch-y-motion.md:49] |
| 18 | Hablando, orb a boton de parar (escala, opacidad, desenfoque) | el orb pasa a boton rojo de parar mientras habla [repo:docs/specs/wave-16f-notch-y-motion.md:89] | icon swap 200 ms desde escala 0,25 con desenfoque 2 [repo:Sources/CompanionUI/Island/IslandMotion.swift:168] [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:132] | Tiempos de transitions.dev, no de Incredible [repo:docs/specs/wave-16f-notch-y-motion.md:194] |
| 19 | Transcripcion viva a fija (opacidad) | 72 % mientras llega, 94 % fija [repo:docs/research/incredible-isla-componentes.md:38] | mismos valores, fundido 150 ms glide [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:36] [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:76] | Curva de Incredible desconocida |
| 20 | Palabras de la respuesta, tenues a claras (opacidad por palabra) | el habla se pinta como la transcripcion y se asienta a 1 [repo:docs/research/incredible-isla-componentes.md:39]; captura de Karen: las ultimas palabras entran grises y se aclaran [KAREN:docs/specs/wave-16f-notch-y-motion.md:97] | todas en pantalla al 62 %, 3 palabras por segundo, 150 ms por palabra, 30 fps [repo:Sources/CompanionUI/Island/IslandMotion.swift:97] [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:82] | D7; ritmo fijo frente a la voz (seccion 9) |
| 21 | Botones, presion (escala, opacidad) | boton de la app: settle 0,2 s y hover a escala 1,03 (ventana, no isla) [repo:docs/research/incredible-componentes.md:55] | `PressableStyle` 0,98 y 85 % con resorte 0,25/0,9 [repo:Sources/CompanionUI/DesignSystem/Pressable.swift:5] [repo:Sources/CompanionUI/DesignSystem/Pressable.swift:49] | Los chips de la isla cambian el relleno sin transicion [repo:Sources/CompanionUI/DesignSystem/SharedControls.swift:73] |
| 22 | Parar (boton y chip) | boton rojo "Stop talking" al hablar [repo:docs/specs/wave-16f-notch-y-motion.md:89] | orb de parar con `PressableStyle`; chip "Detener" sin animacion de presion [repo:Sources/CompanionUI/Island/Notices/IslandNotice.swift:187] [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:53] | Como la fila 21 |
| 23 | Chips de captura con fn (Y, opacidad) | entran 460 ms con bounce, salen 260 ms con `cubic-bezier(.55,0,1,.45)` hacia arriba, apilados cada 31 px [repo:docs/research/incredible-fn-glow-pointer.md:116] | no existen; los chips de referencia aparecen sin transicion [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:87] [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:118] | D2 |
| 24 | Orb junto al puntero (opacidad, escala) | 0 a 1 y escala 0,85 a 1 en 180 ms standard [repo:docs/research/incredible-fn-glow-pointer.md:115] | aparece de golpe [repo:Sources/CompanionUI/Overlay/ScreenOverlay.swift:80] | Falta la transicion |
| 25 | Rastro de tinta (posicion, ancho) | vida 620 ms, cola del 20 %, seguimiento 0,3 por cuadro [repo:docs/research/incredible-fn-glow-pointer.md:95] [repo:docs/research/incredible-fn-glow-pointer.md:97] | mismas constantes, seguimiento por cuadro del TimelineView [repo:Sources/CompanionUI/Overlay/PointerTrail.swift:16] [repo:Sources/CompanionUI/Overlay/PointerTrail.swift:42] | Depende de la tasa de cuadro (seccion 9) |
| 26 | Glow de pantalla (opacidad) | sube lineal en 260 ms, baja en 900 ms; en espera atenua a la mitad en ~250 ms [repo:docs/research/incredible-fn-glow-pointer.md:49] [repo:docs/research/incredible-fn-glow-pointer.md:51] | mismas duraciones con curva standard [repo:Sources/CompanionUI/Overlay/ScreenGlow.swift:14] [repo:Sources/CompanionUI/Overlay/ScreenOverlay.swift:108] | Lineal frente a standard |
| 27 | Cuenta atras de un aviso (trim del anillo) | anillo con pista y progreso [repo:docs/research/incredible-isla-componentes.md:48] | trim lineal a 15 fps sobre 6 s [repo:Sources/CompanionUI/Island/Notices/IslandNoticeCard.swift:112] [repo:Sources/CompanionCore/Session/SessionMachine.swift:26] | Cadencia y curva de Incredible desconocidas |
| 28 | Auto-cierre (recibo, hecho, cancelado, dictado) | dictado con envio automatico y cuenta atras [repo:docs/research/incredible-isla-componentes.md:74] | recibo 8 s, hecho 1,5 s, cancelado 2 s, dictado 12 s; se van con el cierre de la fila 5 [repo:Sources/CompanionCore/Session/SessionMachine+Jobs.swift:11] [repo:Sources/CompanionCore/Session/SessionMachine.swift:11] | Los plazos son de `isla-ciclo-y-legibilidad` |
| 29 | Tarjeta de recibo, entrada y salida | sin dato: el CSS no se pudo releer [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:6] | sin transicion propia: entra con el contenido de la isla [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:11] | Sin dato de Incredible |
| 30 | Hoja de aprobacion (opacidad, desenfoque, Y) | sin dato: el CSS no se pudo releer [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:6] | entra 300 ms con desenfoque 2 y 8 pt; sale con fundido; anillo de auto-denegar a 1 Hz [repo:Sources/CompanionUI/Island/IslandMotion.swift:139] [repo:Sources/CompanionUI/Voice/ApprovalSheet.swift:100] | D8 |
| 31 | Error (color, opacidad) | aviso de error en `#ff8278`; destello rojo del clip con opacidad 150 ms ease-out [repo:docs/research/incredible-isla-componentes.md:49] [repo:docs/research/incredible-ui-detalle.md:193] | `IslandNoticeCard` sin transicion propia [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:18] | Sin entrada ni salida propia |
| 32 | Tarjetas de resultado (opacidad, desenfoque, Y, escalonado) | sin dato: el CSS no se pudo releer [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:6] | 450 ms, desenfoque 3, 12 pt, paso 40 ms, maximo 5 [repo:Sources/CompanionUI/Island/IslandMotion.swift:137] [repo:Sources/CompanionUI/Island/IslandMotion.swift:171] | Sin dato de Incredible |
| 33 | Huecos de tarea girando (rotacion) | sin dato: el CSS no se pudo releer [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:6] | giro lineal de 1,2 s [repo:Sources/CompanionUI/Island/IslandPieces.swift:222] | Sin dato de Incredible |
| 34 | Reducir movimiento | sin dato: los briefs previos no lo mencionan y el CSS no se pudo releer [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:6] | forma con fundido de 150 ms; movimientos a 150 ms como maximo sin desenfoque ni desplazamiento [repo:Sources/CompanionUI/Island/IslandMotion.swift:58] [repo:Sources/CompanionUI/Island/IslandMotion.swift:123] | La respuesta no lee reduceMotion [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:86] |

## 3. Fuentes primarias

- `Animation.timingCurve(_:_:_:_:duration:)` crea la animacion desde una Bezier cubica de (0,0) a (1,1) con dos puntos de control; duracion por defecto 0,35 s; macOS 10.15+ [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/animation/timingcurve(_:_:_:_:duration:).json@macOS-26]
- `spring(response:dampingFraction:blendDuration:)`: response es la rigidez como duracion aproximada y dampingFraction la fraccion de la amortiguacion critica; preserva la velocidad al reemplazarse [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/animation/spring(response:dampingfraction:blendduration:).json@macOS-26]
- `spring(duration:bounce:blendDuration:)`: duration es la duracion perceptual; bounce 0 es amortiguacion critica, positivo rebota hasta 1 y negativo es sobreamortiguado hasta -1 [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/animation/spring(duration:bounce:blendduration:).json@macOS-26]
- `Spring` convierte entre representaciones; su ejemplo da `Spring(duration: 0.5, bounce: 0.3)` = masa 1, rigidez 157,9, amortiguacion 17,6 y `Spring(mass: 1, stiffness: 100, damping: 10)` = duracion 0,63, bounce 0,5 [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring.json@macOS-26]
- `Spring(mass:stiffness:damping:allowOverDamping:)` existe desde macOS 14 y, sin allowOverDamping, trata el sobreamortiguado como critico [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring/init(mass:stiffness:damping:allowoverdamping:).json@macOS-26]
- `keyframeAnimator` (macOS 14+) recorre keyframes Linear, Cubic, Spring y Move, y su closure de contenido corre en cada cuadro [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/keyframeanimator(initialvalue:repeating:content:keyframes:).json@macOS-26]
- `phaseAnimator` (macOS 14+) anima por una secuencia de fases y vuelve a la primera al terminar [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/phaseanimator(_:content:animation:).json@macOS-26]
- `accessibilityReduceMotion`: con el ajuste activo, la UI debe evitar animaciones grandes, en especial las que simulan tercera dimension [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/environmentvalues/accessibilityreducemotion.json@macOS-26]
- La HIG pide motion breve y preciso en el feedback y evitar animar interacciones frecuentes [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/motion.json@2026-10-02]
- WWDC23 "Animate with springs": los resortes conservan la velocidad al interrumpirse y las curvas de tiempo no pueden representar velocidad inicial; sin certeza, bounce 0 [doc:https://developer.apple.com/videos/play/wwdc2023/10158/@WWDC23]
- CSS Easing 1: `cubic-bezier(x1,y1,x2,y2)` exige x en [0,1] y permite y fuera de [0,1]; ease-out es (0,0,0.58,1) y ease-in-out (0.42,0,0.58,1) [doc:https://www.w3.org/TR/css-easing-1/@CRD-2023-02-13]
- WCAG 2.3.3 (AAA): el motion disparado por interaccion se puede desactivar; cambios de color, desenfoque u opacidad que no alteran tamano, forma ni posicion no cuentan como motion [doc:https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html@2.2]

## 4. Implementaciones de referencia

- boring.notch (TheBoredTeam, ~10,9 k estrellas, push 2026-10-02, app de notch SwiftUI mas usada en GitHub): abre con `spring(response: 0.42, dampingFraction: 0.8)` y cierra con `spring(response: 0.45, dampingFraction: 1.0)`, sin rebote al cerrar [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/ContentView.swift#L123@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- boring.notch entra el contenido con escala 0,8 anclada arriba mas opacidad, 0,35 s [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/ContentView.swift#L354@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- boring.notch expresa una curva web en SwiftUI como `timingCurve(0.16, 1, 0.3, 1, duration: 0.7)` cuando no hay notch [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/animations/drop.swift#L23@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- DynamicNotchKit (Kai Azim, libreria SPM, 462 estrellas, push 2026-04-24): abrir `.bouncy(duration: 0.4)`, cerrar `.smooth(duration: 0.4)` y convertir entre tamanos `.snappy(duration: 0.4)` [ref:https://github.com/mrkai77/DynamicNotchKit/blob/cd0b3e52d537db115ad3a9d89601f20e0bee8d27/Sources/DynamicNotchKit/DynamicNotch/DynamicNotchStyle.swift#L68@cd0b3e52d537db115ad3a9d89601f20e0bee8d27]
- DynamicNotchKit define el desenfoque de entrada como un `AnyTransition.modifier` de blur, el mismo patron que `IslandMoveModifier` [ref:https://github.com/mrkai77/DynamicNotchKit/blob/cd0b3e52d537db115ad3a9d89601f20e0bee8d27/Sources/DynamicNotchKit/Utility/BlurModifier.swift#L30@cd0b3e52d537db115ad3a9d89601f20e0bee8d27]
- Las dos referencias coinciden con Incredible en lo esencial: resorte al abrir y cierre sin rebote; ninguna es el estandar de valores, que sigue siendo Incredible [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/ContentView.swift#L123@d58240cc160d5e54da1a8a5925e095d067a8e1e0]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Igualar a Incredible donde hay valor, con curvas por rol, y medir antes los huecos (D9) | Cumple la directiva del piso minimo; reusa tokens que ya existen; no inventa valores | Reabre M3, M4 y la tolerancia del tooltip; nueve filas esperan medicion | media | Recomendada |
| B. Mantener las reglas M1 a M8 de transitions.dev y solo cerrar huecos propios (chips, orb del puntero, error, anillo a 1 Hz) | Sin tocar decisiones firmadas ni tests | Deja tooltip, menu, popover y palabras distintos a Incredible: no alcanza el piso | baja | No |
| C. Portar todo ya, rellenando con valores supuestos donde Incredible no tiene dato | Rapido | Motion inventado: contradice 16f ("no se inventan") y la regla de no concluir sin fuente | media | No |

## 6. Evidencia en contra

- Los valores de Incredible del CSS son de segunda mano: vienen de una extraccion que ya no existe y este brief no pudo releerla [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:6]
- Se acepta con riesgo acotado: los nombres de archivo citados siguen en el binario 0.2.36, asi que la extraccion previa era de esta version [repo:docs/research/evidence/incredible-0.2.36-assets-embebidos-2026-10-02.txt:4]
- M1 a M8 son decisiones firmadas y tienen tests; igualar el fundido de 40 ms rompe el piso de M1 [repo:Tests/CompanionUITests/MotionBudgetTests.swift:57]
- Se resuelve dejando D5 a Karen con una medicion nueva: dos valores de Incredible (40 ms en la grabacion, 150 ms en el CSS del slot) no concuerdan [repo:docs/research/incredible-ui-detalle.md:265]
- Una curva Bezier no conserva velocidad al interrumpirse; cambiar a curvas por rol no debe tocar la forma, que sigue en resortes [doc:https://developer.apple.com/videos/play/wwdc2023/10158/@WWDC23]
- El rebote de 10 % de los chips puede marear; WCAG 2.3.3 pide poder desactivarlo, y con reduceMotion pasa a fundido [doc:https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html@2.2]

## 7. Ejemplares y anti-ejemplos

### Mapeo web a SwiftUI

| Web | SwiftUI | Fuente |
|---|---|---|
| `transition: X Ds cubic-bezier(a,b,c,d) Ls` | `.timingCurve(a, b, c, d, duration: D).delay(L)`, misma semantica de puntos de control [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/animation/timingcurve(_:_:_:_:duration:).json@macOS-26] | CSS Easing 1 [doc:https://www.w3.org/TR/css-easing-1/@CRD-2023-02-13] |
| `linear` | `.linear(duration:)`; para bucles (shimmer, giro) `TimelineView` o `repeatForever` [repo:Sources/CompanionUI/DesignSystem/Shimmer.swift:43] | [doc:https://www.w3.org/TR/css-easing-1/@CRD-2023-02-13] |
| resorte `stiffness k, damping c, mass m` (framer-motion o react-spring) | `Spring(mass: m, stiffness: k, damping: c)`; equivale a response = 2π·raiz(m/k) y dampingFraction = c / (2·raiz(k·m)) [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring.json@macOS-26] | el ejemplo de Apple (100, 10 da 0,63 s y bounce 0,5) cuadra con esas formulas [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring.json@macOS-26] |
| `response r, dampingFraction z` | `spring(duration: r, bounce: 1 - z)` para z hasta 1 [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/animation/spring(duration:bounce:blendduration:).json@macOS-26] | [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring.json@macOS-26] |
| `@keyframes` con varios pasos | `keyframeAnimator` con `LinearKeyframe` o `CubicKeyframe` por pista [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/keyframeanimator(initialvalue:repeating:content:keyframes:).json@macOS-26] | macOS 14+, el proyecto apunta a macOS 26 [repo:Package.swift:9] |
| `animation: X infinite` entre estados fijos | `phaseAnimator` [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/phaseanimator(_:content:animation:).json@macOS-26] | [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/phaseanimator(_:content:animation:).json@macOS-26] |
| `@media (prefers-reduced-motion)` | `@Environment(\.accessibilityReduceMotion)` [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/environmentvalues/accessibilityreducemotion.json@macOS-26] | [doc:https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html@2.2] |

### Tokens recomendados (opcion A)

| Token | Valor | SwiftUI | Origen |
|---|---|---|---|
| `MotionCurve.standard` (ya existe) | (.4, 0, .2, 1) para fundidos, tooltip, orb del puntero, tile elegido | `MotionCurve.animation(.standard, d)` | [repo:docs/research/incredible-componentes.md:43] |
| `MotionCurve.settle` (ya existe) | (.32, .72, 0, 1) para menu, popover e item en hover | `MotionCurve.animation(.settle, d)` | [repo:docs/research/incredible-componentes.md:44] |
| `MotionCurve.glide` (ya existe) | (.22, 1, .36, 1) para el campo (`--ci-ease`) | `.expoOut(d)` | [repo:docs/research/incredible-ui-detalle.md:167] |
| `MotionCurve.bounce` (ya existe, sin uso) | (.34, 1.56, .64, 1) solo para chips de captura | `MotionCurve.animation(.bounce, 0.46)` | [repo:docs/research/incredible-fn-glow-pointer.md:116] |
| `MotionCurve.exit` (nuevo) | (.55, 0, 1, .45), salida acelerada de chips | `MotionCurve.animation(.exit, 0.26)` | [repo:docs/research/incredible-fn-glow-pointer.md:116] |
| `IslandMotionBudget.tooltip` | 0 ms de espera visible, 150 entrar, 150 salir, standard (D3) | `.opacity` con `.timingCurve` | [repo:docs/research/incredible-fn-glow-pointer.md:154] |
| `IslandMotionBudget.menu` (nuevo) | 200 ms settle, 4 pt en Y, sin escala (D4) | `.modifier` de opacidad mas offset | [repo:docs/research/incredible-fn-glow-pointer.md:167] |
| `IslandMotionBudget.popover` | 180 ms settle entrar, 100 ms lineal salir, 4 pt en Y (D4) | `.asymmetric` | [repo:docs/research/incredible-fn-glow-pointer.md:172] |
| `PointerOrb.appear` (nuevo) | 180 ms standard, escala 0,85 a 1 | `.scale(0.85).combined(with: .opacity)` | [repo:docs/research/incredible-fn-glow-pointer.md:115] |
| `CollectChip` (nuevo) | entra 460 ms bounce, sale 260 ms exit hacia arriba, paso 31 pt | `.asymmetric` con offset | [repo:docs/research/incredible-fn-glow-pointer.md:116] |
| `ScreenGlow.fade` | lineal 260 ms subir, 900 ms bajar | `.linear(duration:)` | [repo:docs/research/incredible-fn-glow-pointer.md:49] |
| `IslandInk.dimWord` | 0,72 (D7) | sin cambio de API | [repo:docs/research/incredible-isla-componentes.md:38] |
| Resortes de la forma | sin cambio: pill 0,14/1,0, panel 0,18/0,82 a +160 ms, close 0,18/1,0 | `MotionSpring` | [repo:docs/specs/wave-16f-notch-y-motion.md:81] |

### Ejemplares y anti-ejemplos

- Bien: la forma con resortes medidos de la grabacion y el contenido despues, como esta hoy [repo:Sources/CompanionUI/Island/IslandMotion.swift:56]
- Bien: los numeros viven en un archivo de tokens exento y las vistas solo los aplican [repo:Sources/CompanionUI/Island/IslandMotionViews.swift:4]
- Bien: cerrar sin rebote, igual que boring.notch con dampingFraction 1,0 [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/ContentView.swift#L124@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- Anti-ejemplo: un anillo que avanza una vez por segundo es un salto visible [repo:Sources/CompanionUI/Voice/ApprovalSheet.swift:100]
- Anti-ejemplo: un chip que cambia de relleno sin transicion al presionarse [repo:Sources/CompanionUI/DesignSystem/SharedControls.swift:73]
- Anti-ejemplo: `.snappy` y `.bouncy` en las vistas, como DynamicNotchKit; aqui los prohibe `soft-easing` [ref:https://github.com/mrkai77/DynamicNotchKit/blob/cd0b3e52d537db115ad3a9d89601f20e0bee8d27/Sources/DynamicNotchKit/DynamicNotch/DynamicNotchStyle.swift#L68@cd0b3e52d537db115ad3a9d89601f20e0bee8d27]

## 8. Trampas

- Una curva `timingCurve` interrumpida a medio camino arranca desde velocidad cero y da un tiron; lo que se interrumpe (forma, peek) va en resortes [doc:https://developer.apple.com/videos/play/wwdc2023/10158/@WWDC23]
- `MotionSpring.all` excluye a `islandPeek`; un token nuevo con rebote debe ir a la lista de excepciones o el test M4 falla [repo:Sources/CompanionUI/DesignSystem/Motion.swift:84]
- La regla `raw-duration` atrapa `duration: 0.2` en una vista: los tokens nuevos van en `Motion.swift` o `IslandMotion.swift` [repo:conformance/ui-contract.json:31]
- `Spring(mass:stiffness:damping:)` sin `allowOverDamping` convierte un sobreamortiguado en critico: un resorte web muy amortiguado se veria mas rapido [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring/init(mass:stiffness:damping:allowoverdamping:).json@macOS-26]
- El closure de `keyframeAnimator` corre en cada cuadro: nada caro dentro (Markdown, layout del texto) [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/keyframeanimator(initialvalue:repeating:content:keyframes:).json@macOS-26]
- Los seguimientos por cuadro (0,3 y 0,16) se aplican en cada tick del TimelineView, asi que a 120 Hz convergen mas rapido que a 60 Hz [repo:Sources/CompanionUI/Overlay/PointerTrail.swift:88]
- La spec del shimmer dice 2 s y la linea de estado usa el periodo por defecto de 1,5 s [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:40]
- Contexto app: los resortes y TimelineView corren a la tasa de la pantalla; la verificacion de M7 es en Instruments sobre ProMotion [repo:docs/specs/wave-16f-notch-y-motion.md:173]
- Contexto `swift test`: MotionBudgetTests prueba los tokens, no las vistas; una vista que no lee reduceMotion pasa los tests igual [repo:Tests/CompanionUITests/MotionBudgetTests.swift:68]
- Contexto gates: el contrato es un grep; una curva que llega por `MotionCurve.animation` pasa aunque sea la equivocada para su rol [repo:conformance/ui-contract.json:47]
- Contexto espejo de autoinspeccion: pinta el estado, no los cuadros, asi que no sirve para medir motion [repo:Sources/CompanionUI/Island/IslandView.swift:183]
- La respuesta palabra a palabra no lee reduceMotion; es solo opacidad, que WCAG no cuenta como motion, asi que puede quedarse [doc:https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html@2.2]

## 9. Incertidumbre

- ASSUMPTION: los valores CSS de los briefs previos son los de 0.2.36. prueba: descomprimir los assets del binario (D9) y buscar `--overlay-duration-snap`, `ov-hold-collect` y `ov-menu` en `overlay-CkZPSNkG.css`.
- ASSUMPTION: Incredible anima pensando, escucha, hablando, recibo, aprobacion, error, linea de estado, tarjetas, huecos de tarea y hover out con CSS que los briefs previos no recogieron. prueba: la misma extraccion de D9, buscando `@keyframes` y `transition` en los CSS del overlay, o una grabacion a 120 fps de cada estado.
- ASSUMPTION: Incredible respeta `prefers-reduced-motion` en la isla. prueba: buscar `prefers-reduced-motion` en el CSS extraido, o grabar la isla con Reducir movimiento activo.
- ASSUMPTION: el "+125 ms" del contenido se cuenta desde el inicio de la fase 2 (≈285 ms desde que empieza a abrir). prueba: rehacer la medicion sobre la grabacion de 2026-09-25 marcando el primer cuadro con contenido visible.
- ASSUMPTION: Incredible pinta las palabras al ritmo real de la voz y no a una tasa fija. prueba: grabar una respuesta larga y comparar el avance del brillo con el audio.
- ASSUMPTION: el tooltip de Incredible no espera antes de mostrarse. prueba: grabar a 120 fps un hover sobre el orb y contar cuadros hasta la primera opacidad.
- ASSUMPTION: los seguimientos por cuadro de Incredible se calibraron a 60 Hz. prueba: grabar el rastro en una pantalla de 120 Hz y comparar el arrastre con el de Companion.
- ASSUMPTION: `timingCurve` acepta y mayor que 1 (bounce 1,56) y sobrepasa como en CSS. prueba: un test que muestree `UnitCurve.bezier` con esos puntos en t = 0,55 y espere un valor mayor que 1.
- [NEEDS CLARIFICATION: D1 a D9 de la seccion 1, en especial si se autoriza leer el front comprimido de Incredible o grabar de nuevo.]

## 10. Checklist de estandar

- [ ] Abrir: pildora con `spring(response: 0.14, dampingFraction: 1)`, panel a +160 ms con 0,18/0,82, asentado de la forma en 400 ms como maximo, ±40 ms contra la grabacion de Incredible.
- [ ] Cerrar: el contenido se va antes que la forma (orden de Incredible), forma 0,18/1,0, total en 250 ms como maximo; el valor del fundido sale de D5.
- [ ] Tooltip: 150 ms entrar y salir, curva standard, solo opacidad (si se aprueba D3).
- [ ] Menu del header: 200 ms settle, 4 pt en Y, sin escala; popover de pila 180 ms settle y salida de 100 ms lineal (si se aprueba D4).
- [ ] Orb del puntero: 180 ms standard, escala 0,85 a 1 al aparecer.
- [ ] Chips de captura: 460 ms bounce al entrar, 260 ms con (.55, 0, 1, .45) al salir, pila de 31 pt; listados como excepcion de M4 (si se aprueba D2).
- [ ] Glow de pantalla: subida y bajada lineales de 260 y 900 ms.
- [ ] Palabras: lo no dicho al 72 %, cada palabra se aclara en 150 ms, sin saltos (D7).
- [ ] Anillos de cuenta atras (avisos y aprobacion): trim continuo, ningun salto visible de mas del 25 % del recorrido por cuadro (M1).
- [ ] Chips y botones de la isla: feedback de presion animado con un token de `MotionSpring` o `MotionCurve`.
- [ ] Linea de estado: periodo del shimmer igual al de la spec (o la spec corregida al codigo), con un test.
- [ ] Escucha: barras con subida mas rapida que bajada, con los dos tiempos como tokens.
- [ ] Reducir movimiento: cada transicion nueva pasa a fundido de 150 ms o menos sin resorte, escala, desenfoque ni desplazamiento, con test por token; el puntero y el rastro no se dibujan.
- [ ] Ninguna duracion ni curva literal en las vistas: todo pasa `raw-duration` y `soft-easing`.
- [ ] Cada fila sin dato de Incredible (8, 15, 16, 17, 29, 30, 32, 33, 34) se cierra con una medicion antes de tocar su motion.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Animation.timingCurve | Apple | macOS 10.15+ | 2026-10-02 | high |
| 2 | Animation.spring(response:dampingFraction:blendDuration:) | Apple | macOS 10.15+ | 2026-10-02 | high |
| 3 | Animation.spring(duration:bounce:blendDuration:) | Apple | macOS 10.15+ | 2026-10-02 | high |
| 4 | Spring | Apple | macOS 14+ | 2026-10-02 | high |
| 5 | Spring init(mass:stiffness:damping:allowOverDamping:) | Apple | macOS 14+ | 2026-10-02 | high |
| 6 | keyframeAnimator | Apple | macOS 14+ | 2026-10-02 | high |
| 7 | phaseAnimator | Apple | macOS 14+ | 2026-10-02 | high |
| 8 | accessibilityReduceMotion | Apple | macOS 10.15+ | 2026-10-02 | high |
| 9 | HIG Motion | Apple | sin version | 2026-10-02 | high |
| 10 | Animate with springs | Apple WWDC | 2023 | 2026-10-02 | high |
| 11 | CSS Easing Functions Level 1 | W3C | CRD 2023-02-13 | 2026-10-02 | high |
| 12 | Understanding SC 2.3.3 | W3C WAI | WCAG 2.2 | 2026-10-02 | high |
| 13 | boring.notch ContentView.swift y drop.swift | TheBoredTeam | d58240c | 2026-10-02 | medium |
| 14 | DynamicNotchKit DynamicNotchStyle.swift y BlurModifier.swift | Kai Azim | cd0b3e5 | 2026-10-02 | medium |
| 15 | Spec 16f, grabacion de Karen medida cuadro a cuadro | Companion | 2026-09-25 | 2026-10-02 | high |
| 16 | Briefs incredible-fn-glow-pointer, incredible-ui-detalle, incredible-isla-componentes, incredible-componentes | Companion (extraccion previa de 0.2.36) | 2026-09-25 a 2026-10-01 | 2026-10-02 | medium |
| 17 | Lectura del bundle de Incredible 0.2.36 (evidencia) | este brief | 2026-10-02 | 2026-10-02 | high |
