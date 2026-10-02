# Reference Brief: motion y microinteracciones de la isla de Incredible frente a Companion

Slug: isla-motion-incredible | Nivel: standard | Fecha: 2026-10-02 | Estado: ESCALADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 ESCALATE

## 1. Pregunta y decisiones abiertas

Pregunta: que animaciones y microinteracciones tiene la isla (notch) de Incredible 0.2.36, con disparador, propiedad, duracion, retardo, curva y coreografia; cuales tiene hoy la isla de Companion; y como se expresan las curvas web en SwiftUI para pulir el motion de Companion hasta igualarlo.

Alcance: solo motion. Las medidas y el layout son del brief hermano `isla-maquetacion-incredible`; las reglas de cuando se abre, se cierra y se auto-descarta la isla son de `isla-ciclo-y-legibilidad`. El glow de fn y el puntero se reutilizan de `incredible-fn-glow-pointer.md`, sin reabrirlos.

Evidencia (segunda pasada, 2026-10-02): el front de Incredible 0.2.36 se leyo de primera mano en la referencia de front que Karen nombro para replicar. Politica de Karen (2026-10-02): los extractos de binarios (valores, offsets, selectores, cadenas, hashes, nombres internos) no se publican en el repo. Este brief describe las brechas en palabras y apunta a la copia completa con valores, que vive solo en disco local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]. Los valores de segunda mano se contrastaron con esa lectura (seccion 2, "Contraste"): cuatro difieren.

Directiva aplicada (relayada por el coordinador el 2026-10-02, no leida de primera mano): Incredible es el piso minimo; donde su motion choca con una decision firmada o un token de Companion, la recomendacion es igualar a Incredible y el choque se lista aqui como decision de Karen, con la regla y su archivo:linea.

Decisiones para Karen:

- D1. Curvas por rol en vez de una sola curva de entrada. Incredible usa cinco curvas con nombre segun el rol: standard (fundidos, tooltip, cerrar), settle (menus, tarjetas, palabras), glide (bloques, campo), bounce (chips, notas, contenido que cae) e island (la forma al abrir y el cambio de cabecera); los puntos de control estan en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]. Choca con la regla M3 "una curva de entrada" (`docs/specs/wave-16f-notch-y-motion.md:169`) y con `testOneEnterCurve` (`Tests/CompanionUITests/MotionBudgetTests.swift:24`). La regla `soft-easing` (`conformance/ui-contract.json:47`) no se toca: las curvas viven en `MotionCurve` (`Sources/CompanionUI/DesignSystem/Motion.swift:27`). Recomendado: igualar y reescribir M3 como "cada rol, su curva de MotionCurve".
- D2. Rebote en chips y notas. Incredible entra con la curva bounce, que sobrepasa de forma visible (mucho mas que el 2 %), los chips de captura, las notas de la linea de voz y el carrete; duraciones en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]. Choca con M4 "sobrepaso de 2 % como maximo" (`docs/specs/wave-16f-notch-y-motion.md:170`) y `testSpringsBarelyOvershoot` (`Tests/CompanionUITests/MotionBudgetTests.swift:29`). Recomendado: igualar, como excepcion nombrada igual que `MotionSpring.lively` (`Sources/CompanionUI/DesignSystem/Motion.swift:82`).
- D3. Tooltips. Incredible tiene dos: el de la isla, solo opacidad, sin espera; y el del orb, con un pequeno desplazamiento en Y, que espera al entrar y sale sin espera (tiempos en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]). Companion usa uno para todo: espera 80 ms, entra en 150 y sale en 50 con glide (`Sources/CompanionUI/Island/IslandMotion.swift:166`), fijado por M2 (`docs/specs/wave-16f-notch-y-motion.md:168`). Recomendado: igualar los dos.
- D4. Menu y popovers. Incredible anima el menu con fundido mas un desplazamiento corto en Y, el popover de pila con salida mas rapida que la entrada, y el popup rico con desplazamiento y una escala apenas menor que 1 (valores en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]). Companion: escala desde 0,97, 250 y 150 ms con glide (`Sources/CompanionUI/Island/IslandMotion.swift:165`). Recomendado: igualar.
- D5. Contenido al abrir y cerrar. En Incredible el contenido entra con un fundido tras un breve retardo, escalonado por slot; sale sin retardo, a la vez que la forma se recoge. Los fundidos de unos 40 y 35 ms de la grabacion de Karen eran lectura de cuadros, no el valor real de Incredible (`docs/specs/wave-16f-notch-y-motion.md:83`); el valor real esta en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]. Companion ya entra en 130 ms (`Sources/CompanionUI/Island/IslandMotion.swift:133`) pero sale en 80 ms (`Sources/CompanionUI/Island/IslandMotion.swift:51`): sale mas rapido que Incredible. Recomendado: igualar la salida, usar el fundido `ease` y escalonar los slots con el paso de la referencia local. D5b: la forma en CSS es una sola curva con la curva island, y su sobrepaso coincide con el que midio la grabacion; Companion usa dos resortes medidos. Recomendado: conservar los resortes (igualan la grabacion y conservan velocidad al interrumpirse) salvo que Karen pida la curva literal.
- D6. El peek de NotchNook (`Sources/CompanionUI/DesignSystem/Motion.swift:76`) sobrepasa ~6,8 %. Incredible no hace peek: al posar el puntero en reposo enciende un haz que gira de forma lineal y aparece con un fundido (tiempos en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]). Recomendado: agregar el haz; Karen decide si el peek se queda ademas.
- D7. Palabras de la respuesta. Incredible pinta lo no dicho mas tenue y lo dicho casi pleno, con un cambio de color suave por palabra (niveles y tiempo en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]). Companion pinta lo no dicho al 62 % (`Sources/CompanionUI/Island/IslandPieces.swift:31`) con 150 ms. Recomendado: usar los niveles y la curva settle de la referencia local.
- D8. Cuenta atras. Incredible llena el anillo (de vacio a lleno) de forma lineal durante varios segundos y lo pausa con el puntero encima. Companion lo vacia, sin pausa, y la hoja de aprobacion avanza a 1 Hz (`Sources/CompanionUI/Voice/ApprovalSheet.swift:100`). Recomendado: llenar, pausar al pasar el puntero, trim continuo; duracion en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456].
- D9 (acotada). Lo que sigue sin dato vive en JS, no en CSS: plazos de hover (espera y salida), ritmo de palabras frente a la voz, barras de escucha (no hay en la isla), giro de los huecos de tarea, salida de las tarjetas y la secuencia en dos fases al abrir. Pedido: autorizar leer el JS del front de Incredible para esas constantes o grabar esos estados a 120 fps.
- D10 (nueva). Contenido que cae con rebote. Al abrir, el campo y la conversacion bajan desde arriba con la curva bounce; distancia y duracion en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]. Companion sube 4 pt desde abajo sin rebote. Choca con M4 ("el texto nunca rebota", `docs/specs/wave-16f-notch-y-motion.md:170`) y M5 (desplazamiento de 12 como maximo, `Tests/CompanionUITests/MotionBudgetTests.swift:56`). Recomendado: igualar.
- D11 (nueva). Presion de botones. Incredible encoge el icono con una escala y un tiempo cortos, sin cambio de opacidad (valores en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]). Companion: 0,98 y 85 % de opacidad con resorte 0,25/0,9 (`Sources/CompanionUI/DesignSystem/Pressable.swift:5`). Recomendado: igualar en la isla.
- D12 (nueva). Reducir movimiento. Incredible pone todo a 0 ms (cambio instantaneo); Companion hace fundidos de 150 ms como maximo (M8, `docs/specs/wave-16f-notch-y-motion.md:174`). Companion no queda por debajo del piso (WCAG no cuenta la opacidad como motion). Recomendado: conservar el fundido; Karen decide.

## 2. Estado actual

- Los tokens de tiempo de Companion son `MotionTime`: fast 0,15, base 0,2, panel 0,3, enter 0,6, layout 0,9 y follow 0,08 [repo:Sources/CompanionUI/DesignSystem/Motion.swift:8]
- Cuatro curvas de Incredible ya estan declaradas como tokens: standard, settle, glide y bounce; falta island [repo:Sources/CompanionUI/DesignSystem/Motion.swift:27]
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
- Los valores de forma de Incredible salen tambien de la grabacion de Karen a 120 fps medida cuadro a cuadro [repo:docs/specs/wave-16f-notch-y-motion.md:65]
- La comparacion de la grabacion de Companion contra la de Incredible (±40 ms) sigue pendiente [repo:docs/specs/wave-16f-notch-y-motion.md:132]
- Los valores de motion de Incredible 0.2.36 (tiempos, curvas, retardos, distancias, niveles) viven solo en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]; este brief no los publica
Contextos: app instalada (`/Applications/Companion.app`, build release, pantallas de 60 y 120 Hz), `swift test` (CompanionUITests: MotionBudgetTests y ControlTests prueban tokens y funciones puras sin ventana), gates (`scripts/gates.sh` y uiConformanceTests aplican `conformance/ui-contract.json` por grep sobre las vistas), espejo de autoinspeccion (pinta el estado, no los cuadros)

### Inventario de motion

| # | Momento | Incredible (valor) | Companion hoy | Brecha |
|---|---|---|---|---|
| 1 | Abrir fase 1, notch a pildora (tamano) | grabacion de Karen: tramo corto sin rebote [repo:docs/specs/wave-16f-notch-y-motion.md:70]; CSS: una sola curva con la curva island (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | `islandPill` 0,14/1,0 sin retardo [repo:Sources/CompanionUI/Island/IslandMotion.swift:61] | D5b; falta la grabacion comparada [repo:docs/specs/wave-16f-notch-y-motion.md:132] |
| 2 | Pausa y fase 2, pildora a panel (tamano) | grabacion de Karen: segundo tramo con sobrepaso leve [repo:docs/specs/wave-16f-notch-y-motion.md:72]; la curva island sobrepasa algo mas (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | 0,16 s y `islandPanel` 0,18/0,82, sobrepaso 1,1 % [repo:Sources/CompanionUI/Island/IslandMotion.swift:46] [repo:Tests/CompanionUITests/MotionBudgetTests.swift:34] | Companion sobrepasa un poco menos |
| 3 | Crecer o encoger con la isla abierta (tamano) | crecer con el mismo morph; encoger con curva standard y sin rebote (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | resorte de fase 2 en ambos sentidos [repo:Sources/CompanionUI/Island/IslandView.swift:173] | Encoger sin rebote en Incredible |
| 4 | Contenido entra (opacidad, Y) | fundido `ease` tras un retardo, escalonado por slot; campo y conversacion caen con bounce (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | a 0,20 s, 130 ms glide, desenfoque 3, sube 4 pt [repo:Sources/CompanionUI/Island/IslandMotion.swift:133] [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:91] | D5 y D10 |
| 5 | Cerrar (opacidad y tamano) | contenido sale sin retardo a la vez que la forma, que se recoge con curva standard (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | contenido 80 ms a la vez que la forma con 0,18/1,0 [repo:Sources/CompanionUI/Island/IslandMotion.swift:51] [repo:Sources/CompanionUI/Island/IslandMotion.swift:64] | El contenido de Companion sale mas rapido (D5) |
| 6 | Radio de esquina | interpolado por el mismo morph del clip (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | 10 a 22 por umbral, interpolado por `animatableData` [repo:Sources/CompanionUI/Island/IslandMotionViews.swift:70] [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:37] | Valores de radio en `isla-maquetacion-incredible` |
| 7 | Hover in en reposo | un haz que gira de forma lineal y aparece con fundido; sin peek (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | peek 0,35/0,65 y la sesion se entera a los 150 ms [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:46] [repo:Sources/CompanionUI/Island/IslandChrome.swift:344] | D6 |
| 8 | Hover out | los plazos viven en JS y no se encontraron en CSS | 150 ms de gracia [repo:Sources/CompanionUI/Island/IslandChrome.swift:352] | D9 |
| 9 | Hairline y rim (opacidad) | hairline con fundido al abrir; rim en cue con un barrido (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | hairline `resting ? 0 : 1` sin animacion propia; sin rim [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:23] | Falta el fundido y el rim |
| 10 | Senal de tarea bloqueada o hecha | bloqueada: pulso alternado; hecha: un destello unico con desenfoque (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | punto `IslandLight` con escala 0,4 y `success` 0,35/0,8 [repo:Sources/CompanionUI/Island/IslandPieces.swift:61] [repo:Sources/CompanionUI/Island/IslandPieces.swift:67] | Halo animado frente a punto |
| 11 | Tooltip (opacidad) | isla: solo opacidad y sin espera; orb: glide con espera al entrar (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | espera 80 ms, 150 entra, 50 sale, glide [repo:Sources/CompanionUI/Island/IslandMotion.swift:166] [repo:Sources/CompanionUI/Island/IslandPopover.swift:167] | D3 |
| 12 | Menu del header (opacidad, Y) | fundido con desplazamiento corto en Y y curva settle (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | escala 0,97, 250 y 150 ms glide [repo:Sources/CompanionUI/Island/IslandPopover.swift:60] | D4 |
| 13 | Item de menu en hover (fondo) | transicion corta de fondo con curva settle (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | el menu del campo es nativo de macOS [repo:docs/specs/wave-16f-notch-y-motion.md:245] | Solo menus propios |
| 14 | Popover de pila y popup rico (opacidad, Y, escala) | salida mas rapida y lineal en la pila; el popup rico suma desplazamiento y escala leve (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | popover de 250 ms [repo:Sources/CompanionUI/Island/Data/IslandView+Answer.swift:69] | D4 |
| 15 | Cambio de estado en la cabecera (Y, opacidad, desenfoque) | lo nuevo entra desde abajo con la curva island y desenfoque que se disuelve; lo viejo sale hacia arriba con curva standard (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | text swap 150 ms, desenfoque 2, 4 pt [repo:Sources/CompanionUI/Island/IslandMotion.swift:135] [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:42] | Recorrido y tiempos distintos |
| 16 | Pensando (shimmer) | degradado de tinta que sube y baja, lineal e infinito (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | mascara lineal de 1,5 s, espera 0,25 s, 15 % a 100 % [repo:Sources/CompanionUI/DesignSystem/Shimmer.swift:35] [repo:Sources/CompanionUI/DesignSystem/Shimmer.swift:59] | Periodo y rango de tinta distintos; la spec decia otro periodo [repo:docs/specs/wave-16f-notch-y-motion.md:189] |
| 17 | Escucha (nivel) | el orb escala segun el nivel con ease-out corto; no hay barras en la isla (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | 5 barras, expoOut 80 ms; orb que escala por nivel [repo:Sources/CompanionUI/Island/IslandPieces.swift:96] [repo:Sources/CompanionUI/Orb/Orb.swift:38] | Ganancia y tiempo del orb |
| 18 | Hablando, parar (opacidad) | mientras habla, al pasar el puntero el orb muestra una cara roja de parar con fundido (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | el orb se cambia por el boton de parar en 200 ms desde escala 0,25 [repo:Sources/CompanionUI/Island/IslandMotion.swift:168] [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:132] | Incredible solo funde, y solo con hover |
| 19 | Transcripcion (color, opacidad) | tinta tenue; color, opacidad y transform con curvas settle y standard (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | 72 % viva, 94 % fija, 150 ms glide [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:36] [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:76] | Curvas y tiempos |
| 20 | Palabras de la respuesta (color por palabra) | no dicha mas tenue, dicha casi plena, con curva settle; palabras nuevas entran con un desplazamiento corto (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]); captura de Karen: grises que se aclaran [KAREN:docs/specs/wave-16f-notch-y-motion.md:97] | 62 %, 3 palabras por segundo, 150 ms [repo:Sources/CompanionUI/Island/IslandMotion.swift:97] [repo:Sources/CompanionUI/Island/IslandPieces.swift:31] | D7 |
| 21 | Presion de botones (escala) | el icono se encoge con ease-out corto (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | 0,98 y 85 % con resorte [repo:Sources/CompanionUI/DesignSystem/Pressable.swift:5]; chips sin transicion [repo:Sources/CompanionUI/DesignSystem/SharedControls.swift:73] | D11 |
| 22 | Botones de tarjeta | fondo y transform con transicion corta (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | chip "Detener" sin animacion de presion [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:53] | Falta |
| 23 | Chips de captura con fn | entran con bounce desde abajo y escala chica; salen con curva de salida hacia el mismo punto (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | no existen; chips de referencia sin transicion [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:87] | D2 |
| 24 | Pildora y orb del hold | escala y opacidad con curva standard (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | el orb del puntero aparece de golpe [repo:Sources/CompanionUI/Overlay/ScreenOverlay.swift:80] | Falta la transicion |
| 25 | Rastro de tinta | constantes ya recogidas en `incredible-fn-glow-pointer.md` [repo:docs/research/incredible-fn-glow-pointer.md:95] | mismas constantes por tick del TimelineView [repo:Sources/CompanionUI/Overlay/PointerTrail.swift:42] | Tasa de cuadro (seccion 9) |
| 26 | Glow de pantalla | subida y bajada lineales, ya recogidas en `incredible-fn-glow-pointer.md` [repo:docs/research/incredible-fn-glow-pointer.md:49] | mismas duraciones con standard [repo:Sources/CompanionUI/Overlay/ScreenOverlay.swift:108] | Lineal frente a standard |
| 27 | Cuenta atras (trim) | el anillo se llena lineal y se pausa con el puntero encima (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | se vacia a 15 fps en 6 s, sin pausa [repo:Sources/CompanionUI/Island/Notices/IslandNoticeCard.swift:112] [repo:Sources/CompanionCore/Session/SessionMachine.swift:26] | D8 |
| 28 | Auto-cierre | la cuenta atras dura un plazo configurable por defecto (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | recibo 8 s, hecho 1,5 s, cancelado 2 s, dictado 12 s [repo:Sources/CompanionCore/Session/SessionMachine+Jobs.swift:11] [repo:Sources/CompanionCore/Session/SessionMachine.swift:11] | Plazos en `isla-ciclo-y-legibilidad` |
| 29 | Tarjeta de recibo o aviso, entrada y salida | la tarjeta entra con curva settle, desplazamiento y escala leves; sin salida en CSS; las notas entran con bounce (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | sin transicion propia [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:11] | Falta la entrada |
| 30 | Hoja o tarjeta de aprobacion | entra como la tarjeta, con settle, desplazamiento y escala leves (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | 300 ms glide, desenfoque 2, 8 pt; sale con fundido [repo:Sources/CompanionUI/Island/IslandMotion.swift:139] [repo:Sources/CompanionUI/Island/IslandMotionViews.swift:36] | Curva, tiempo, escala en vez de desenfoque |
| 31 | Error | el destello rojo era la cara de parar del orb; los avisos llegan como notas o tarjetas (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | `IslandNoticeCard` sin transicion propia [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:18] | Falta la entrada |
| 32 | Tarjetas y bloques de resultado | bloques con glide, desplazamiento corto y escalonado fino por indice (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | 450 ms, desenfoque 3, 12 pt, 40 ms, maximo 5 [repo:Sources/CompanionUI/Island/IslandMotion.swift:137] [repo:Sources/CompanionUI/Island/IslandMotion.swift:171] | Companion es mas lento y usa desenfoque; Incredible no |
| 33 | Trabajo en curso | punto que respira; isla calentando con un pulso suave; el giro de huecos no esta en CSS (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | giro lineal de 1,2 s [repo:Sources/CompanionUI/Island/IslandPieces.swift:222] | Falta el pulso de arranque |
| 34 | Reducir movimiento | todos los tiempos de la isla a 0 ms y sin caida; shimmer estatico; palabras, tarjetas y chips sin animacion (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]) | fundido de 150 ms como maximo, sin desenfoque ni desplazamiento [repo:Sources/CompanionUI/Island/IslandMotion.swift:58] [repo:Sources/CompanionUI/Island/IslandMotion.swift:123]; la respuesta no lee reduceMotion [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:86] | D12 |

### Contraste de valores de segunda mano contra la lectura del front

- Tooltip, menu, popover de pila y pildora del hold: los valores de segunda mano coinciden con el CSS [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]
- Las cuatro curvas con nombre coinciden; ademas existen island y push [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]
- DIFIERE: los chips de captura no salen hacia arriba como dice el brief previo; vuelven hacia abajo encogiendo [repo:docs/research/incredible-fn-glow-pointer.md:116]
- DIFIERE: el "destello rojo al detectar algo" es la cara de parar del orb mientras habla, con el puntero encima [repo:docs/research/incredible-ui-detalle.md:193]
- DIFIERE: el habla no se pinta como la transcripcion; lo no dicho y lo dicho tienen niveles propios [repo:docs/research/incredible-isla-componentes.md:39]
- DIFIERE: el fundido de contenido medido en la grabacion de Karen no es el del CSS, que es mas largo e igual en ambos sentidos [repo:docs/specs/wave-16f-notch-y-motion.md:83]
- Resuelto: el token de fundido de la isla, que el brief previo no tenia, queda en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]

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
- CSS Easing 1: `cubic-bezier(x1,y1,x2,y2)` exige x en [0,1] y permite y fuera de [0,1]; `ease` es (0.25,0.1,0.25,1), ease-out (0,0,0.58,1) y ease-in-out (0.42,0,0.58,1) [doc:https://www.w3.org/TR/css-easing-1/@CRD-2023-02-13]
- WCAG 2.3.3 (AAA): el motion disparado por interaccion se puede desactivar; cambios de color, desenfoque u opacidad que no alteran tamano, forma ni posicion no cuentan como motion [doc:https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html@2.2]

## 4. Implementaciones de referencia

- boring.notch (TheBoredTeam, ~10,9 k estrellas, push 2026-10-02, app de notch SwiftUI mas usada en GitHub): abre con `spring(response: 0.42, dampingFraction: 0.8)` y cierra con `spring(response: 0.45, dampingFraction: 1.0)`, sin rebote al cerrar [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/ContentView.swift#L123@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- boring.notch entra el contenido con escala 0,8 anclada arriba mas opacidad, 0,35 s [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/ContentView.swift#L354@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- boring.notch expresa una curva web en SwiftUI como `timingCurve(0.16, 1, 0.3, 1, duration: 0.7)` cuando no hay notch [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/animations/drop.swift#L19@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- DynamicNotchKit (Kai Azim, libreria SPM, 462 estrellas, push 2026-04-24): abrir `.bouncy(duration: 0.4)`, cerrar `.smooth(duration: 0.4)` y convertir entre tamanos `.snappy(duration: 0.4)` [ref:https://github.com/mrkai77/DynamicNotchKit/blob/cd0b3e52d537db115ad3a9d89601f20e0bee8d27/Sources/DynamicNotchKit/DynamicNotch/DynamicNotchStyle.swift#L66@cd0b3e52d537db115ad3a9d89601f20e0bee8d27]
- DynamicNotchKit define el desenfoque de entrada como un `AnyTransition.modifier` de blur, el mismo patron que `IslandMoveModifier` [ref:https://github.com/mrkai77/DynamicNotchKit/blob/cd0b3e52d537db115ad3a9d89601f20e0bee8d27/Sources/DynamicNotchKit/Utility/BlurModifier.swift#L30@cd0b3e52d537db115ad3a9d89601f20e0bee8d27]
- Las dos referencias coinciden con Incredible en lo esencial: abrir con algo de rebote y cerrar sin el; ninguna es el estandar de valores, que sigue siendo Incredible [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/ContentView.swift#L123@d58240cc160d5e54da1a8a5925e095d067a8e1e0]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Igualar a Incredible con los valores del CSS, curvas por rol, y medir en JS lo que falta (D9) | Cumple la directiva del piso minimo; valores de primera mano; reusa tokens existentes | Reabre M2, M3, M4 y M5 con sus tests; seis huecos esperan el JS | media | Recomendada |
| B. Mantener M1 a M8 y solo cerrar huecos propios (chips, orb, error, anillo) | Sin tocar decisiones firmadas | Deja tooltip, menu, palabras, caida y presion distintos: no alcanza el piso | baja | No |
| C. Portar tambien la forma como curva CSS literal | Identico al CSS | Pierde la velocidad al interrumpir y las dos fases que midio la grabacion | media | No, salvo D5b |

## 6. Evidencia en contra

- La forma en CSS es una curva, no un resorte; igualarla al pie de la letra rompe la continuidad al interrumpir un abrir con un cerrar [doc:https://developer.apple.com/videos/play/wwdc2023/10158/@WWDC23]
- Se resuelve conservando los resortes: el sobrepaso de la curva island ya es del orden del medido en la grabacion [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]
- M1 a M8 son decisiones firmadas con tests; la caida con rebote del contenido rompe M4 y M5 [repo:Tests/CompanionUITests/MotionBudgetTests.swift:56]
- Se acepta como decision de Karen (D10), por la directiva del piso minimo [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]
- El rebote visible en chips y notas puede marear; WCAG 2.3.3 pide poder desactivarlo, y Incredible lo apaga con reducir movimiento [doc:https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html@2.2]
- El CSS describe el estado, no la secuencia: la orden de que estado se pone y cuando la da el JS, sin leer todavia [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]

## 7. Ejemplares y anti-ejemplos

### Mapeo web a SwiftUI

| Web | SwiftUI | Fuente |
|---|---|---|
| `transition: X Ds cubic-bezier(a,b,c,d) Ls` | `.timingCurve(a, b, c, d, duration: D).delay(L)`, misma semantica de puntos de control [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/animation/timingcurve(_:_:_:_:duration:).json@macOS-26] | CSS Easing 1 [doc:https://www.w3.org/TR/css-easing-1/@CRD-2023-02-13] |
| `ease` y `ease-out` | `.timingCurve(0.25, 0.1, 0.25, 1, duration:)` y `.timingCurve(0, 0, 0.58, 1, duration:)` como tokens, nunca `.easeOut` (lo prohibe `soft-easing`) [repo:conformance/ui-contract.json:47] | [doc:https://www.w3.org/TR/css-easing-1/@CRD-2023-02-13] |
| `linear` | `.linear(duration:)`; bucles (shimmer, giro) con `TimelineView` o `repeatForever` [repo:Sources/CompanionUI/DesignSystem/Shimmer.swift:43] | [doc:https://www.w3.org/TR/css-easing-1/@CRD-2023-02-13] |
| resorte `stiffness k, damping c, mass m` | `Spring(mass: m, stiffness: k, damping: c)`; response = 2π·raiz(m/k), dampingFraction = c / (2·raiz(k·m)) [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring.json@macOS-26] | el ejemplo de Apple (100, 10 da 0,63 s y bounce 0,5) cuadra [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring.json@macOS-26] |
| `response r, dampingFraction z` | `spring(duration: r, bounce: 1 - z)` para z hasta 1 [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/animation/spring(duration:bounce:blendduration:).json@macOS-26] | [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring.json@macOS-26] |
| `@keyframes` con pasos (completed 0, 30 %, 100 %) | `keyframeAnimator` con `LinearKeyframe` o `CubicKeyframe` por pista [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/keyframeanimator(initialvalue:repeating:content:keyframes:).json@macOS-26] | macOS 14+, el proyecto apunta a macOS 26 [repo:Package.swift:9] |
| `animation: X infinite alternate` (bloqueada, respirar) | `phaseAnimator` entre dos fases [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/phaseanimator(_:content:animation:).json@macOS-26] | [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/phaseanimator(_:content:animation:).json@macOS-26] |
| `transition-delay` escalonado por slot | `.delay(base + i · paso)` sobre el token [repo:Sources/CompanionUI/Island/IslandMotionViews.swift:52] | paso y base en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `@media (prefers-reduced-motion)` | `@Environment(\.accessibilityReduceMotion)` [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/environmentvalues/accessibilityreducemotion.json@macOS-26] | [doc:https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html@2.2] |

### Tokens recomendados (opcion A)

| Token | Valor | SwiftUI | Origen |
|---|---|---|---|
| `MotionCurve.standard`, `.settle`, `.glide`, `.bounce` (ya existen) | por rol, ver D1 | `MotionCurve.animation(c, d)` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `MotionCurve.island` (nuevo) | para el cambio de cabecera y la forma | `MotionCurve.animation(.island, d)` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `MotionCurve.ease` y `.easeOutCSS` (nuevos) | (.25, .1, .25, 1) y (0, 0, .58, 1) | `.timingCurve` | [doc:https://www.w3.org/TR/css-easing-1/@CRD-2023-02-13] |
| `MotionCurve.exit` (nuevo) | curva de salida de los chips | `.timingCurve` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `IslandMotionBudget.contentIn` | fundido `ease`, retardo y paso por slot | `.delay` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `IslandMotionBudget.contentOut` | fundido `ease`, sin retardo, a la vez que la forma | `.opacity` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `IslandMotionBudget.momentum` (nuevo, D10) | caida con `MotionCurve.bounce` | offset | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| Resortes de la forma | sin cambio (D5b); encoger abierto: curva standard | `MotionSpring` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `IslandMotionBudget.headerSwap` | entra con island, sale con standard, desenfoque | `.asymmetric` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `ShimmerMotion` de pensando | lineal, rango de tinta propio | `TimelineView` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `IslandReveal` | niveles de no dicha y dicha, curva settle; entrada de palabra con desplazamiento corto | color por palabra | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `OrbLevel` | escala por nivel con ease-out corto | `.scaleEffect` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `IslandMotionBudget.tooltip` y `.orbTip` | isla sin espera; orb con glide y espera al entrar | `.opacity` y offset | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `PressMotion.island` | escala y tiempo cortos | `.scaleEffect` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `IslandMotionBudget.card` | settle, desplazamiento y escala leves | `.asymmetric` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `IslandMotionBudget.block` | glide, desplazamiento corto, escalonado fino | `.delay(i · paso)` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `IslandMotionBudget.menu` y `.popover` | menu, pila y popup rico con settle; salida de pila lineal | `.asymmetric` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `CollectChip` y `NoticeChip` | chip con bounce y salida con `MotionCurve.exit`; nota con bounce | `.asymmetric` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `Countdown` | llenar lineal, pausa con hover | `TimelineView` con reloj pausable | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |
| `TaskSignal` | bloqueada alternada con settle; hecha una sola vez | `phaseAnimator` y `keyframeAnimator` | valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456] |

### Ejemplares y anti-ejemplos

- Bien: la forma con resortes medidos de la grabacion y el contenido despues, como esta hoy [repo:Sources/CompanionUI/Island/IslandMotion.swift:56]
- Bien: los numeros viven en un archivo de tokens exento y las vistas solo los aplican [repo:Sources/CompanionUI/Island/IslandMotionViews.swift:4]
- Bien: Incredible declara cada tiempo de la isla como variable y los pone todos a 0 con reducir movimiento en un solo bloque [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]
- Bien: cerrar sin rebote, igual que boring.notch con dampingFraction 1,0 [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/ContentView.swift#L123@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- Anti-ejemplo: un anillo que avanza una vez por segundo es un salto visible [repo:Sources/CompanionUI/Voice/ApprovalSheet.swift:100]
- Anti-ejemplo: un chip que cambia de relleno sin transicion al presionarse [repo:Sources/CompanionUI/DesignSystem/SharedControls.swift:73]
- Anti-ejemplo: `.snappy` y `.bouncy` en las vistas, como DynamicNotchKit; aqui los prohibe `soft-easing` [ref:https://github.com/mrkai77/DynamicNotchKit/blob/cd0b3e52d537db115ad3a9d89601f20e0bee8d27/Sources/DynamicNotchKit/DynamicNotch/DynamicNotchStyle.swift#L66@cd0b3e52d537db115ad3a9d89601f20e0bee8d27]

## 8. Trampas

- Una curva `timingCurve` interrumpida a medio camino arranca desde velocidad cero y da un tiron; lo que se interrumpe (forma, peek) va en resortes [doc:https://developer.apple.com/videos/play/wwdc2023/10158/@WWDC23]
- `MotionSpring.all` excluye a `islandPeek`; un token nuevo con rebote debe ir a la lista de excepciones o el test M4 falla [repo:Sources/CompanionUI/DesignSystem/Motion.swift:84]
- La regla `raw-duration` atrapa `duration: 0.2` en una vista: los tokens nuevos van en `Motion.swift` o `IslandMotion.swift` [repo:conformance/ui-contract.json:31]
- `ease` de CSS no es `.easeInOut` de SwiftUI: hay que declararlo con sus puntos, y `soft-easing` prohibe el atajo [repo:conformance/ui-contract.json:47]
- `Spring(mass:stiffness:damping:)` sin `allowOverDamping` convierte un sobreamortiguado en critico [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/spring/init(mass:stiffness:damping:allowoverdamping:).json@macOS-26]
- El closure de `keyframeAnimator` corre en cada cuadro: nada caro dentro (Markdown, layout del texto) [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/keyframeanimator(initialvalue:repeating:content:keyframes:).json@macOS-26]
- Los seguimientos por cuadro (0,3 y 0,16) se aplican en cada tick del TimelineView, asi que a 120 Hz convergen mas rapido que a 60 Hz [repo:Sources/CompanionUI/Overlay/PointerTrail.swift:88]
- La cuenta atras de Incredible llena el anillo; copiar solo el tiempo y dejar el anillo vaciandose invierte el significado [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]
- Contexto app: los resortes y TimelineView corren a la tasa de la pantalla; la verificacion de M7 es en Instruments sobre ProMotion [repo:docs/specs/wave-16f-notch-y-motion.md:173]
- Contexto `swift test`: MotionBudgetTests prueba los tokens, no las vistas; una vista que no lee reduceMotion pasa los tests igual [repo:Tests/CompanionUITests/MotionBudgetTests.swift:68]
- Contexto gates: el contrato es un grep; una curva que llega por `MotionCurve.animation` pasa aunque sea la equivocada para su rol [repo:conformance/ui-contract.json:47]
- Contexto espejo de autoinspeccion: pinta el estado, no los cuadros, asi que no sirve para medir motion [repo:Sources/CompanionUI/Island/IslandView.swift:183]
- La respuesta palabra a palabra no lee reduceMotion; es solo color, que WCAG no cuenta como motion, pero Incredible la apaga igual [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]

## 9. Incertidumbre

- La lectura del front de Incredible si se hizo; la primera pasada miro otra carpeta.
- ASSUMPTION: Incredible abre en dos fases (pildora y panel) porque el JS pone dos estados seguidos, y el CSS solo anima cada uno. prueba: leer en el JS del front donde se fija el estado de la ventana de la isla y con que espera.
- ASSUMPTION: los plazos de hover (espera al entrar, gracia al salir) estan en JS como constantes o timeouts. prueba: buscar los timeouts cercanos al estado de hover en reposo en el JS del front.
- ASSUMPTION: Incredible marca lo dicho al ritmo real de la voz (eventos de TTS) y no a una tasa fija. prueba: buscar en el JS quien marca la palabra como dicha y de que evento cuelga.
- ASSUMPTION: la salida de la tarjeta es un desmontaje sin animacion porque el CSS no declara salida. prueba: buscar en el JS una clase o atributo de salida para la tarjeta.
- ASSUMPTION: los huecos de tarea giran con un componente JS o SVG, no con CSS. prueba: buscar en el JS el elemento de los huecos de la cabecera.
- ASSUMPTION: los seguimientos por cuadro de Incredible se calibraron a 60 Hz. prueba: grabar el rastro en una pantalla de 120 Hz y comparar el arrastre con el de Companion.
- ASSUMPTION: `timingCurve` acepta y mayor que 1 y sobrepasa como en CSS. prueba: un test que muestree `UnitCurve.bezier` con puntos de control de y mayor que 1 en t = 0,55 y espere un valor mayor que 1.
- [NEEDS CLARIFICATION: D1 a D12 de la seccion 1, en especial D5b (resortes o curva literal), D10 (caida con rebote) y D12 (fundido o corte con reducir movimiento).]

## 10. Checklist de estandar

- [ ] Abrir: pildora 0,14/1,0 y panel a +160 ms con 0,18/0,82 (D5b), asentado en 400 ms como maximo, ±40 ms contra la grabacion [repo:docs/specs/wave-16f-notch-y-motion.md:132].
- [ ] Contenido: entra con fundido `ease` tras un retardo y escalonado por slot; sale sin retardo a la vez que la forma (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Cerrar: forma de vuelta al notch sin rebote; encoger con la isla abierta con curva standard (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Caida del campo y la conversacion con bounce (si se aprueba D10) (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Cabecera: lo nuevo entra con island y desenfoque que se disuelve; lo viejo sale con standard (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Tooltips: isla sin espera; orb con glide y espera al entrar y ninguna al salir (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Menu, popover de pila y popup rico con settle; salida de pila lineal (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Pensando: shimmer lineal con rango de tinta propio (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Palabras: no dichas y dichas con niveles propios y cambio settle (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Orb: escala por nivel con ease-out corto; mientras habla, cara de parar con fundido al pasar el puntero (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Presion en la isla: escala corta con ease-out (si se aprueba D11); botones de tarjeta con transicion corta (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Tarjetas (recibo, aviso, aprobacion) con settle, desplazamiento y escala leves; bloques de resultado con glide y escalonado fino (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Chips de captura y notas con bounce, salida con curva de salida al mismo punto (si se aprueba D2) (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Cuenta atras: el anillo se llena lineal, se pausa con el puntero, sin saltos de mas del 25 % del recorrido por cuadro.
- [ ] Senal de tarea: bloqueada pulsa alternada con settle; hecha una sola vez; haz de hover lineal con entrada suave (valor en la referencia local [ref:incredible-ref/briefs/isla-motion-incredible.md@daa2da996456]).
- [ ] Reducir movimiento: sin resorte, caida, escala, desenfoque ni desplazamiento; shimmer estatico; fundido de 150 ms como maximo o corte segun D12; test por token.
- [ ] Ninguna duracion ni curva literal en las vistas: todo pasa `raw-duration` y `soft-easing`.
- [ ] Los seis huecos de D9 se cierran leyendo el JS o grabando antes de tocar su motion.

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
| 16 | Briefs incredible-fn-glow-pointer, incredible-ui-detalle, incredible-isla-componentes, incredible-componentes | Companion (segunda mano) | 2026-09-25 a 2026-10-01 | 2026-10-02 | medium |
| 17 | Referencia local con los valores de Incredible 0.2.36 (no publicada en el repo) | Karen, disco local | 2026-10-02 | 2026-10-02 | high |
