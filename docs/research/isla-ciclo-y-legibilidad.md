# Reference Brief: ciclo de vida y legibilidad de la isla (que abre, que cierra, la cuenta atras, el texto largo y los elementos vacios), contra Incredible 0.2.36

Slug: isla-ciclo-y-legibilidad | Nivel: standard | Fecha: 2026-10-02 | Estado: ESCALADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 ESCALATE

Origen: Karen probo la app de release el 2026-10-02 y mando cinco capturas (karen-ui-2026-10-02: 1-no-puede-escribir, 2-pensando-barra-vacia, 3-chips-vacios, 4-texto-cortado, 5-ventana-chat). Directiva del mismo dia: Incredible es el minimo de Companion; donde Incredible difiere de una regla firmada, se recomienda igualarlo y el choque va como decision de Karen. Se replica el comportamiento, nunca el codigo.

Alcance: este brief decide QUE abre y cierra la isla, CUANDO corre y se reinicia la cuenta atras, si el texto largo se corta o se desplaza y DONDE aplica el tope de alto. Las medidas exactas en pixeles (anchos, alto de cada tamano, zonas near/commit, rejilla) son de `isla-maquetacion-incredible`; las curvas, duraciones de animacion y keyframes son de `isla-motion-incredible`. Los numeros de Companion se quedan con su evidencia, y el tope de texto se alinea con el D4 de `isla-maquetacion-incredible`.

Evidencia de Incredible de esta corrida: los valores extraidos del binario no se publican en este repo; viven en la referencia local, citada como [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]. Se reusan sin rehacer: `incredible-isla-componentes.md`, `incredible-ui-detalle.md`, `incredible-componentes.md`, `ux-incredible-vs-companion.md`, `audit-ui-companion-vs-incredible.md` y `ajuste-en-la-isla.md`.

## 1. Pregunta y decisiones abiertas

Pregunta: por que la isla muestra elementos vacios (barra bajo "Pensando"/"Hablando", chip vacio junto a "Notes", circulos punteados), corta el texto con "…" y no se cierra nunca; que hace Incredible 0.2.36 en cada caso; y que reglas medibles adopta Companion para A-E.

Hallazgo que cambia la lectura de la captura 5: no es la ventana principal, es la isla en tamano `.nudge` (panel de hover). Lo prueban la cabecera (altavoz y "…"), los tres circulos, el campo "Pidele algo a Companion…", la tarjeta MD de un adjunto aun no enviado y las tarjetas "Ver →", piezas que solo existen en `IslandView` (seccion 2).

Decisiones para Karen. En cada una, la recomendacion es igualar a Incredible; donde eso choca con una regla firmada se nombra la regla y los tests que la fijan (cambian en el mismo PR).

- K1. Modelo de abrir y cerrar. Recomendado: igualar a Incredible (local reference): abre por actividad, interaccion o hover; cerrado en todo lo demas; asentamiento breve al terminar la respuesta, pausado por hover y con un piso al salir el puntero (valores en la referencia local). Choca con el valor actual de Companion, `SessionMachine.completedDelay = 1.5` (Sources/CompanionCore/Session/SessionMachine.swift:11), que hoy deja "Listo" 1,5 s sin importar el puntero. Tests que lo fijan: SessionMachineTests.swift:152 y :426, Island16m4Tests.swift:46 e Island16m4ReviewTests.swift:28 (los cuatro esperan `scheduleCompletedExpiry(completedDelay)`).
- K2. Trabajo de fondo. Recomendado: un encargo corriendo sin turno de la usuaria deja la isla en un estado chico de reposo con las ranuras de tareas (el `seed` de Incredible), no en tarjeta abierta. Choca con la tarjeta `.card` que hoy dura todo el encargo (Sources/CompanionCore/Island/IslandState.swift:261) y con la runcard/checklist de 16m-2 visibles sin hover.
- K3. Escucha en manos libres. Incredible mantiene la isla abierta mientras escucha (turno activo). Recomendado: igual. Si Karen quiere que se cierre tambien ahi, es una regla nueva sin referencia y necesita un plazo que ella firme.
- K4. Tarjetas con cuenta atras. Recomendado: el anillo y el reloj de la sesion se pausan con el puntero encima y siguen donde iban; la tarjeta de dictado baja de los 12 s actuales al plazo de Incredible (local reference). Choca con `dictationCardDelay = 12` (SessionMachine.swift:30, marcado "Not measured" en su comentario) y con avisos que hoy no se pausan. Tests que lo fijan: Island16m4Tests.swift:39 (exige dictado mas largo que Completed; hay que revisar si sigue valiendo con los plazos de Incredible, y cambia si Completed desaparece como constante) y :46.
- K5. Texto largo. Recomendado, alineado con el D4 de `isla-maquetacion-incredible`: la respuesta hablada entera hasta el tope de palabras de Incredible (descarta las primeras y refluye), todos sus parrafos, sin "…", dentro de una columna con el tope de alto de Incredible y desplazamiento vertical cuando no cabe. El tope de seguridad deja de ser 240/960 caracteres y pasa al de Incredible (local reference). Choca con el recorte a 240 caracteres y al primer parrafo de 16f ("The rest lives in the window", Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:36). Tests que lo fijan: NotchTests.swift:156; IslandCardsTests.swift:29-55 y ConversationQualityVoiceTests.swift:86-92 y :229-230 (CompanionIntegrationTests) llaman a `IslandReplyText.spoken` y esperan solo el primer parrafo o la cadena filtrada; hay que revisarlos uno por uno.
- K6. Tarjetas "Ver →". Recomendado: solo para respuestas que traen un resultado (tarjeta de datos, entregable), no una por cada respuesta pasada. Choca con 16c/16e "tarjetas de respuesta (3, Ver →)" (docs/specs/wave-16c-ux-como-incredible.md:89).
- K7. Circulos punteados. Recomendado: las tres ranuras solo mientras corre un encargo, como la banda de agentes de Incredible, que no se ve sin agentes. Choca con 16f, que los copio de una grabacion como fijos (docs/specs/wave-16f-notch-y-motion.md:88). Ningun test pinta `IslandSlots`; solo PrimitivesTests.swift:50 usa su medida `slotSide`.
- K8. Carrete de apps tocadas. Recomendado: un solo item a la vez (el ultimo), como el carrete de Incredible, y nunca un item vacio. Choca con la fila de chips de 16m-2. Tests que fijan `touched` y el chip (fix A1): Island16m2Tests.swift:85-130 (orden, reinicio por turno, tope de 12), IncredibleComponentsTests.swift:205-210 (fija `ReferentChipMetrics.maxWidth` = 230) y SelfInspectionTests.swift:80 y :506 (el espejo lee `touched`).
- K9. Linea de estado al actuar. Incredible pinta la linea de pensar tambien mientras ejecuta una herramienta y no nombra la app. Recomendado: "Pensando" como linea, y el nombre de la app pasa al item del carrete (K8), asi el dato no se pierde. Choca con la linea `.acting` que nombra el destino (Sources/CompanionUI/Island/IslandCopy.swift:23).
- K10. Etiqueta "Hablando". Recomendado: sin etiqueta cuando la isla ya muestra la frase que se dice; el orbe y la onda bastan. Choca con `island.speaking` que hoy se pinta junto a la onda.
- K11. Alto maximo abierto. El alto abierto maximo de Incredible (local reference) es mayor que el de Companion, que recorta hoy la forma a 592 (lienzo 620 menos 28 de sombra, Sources/CompanionUI/Island/IslandChrome.swift:51). Opciones: agrandar el lienzo para que quepa el alto de Incredible mas la sombra (recomendado), o dejar el lienzo y topar la columna en 592 menos la cabecera y el margen inferior. Las medidas finas son de `isla-maquetacion-incredible`.

No choca: la tarjeta de un ajuste (ajuste-en-la-isla) ya pide no contar con el puntero o el foco encima (docs/research/ajuste-en-la-isla.md:229), que es la misma regla de pausa de K4; su vida de 20 s no tiene equivalente en Incredible y se queda.

## 2. Estado actual

Contextos: app de release (IslandPanel, NSPanel no activante colgado del notch); swift test de CompanionCoreTests y CompanionUITests (IslandState y SessionMachine puros, NotchTests, IslandCardsTests, Island16m2Tests, Island16m4Tests, IncredibleComponentsTests, SelfInspectionTests); swift test de CompanionIntegrationTests (Island16m4ReviewTests, ConversationQualityVoiceTests); autoinspeccion por el puente (InspectionMirror pinta el IslandState que la vista dibujo); CI (los mismos tests); Island/ no tiene previews.

### A. Elementos vacios (capturas 1-3)

- `ParentTool.target` devuelve cadena vacia cuando la herramienta no tiene argumento que nombrar [repo:Sources/CompanionCore/Tools/ParentTools.swift:106]
- typeText, readFocused, pressKey y focusWindow no tienen clave de destino a proposito, para no mostrar lo que se escribe en otra app [repo:Sources/CompanionCore/Tools/ParentTools.swift:120]
- look, click, scroll, menu y see tampoco tienen clave de destino [repo:Sources/CompanionCore/Tools/ParentTools.swift:122]
- El turno escrito manda esos destinos tal cual, vacios incluidos [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:184]
- El reductor agrega cada destino a `touched` sin filtrar la cadena vacia [repo:Sources/CompanionCore/Session/SessionMachine.swift:98]
- La isla pinta el carrete siempre que `touched` no este vacio, aunque su unico item sea "" [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:72]
- El carrete pinta un `ReferentChip` por item [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:87]
- El chip tiene un marco de ancho maximo y el fondo va despues del marco [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:144]
- Ese maximo es 230 pt, el ancho de la barra vacia de la captura 2 (460 px a 2x) [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:45]
- Un test fija ese maximo de 230 como medida de Incredible [repo:Tests/CompanionUITests/IncredibleComponentsTests.swift:208]
- Las tres ranuras punteadas se dibujan en todo tamano que no sea `.bar`, haya o no encargo; `active` solo decide si la primera gira [repo:Sources/CompanionUI/Island/IslandView.swift:283]
- Cada ranura es un circulo con trazo discontinuo 3/4 [repo:Sources/CompanionUI/Island/IslandPieces.swift:214]

### B. Texto cortado (capturas 4 y 5)

- La isla muestra solo el primer parrafo no vacio de la respuesta [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:46]
- El tope de lo que se pinta es 240 caracteres [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:38]
- Pasado el tope se corta y se agrega "…" (el "aquel p…" de la captura 4) [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:72]
- Antes de limpiar se corta a cuatro veces el tope para que el costo por token no dependa de la respuesta (revision de seguridad 16f) [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:49]
- Un test exige ese tope [repo:Tests/CompanionUITests/NotchTests.swift:156]
- Otros tests esperan solo el primer parrafo o la cadena filtrada de `IslandReplyText.spoken` [repo:Tests/CompanionUITests/IslandCardsTests.swift:29]
- Y en el target de integracion tambien [repo:Tests/CompanionIntegrationTests/ConversationQualityVoiceTests.swift:229]
- La transcripcion en vivo se limita a 2 lineas y corta por la cabeza [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:73]
- El titulo de cada tarjeta de resultado se corta a 60 caracteres con "…" [repo:Sources/CompanionCore/Island/IslandParts.swift:46]
- Y ademas a una linea en la vista [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:15]
- El cuerpo de la isla no tiene ScrollView: el contenido se mide a su alto ideal [repo:Sources/CompanionUI/Island/IslandView.swift:153]
- El alto de la forma se recorta al lienzo menos el espacio de sombra, 620 menos 28 = 592, menos que el alto abierto de Incredible [repo:Sources/CompanionUI/Island/IslandChrome.swift:51]
- El repo ya tiene el patron de abrazar el contenido y desplazar solo pasado el tope, en el popup de respuesta rica [repo:Sources/CompanionUI/Island/Data/AnswerBlockViews.swift:33]

### C. Ciclo de abrir y cerrar

- Cerrado hoy es `.pebble` (la forma del notch) o `.hidden`; con voz viva el pebble no se puede esconder [repo:Sources/CompanionCore/Island/IslandState.swift:242]
- Hover: el panel asoma al entrar y avisa a la sesion tras 0,15 s de permanencia [repo:Sources/CompanionUI/Island/IslandChrome.swift:344]
- Al salir, el hover termina 0,15 s despues [repo:Sources/CompanionUI/Island/IslandChrome.swift:352]
- El hover solo abre desde reposo: `hoverEntered` pasa de idle a hover [repo:Sources/CompanionCore/Session/SessionMachine.swift:144]
- Hover pinta `.nudge`, el panel con el campo [repo:Sources/CompanionCore/Island/IslandState.swift:150]
- Escribir mantiene `.nudge` sin puntero [repo:Sources/CompanionCore/Island/IslandState.swift:132]
- Escribir = foco en el campo, borrador, confirmacion de borrar, selector abierto o adjuntos en espera sin la ventana principal delante [repo:Sources/CompanionCore/Island/IslandAttach.swift:143]
- El adjunto en espera de la captura 5 se pinta en la bandeja del panel [repo:Sources/CompanionUI/Island/Attach/IslandView+Attach.swift:41]
- Escuchando pinta `.bar` con el medidor del microfono [repo:Sources/CompanionCore/Island/IslandState.swift:158]
- Hablando pinta `.bar` con el medidor de la voz [repo:Sources/CompanionCore/Island/IslandState.swift:257]
- Un encargo corriendo construye un estado `.card` que dura toda su vida [repo:Sources/CompanionCore/Island/IslandState.swift:261]
- Al terminar una pieza de trabajo, si la voz sigue escuchando sin silencio la isla vuelve a escuchar, no a reposo [repo:Sources/CompanionCore/Session/SessionMachine+Resting.swift:59]
- Si no, pasa a Completed y programa su vencimiento [repo:Sources/CompanionCore/Session/SessionMachine+Resting.swift:72]
- Completed dura 1,5 s [repo:Sources/CompanionCore/Session/SessionMachine.swift:11]
- Completed pinta `.bar` [repo:Sources/CompanionCore/Island/IslandState.swift:265]
- El evento de vencimiento es `case .completedTimerExpired` [repo:Sources/CompanionCore/Session/SessionMachine.swift:147]
- Su guarda: solo si la isla sigue en Completed pasa a idle (y borra el dictado); si otro turno ya empezo, el vencimiento no hace nada [repo:Sources/CompanionCore/Session/SessionMachine.swift:148]
- Cuatro tests fijan que terminar programa `scheduleCompletedExpiry(completedDelay)` [repo:Tests/CompanionCoreTests/SessionMachineTests.swift:152]
- El segundo en el mismo archivo [repo:Tests/CompanionCoreTests/SessionMachineTests.swift:426]
- El tercero, en el dictado [repo:Tests/CompanionUITests/Island16m4Tests.swift:46]
- El cuarto, al reves: que no se programe en un caso de revision [repo:Tests/CompanionIntegrationTests/Island16m4ReviewTests.swift:28]
- Un test exige que la tarjeta de dictado dure mas que Completed [repo:Tests/CompanionUITests/Island16m4Tests.swift:39]
- "No te oi" y la pista viven 6 s [repo:Sources/CompanionCore/Session/SessionMachine.swift:26]
- La tarjeta de dictado vive 12 s, sin medicion [repo:Sources/CompanionCore/Session/SessionMachine.swift:30]
- Con el puntero sobre la tarjeta de dictado el tope sube a 60 s; es la unica pausa por hover del codigo [repo:Sources/CompanionCore/Session/SessionMachine+Dictation.swift:23]
- Un aviso nuevo arma su propio reloj y cancela el anterior [repo:Sources/CompanionUI/Voice/SessionModel.swift:126]
- El anillo del aviso se vacia con el tiempo transcurrido, sin mirar el puntero [repo:Sources/CompanionUI/Island/Notices/IslandNoticeCard.swift:113]
- Una sesion de voz por hold cuelga a los 20 s de reposo [repo:Sources/CompanionCore/Session/SessionMachine.swift:22]
- Cada cambio de tamano queda en el log de la app con la palabra "island:" [repo:Sources/CompanionApp/CompanionMainWindow.swift:155]

### D. Ventana de la captura 5

- La cabecera del panel lleva altavoz y menu [repo:Sources/CompanionUI/Island/IslandHeaderControls.swift:10]
- El texto de la respuesta del panel es `IslandReply` [repo:Sources/CompanionUI/Island/IslandView.swift:329]
- Cada respuesta anterior, salvo la ultima, se pinta como tarjeta "Ver →" [repo:Sources/CompanionUI/Island/IslandView.swift:317]
- Hasta tres tarjetas [repo:Sources/CompanionUI/Island/IslandView.swift:65]
- El nombre del adjunto se corta a 2 lineas por el medio [repo:Sources/CompanionUI/Island/Attach/IslandAttachCards.swift:148]

### E. Proceso de escribir y actuar

- Mientras actua, la linea nombra los destinos [repo:Sources/CompanionUI/Island/IslandCopy.swift:23]
- Pendiente, pensando, actuando y pegando llevan brillo [repo:Sources/CompanionUI/Island/IslandCopy.swift:78]
- La respuesta se pinta en la barra mientras habla o al terminar con luz verde [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:89]
- Hablando se escribe "Hablando" junto a la onda [repo:Sources/CompanionUI/Island/IslandCopy.swift:24]
- La transcripcion ya usa las dos tintas medidas de Incredible (local reference) [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:36]

## 3. Fuentes primarias

- SwiftUI: con solo un maximo, si el padre propone mas de lo que mide la vista, el marco toma lo propuesto recortado al maximo; por eso un chip vacio con `maxWidth` se estira hasta 230 [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:).json@macOS26]
- SwiftUI: `defaultScrollAnchor` fija que parte del contenido se ve al inicio y como se recoloca cuando el contenido cambia de tamano; la usuaria puede desplazarse lejos de esa posicion; disponible desde macOS 14 [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/defaultscrollanchor(_:).json@macOS26]
- HIG, Live Activities: la presentacion expandida es una version agrandada de la compacta y debe expandirse de forma predecible [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json@HIG-2026]
- HIG, Live Activities: alertar solo por actualizaciones esenciales, y terminar la actividad en cuanto termina la tarea, con un tiempo de retiro propio [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json@HIG-2026]
- WCAG 2.2, 2.2.1: un limite de tiempo se puede apagar, ajustar o extender; el contenido con temporizador no necesita ser ajustable si hay otra via sin temporizador para llegar a la misma informacion [doc:https://www.w3.org/WAI/WCAG22/Understanding/timing-adjustable.html@WCAG2.2]

## 4. Implementaciones de referencia

- Incredible 0.2.36 (Norditech, la referencia que Karen fija como minimo): la isla tiene un conjunto cerrado de estados, de oculto a abierto [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible abre la isla por una lista cerrada de razones de actividad o interaccion (dictado, voz, menu, campo, envio, adjuntos en espera, puntero, turno activo); fuera de ella queda en reposo chico o cerrada [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible no abre la isla por trabajo de fondo: queda en reposo chico con las ranuras de tareas [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible sostiene la isla un plazo corto tras un envio escrito, o hasta que cambie el turno [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: al terminar la respuesta corre un asentamiento breve; el hover lo pausa y al salir queda un piso; con una tarjeta presente o expandida no corre; un turno nuevo lo cancela [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible abre por hover tras una permanencia corta, mas larga si el puntero va rapido, y baja de nivel con histeresis [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: las tarjetas con cuenta atras tienen plazos por tipo (pista y "no te oi", trabajo de fondo y uso, dictado, este el mas corto); el anillo es el boton de cerrar y el hover lo pausa y lo reanuda donde iba [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: la columna de la isla tiene tope de alto y sus ranuras de conversacion y de tarjeta se desplazan en vertical dentro del tope [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: el texto hablado se pinta sin clamp ni puntos suspensivos; guarda solo las ultimas palabras hasta un tope y el resto refluye [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: el alto abierto maximo es la suma de barra, columna y un margen [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: la transcripcion en vivo es una ventana de pocas lineas que desvanece el borde de arriba al desbordar [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible usa puntos suspensivos solo en metadatos de una linea; el nombre de un adjunto va a mas de una linea [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: ranuras de tareas, las vacias como circulos punteados; la banda de agentes no se ve ni recibe clics sin agentes [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: ejecutar una herramienta se pinta con la misma linea de pensar, sin nombrar la app [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: el carrete muestra un solo item y el cambio entra con retardo; el campo de estado se sostiene un minimo antes de cambiar [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Incredible: los resultados se apilan como tarjetas con acceso a verlos; la voz apunta a la tarjeta [repo:docs/research/ux-incredible-vs-companion.md:144]
- boring.notch (app de notch para macOS, unas 10,9k estrellas, push 2026-10-02, codigo abierto): abre tras un hover minimo y cierra 100 ms despues de que el puntero sale, salvo que un popover lo retenga [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/ContentView.swift#L513-L557@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- boring.notch: el hover minimo por defecto es 0,3 s [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/models/Constants.swift#L79@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- boring.notch: cada aviso nuevo cancela y rearma el temporizador de retiro, 1,5 s por defecto [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/BoringViewCoordinator.swift#L237-L259@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- Donde boring.notch e Incredible difieren (plazo de cierre y hover minimo), manda Incredible por la directiva relayada de que Incredible es el minimo de Companion, sobre el pedido firmado de replicar el notch y el motion de Incredible [repo:docs/specs/wave-16f-notch-y-motion.md:3]; boring.notch solo confirma el patron (dwell al entrar, gracia al salir, rearmar el retiro)

## 5. Opciones

A. Elementos vacios

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A1. Filtrar destinos vacios en el reductor, chip que abraza su texto, ranuras solo con encargo | Arregla la causa en el unico escritor de `touched`; cubre turno escrito, clasico y realtime de una vez | Revisar Island16m2Tests, IncredibleComponentsTests y SelfInspectionTests | baja | Si |
| A2. Esconder el chip vacio en la vista | Diff minimo | Deja `touched` con basura para el espejo de autoinspeccion y cualquier otro lector | baja | No |
| A3. Quitar carrete y ranuras | Nada vacio | Pierde la senal de que toca y de los encargos, que Incredible si tiene | baja | No |

B. Texto largo

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| B1. Respuesta entera hasta el tope de palabras de Incredible en una columna con tope de alto y desplazamiento vertical solo pasado el tope | Es lo de Incredible; el patron ya existe en el popup rico; el tope de palabras sigue acotando el costo | Cambiar NotchTests, IslandCardsTests y ConversationQualityVoiceTests; decidir K11 | media | Si |
| B2. Seguir cortando y que "Ver" abra la ventana | Sin cambio | Es la queja de Karen; Incredible no corta | baja | No |
| B3. Una frase por cuadro, como la linea de voz pasiva de Incredible | Sin desplazamiento | Incredible lo usa solo en modo pasivo; en la isla abierta pinta todo | media | No |

C. Abrir y cerrar

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| C1. Modelo de escena de Incredible: lista cerrada de razones para abrir; asentamiento corto con pausa por hover y piso; trabajo de fondo en reposo chico; tarjetas con anillo que se pausa | Medido; cada razon se puede probar en el reductor puro | Toca IslandState, SessionMachine y la vista; un tamano nuevo de reposo; cuatro tests de `completedDelay` | media | Si |
| C2. Mantener el modelo y bajar tiempos | Diff chico | No arregla el encargo que deja la tarjeta abierta ni la pausa por hover | baja | No |
| C3. Temporizador global de inactividad | Facil de explicar | No es lo de Incredible; cerraria una aprobacion o un campo con texto | baja | No |

D y E se resuelven con A, B y C mas las decisiones K6, K8, K9 y K10 (seccion 1).

## 6. Evidencia en contra

- Contra el asentamiento corto: la respuesta se iria casi al callar la voz; se acepta porque el hover la retiene y le da un piso al salir, y porque el hilo de la ventana es la via sin temporizador que WCAG pide para contenido que se retira solo [doc:https://www.w3.org/WAI/WCAG22/Understanding/timing-adjustable.html@WCAG2.2]
- La isla lee la respuesta del mismo hilo `chat.messages` que muestra la ventana, asi que lo que la isla retira no se pierde [repo:Sources/CompanionUI/Island/IslandView.swift:143]
- Contra el texto entero en el notch: Apple pide que la presentacion expandida sea una version agrandada y predecible de la compacta, no un lector; se resuelve con el tope de columna y desplazamiento, que es lo que hace Incredible [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json@HIG-2026]
- Contra quitar el tope de 240: el tope tambien acotaba el costo por token del texto del modelo; se resuelve con el tope de palabras de Incredible, aplicado antes de limpiar [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:49]
- Contra el alto de Incredible: no cabe en la forma de hoy, que se recorta a 592; se resuelve en K11 (agrandar el lienzo o topar la columna) [repo:Sources/CompanionUI/Island/IslandChrome.swift:51]
- Contra mandar el encargo a reposo chico: la usuaria deja de ver el progreso sin pedirlo; se acepta porque Incredible hace eso y porque el hover o un pedido de atencion lo vuelven a abrir [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Contra pausar avisos con el puntero: una tarjeta podria quedarse para siempre con el puntero encima; ya pasa con el dictado y se acoto con un tope de 60 s, que sirve de patron [repo:Sources/CompanionCore/Session/SessionMachine+Dictation.swift:11]
- Contra quitar los circulos: 16f los copio de una grabacion de Incredible, asi que Incredible si los tiene; se resuelve mostrandolos solo cuando Incredible muestra su banda, con agentes [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, en el repo: el popup abraza una respuesta corta y solo pasado el tope cambia a ScrollView con alto fijo; un ScrollView avido hacia que todo midiera el tope [repo:Sources/CompanionUI/Island/Data/AnswerBlockViews.swift:27]
- Bien hecho, en el repo: un aviso nuevo cancela el reloj del anterior y arma el suyo [repo:Sources/CompanionUI/Voice/SessionModel.swift:123]
- Bien hecho, fuera: boring.notch rearma el retiro en cada aviso nuevo y lo cancela al esconderse [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/BoringViewCoordinator.swift#L237-L259@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- Bien hecho, Incredible: la pausa reanuda donde iba y la salida del puntero garantiza un piso, en vez de reiniciar el reloj completo [ref:incredible-ref/briefs/isla-ciclo-y-legibilidad.md@f5b635381a94]
- Anti-ejemplo, en el repo: un chip con `maxWidth` y fondo detras del marco crece hasta el maximo aunque su texto este vacio [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:144]
- Anti-ejemplo, en el repo: el corte con "…" despues de quedarse con un solo parrafo [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:72]
- Anti-ejemplo, en el repo: ranuras de tareas dibujadas sin tareas [repo:Sources/CompanionUI/Island/IslandView.swift:283]

## 8. Trampas

- Un `.frame(maxWidth:)` no es un tope pasivo: con espacio de sobra el marco se estira; el chip tiene que medir su texto [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:).json@macOS26]
- El contenido de la isla se mide con `fixedSize` vertical; un ScrollView sin alto explicito dentro de eso no da el alto esperado, por eso el patron del repo fija el alto al tope [repo:Sources/CompanionUI/Island/IslandView.swift:153]
- La forma y el area de clics siguen el alto medido y se recortan a 592; con la columna de Incredible la forma pasaria de 592, y sin decidir K11 el fondo del texto queda fuera de la forma [repo:Sources/CompanionUI/Island/IslandChrome.swift:51]
- Filtrar en la vista y no en el reductor deja la cadena vacia en `touched`, que la autoinspeccion lee [repo:Sources/CompanionCore/Session/SessionMachine.swift:98]
- El reloj de la sesion y el anillo de la tarjeta son dos relojes: pausar solo el anillo deja que el aviso se vaya con el puntero encima [repo:Sources/CompanionUI/Voice/SessionModel.swift:126]
- Con reduce motion la cuenta atras debe vencer por tiempo, no por el fin de una animacion; hoy el anillo se calcula del tiempo transcurrido y asi debe seguir [repo:Sources/CompanionUI/Island/Notices/IslandNoticeCard.swift:113]
- El hover se sigue con monitores globales de mouseMoved; sin movimiento no llega evento, asi que la pausa se sostiene sola mientras el puntero no se mueva [repo:Sources/CompanionUI/Island/IslandChrome.swift:318]
- Un estado de reposo nuevo (el seed de K2) tiene que entrar en `IslandMotion.rests` o la forma lo trata como abierto [repo:Sources/CompanionUI/Island/IslandChrome.swift:50]
- Contexto app de release: el panel no activante pierde el foco cuando otra app toma el teclado, y eso ya baja `fieldFocused`; la regla de K1 depende de ese aviso [repo:Sources/CompanionUI/Island/IslandView.swift:224]
- Contexto swift test: IslandState y SessionMachine son puros; el asentamiento y la pausa deben vivir ahi como eventos (como `completedTimerExpired`) para probarse sin reloj de pared [repo:Sources/CompanionCore/Session/SessionMachine.swift:147]
- Contexto autoinspeccion: el espejo guarda el IslandState pintado; un tamano nuevo cambia lo que ven los agentes de QA por el puente [repo:Sources/CompanionUI/Inspection/SelfInspectionSource.swift:18]
- Contexto CI, K5: el tope de 240 lo fija NotchTests y cambia en el mismo PR [repo:Tests/CompanionUITests/NotchTests.swift:156]
- Contexto CI, K5: IslandCardsTests espera de `IslandReplyText.spoken` solo el texto filtrado del primer parrafo [repo:Tests/CompanionUITests/IslandCardsTests.swift:29]
- Contexto CI, K5, target CompanionIntegrationTests: ConversationQualityVoiceTests espera la misma salida filtrada [repo:Tests/CompanionIntegrationTests/ConversationQualityVoiceTests.swift:86]
- Contexto CI, K1: SessionMachineTests espera `scheduleCompletedExpiry(completedDelay)` al terminar [repo:Tests/CompanionCoreTests/SessionMachineTests.swift:152]
- Contexto CI, K1: y otra vez en el mismo archivo [repo:Tests/CompanionCoreTests/SessionMachineTests.swift:426]
- Contexto CI, K1/K4: Island16m4Tests espera ese mismo efecto en el dictado [repo:Tests/CompanionUITests/Island16m4Tests.swift:46]
- Contexto CI, K4: Island16m4Tests exige que el dictado dure mas que Completed [repo:Tests/CompanionUITests/Island16m4Tests.swift:39]
- Contexto CI, K1, target CompanionIntegrationTests: Island16m4ReviewTests exige que ese efecto NO se programe en su caso [repo:Tests/CompanionIntegrationTests/Island16m4ReviewTests.swift:28]
- Contexto CI, A1/K8: Island16m2Tests fija el orden, el reinicio y el tope de `touched` [repo:Tests/CompanionUITests/Island16m2Tests.swift:85]
- Contexto CI, A1: IncredibleComponentsTests fija el maximo de 230 del chip [repo:Tests/CompanionUITests/IncredibleComponentsTests.swift:208]
- Contexto CI, A1: SelfInspectionTests carga `touched` y lo espera en el espejo [repo:Tests/CompanionCoreTests/SelfInspectionTests.swift:80]
- Contexto CI, K7: ningun test pinta `IslandSlots`; solo se fija su medida `slotSide` [repo:Tests/CompanionUITests/PrimitivesTests.swift:50]
- La pista "no te oi" ya coincide con Incredible; no tocarla al cambiar las demas vidas [repo:Sources/CompanionCore/Session/SessionMachine.swift:26]

## 9. Incertidumbre

- ASSUMPTION: no se sabe que regla dejo la isla abierta en la sesion de Karen (voz en manos libres escuchando, campo con foco, adjunto en espera o encargo corriendo). prueba: leer en el log de la app las lineas "island:" de la hora de las capturas y ver el ultimo tamano antes de quedarse fijo
- ASSUMPTION: Incredible 0.2.36 muestra las tres ranuras punteadas solo con agentes; no se aislo el nodo donde se pintan. prueba: abrir Incredible sin tareas y mirar arriba a la derecha con hover; luego lanzar una tarea de fondo y mirar otra vez
- ASSUMPTION: el asentamiento medido es lo que se ve; el backend nativo podria sostener Completed mas tiempo. prueba: grabar la pantalla con Incredible respondiendo por voz y medir del fin del audio al cierre
- ASSUMPTION: Incredible no desplaza solo la columna para seguir la palabra dicha (sin llamadas de desplazamiento programatico en el extracto). prueba: pedirle una respuesta larga por voz y ver si la columna sigue a la voz
- ASSUMPTION: Incredible mantiene la isla abierta durante toda la escucha en manos libres. prueba: activar manos libres en Incredible y esperar 60 s en silencio
- [NEEDS CLARIFICATION: con la isla desplazada por la usuaria, la columna sigue a la voz al llegar palabras nuevas o se queda donde ella la dejo? Recomendado: seguir a la voz solo si estaba al final, como un terminal.]
- [NEEDS CLARIFICATION: K11, alto abierto: agrandar el lienzo para el alto de Incredible mas la sombra (recomendado), o dejar el lienzo de 620 y topar la columna en 592 menos la cabecera y el margen inferior?]

## 10. Checklist de estandar

- [ ] A: `parentActing` con destinos "", "  " y "Notes" deja `touched == ["Notes"]` (test del reductor, sin vista).
- [ ] A: con `touched` vacio no se pinta carrete; ningun chip se pinta con texto vacio.
- [ ] A: el ancho de un chip es el de su texto mas su padding (5 + 7), y nunca pasa de 230.
- [ ] A/K7: sin encargo, la cabecera derecha no pinta ranuras; con un encargo, tres ranuras y la primera gira.
- [ ] B: una respuesta hablada de 1.200 caracteres en tres parrafos se pinta entera, sin "…".
- [ ] B: una respuesta mas larga que el tope de palabras de Incredible pinta solo las ultimas palabras hasta ese tope; el tope se aplica antes de limpiar el texto.
- [ ] B: con contenido de la columna hasta el tope de Incredible no hay ScrollView y la forma abraza el contenido; pasado el tope la columna mide el tope y se desplaza en vertical.
- [ ] B/K11: la forma abierta llega al alto que Karen firme en K11 (el de Incredible, o el tope reducido) y el texto nunca queda fuera de la forma.
- [ ] B: la transcripcion en vivo muestra la ventana de lineas de Incredible, la mas nueva abajo, y desvanece el borde de arriba al desbordar.
- [ ] B: los puntos suspensivos solo quedan en titulos y metadatos de una linea y en el nombre de adjunto (2 lineas).
- [ ] C: cerrado = `.hidden` o `.pebble`; en idle, sin puntero, sin campo con foco ni borrador, sin adjuntos, sin aviso, sin hoja y sin turno, la isla esta cerrada.
- [ ] C: el hover abre tras la permanencia de Incredible (mas larga si el puntero va rapido) y, al salir sin otra razon, cierra con su histeresis (valores en la referencia local).
- [ ] C: al terminar la respuesta (voz callada, sin herramienta ni turno) la isla sigue abierta el asentamiento de Incredible (referencia local) y se cierra.
- [ ] C: con el puntero sobre el panel, ese plazo no corre; al salir queda como minimo el piso de Incredible (referencia local).
- [ ] C: press, escucha, pensar, actuar, hablar o un envio escrito cancelan el plazo y abren; un envio escrito sostiene la isla el plazo de Incredible o hasta que empiece el turno.
- [ ] C/K2: un encargo corriendo sin turno de la usuaria no pinta `.card`; el hover lo abre y un pedido de atencion (aprobacion) lo abre.
- [ ] C/K4: "no te oi" y la pista viven 6 s; el aviso de trabajo de fondo y la tarjeta de dictado viven los plazos de Incredible (referencia local).
- [ ] C/K4: el puntero encima pausa el anillo y el reloj de la sesion; al salir sigue donde iba, sin reiniciar; un aviso nuevo arma su propio reloj completo.
- [ ] C: con reduce motion los avisos vencen en el mismo tiempo.
- [ ] Tests: el PR que implemente K1/K4/K5/A1 actualiza SessionMachineTests:152 y :426, Island16m4Tests:39 y :46, Island16m4ReviewTests:28, NotchTests:156, IslandCardsTests, ConversationQualityVoiceTests, Island16m2Tests, IncredibleComponentsTests y SelfInspectionTests, y corre CompanionIntegrationTests ademas de los targets unitarios.
- [ ] D/K6: una respuesta sin resultado no genera tarjeta "Ver →".
- [ ] E: la linea de estado se sostiene el minimo de Incredible (referencia local) antes de cambiar.
- [ ] E/K8: el carrete muestra un solo item; un item nuevo entra con el retardo de Incredible (referencia local).
- [ ] E/K9-K10: mientras actua la linea dice "Pensando"; mientras la frase dicha esta en pantalla no se escribe "Hablando".
- [ ] Medidas de pixeles y curvas: las de `isla-maquetacion-incredible` e `isla-motion-incredible`.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Incredible.app 0.2.36, extractos del overlay (solo en la referencia local, no se publican) | Norditech, binario instalado | 0.2.36 | 2026-10-02 | high (reglas leidas; geometria de zonas no) |
| 2 | frame(minWidth:idealWidth:maxWidth:...) | Apple, SwiftUI | macOS 26 | 2026-10-02 | high |
| 3 | defaultScrollAnchor(_:) | Apple, SwiftUI | macOS 14+ | 2026-10-02 | high |
| 4 | HIG, Live Activities | Apple | 2026 | 2026-10-02 | medium (iPhone; macOS sin guia de notch) |
| 5 | Understanding SC 2.2.1 Timing Adjustable | W3C | WCAG 2.2 | 2026-10-02 | high |
| 6 | boring.notch, ContentView, Constants, BoringViewCoordinator | TheBoredTeam | d58240c | 2026-10-02 | medium |
| 7 | incredible-isla-componentes, incredible-ui-detalle, ux-incredible-vs-companion | este repo | 2026-09-24/25 | 2026-10-02 | medium |
| 8 | isla-maquetacion-incredible (brief hermano, D4) | este programa | BORRADOR 2026-10-02 | 2026-10-02 | medium |
| 9 | Codigo y tests de companion-next (Island, Session, Tools, Tests) | este repo | main 9085264 | 2026-10-02 | high |
