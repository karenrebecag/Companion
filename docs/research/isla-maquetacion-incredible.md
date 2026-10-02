# Reference Brief: maquetacion de la isla, el sistema de medidas y desborde de Incredible frente al de Companion

Slug: isla-maquetacion-incredible | Nivel: standard | Fecha: 2026-10-02 | Estado: ESCALADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 ESCALATE

## 1. Pregunta y decisiones abiertas

Pedido (orquestador, 2026-10-02): mapear el sistema exacto de maquetacion de la isla de Incredible 0.2.36 para que la de Companion lo iguale: anchos y altos por tamano, paddings, margenes y radios, como abraza el notch fisico, limites de cada widget, reglas de desborde, rejilla interna, tipografia y como refluye el texto largo. Las capturas de Karen del 2026-10-02 muestran tres fallos: texto cortado con "…" (4-texto-cortado.png), una barra vacia bajo "Pensando…" (2-pensando-barra-vacia.png) y dos chips, uno vacio (3-chips-vacios.png).

Directiva de Karen relayada por el orquestador el 2026-10-02: Incredible es el piso de Companion; donde su maquetacion difiera de una decision firmada de Companion, se recomienda igualar a Incredible y el conflicto queda aqui como decision suya, con la regla citada.

Fuera de alcance: el movimiento (brief hermano isla-motion-incredible) y las reglas de abrir/cerrar y la decision de scroll (brief hermano isla-ciclo-y-legibilidad). Este brief solo fija CUANTO cabe y QUE pasa cuando no cabe.

Hallazgos que no son decision (son fallos con causa, van a tdd-guide con test en rojo):

- F1. La barra vacia (captura 2) y el chip vacio (captura 3) son el mismo fallo. El carrete pinta un chip por cada objetivo tocado sin filtrar vacios, y `ParentTool.target` devuelve "" para look, click, typeText y demas. Ademas el chip se estira hasta 230 por `frame(maxWidth:)`: uno solo vacio dibuja una barra de 230, y dos se reparten la fila. La linea de estado ya filtra los vacios; el carrete no.
- F2. El "…" de la captura 4 no es maquetacion: `IslandReplyText` corta a 240 caracteres y solo toma el primer parrafo. Incredible no corta por caracteres 
[ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3].

Politica de publicacion (Karen, 2026-10-02): los extractos del binario de Incredible (valores, direcciones, selectores, nombres de variables y archivos del bundle) no se publican en el repo. Este brief describe cada medida de Incredible de forma cualitativa y la cita a la referencia local [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]; los valores exactos viven ahi y se leen con la geometria resuelta antes de implementar.

Decisiones para Karen (recomendacion entre parentesis, segun la directiva). En cada una, "igualar a Incredible" significa igualar el valor de la referencia local:

- D1. Ancho abierto: el cuerpo de Incredible (valor en la referencia local) contra 492 de Companion, medido en video y fijado por test en IslandChromeTests.swift:17 y spec 16f linea 72. (Recomendado: igualar el cuerpo de Incredible con hombros concavos que crecen con el alto; el ancho ancho tambien se iguala.) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- D2. Radio abierto: el de Incredible contra 22 en `NotchShape.openRadius` (IslandMotionViews.swift:71) y "radio inferior ~20 pt" de la spec 16f linea 78. El token `IslandMetrics.openRadius` ya vale 28 y tiene test, pero el recorte no lo usa. (Recomendado: igualar a Incredible en el recorte.) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- D3. Texto de la respuesta en la isla: tamano, interlineado y peso del CSS de Incredible (local) contra 16 pt con 4 de interlineado (TypeSize.strong) y la nota "~22 pt" de la spec 16f linea 95, que siguio la regla "si el CSS y la captura difieren, gana la captura" (audit-ui-companion-vs-incredible.md:209). (Recomendado: el CSS; la regla de la captura se suspende para la isla porque el CSS ahora se lee con su geometria resuelta.) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- D4. Texto largo: quitar el corte de 240 caracteres y el de primer parrafo; mostrar hasta el tope en palabras de Incredible, que refluyen y, si no caben, la columna de contenido desborda segun lo que decida isla-ciclo-y-legibilidad. (Recomendado: si.) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- D5. Asomo al pasar el puntero: crecimiento y radio de Incredible contra +10 por lado y +9 de alto con radio 10, medido de NotchNook (IslandChrome.swift:99, spec 16i seccion 11). (Recomendado: el de Incredible.) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- D6. Carrete: un solo elemento a la vez que rueda (Incredible) contra una fila de chips de todo lo tocado, hasta 12 (spec 16m-2). (Recomendado: un elemento a la vez; los chips de referencia van dentro de la transcripcion, como en Incredible.) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- D7. Campo de la isla: crece de una linea hasta un tope de lineas y luego desborda (Incredible) contra un `TextField` de una linea. (Recomendado: crecer hasta el tope de Incredible.) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- D8. Banda superior: alto fijo con rejilla de tres columnas centrada en el notch (Incredible) contra el alto del notch con un HStack. (Recomendado: banda fija y rejilla.) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- D9. Huecos de tareas: circulos con un contador "+N" cuando hay mas (Incredible) contra 3 de 22 con hueco 8 y sin contador. (Recomendado: el de Incredible.) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- D10. El tamano `.bar` de 320 no tiene par claro en la geometria de Incredible (sus estados son oculto, semilla, asomo y abierto). [NEEDS CLARIFICATION: grabar Incredible escuchando y pensando para ver si pinta algo entre el notch y el panel abierto antes de tocar `.bar`; ver seccion 9.] [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]

## 2. Estado actual

### Tabla de medidas, Incredible contra Companion (los valores de Incredible estan en la referencia local)

| Medida | Incredible | Companion | Brecha |
|---|---|---|---|
| Ancho abierto | cuerpo mas angosto y ancho ancho mayor [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 492; ancho 554 [repo:Sources/CompanionUI/Island/IslandChrome.swift:16] | el cuerpo sobra y el ancho falta (D1) |
| Ancho intermedio | no hay estado entre asomo y abierto [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | `.bar` 320 [repo:Sources/CompanionUI/Island/IslandChrome.swift:14] | estado propio (D10) |
| Alto abierto minimo | banda mas fila del campo mas relleno inferior [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | alto del contenido, minimo el del notch [repo:Sources/CompanionUI/Island/IslandChrome.swift:51] | sin piso de cromo |
| Alto abierto maximo | banda mas columna con tope mas relleno [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 620 - 28 = 592 [repo:Sources/CompanionUI/Island/IslandChrome.swift:51] | Companion tiene menos alto |
| Reposo | notch x notch, radio pequeno [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | notch x notch, radio 10 [repo:Sources/CompanionUI/Island/IslandMotionViews.swift:70] | igual |
| Asomo | crecimiento menor y radio algo mayor [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | notch + 20 x notch + 9, radio 10 [repo:Sources/CompanionUI/Island/IslandChrome.swift:100] | Companion crece mas (D5) |
| Radio abierto | mayor que el de Companion [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 22 en el recorte [repo:Sources/CompanionUI/Island/IslandMotionViews.swift:71] | menor (D2) |
| Hombro concavo | crece con el alto entre un minimo y un maximo [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 8 fijo [repo:Sources/CompanionUI/Island/IslandMotionViews.swift:68] | no crece |
| Banda superior | alto fijo, rejilla flexible / notch / flexible [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | alto del notch, HStack [repo:Sources/CompanionUI/Island/IslandView.swift:286] | D8 |
| Margen lateral | algo mayor [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 16 [repo:Sources/CompanionUI/Island/IslandView.swift:289] | menor |
| Hueco de la pila | mayor, con padding asimetrico [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 8 [repo:Sources/CompanionUI/Island/IslandView.swift:294] | menor |
| Columna de contenido | con minimo y tope [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | sin tope propio (el del lienzo) [repo:Sources/CompanionUI/Island/IslandChrome.swift:51] | falta el tope |
| Fila del campo | crece por linea hasta un tope [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 38, una linea [repo:Sources/CompanionUI/Window/IncredibleWindow.swift:81] | D7 |
| Huecos de tareas | circulos algo mayores con contador "+N" [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 3 de 22, hueco 8, sin contador [repo:Sources/CompanionUI/Island/IslandPieces.swift:228] | D9 |
| Chip de referencia | abraza el texto con tope, elipsis dentro [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | toma el ancho propuesto hasta 230 [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:144] | F1 |
| Carrete | un elemento a la vez, recorta [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | todos los tocados, alto 26 [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:87] | D6 y F1 |
| Transcripcion | mas lineas visibles, cola y fundido arriba [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 2 lineas, "…" al inicio [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:73] | menos lineas, elipsis |
| Respuesta | ultimas palabras hasta un tope, refluye [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 240 caracteres + "…" [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:38] | F2 y D4 |
| Texto de la respuesta | mas chico, interlineado proporcional [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 16, +4 de interlineado [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:89] | D3 |
| Texto de estado | peso medio, con alto minimo [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 13 regular, 2 lineas [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:123] | tamano y peso |
| Historial visible | filas con una fila parcial visible [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | 3 resultados [repo:Sources/CompanionUI/Island/IslandView.swift:65] | sin pista de "hay mas" |
| Barra de scroll | la del sistema en mac [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3] | sin scroll en la isla (lo decide isla-ciclo-y-legibilidad) [repo:Sources/CompanionUI/Island/IslandView.swift:153] | ver brief hermano |

### Companion, tamanos y forma

- Los tamanos son roles en Core: hidden, pebble, nudge, bar, card y wideCard [repo:Sources/CompanionCore/Island/IslandState.swift:8]
- Ancho de la pildora de la fase 1 del movimiento: 240 [repo:Sources/CompanionUI/Island/IslandChrome.swift:13]
- Ancho de `.card`: 492 [repo:Sources/CompanionUI/Island/IslandChrome.swift:17]
- Margen lateral del contenido (`shellMargin`): Space.x4 = 16 [repo:Sources/CompanionUI/Island/IslandChrome.swift:20]
- `.wideCard` mide 522 + 16 + 16 = 554 [repo:Sources/CompanionUI/Island/IslandChrome.swift:21]
- Lienzo fijo de 620 x 620 para la isla, su popup de 580 y la sombra [repo:Sources/CompanionUI/Island/IslandChrome.swift:26]
- Reserva de sombra bajo la forma: 28 [repo:Sources/CompanionUI/Island/IslandChrome.swift:29]
- El radio de la forma solo pasa a abierto cuando el alto supera el del asomo [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:37]
- Hay un segundo radio abierto, `IslandMetrics.openRadius` = Radius.panel = 28, que el recorte no usa [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:27]
- Un test fija ese 28 aunque no llegue a la forma [repo:Tests/CompanionUITests/IncredibleComponentsTests.swift:195]
- Un test fija el ancho de tarjeta en 492 como "el ancho medido en la grabacion" [repo:Tests/CompanionUITests/IslandChromeTests.swift:17]
- El contenido se dibuja al ancho del rol y a su alto natural, y la forma lo recorta [repo:Sources/CompanionUI/Island/IslandView.swift:152]

### Companion, notch y areas seguras

- `ScreenShape` guarda `safeAreaInsets.top` y los anchos de `auxiliaryTopLeftArea` y `auxiliaryTopRightArea` [repo:Sources/CompanionCore/Island/NotchGeometry.swift:8]
- Con safeTop mayor que 0 y las dos areas, el notch mide el ancho de pantalla menos las dos areas y el alto del inset [repo:Sources/CompanionCore/Island/NotchGeometry.swift:49]
- El centro del notch sale del centro de la pantalla, nunca de las areas, porque pueden ser desiguales mientras la barra de menus se acomoda [repo:Sources/CompanionCore/Island/NotchGeometry.swift:46]
- Sin notch, la isla es una pildora de 190 de ancho y el alto de la barra de menus, minimo 24 [repo:Sources/CompanionCore/Island/NotchGeometry.swift:55]
- La isla vive en la pantalla con notch o, si no hay, en la primera [repo:Sources/CompanionCore/Island/NotchGeometry.swift:63]
- La app lee esos valores de `NSScreen` en un solo lugar [repo:Sources/CompanionUI/Island/IslandChrome.swift:168]
- El lienzo se recoloca en cada cambio de parametros de pantalla [repo:Sources/CompanionUI/Island/IslandChrome.swift:236]
- Las pruebas construyen la geometria con una pantalla falsa de 1512 x 982 sin notch [repo:Sources/CompanionUI/Island/IslandChrome.swift:160]

### Companion, rejilla interna

- La concha es un VStack con hueco 8: la banda del notch y debajo el contenido [repo:Sources/CompanionUI/Island/IslandView.swift:278]
- Padding lateral 16 y 16 abajo, sin padding arriba aparte de la banda [repo:Sources/CompanionUI/Island/IslandView.swift:290]
- La fila de estado es un HStack con hueco 12: medidor, texto, accion, parar y luz [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:32]
- Los huecos de tareas son 3 circulos discontinuos fijos con hueco 8 [repo:Sources/CompanionUI/Island/IslandPieces.swift:210]
- El campo es un `TextField` de una linea [repo:Sources/CompanionUI/Island/IslandPieces.swift:131]

### Companion, limites y desborde

- El corte de la respuesta agrega "…" al final; es el "aquel p…" de la captura 4 [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:72]
- Antes del corte solo se toma el primer parrafo no vacio [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:46]
- La respuesta lleva interlineado extra de Space.x1 (4) [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:90]
- La transcripcion en vivo trunca por la cabeza con "…" [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:74]
- El carrete es un HStack de alto 26 sin envoltura ni recorte propio [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:90]
- `ParentTool.target` devuelve "" cuando la tool no tiene clave de objetivo [repo:Sources/CompanionCore/Tools/ParentTools.swift:107]
- Look, click, scroll, menu y see no tienen clave a proposito (tampoco typeText, readFocused, pressKey ni focusWindow) [repo:Sources/CompanionCore/Tools/ParentTools.swift:122]
- Esos objetivos vacios entran al anillo `touched` (tope 12) sin filtro [repo:Sources/CompanionCore/Session/SessionMachine.swift:97]
- La linea de estado si filtra los vacios antes de pintar chips [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:97]
- El tope 230 del chip viene del CSS de Incredible [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:45]
- La leyenda bajo el campo se limita a 2 lineas [repo:Sources/CompanionUI/Island/IslandView.swift:353]
- El texto de estado se limita a 2 lineas [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:125]
- El recibo es 1 linea [repo:Sources/CompanionUI/Island/IslandPieces.swift:248]
- Y trunca al medio [repo:Sources/CompanionUI/Island/IslandPieces.swift:249]
- La tarjeta de ejecucion muestra los ultimos 4 pasos [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:51]

### Companion, regla de tokens

- El contrato de UI prohibe radios literales en las vistas [repo:conformance/ui-contract.json:7]
- Y medidas literales en `.frame` [repo:conformance/ui-contract.json:11]
- Y aritmetica con Space para esquivar la rampa: si falta un valor, se agrega el token [repo:conformance/ui-contract.json:15]
- Las fuentes Geist de la isla pasan por la escala del usuario [repo:Sources/CompanionUI/DesignSystem/Typography.swift:358]

### Incredible 0.2.36, geometria (descripcion cualitativa; extractos en la referencia local)

- El frontend va embebido en el binario instalado y no en los recursos de la app; ahi se leyo la geometria [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Hay una escala de espaciado, un perfil propio de mac y un notch por defecto cuando el nativo no llega [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- El notch real llega del lado nativo y solo se acepta dentro de un rango de cordura; fuera de el cae al notch por defecto [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Las zonas de hover salen del notch real: un compromiso apenas mayor que el notch y una cercania de tamano minimo [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- En la banda los iconos y los items tienen medidas fijas, y la fila del campo va debajo con inset y hueco propios [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Los lados de la banda son flex centrado con hueco fijo [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- El binario usa safeAreaInsets, auxiliaryTopLeftArea y auxiliaryTopRightArea, igual que Companion [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Un sondeo nativo de la pantalla marca en el documento si hay notch y si la app esta en pantalla completa [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- No hay tamano fijo de panel en los strings del binario; el ancho del lienzo lo fija el JS [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]

### Incredible 0.2.36, limites y desborde

- La linea de voz fuera del panel muestra la frase en curso y rueda a la siguiente; con hover despliega todas, y queda unos segundos tras asentarse [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Al desbordar, la transcripcion se desvanece arriba; no hay elipsis [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- El carrete muestra un solo elemento a la vez y lo hace rodar [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Dentro del chip de referencia, el texto trunca con elipsis [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Los huecos de tareas son un numero fijo de circulos; las orejas de los lados del notch crecen con la cantidad de agentes hasta un maximo [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Los slots de conversacion y de tarjeta desbordan con scroll vertical y recortan en horizontal; la conversacion es lo ultimo que cede alto [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Hay limites de lineas en opcion de respuesta, subtitulo de confirmacion y tarjeta de texto capturado [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- El campo crece hasta un alto de texto maximo antes de desbordar [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]

### Incredible 0.2.36, tipografia de la isla

- Transcripcion: tamano chico, interlineado proporcional y peso medio; la opacidad sube al fijarse el texto [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Linea de voz: algo mayor que la transcripcion, con interlineado fijo [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Chip de la linea de voz: padding asimetrico, rejilla de icono mas texto, ancho maximo y radio pleno [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Campo: tamano chico con interlineado proporcional [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Cuerpo base de la isla en Geist [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]

Contextos: app release en /Applications sobre un MacBook con notch (los tamanos de notch cambian por modelo y escala); pantalla externa sin notch (pildora de respaldo); dos pantallas; un Space de app en pantalla completa (la barra de menus se oculta); escala de texto del usuario (TypeScale de -1 a +3); `swift test` local y en CI (pantalla falsa sin notch, sin ventana real); tests de snapshot opt-in; el espejo de autoinspeccion del puente; grabaciones de pantalla (la isla es visible a proposito); VoiceOver.
## 3. Fuentes primarias

- `safeAreaInsets` da las distancias desde los bordes donde el contenido no queda tapado; en algunos Mac reflejan la carcasa de la camara; existe desde macOS 12 [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsscreen/safeareainsets.json@macOS12]
- `auxiliaryTopLeftArea` es la parte visible arriba a la izquierda, en coordenadas globales y fuera del area segura; es nil si la parte de arriba no esta tapada [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc.json@macOS12]
- `auxiliaryTopRightArea` es lo mismo a la derecha [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsscreen/auxiliarytoprightarea-gr2n.json@macOS12]
- Un `frame` con maximo, si el padre propone mas que el tamano de la vista, toma lo propuesto recortado al maximo: no abraza el contenido [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:).json@macOS14]
- `lineLimit`: un Text que pasa el limite se trunca; un TextField vertical se vuelve desplazable [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/linelimit(_:).json@macOS14]
- `ViewThatFits` elige el primer hijo cuyo tamano ideal cabe en el eje restringido [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/viewthatfits.json@macOS14]
- `scrollIndicators(.automatic)` deja la decision a la politica del componente; `.visible` puede mostrarse solo al desplazar en algunas plataformas [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/scrollindicators(_:axes:).json@macOS14]
- El estilo de barra de scroll lo decide el ajuste "Mostrar barras de desplazamiento" de la usuaria y puede cambiar en vivo [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsscroller/preferredscrollerstyle.json@macOS14]
- HIG, paneles: un HUD debe ser chico y no competir con el contenido; color con mesura en lo oscuro [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/panels.json@2026-10-02]
- HIG, layout: no mostrar contenido detras de la carcasa de la camara; filas de una linea pueden necesitar crecer cuando el texto crece [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.json@2026-10-02]


## 4. Implementaciones de referencia

- boring.notch (TheBoredTeam, unas 10 900 estrellas, push del 2026-10-02): mide el notch como ancho de pantalla menos las dos areas auxiliares, igual que Companion [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/sizing/matters.swift#L53@d58240c]
- boring.notch toma el alto del notch de `safeAreaInsets.top` o de la barra de menus segun el modo [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/sizing/matters.swift#L63@d58240c]
- boring.notch fija el panel abierto en 640 x 190 con radios 19 arriba y 24 abajo [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/sizing/matters.swift#L16@d58240c]
- DynamicNotchKit (Kai Azim, autor de Loop; libreria SwiftUI de notch, unas 460 estrellas): `hasNotch` es que existan las dos areas auxiliares [ref:https://github.com/MrKai77/DynamicNotchKit/blob/cd0b3e52d537db115ad3a9d89601f20e0bee8d27/Sources/DynamicNotchKit/Utility/NSScreen+Extensions.swift#L19@cd0b3e5]
- DynamicNotchKit cae a un notch arbitrario de 300 por el alto de la barra de menus cuando no hay notch [ref:https://github.com/MrKai77/DynamicNotchKit/blob/cd0b3e52d537db115ad3a9d89601f20e0bee8d27/Sources/DynamicNotchKit/Utility/NSScreen+Extensions.swift#L50@cd0b3e5]
- DynamicNotchKit dimensiona el contenido expandido con `fixedSize` y suma el radio superior como padding lateral, para que el contenido nunca entre al hombro [ref:https://github.com/MrKai77/DynamicNotchKit/blob/cd0b3e52d537db115ad3a9d89601f20e0bee8d27/Sources/DynamicNotchKit/Views/NotchView.swift#L97@cd0b3e5]
- Incredible 0.2.36 es la referencia de producto que manda (directiva de la seccion 1); no es un repo publico y sus extractos viven solo en la referencia local [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Adoptar la geometria de Incredible como tokens (`IslandLayout`, lista de la seccion 10) | Cumple la directiva; un solo origen de medidas; F1 y F2 desaparecen por diseno | Rompe pins firmados (492, radio 22, texto 16 y 22, asomo de NotchNook); toca IslandChrome, IslandView y piezas | media | Recomendada, con D1-D9 firmadas por Karen |
| B. Mantener las medidas de Companion y solo arreglar F1 y F2 | Diff chico, ningun pin se mueve | Deja a Companion por debajo del piso en ancho, radio, rejilla y desborde; no cumple la directiva | baja | Solo como primer paso de A |
| C. A en dos tandas: primero F1 y F2 con test en rojo (no dependen de ninguna decision), despues la geometria cuando Karen firme | Arregla ya lo que Karen vio; la geometria espera su firma | Dos PR | media | Orden recomendado para ejecutar A |

## 6. Evidencia en contra

- La razon mas fuerte contra A: el 492 no es un capricho, salio de medir la grabacion de Incredible cuadro a cuadro [repo:docs/specs/wave-16f-notch-y-motion.md:72]
- Respuesta: el codigo de Incredible da un cuerpo mas angosto mas hombros que crecen con el alto, asi que una medicion sobre la silueta puede leer un valor mayor segun la altura del corte; la prueba de la seccion 9 lo resuelve [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Segunda razon: la regla vigente dice que gana la captura cuando difiere del CSS, y la captura pedia texto de ~22 pt [repo:docs/research/audit-ui-companion-vs-incredible.md:209]
- Respuesta: esa regla se tomo cuando solo se tenian clases sueltas; ahora el CSS esta leido con sus variables resueltas, y la habla dentro de la isla no tiene ninguna regla de tamano mayor al que Companion usa para texto corrido; se acepta el conflicto y lo decide Karen (D3) [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Tercera: Companion tiene escala de texto del usuario e Incredible no, asi que copiar altos en px rompe con escala +3 [repo:Sources/CompanionUI/DesignSystem/Typography.swift:358]
- Respuesta: los altos que dependen de texto se expresan en lineas por el interlineado escalado; los altos de cromo (banda, fila del campo) quedan fijos [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.json@2026-10-02]

## 7. Ejemplares y anti-ejemplos

- Bien: el chip de Incredible abraza su texto y trunca dentro, con tope de ancho y elipsis en el texto [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Mal: el chip de Companion con `frame(maxWidth: 230)` toma el ancho propuesto; dos chips se reparten la fila y uno vacio dibuja una barra (capturas 2 y 3) [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:144]
- Por que pasa: con maximo y propuesta mayor, el frame toma la propuesta recortada al maximo [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:).json@macOS14]
- Bien: la linea de estado filtra objetivos vacios antes de pintar chips [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:97]
- Mal: el carrete no filtra y pinta el "" que devuelve un click o un look [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:87]
- Bien: Incredible limita la habla por palabras y deja refluir; el costo queda acotado sin cortar a la vista [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Mal: cortar por caracteres a 240 con "…" a media palabra [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:72]
- Bien: la transcripcion muestra la cola y funde arriba en vez de poner elipsis al inicio [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Bien: el contador "+N" en vez de dejar caer tareas en silencio [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Bien: el visor de historial deja ver media fila como pista de que hay mas [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Bien: medir el notch con las areas auxiliares y centrar con el centro de pantalla, como ya hace Companion [repo:Sources/CompanionCore/Island/NotchGeometry.swift:46]

## 8. Trampas

- En un Space de pantalla completa la barra de menus se oculta y `visibleFrame.maxY` puede igualar `frame.maxY`; sin notch eso da alto 0 y entra el minimo de 24 [repo:Sources/CompanionCore/Island/NotchGeometry.swift:55]
- Las areas auxiliares son nil cuando arriba no hay nada tapado, asi que una pantalla externa nunca da notch [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc.json@macOS12]
- Incredible desconfia del notch nativo fuera de un rango de cordura y cae a un notch por defecto; Companion no tiene esa barrera y un valor raro mientras la barra se acomoda pasaria directo [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- El alto maximo abierto de Incredible es mayor que el de Companion (592, por la sombra del lienzo de 620): el lienzo tiene que crecer o la columna pierde alto [repo:Sources/CompanionUI/Island/IslandChrome.swift:51] [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Con escala de usuario +3, las lineas de transcripcion no caben en un alto fijo en puntos; el alto se calcula de lineas por interlineado escalado [repo:Sources/CompanionUI/DesignSystem/Typography.swift:358]
- Cambiar 492 rompe pins en IslandChromeTests y en Notices16m6Tests, que asumen tarjetas de 492 y un aviso recortado a 460 [repo:Tests/CompanionIntegrationTests/Notices16m6Tests.swift:120]
- Cambiar el radio del recorte al de Incredible sin mover la condicion de `radius()` deja el asomo con 10 y el abierto con el nuevo: el asomo de Incredible pide un radio propio [repo:Sources/CompanionUI/Island/IslandView+Motion.swift:37] [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- Quitar el corte de 240 sin otro tope reabre el hallazgo de seguridad 16f (costo por token sin limite); el tope pasa a palabras, no desaparece [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:47]
- La barra de scroll en mac la decide el ajuste de la usuaria y cambia en vivo; ocultarla a mano rompe a quien eligio "siempre" [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsscroller/preferredscrollerstyle.json@macOS14]
- En `swift test` la pantalla es falsa y sin notch: ningun test de geometria con notch real corre ahi; las formulas se prueban con `ScreenShape` construidas a mano [repo:Sources/CompanionUI/Island/IslandChrome.swift:160]
- El espejo de autoinspeccion guarda el estado pintado; si el tamano cambia de rol, el oraculo de QA que lea `size` tiene que seguirlo [repo:Sources/CompanionUI/Island/IslandView.swift:183]
- VoiceOver lee la respuesta entera por `accessibilityLabel(text)`: con el corte quitado la etiqueta crece igual que la vista [repo:Sources/CompanionUI/Island/Data/IslandReplyPieces.swift:94]
- La regla de tokens no ve constantes en enums de metricas: toda medida nueva va a un enum (`IslandLayout`) y nunca a la vista, o el contrato falla [repo:conformance/ui-contract.json:11]
- Por contexto: con notch se usa el notch real y la banda fija; pantalla externa y pantalla de test usan la pildora de respaldo con la misma rejilla; pantalla completa, ver la trampa del alto 0 y la seccion 9; escala de usuario, lineas por interlineado; snapshots, se regeneran tras D1-D3; espejo de QA, sigue el rol; grabaciones, sin cambio; VoiceOver, etiqueta completa [repo:Sources/CompanionCore/Island/NotchGeometry.swift:44]


## 9. Incertidumbre

- ASSUMPTION: el 492 medido en la grabacion es el cuerpo de Incredible mas parte del hombro o del borde, no un ancho distinto. prueba: medir la grabacion CleanShot 2026-09-25 en el borde inferior de la silueta abierta (donde el hombro ya no cuenta) y comparar con el cuerpo de la referencia local. [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- ASSUMPTION: una variante de reposo mas chica de Incredible corresponde a la pantalla completa (por el nombre del atributo que marca ese estado). prueba: abrir Incredible con una app en pantalla completa en el notch y medir la forma en reposo. [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- ASSUMPTION: Incredible no pinta nada del ancho de `.bar` entre el notch y el panel mientras escucha o piensa. prueba: grabar a 120 fps un hold de FN corto en Incredible y medir el ancho en cada cuadro.
- ASSUMPTION: en mac el WKWebView de Incredible muestra la barra de scroll del sistema (superpuesta, solo al desplazar con el ajuste por defecto). prueba: en Incredible, una respuesta larga en el panel con "Mostrar barras de desplazamiento: siempre" y luego "al desplazar".
- ASSUMPTION: el tope de la habla de Incredible cuenta palabras y no tokens. prueba: hacer que Incredible lea un texto de 700 palabras numeradas y ver cual es la primera que aparece. [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]
- [NEEDS CLARIFICATION: D1 a D10 de la seccion 1; cada una mueve un pin o una spec firmada.]
- [NEEDS CLARIFICATION: el limite de recibos visibles a la vez en Incredible no se encontro en esta corrida; se mantiene 1 linea con truncado al medio hasta medirlo.]

## 10. Checklist de estandar

Tokens propuestos (`IslandLayout`, un enum en CompanionUI, sin valores de respaldo; las vistas solo leen de aqui). Los valores que vienen de Incredible se toman de la referencia local, no de este documento [ref:incredible-ref/briefs/isla-maquetacion-incredible.md@7a42bfd8b1a3]

| Token | Valor | Origen |
|---|---|---|
| openWidth / wideWidth | los de Incredible (local) | D1 |
| bandHeight | el de Incredible (local) | D8 |
| chatRowHeight / chatLineStep / chatMaxLines | los de Incredible (local) | D7 |
| inset, bandTopPadding, stackGap, stackPad*, bottomPad | los de Incredible (local) | pila |
| bodyMinHeight / columnMaxHeight | los de Incredible (local) | columna |
| radius seed / cue / open, cueSwell | los de Incredible (local) | D2, D5 |
| shoulder | funcion del alto con minimo y maximo (local) | hombro |
| itemSide / headerIcon | los de Incredible (local) | banda |
| taskSlot / taskSlotGap / taskSlotsMax | los de Incredible (local) | D9 |
| referentMaxWidth | 230 de Companion, abrazando el texto | F1 |
| reelHeight / reelItems | alto 26 de Companion / 1 | D6 |
| transcriptLines / transcriptFade | los de Incredible (local) | transcripcion |
| speech size / leading / weight / wordCap | los de Incredible (local) | D3, D4 |
| voiceLine size / lineHeight / maxWidth | los de Incredible (local) | linea de voz |
| statusMinHeight | el de Incredible (local) | pensando |
| historyRow / historyGap / historyVisibleRows | los de Incredible (local) | historial |
| notchSane | rango de cordura de Incredible (local) | notch |

Criterios (cada medida marcada "local" se verifica contra la referencia local, no contra este documento):

- [ ] Todas las medidas de la lista viven en `IslandLayout`; ninguna vista de Island usa un literal nuevo y el baseline de conformance no sube.
- [ ] F1: un test en rojo pinta el carrete con objetivos ["Notes", ""] y espera exactamente un chip; el anillo `touched` nunca guarda una cadena vacia.
- [ ] F1: el chip "Notes" en una fila de 460 mide su ancho intrinseco, no 230 ni media fila; con 400 caracteres mide 230 y muestra elipsis.
- [ ] F2: una respuesta de 1 000 caracteres y dos parrafos se pinta entera, sin "…"; con mas palabras que el tope se pintan las ultimas del tope.
- [ ] Ancho abierto y ancho ancho de Incredible (si Karen firma D1); el aviso de actualizacion de 522 cabe sin recorte.
- [ ] Alto abierto = banda + fila del campo + lineas extra + min(columna, tope) + relleno inferior, probado con 1 y el maximo de lineas y con columna 0, media y mayor al tope.
- [ ] Radio del recorte: reposo 10, asomo y abierto de Incredible (si firma D2 y D5).
- [ ] Asomo con el crecimiento de Incredible (si firma D5).
- [ ] Hombro con la funcion de Incredible a cada lado.
- [ ] Banda fija con rejilla izquierda flexible, centro del ancho del notch y derecha flexible (si firma D8).
- [ ] Pila con inset, hueco, padding, minimo y maximo de Incredible.
- [ ] Huecos de tareas con las medidas de Incredible; con mas tareas que huecos se ve el contador "+N" (si firma D9).
- [ ] Carrete: un elemento a la vez, nunca mas ancho que su fila (si firma D6).
- [ ] Transcripcion: lineas por el interlineado escalado; con una mas se ve la cola y un fundido arriba, sin "…".
- [ ] Campo: crece desde una linea hasta el tope de Incredible y desborda despues (si firma D7).
- [ ] Habla y linea de voz con la tipografia de Incredible (si firma D3).
- [ ] Con escala de texto +3 ningun texto de la isla se corta sin elipsis o fundido declarado.
- [ ] Sin notch (pantalla externa y pantalla de test) la isla usa la pildora de respaldo con la misma rejilla.
- [ ] Un notch nativo fuera del rango de cordura de Incredible cae al de respaldo.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Incredible.app: frontend embebido y strings del binario (extractos solo en referencia local) | Incredible (one.incredible.new) | 0.2.36 | 2026-10-02 | high |
| 2 | NSScreen.safeAreaInsets | Apple | macOS 12+ | 2026-10-02 | high |
| 3 | NSScreen.auxiliaryTopLeftArea / auxiliaryTopRightArea | Apple | macOS 12+ | 2026-10-02 | high |
| 4 | View.frame(minWidth:...maxHeight:alignment:) | Apple | SwiftUI | 2026-10-02 | high |
| 5 | View.lineLimit(_:) | Apple | SwiftUI | 2026-10-02 | high |
| 6 | ViewThatFits | Apple | SwiftUI | 2026-10-02 | high |
| 7 | View.scrollIndicators(_:axes:) | Apple | SwiftUI | 2026-10-02 | medium |
| 8 | NSScroller.preferredScrollerStyle | Apple | AppKit | 2026-10-02 | high |
| 9 | HIG Panels | Apple | 2026-10-02 | 2026-10-02 | high |
| 10 | HIG Layout | Apple | 2026-10-02 | 2026-10-02 | high |
| 11 | boring.notch sizing/matters.swift | TheBoredTeam | d58240c | 2026-10-02 | medium |
| 12 | DynamicNotchKit NSScreen+Extensions.swift y NotchView.swift | MrKai77 | cd0b3e5 | 2026-10-02 | medium |
| 13 | Capturas de Karen 2 a 4 (karen-ui-2026-10-02) | Karen | 2026-10-02 | 2026-10-02 | high |
