# Reference Brief: tejer en la transcripcion de la isla lo que la usuaria hizo mientras sostenia FN (Incredible 0.2.36)

Slug: transcript-tejido-hold | Nivel: standard | Fecha: 2026-10-04 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-04 ESCALATE

## 1. Pregunta y decisiones abiertas

Pregunta (encargo relayado por el orquestador el 2026-10-03, no palabra directa de Karen salvo donde se marca): como debe Companion tejer en la transcripcion de la isla (`IslandTranscript`) lo que la usuaria hizo mientras sostenia la tecla, junto a sus palabras, como hace Incredible 0.2.36. "Lo que hizo": cambios de superficie (app, ventana o pestana, con titulo y origen de la URL), clics, texto seleccionado, archivos de Finder, copias, dialogos abiertos y, mas adelante, texto tecleado.

Toolchain al investigar: swift-tools 6.2 en Package.swift, plataforma minima macOS 26. Worktree en 5a03a34 (base de la rama docs/brief-transcript-tejido); PR #181 en 8f9ff06 y PR #184 en 5e8833f, ambos abiertos.

Decisiones de Karen que el brief respeta (relayadas, no reinterpretadas):
- Capturar solo mientras FN esta sostenida [KAREN:relayed by orchestrator 2026-10-03, b2b-2 / PR #222]
- Los chips de archivo muestran la ruta completa [KAREN:relayed by orchestrator 2026-10-03, b2b-2 / PR #222]
- Alcance: clics, seleccion y rutas primero; despues copied y dialog_opened [KAREN:relayed by orchestrator 2026-10-03, b2b-2 / PR #222]
- Privacidad: rutas y texto seleccionado si, su contenido nunca en logs [KAREN:relayed by orchestrator 2026-10-03, b2b-2 / PR #222]

### Hallazgos en Incredible 0.2.36 (referencia local de solo lectura, ~/Desktop/incredible-ref)

La referencia local no es URL ni archivo del repo y el linter verifica toda URL citada, asi que estos hallazgos van aqui, por archivo, offset de caracter (Python, cercano al byte) y prefijo sha256 del archivo leido en esta corrida: overlay-DstkIEbM.js 9d280ba68346, incredible.md e04e9fa2f699, accessibility-helper.md 00d9f9efb8d2. Se describe comportamiento con palabras propias; no se copia codigo.

- Tipos que se tejen: solo archivo, texto seleccionado y copiado entran en la transcripcion (lista de tres tipos, @40562). Ventana, pestana, boton, celda, tecleado y dialogo solo destellan en el orbe del puntero.
- Etiqueta: se aplana el espacio en blanco y se corta a 42 caracteres con elipsis (@40647). Un archivo usa solo el ultimo componente de la ruta como etiqueta y guarda la ruta entera como detalle (@40755 y @41191). Texto seleccionado y copiado se tejen entre comillas tipograficas (@42188).
- Superficie: una pestana con URL se etiqueta con el titulo o, sin titulo, con el host sin www; una ventana con "App — Titulo"; una ventana de la misma app que la anterior no genera item (@41191).
- Clic que abre: un clic seguido en 800 ms o menos por una ventana o pestana se descarta y queda solo la ventana (@45264 y @45450).
- Orden: cada item tejible se ancla al numero de palabras que tenia el parcial en el momento en que llego el lote (@45848), en un mapa indice-de-palabra a etiquetas; la misma etiqueta no se repite en el mismo indice (@47221).
- Tejido: se recorre el parcial palabra por palabra y antes de cada palabra van sus marcas entre corchetes; las marcas con indice mas alla de la ultima palabra van al final en orden de indice; un parcial sin palabras se devuelve tal cual (@42554). Sin marcas no se teje nada (@47791).
- Ciclo: al empezar un hold y al empezar un dictado se vacian marcas y pila; se ignoran lotes si no se esta escuchando; una generacion nueva limpia lo anterior (@47221 y @45264). Tras soltar, el compañero sigue 1200 ms visible sin recolectar (@45264).
- Que ve el modelo vs la isla: el tejido se aplica al texto parcial justo antes de pasarlo al modelo de vista de la isla (@208520). En el front no hay otro consumidor del tejido; lo que el host manda al modelo con esas observaciones no esta en el front extraido.
- Chip en la transcripcion: el renglon de la isla vuelve a partir el texto tejido con una expresion de corchetes de 1 a 120 caracteres sin corchetes ni salto de linea (@73836), y cada coincidencia se pinta como chip con icono de 12 en negrita (@75064).
- Categoria del chip: se infiere del contenido del corchete: comillas al inicio = cita; esquema o www = web; extension conocida = pdf, hoja, imagen o archivo, y la etiqueta del chip es solo el nombre del archivo; "cell" = celda; "#" = canal; si no, generico (@73269).
- Ventana de la transcripcion: alto maximo de 4 renglones de 21 px; al desbordar se desplaza para mostrar la cola y marca el desborde para el fundido de arriba (@74137).
- Tras soltar: el parcial sigue visible hasta que llega el final; despues espera 350 ms y se desvanece en 260 ms (@77723 y @77850).
- Host nativo: el binario trae un crate `workflow-recording` con `hold_capture.rs`, `pollers.rs`, `browser_ax.rs`, `event_tap.rs` y `text_coalesce.rs` (incredible.md lineas 8450 a 8462). El formato que llega al modelo no aparece en las cadenas extraidas.

### Decisiones a tomar

- D1. Orden entre palabras y observaciones: indice de palabra al llegar (Incredible) o alineacion por tiempo de audio.
- D2. Formato de cada chip en la isla y como se representa el tejido (cadena con corchetes que se vuelve a parsear, o segmentos tipados).
- D3. Que se muestra en la isla y que se manda al modelo, y por que canal.
- D4. Limites y topes (isla, bloque del modelo, observador).
- D5. Privacidad.
- D6. Que pasa con el parcial que sigue cambiando, y con el final que lo reemplaza.

## 2. Estado actual

- Core ya modela los ocho tipos de observacion de Incredible, incluido `hovered` [repo:Sources/CompanionCore/Island/HoldCollect.swift:6]
- Solo archivo, texto seleccionado y copiado se apilan junto al orbe; el resto solo destella [repo:Sources/CompanionCore/Island/HoldCollect.swift:33]
- La forma tejida pone comillas tipograficas al texto propio y cambia corchetes por parentesis para que un titulo no cierre su propia marca [repo:Sources/CompanionCore/Island/HoldCollect.swift:57]
- El tope de etiqueta es 42 caracteres, igual que Incredible [repo:Sources/CompanionCore/Island/HoldCollect.swift:66]
- La regla del clic que abre ventana usa 800 ms [repo:Sources/CompanionCore/Island/HoldCollect.swift:68]
- Hoy la etiqueta de un archivo es el ultimo componente de la ruta, no la ruta completa que pidio Karen [repo:Sources/CompanionCore/Island/HoldCollect.swift:112]
- `mark` registra una marca por indice de palabra y solo para los tipos que se apilan, sin duplicar en el mismo indice [repo:Sources/CompanionCore/Island/HoldCollect.swift:162]
- `weave` devuelve una cadena con las marcas entre corchetes antes de su palabra y las que pasan del final al final [repo:Sources/CompanionCore/Island/HoldCollect.swift:174]
- El estado del compañero guarda las marcas en un diccionario indice-a-etiquetas [repo:Sources/CompanionUI/Overlay/HoldCompanionModel.swift:110]
- Recibir lotes no hace nada si no se esta escuchando [repo:Sources/CompanionUI/Overlay/HoldCompanionModel.swift:149]
- `woven(_:)` existe en el estado del compañero [repo:Sources/CompanionUI/Overlay/HoldCompanionModel.swift:183]
- Antes de marcar, el estado borra `detail` y `siteURL` del item: lo tejido solo lleva la etiqueta [repo:Sources/CompanionUI/Overlay/HoldCompanionModel.swift:190]
- Un test fija que la vista no guarda lo tecleado ni la direccion completa [repo:Tests/CompanionUITests/HoldCompanionTests.swift:197]
- La isla pinta `IslandTranscript` con el `partial` crudo del estado, no con el tejido: `woven(_:)` no tiene ningun llamador en Sources (grep de esta corrida) [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:80]
- `IslandTranscript` es un solo `Text` plano [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:69]
- La transcripcion se limita a 2 lineas [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:76]
- y se corta por la cabeza con elipsis [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:77]
- El parcial entra al estado solo mientras se escucha [repo:Sources/CompanionCore/Session/SessionMachine.swift:259]
- y se borra en cualquier fase que no sea escuchar o la espera de sus palabras [repo:Sources/CompanionCore/Session/SessionMachine.swift:326]
- Los parciales solo se emiten con el hold abierto [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:72]
- El oido de Apple se crea sin atributos de resultado, asi que no hay rangos de tiempo por palabra [repo:Sources/CompanionServices/Voice/Ear/AppleSpeechEngine.swift:97]
- El chip del compañero muestra `item.label` en una linea cortada por la cola [repo:Sources/CompanionUI/Overlay/HoldCompanion.swift:114]
- Los iconos por tipo ya existen como SF Symbols (archivo = doc) [repo:Sources/CompanionUI/Overlay/HoldCompanion.swift:178]
- El chip de la isla ya tiene un tope de ancho de 230 tomado del CSS de Incredible [repo:Sources/CompanionUI/Island/Data/IslandAnswerPieces.swift:45]
- Ya hay un `Layout` que envuelve hijos completos de linea en linea [repo:Sources/CompanionUI/Feedback/FeedbackAttachRow.swift:37]
- El carrete ya limpia caracteres invisibles, bidi y U+2800 de un nombre elegido por el modelo [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:96]
- El modelo hoy recibe lo que el cursor toco al hablar como bloque `pointed_while_speaking`, con segundos desde el inicio del hold [repo:Sources/CompanionCore/Perception/ContextBlock.swift:117]
- Ese bloque se llena desde el brief de pantalla en la voz clasica [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:627]
- y en la voz de VoiceSession [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Commit.swift:109]
- La traza del puntero se tope a 8 elementos y no se persiste [repo:Sources/CompanionCore/Perception/PointerTrace.swift:29]
- El bloque de contexto entero tiene tope de 1600 caracteres [repo:Sources/CompanionCore/Perception/ContextBlock.swift:25]
- El portapapeles al modelo se corta a 400 [repo:Sources/CompanionCore/Perception/ContextBlock.swift:19]
- Los eventos de la isla nunca se degradan, porque el turno los da por recibidos [repo:Sources/CompanionCore/Perception/ContextBlock.swift:29]
- Lo que se guarda en el historial es la linea compacta, sin contenido del portapapeles [repo:Sources/CompanionCore/Perception/ContextBlock.swift:157]
- El filtro de voz conoce una lista fija de etiquetas internas que no se leen en voz alta [repo:Sources/CompanionCore/Voice/SpeechFilter.swift:297]
- El sensor de portapapeles salta contenido oculto o transitorio [repo:Sources/CompanionServices/Perception/ContextSensors.swift:444]
- y para archivos del portapapeles da nombres, no rutas [repo:Sources/CompanionServices/Perception/ContextSensors.swift:409]
- `Log.app` escribe el mensaje tal cual al archivo, sin redaccion [repo:Sources/CompanionServices/Platform/Log.swift:67]
- Un snapshot test pinta `IslandTranscript` con texto plano [repo:Tests/CompanionUITests/AnswerPopupSnapshotTests.swift:105]
- PR #184: el lote de observaciones lleva la lista entera de la generacion en cada envio [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionCore/Island/HoldCollect.swift#L28-L36@5e8833f]
- PR #184: el indice de palabra es el conteo de palabras del parcial de la sesion en el momento de entregar el lote [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionApp/CompanionMainHold.swift#L19@5e8833f]
- PR #184: un lote que llega despues de soltar o de otra generacion se descarta [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionUI/Overlay/HoldObservationSync.swift#L68-L71@5e8833f]
- PR #184: los lotes solo van al compañero del puntero; nada los pasa al contexto del turno [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionUI/Overlay/HoldObservationSync.swift#L71@5e8833f]
- PR #184: el observador sondea cada 150 ms y guarda a lo sumo 4096 caracteres de una copia [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionServices/Perception/HoldObserver.swift#L118-L120@5e8833f]
- PR #184: una copia de un gestor de contrasenas (marcada oculta) nunca se lee [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionServices/Perception/HoldObserver.swift#L75-L77@5e8833f]
- PR #184: de una pagina solo se guarda el origen (esquema y host), sin ruta, query, fragmento ni credenciales [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionServices/Perception/HoldObserver.swift#L191-L203@5e8833f]
- PR #184: titulos y dialogos se cortan a 512 caracteres al leerse [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionServices/Perception/HoldObserver.swift#L18@5e8833f]
Contextos: app instalada con voz clasica (hold FN, oido de Apple) y con voz realtime (parcial del oido de auditoria); swift test (observador con `polls: false` y fakes de superficie y portapapeles, sin AX ni TCC); snapshot tests de la isla (AnswerPopupSnapshotTests); CI macOS (sin TCC: la superficie solo da el nombre de la app). No hay previews en Island.

## 3. Fuentes primarias

- `changeCount` sube cada vez que cambia el dueno del portapapeles; comparar valores dice si hubo copia, no que se copio [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nspasteboard/changecount.json@macOS26-sdk]
- La convencion nspasteboard.org: `TransientType` es contenido momentaneo que no se debe registrar ni mostrar; `ConcealedType` es confidencial, no se guarda a archivo y se ofusca al mostrar [doc:https://nspasteboard.org/@2026-10-04]
- `TextRenderer` reemplaza el dibujo de un `Text`, macOS 14+ [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/textrenderer.json@macOS26-sdk]
- `Text.customAttribute(_:)` adjunta un atributo que un renderer puede consultar, macOS 14+ [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/text/customattribute(_:).json@macOS26-sdk]
- `Text.Layout` expone lineas y corridas de glifos de un arbol de `Text` [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/text/layout.json@macOS26-sdk]
- `Text.TruncationMode` tiene cabeza, medio y cola, y se aplica a la linea de la vista [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/text/truncationmode.json@macOS26-sdk]
- `Layout` define la geometria de un contenedor propio cuando HStack o Grid no alcanzan, macOS 13+ [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/layout.json@macOS26-sdk]
- `accessibilityLabel(_:)` da a la vista una etiqueta que describe su contenido para VoiceOver [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/accessibilitylabel(_:)-1d7jv.json@macOS26-sdk]
- `SpeechTranscriber.ResultAttributeOption.audioTimeRange` agrega rangos de tiempo al texto transcrito, macOS 26 [doc:https://developer.apple.com/tutorials/data/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange.json@macOS26-sdk]
- OWASP LLM01: la inyeccion indirecta llega por fuentes externas (sitios, archivos); mitigacion: separar y marcar con claridad el contenido no confiable [doc:https://genai.owasp.org/llmrisk/llm01-prompt-injection/@2025]
- Guia de prompting de Anthropic: envolver cada tipo de contenido (instrucciones, contexto, entrada) en su propia etiqueta XML reduce malas interpretaciones [doc:https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices@2026-10]

## 4. Implementaciones de referencia

- Zed (editor, zed-industries, unas 91k estrellas, push del 2026-10-03): el mensaje del usuario conserva cada mencion como enlace corto en su posicion y el contenido viaja aparte en un bloque de contexto; es el mismo problema (referentes entrelazados con texto del usuario, contenido para el modelo) resuelto en produccion [ref:https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/agent/src/thread.rs#L489@a846890]
- Zed abre el bloque con una frase propia que dice que los items los adjunto el usuario, antes de los archivos y selecciones [ref:https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/agent/src/thread.rs#L337-L339@a846890]
- Zed solo inserta el bloque si hubo algun item, despues del texto del usuario [ref:https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/agent/src/thread.rs#L576-L583@a846890]
- El enlace inline de Zed es nombre corto mas URI, no el contenido [ref:https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/acp_thread/src/mention.rs#L591-L594@a846890]
- Maccy (gestor de portapapeles de macOS, unas 21.8k estrellas, push del 2026-10-03): ignora los tipos oculto y transitorio de nspasteboard.org [ref:https://github.com/p0deje/Maccy/blob/b2a7c413f7ecb6f2e5930dad1519e7b495177fab/Maccy/Clipboard.swift#L27-L31@b2a7c41]
- Maccy detecta copias comparando `changeCount` con el ultimo visto, el mismo mecanismo que el observador del PR #184 [ref:https://github.com/p0deje/Maccy/blob/b2a7c413f7ecb6f2e5930dad1519e7b495177fab/Maccy/Clipboard.swift#L152-L156@b2a7c41]

## 5. Opciones

D1. Orden

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| 1a. Indice de palabra al llegar el lote (Incredible) | ya implementado en Core y en el PR #184; igual a Incredible; determinista en tests | el parcial va detras de la voz: una marca puede caer una palabra antes de donde se dijo | baja | Recomendada |
| 1b. Alinear por tiempo de audio (`audioTimeRange`) contra el reloj del observador | posicion mas fiel | dos relojes distintos; cambia la configuracion del oido; el realtime usa otro oido | alta | No en v1 |

D2. Representacion y chip

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| 2a. Cadena con corchetes que la vista vuelve a parsear (Incredible) | igual a Incredible; ya existe `weave` | parsear lo que uno mismo serializo; un corchete en un titulo o una ruta de mas de 120 rompe el chip; el chip no sabe su tipo, lo adivina | baja | No |
| 2b. Segmentos tipados (texto o chip con su `HoldItem`) y un `Layout` que envuelve palabras y chips | cada chip es una vista: icono, capsula, ruta completa cortada al medio; sin parseo ni inyeccion por corchetes | muchas vistas por palabra; hay que dar a VoiceOver una sola etiqueta | media | Recomendada |
| 2c. Un solo `Text` con `TextRenderer` y atributo propio que dibuja la capsula | un Text, misma tipografia y corte | el renderer dibuja pero no reserva espacio; no hay corte al medio de una sola corrida | media | No |

D3. Isla vs modelo

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| 3a. Isla teje solo archivo, seleccion y copia (Incredible); el modelo recibe un bloque propio de datos con todos los tipos en orden de tiempo, cada uno con su indice de palabra, y la transcripcion del usuario intacta | separa datos no confiables de la voz del usuario (OWASP, guia de Anthropic); sigue el patron ya probado de `pointed_while_speaking`; el historial guarda la frase limpia | el modelo tiene que unir el indice con la frase | media | Recomendada |
| 3b. Mandar al modelo la cadena tejida como mensaje del usuario | lo que ve la isla es lo que lee el modelo | texto seleccionado de una pagina entra con la autoridad de la usuaria; corchetes en el historial; sin contenido completo | baja | No |
| 3c. Hibrido Zed: marca corta inline en el mensaje mas bloque con el contenido | posicion explicita en la frase | cambia lo que la usuaria dijo y lo que se guarda; el filtro de voz y la memoria verian marcas | media | Alternativa si 3a falla en la prueba de la seccion 9 |

## 6. Evidencia en contra

- Contra 2b: Incredible usa la cadena con corchetes, y la regla de la casa es replicar a Incredible cuando ya resolvio la decision [repo:Sources/CompanionCore/Island/HoldCollect.swift:174]
- Resolucion: lo visible es identico (chip con icono en su posicion de palabra); solo cambia la representacion interna, y la cadena no puede mostrar la ruta completa de Karen porque el chip de Incredible reduce todo archivo a su nombre [KAREN:relayed by orchestrator 2026-10-03, b2b-2 / PR #222]
- Contra 3a: no se sabe que recibe el modelo de Incredible; un bloque aparte puede no ser lo que hace [repo:Sources/CompanionCore/Perception/ContextBlock.swift:117]
- Resolucion: se acepta; el front de Incredible no usa el tejido para nada mas que la vista, y el canal de datos con su marco de "contexto, no instrucciones" es el que Companion ya usa para lo apuntado al hablar [doc:https://genai.owasp.org/llmrisk/llm01-prompt-injection/@2025]
- Contra mandar contenido seleccionado o copiado al modelo: es contenido de terceros y puede ser sensible [doc:https://nspasteboard.org/@2026-10-04]
- Resolucion: el contenido marcado oculto o transitorio nunca se lee, el resto va con tope y escapado dentro del bloque, y nunca a logs ni al historial [repo:Sources/CompanionServices/Perception/ContextSensors.swift:444]

## 7. Ejemplares y anti-ejemplos

- Bien: el contenido de las menciones va en un bloque de contexto con su propia frase de encuadre, y el texto del usuario solo lleva una referencia corta [ref:https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/agent/src/thread.rs#L337-L339@a846890]
- Bien: un bloque de contexto con atributo de tiempo por item y texto escapado y cortado, ya en el repo [repo:Sources/CompanionCore/Perception/ContextBlock.swift:117]
- Bien: neutralizar en la etiqueta los caracteres que la vista o el parser tratan como estructura [repo:Sources/CompanionCore/Island/HoldCollect.swift:59]
- Bien: quitar bidi, ancho cero y U+2800 antes de mostrar un texto ajeno [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:96]
- Bien: ignorar por tipo lo oculto y lo transitorio antes de leer la cadena [ref:https://github.com/p0deje/Maccy/blob/b2a7c413f7ecb6f2e5930dad1519e7b495177fab/Maccy/Clipboard.swift#L27-L31@b2a7c41]
- Anti-ejemplo: escribir en el log el texto seleccionado (lo hace SelectedTextKit, citado en el brief de Finder) [ref:https://github.com/tisfeng/SelectedTextKit/blob/93dc960a5ef8d52de98af41d4abd7a89576d091c/Sources/SelectedTextKit/Accessibility/AXManager.swift#L51@93dc960]
- Anti-ejemplo: tejer en una cadena y mandar esa cadena como mensaje del usuario, que mezcla datos externos con su voz [doc:https://genai.owasp.org/llmrisk/llm01-prompt-injection/@2025]

## 8. Trampas

- `woven(_:)` no tiene llamador: si la spec solo "activa el tejido" sin cablear la isla, no se ve nada [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:80]
- El compañero vive en `ScreenOverlays`, otra ventana; la isla tiene que leer ese mismo modelo o una copia en Core, no crear otro [repo:Sources/CompanionUI/Overlay/ScreenOverlay.swift:42]
- El estado del compañero borra `detail` antes de marcar: el bloque del modelo no puede salir de ahi, tiene que salir del lote del observador [repo:Sources/CompanionUI/Overlay/HoldCompanionModel.swift:190]
- Con 2 lineas cortadas por la cabeza, los chips del principio son lo primero que desaparece; hace falta la ventana de lineas de la cola [repo:Sources/CompanionUI/Island/Work/IslandWorkPieces.swift:76]
- Cambiar la etiqueta de archivo a ruta completa cambia tambien el chip del compañero, que hoy corta por la cola y perderia el nombre del archivo [repo:Sources/CompanionUI/Overlay/HoldCompanion.swift:114]
- Una etiqueta nueva del bloque de contexto que no este en la lista del filtro de voz puede leerse en voz alta [repo:Sources/CompanionCore/Voice/SpeechFilter.swift:297]
- El bucle de degradacion del bloque no conoce el campo nuevo: sin un caso propio el bloque puede pasar de 1600 [repo:Sources/CompanionCore/Perception/ContextBlock.swift:25]
- Una copia durante el hold tambien llega por el sensor de portapapeles: sin deduplicar, el modelo la lee dos veces [repo:Sources/CompanionCore/Perception/ContextBlock.swift:19]
- `Log.app` no redacta: cualquier etiqueta, ruta o texto pasado a un log queda en Companion.log [repo:Sources/CompanionServices/Platform/Log.swift:67]
- El flujo de parciales que mide el indice cambia segun el pipeline; si el texto final difiere del ultimo parcial, las marcas reaplicadas por indice pueden correrse (ver la prueba de la seccion 9) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:69]
- Contexto app clasica: el parcial es el texto actual del transcriptor de Apple y el indice se mide sobre el [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:74]
- Contexto app realtime: el parcial es el texto del turno del oido de auditoria y se mide sobre ese [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:73]
- Contexto swift test: el observador se maneja con `tick()` y fakes; ningun test toca AX real, asi que la lectura real de Finder y seleccion solo se prueba a mano [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionServices/Perception/HoldObserver.swift#L132-L135@5e8833f]
- Contexto snapshot: el snapshot actual de `IslandTranscript` pasa un `String`; con segmentos su firma cambia y el snapshot se regenera [repo:Tests/CompanionUITests/AnswerPopupSnapshotTests.swift:105]
- Contexto CI: sin Accesibilidad la superficie solo trae el nombre de la app, asi que no hay titulos, URL ni dialogos que tejer [ref:https://github.com/karenrebecag/Companion/blob/5e8833f36a28f2fb5ff1952e0ef7d32756e7bd5d/Sources/CompanionServices/Perception/HoldObserver.swift#L209@5e8833f]

## 9. Incertidumbre

- ASSUMPTION: el bloque aparte con indice de palabra basta para que el modelo resuelva "esto" al item correcto (3a). prueba: 10 turnos grabados con dos items en posiciones distintas ("abre este y despues este"), comparar acierto de 3a contra 3c con el mismo modelo; si 3a acierta menos de 9/10, pasar a 3c.
- ASSUMPTION: Incredible manda al modelo algo distinto de la cadena tejida (el front no la reusa). prueba: con Incredible instalado, sin tocar el .app, sostener la tecla, seleccionar texto y decir "que dice esto"; si responde citando el texto completo y no solo la etiqueta de 42, el host manda contenido aparte.
- ASSUMPTION: un `Text` no puede cortar al medio solo una corrida, por eso la ruta va en su propia vista. prueba: un snapshot de `Text("a ") + Text(rutaLarga)` con `.truncationMode(.middle)` y `lineLimit(1)` y ver si corta la ruta o la linea.
- ASSUMPTION: 230 de ancho de chip deja ver nombre y carpeta de una ruta tipica de Documentos cortada al medio. prueba: snapshot con /Users/x/Library/Mobile Documents/com~apple~CloudDocs/Proyectos/2026/plan-final.pdf.
- ASSUMPTION: la marca se corre como mucho una palabra entre el ultimo parcial y el texto final. prueba: test con un fake de oido que emite parcial y final distintos y mide la posicion de la marca en ambos.
- Resuelto: la ruta completa va solo en el chip de la transcripcion (cortada al medio, 230); el chip del compañero en el puntero muestra el nombre, como Incredible [KAREN:respuesta en la sesion Companion1 2026-10-05]
- Resuelto: el texto seleccionado y copiado va completo al modelo, con tope de 400 por item, en el bloque aparte y escapado; nunca en logs [KAREN:respuesta en la sesion Companion1 2026-10-05]
- Resuelto: el texto tecleado (b2c) va solo al modelo, en el bloque aparte; no se teje en la isla, que solo lo destella en el orbe como Incredible; los campos seguros nunca se leen [KAREN:respuesta en la sesion Companion1 2026-10-05]
- Resuelto: se acepta la desviacion 2b (segmentos tipados con `Layout` que envuelve, en vez de la cadena con corchetes de Incredible) porque el chip con ruta completa no cabe en la cadena; queda en un ADR que firma Karen [KAREN:respuesta en la sesion Companion1 2026-10-05]

## 10. Checklist de estandar

- [ ] La isla pinta la transcripcion tejida, no el parcial crudo, mientras se escucha y mientras espera sus palabras.
- [ ] Solo archivo, texto seleccionado y copiado se tejen en la isla; ventana, pestana, clic, celda, dialogo y tecleado solo destellan en el orbe.
- [ ] Cada item tejido se ancla al conteo de palabras del parcial al llegar su lote; la misma etiqueta no se repite en el mismo indice; las marcas mas alla del final van al final en orden de indice.
- [ ] Marcas y pila se vacian al empezar un hold y al empezar un dictado; un lote de otra generacion o tras soltar se descarta.
- [ ] El tejido es una lista de segmentos tipados (texto o chip), no una cadena que se vuelve a parsear; un titulo con corchetes no crea ni rompe un chip (test).
- [ ] Chip: icono del tipo, etiqueta en una linea; texto entre comillas cortado a 42; archivo con la ruta completa cortada al medio y ancho tope de chip de la isla.
- [ ] La transcripcion muestra la ventana de lineas de la cola (la mas nueva abajo); un chip del principio no desaparece antes que las palabras que lo siguen.
- [ ] VoiceOver lee la transcripcion como una sola etiqueta con los chips en su lugar.
- [ ] El modelo recibe un bloque propio dentro del contexto con todos los items del hold en orden de tiempo, cada uno con su tipo, indice de palabra y segundos desde el inicio, escapado; la frase del usuario va sin corchetes.
- [ ] El bloque tiene tope de items y de caracteres por item, entra en el bucle de degradacion sin pasar de 1600, y una copia que tambien esta en el portapapeles no se manda dos veces.
- [ ] La etiqueta nueva esta en la lista del filtro de voz (test que la hace aparecer en una respuesta y no se lee).
- [ ] Nada de lo observado (etiquetas, rutas, texto, URL) llega a Companion.log ni a la linea compacta del historial; solo conteos y tipos (test sobre el log capturado).
- [ ] Contenido marcado oculto o transitorio nunca se lee; de una pagina solo se guarda el origen.
- [ ] Nada se observa ni se teje fuera del hold de FN.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Incredible 0.2.36, overlay del front (referencia local) | Incredible | 0.2.36, sha256 9d280ba68346 | 2026-10-04 | high |
| 2 | Incredible 0.2.36, cadenas del binario (referencia local) | Incredible | 0.2.36, sha256 e04e9fa2f699 | 2026-10-04 | medium |
| 3 | NSPasteboard changeCount | Apple | SDK macOS 26 | 2026-10-04 | high |
| 4 | nspasteboard.org, marcadores de tipo | comunidad nspasteboard.org | pagina vigente | 2026-10-04 | medium |
| 5 | TextRenderer, Text.customAttribute, Text.Layout, Text.TruncationMode, Layout, accessibilityLabel | Apple | SDK macOS 26 | 2026-10-04 | high |
| 6 | SpeechTranscriber audioTimeRange | Apple | macOS 26 | 2026-10-04 | high |
| 7 | OWASP LLM01 Prompt Injection | OWASP GenAI | 2025 | 2026-10-04 | high |
| 8 | Guia de prompting, etiquetas XML | Anthropic | 2026-10 | 2026-10-04 | high |
| 9 | Zed, thread.rs y mention.rs | zed-industries | a846890 | 2026-10-04 | high |
| 10 | Maccy, Clipboard.swift | p0deje | b2a7c41 | 2026-10-04 | high |
| 11 | Companion PR #184 (hold observer) | karenrebecag | 5e8833f | 2026-10-04 | high |
| 12 | Brief finder-seleccion-ax (rama docs/brief-finder-seleccion-ax) | Companion | 2026-10-03 | 2026-10-04 | high |
