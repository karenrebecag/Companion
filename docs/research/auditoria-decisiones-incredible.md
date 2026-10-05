# Auditoría v2: qué hace Incredible en 7 decisiones abiertas de Companion

Fecha: 2026-09-29. Solo lectura. No se copió código, prompts ni textos de Incredible a Companion, y este
brief ya no cita cadenas, nombres de archivos del bundle, posiciones ni nombres internos de comandos o
eventos: lo que Incredible hace se describe en palabras, y el detalle solo se consulta en la referencia
local. No se abrió nada de `~/.incredible`.

## Fuentes y método

- Frontend y backend de la app instalada, inspeccionados en solo lectura, más sus metadatos de empaquetado
  y de permisos (referencia local para el detalle).
- Companion: `companion-next-ui-gap-f`, HEAD `d5b170b`. Árbol idéntico a `origin/feat/ui-gap`
  (`8efc1dd`): `git diff --stat HEAD origin/feat/ui-gap` sale vacío.

Nota de arquitectura, necesaria para leer todo lo demás: Incredible no usa un modelo realtime
speech-to-speech. Tiene un orquestador de voz (STT, LLM, TTS) que no ejecuta nada por sí mismo.
Delega en agentes de fondo, y los agentes llaman a los conectores dentro de una celda Python. Lo que el
usuario decide aparece como tarjeta en la isla. En Incredible, "durante la voz" significa "mientras hay
una sesión de voz y trabajan agentes"; no existe un equivalente al `mcp_approval_request` del lado del
servidor.

---

## 1. Aprobaciones de tools de MCP externos durante la voz

### (a) Incredible

Son tres capas, todas verificadas (referencia local para el detalle):

1. **Confianza por servidor MCP (ajustes).** El detalle de un servidor MCP propio tiene un interruptor
   para correr las consultas sin preguntar. Encendido, las lecturas corren sin preguntar y todo lo que
   cambia o borra sigue preguntando; apagado, todas las acciones preguntan.
   - La configuración guarda si el servidor es de confianza y un hash de sus tools aprobadas. Si las
     tools del servidor cambian, aparece un aviso con un botón para aprobarlas de nuevo: es un pin del
     manifiesto de tools.
   - No se pudo determinar el valor por defecto de la confianza en un servidor nuevo.
2. **Juez automático (clasificador) antes de cada lote de escrituras.** Las lecturas pasan sin tarjeta;
   las escrituras y los borrados van a un juez LLM.
   - El juez aprueba lo que se puede deshacer, y lo irreversible o lo que llega a otra persona solo si
     el usuario lo cubrió con sus propias palabras en una tarjeta que confirmó. Rechaza lo que viene de
     una instrucción incrustada en una web, un correo o un documento.
   - Si el juez rechaza, el agente tiene que mostrar una tarjeta de plan o borrador y esperar el "go".
   - Hay un segundo clasificador para comandos destructivos, con dos salidas: permitir o preguntar.
3. **La tarjeta en la isla es la UI de aprobación.** Tiene botones de confirmar (o conectar) y de
   rechazar. Al confirmar, la isla emite un evento de "go" que lleva el elemento y su versión, y el go
   queda fijado a la versión mostrada: una versión vieja ya no se puede confirmar.
   - La tarjeta también se aprueba por voz: un sí dicho en voz alta vale como go. Ver la decisión 3.
   - Las acciones ya ejecutadas tienen una cadena de estados (aprobada, denegada, cancelada, rechazada
     por el revisor, etc.).

No se encontró el componente del diálogo de aprobación del clasificador de comandos. Las tarjetas de
aprobación que sí existen en código son la de subida de archivos ("No permitir" / "Permitir siempre",
Escape = no) y la del go.

### (b) Companion hoy

- Los servidores MCP propios van al servidor de OpenAI Realtime con `require_approval` en `"always"`
  por defecto: `Sources/CompanionCore/MCPTools.swift:42` (y `OwnMCP.swift:48`, que a propósito no
  escribe `requireApproval`).
- Cuando llega `mcp_approval_request` (`RealtimeCodec.swift:63`), `RealtimeRuntime.swift:271-280`
  aparca la petición (`onMCPApproval`) y le inyecta al modelo el texto de `MCPTools.swift:53-66`, que
  le pide al modelo que pregunte en voz alta y después llame a `resolve_approval`.
- **No existe UI para esta petición.** `VoiceSession.swift:283` solo guarda `pendingMCPApproval`, y
  en `Sources/CompanionUI` no hay nada de MCP approval (grep de `mcp.*sheet|MCPApproval` sin
  resultados).
- El sí hablado la resuelve por la rama HACK, sin `SpokenYes`: `VoiceSessionApprovals.swift:47-58`.
- Las escrituras `app:` y las tools del propio padre sí pasan por la hoja: `ParentToolGuard` en
  `VoiceSession.swift:289-296`, con la hoja `ApprovalSheet.swift` y auto-denegación a los 60 s
  (`ApprovalPorts.swift:7`).

### (c) Cambio mínimo para igualarlo

1. Llevar el `mcpApprovalRequest` a la misma cola que ve la hoja. Basta con emitir
   `.job(.approvalRequested(request))` como hace `ParentToolGuard` (`VoiceSession.swift:289-294`) y
   responder con `RealtimeCodec.mcpApprovalResponse` cuando la hoja resuelva. Con eso la aprobación
   se hace con clic, que es lo que Incredible hace con los botones de su tarjeta.
2. Opcional, para igualar su interruptor de consultas sin preguntar: un `Bool` por servidor en
   `MCPServerConfig` que, cuando está activo, mande `require_approval` en su forma por nombre
   (`{"never":{"tool_names":[…]}}`) solo para las tools marcadas `readOnlyHint`. Si no hay anotación,
   la tool se queda en `always`.
3. Opcional: fijar un hash del manifiesto de tools y avisar cuando cambie, como hace Incredible.

### (d) ¿Debilita un invariante?

- La hoja: no. Añade la vía del clic y el HACK puede quedar como está.
- Si además se quiere igualar el "sí hablado aprueba" de Incredible para MCP: el invariante literal
  ("el sí nunca aprueba escrituras `app:`") no aplica, porque el `toolName` es `server/tool`, no
  `app:`. Pero la razón de ese invariante (F-D, `VoiceSessionApprovals.swift:76-80`: la salida de un
  servidor puede inyectar un "sí") es idéntica para un MCP externo. Incredible compensa esa vía con
  el juez LLM y con el go fijado a una versión; Companion no tiene ninguna de las
  dos cosas. Recomendación: poner la hoja y pasar la rama MCP por `SpokenYes.admits`, que en
  realtime devuelve `false`. Eso cierra el HACK por la condición que su propio comentario da como
  trigger ("when a sheet exists for MCP approvals").

---

## 2. Stop

### (a) Incredible

**Hay varios controles y cada uno para una cosa distinta. Ninguno para "todo".** (referencia local para el detalle)

- **Orbe o píldora de la isla ("Click to stop"):** interrumpe **el turno del orquestador**, el habla y el
  pensamiento. Los agentes siguen trabajando y sus reportes quedan en cola. Las aprobaciones y ediciones
  pendientes se cancelan.
- **Parar una tarea concreta:** por agente.
- **Parar la ejecución de un workflow.**
- **Por voz:** el orquestador puede parar un agente a la vez; para "parar todo" para cada uno en el mismo
  turno. Una tarea programada se para solo por esta corrida. Parar no deshace nada.
- **Cancelar la acción de conector en vuelo:** el agente recibe que el usuario la canceló y que no debe
  reintentarla.
- La ayuda de la ventana principal dice que un clic en la píldora para en el acto, que redirigir se hace
  con otro hold y que el trabajo terminado se queda.
- Al agente parado le llega que no debe reiniciar el trabajo solo.

### (b) Companion hoy

**Hay un solo freno que para todo.**

- El evento `.stop` (`SessionTypes.swift:211-212`: "Esc, the Stop button, "stop"") llega a
  `SessionMachine.swift:251-264`. Corta la salida de voz (`.cancelVoiceOutput`), descarta el hold en
  curso (`.stopListening(commit:false)`) y llama a `stop()` (`SessionMachine.swift:450-472`), que
  cancela el job y la cola (`.cancelJob`), **deniega todas las aprobaciones pendientes**, abandona el
  turno escrito y marca `.userStopped`.
- `.cancelJob` llama a `JobRunner.cancel()` y de ahí a `JobQueue.cancelAll()`
  (`JobQueue.swift:93-100`, `stopEpoch += 1`), que para el job en vuelo y todos los que esperan.
- Quién dispara `.stop`: el chip "Parar" de la isla (`IslandView+Status.swift:52-54`, `stop()` en
  136-149; si hay job usa `chat.cancelJob()`, que también manda `.stop`, en
  `ChatViewModelJobs.swift:68`) y el menú de la barra (`CompanionMainWindow.swift:190-193`).
- Por voz, la tool `stop_job` (`ToolSpec.swift:82-100`) llega a `onStopJob = { await jobs.cancel() }`
  (`VoiceSession.swift:254`). Para jobs, no la voz.
- Las tools MCP de realtime corren en el servidor de OpenAI y Companion no puede cancelarlas una vez
  aprobadas.

### (c) Cambio mínimo para igualarlo

Separar los dos frenos:
1. El orbe o chip de la isla durante voz sin job: solo `.cancelVoiceOutput` y `.stopListening`, sin
   `stop()`.
2. El freno de la tarea: `chat.cancelJob()` para el job y su cola. Incredible para por agente, pero
   como la cola de Companion es serial, "la tarea" equivale al job actual.
3. `stop_job` por voz ya se parece al parar-agente de Incredible y se queda igual.

Hoy `IslandView+Status.swift:136-141` ya elige entre job y sesión, pero la rama de sesión termina
igualmente en `stop()`, que cancela jobs.

### (d) ¿Debilita un invariante?

No toca ninguno de los tres. Sí pierde una propiedad de seguridad que Companion tiene y no está en
la lista: hoy el freno de voz **deniega las aprobaciones pendientes** (`SessionMachine.swift:456-459`).
Si se iguala a Incredible, que solo interrumpe el turno, una hoja pendiente sobreviviría al "para".
Recomendación: si se separan los frenos, que el freno de voz siga denegando las aprobaciones
pendientes. Incredible hace algo equivalente, porque su abort cancela la aprobación de celda en curso.

---

## 3. "Sí" hablado

### (a) Incredible

- **Un sí aprueba.** El orquestador, ante un "looks good, send it", quita la tarjeta y le pasa el go al
  agente en la misma respuesta. También puede dar el go para lo que el usuario ya aceptó.
- **La voz no lee la tarjeta entera.** Dice una frase corta; la tarjeta lleva el texto exacto que se va a
  mandar y el usuario lo lee ahí. Los nombres de archivo y las rutas no se dicen: los muestra la tarjeta.
- **Restricciones.** Todas son a nivel de modelo; no hay ninguna compuerta determinista.
  - El orquestador interpreta el sí. No existe una regla que ate el sí a que la pregunta haya sonado
    antes, como hace el `announcedAt` de Companion.
  - El juez vuelve a comprobar la cobertura sobre la conversación y las tarjetas confirmadas, y rechaza
    lo que viene de una web, un correo o un documento.
  - El go por clic va fijado al elemento y a la versión. El go hablado viaja como texto de contexto.
  - Hay campos de estado de voz en las tarjetas presentadas. **No se pudo determinar** si limitan el sí
    hablado: solo se encontraron nombres de campo, ningún mensaje de log ni texto de política.

### (b) Companion hoy

- `SpokenYes.admits` (`Acknowledgement.swift:52-58`) no admite nunca un sí en realtime, y en clásico
  solo si la voz dijo la pregunta y el hold empezó después, con un dwell de 0,6 s
  (`IslandState.swift:263`).
- Las escrituras `app:` no se aprueban nunca por voz (`VoiceSessionApprovals.swift:75-84`).
- La voz no pregunta, por decisión de producto del 2026-08-22 (`VoiceSessionApprovals.swift:26-33`):
  `approvalAnnounced` no tiene ningún llamador, así que en la práctica todo sí pide el clic.
- Un no hablado siempre se acepta (`VoiceSessionApprovals.swift:63-65`).
- Excepción: la rama HACK de MCP (`VoiceSessionApprovals.swift:47-58`), ver la decisión 1.

### (c) Cambio mínimo para igualarlo

Igualarlo del todo significa que un sí hablado aprueba en realtime. Eso exige quitar la condición
`!realtime` de `SpokenYes.admits` y la exclusión de `app:`.

La parte que se puede igualar sin riesgo es "la voz pregunta con una frase". Consiste en llamar a
`approvalAnnounced(requestId)` cuando la voz dice la pregunta, en clásico, que es la costura que ya
existe (`VoiceSessionApprovals.swift:31-33`). Así un sí dado después vale, excepto para `app:`.

### (d) ¿Debilita un invariante?

**Sí, si se iguala del todo.** Rompe "el sí hablado nunca aprueba escrituras `app:`". Incredible
acepta ese riesgo porque detrás tiene el juez LLM y el go fijado a una versión; Companion no tiene
equivalente. Recomendación: **no igualar el sí para `app:` ni en realtime.** Igualar solo "pregunta
con una frase" en clásico, con el anuncio.

---

## 4. Ubicación

### (a) Incredible

**Incredible no tiene ninguna función de ubicación.** (referencia local para cómo se comprobó)

- No enlaza CoreLocation en ninguno de sus tres binarios.
- No declara permiso de ubicación en su `Info.plist` ni la entitlement correspondiente.
- No hay ajuste. En el frontend, ubicación solo aparece en ejemplos de conectores.
- **Al modelo le llega la hora local con su desfase UTC.** No le llega ciudad ni coordenadas.
- Las búsquedas cercanas no tienen un sitio propio: van a conectores de lugares o al navegador del
  usuario. La ubicación la infiere el servicio, o el agente pregunta.

### (b) Companion hoy

- La ciudad sale de Ajustes y, si ese campo está vacío, de CoreLocation
  (`UserLocation.swift:55-70`, `UserLocationSource`). La cachea `CachedCityLocator`
  (`CityLocator.swift:9-40`).
- El canal de contexto "Tu ciudad" se puede apagar (`ContextSettings.swift:82-85`). Por migración
  arranca encendido (`ContextSettings.swift:22-27`). Cuando está encendido, cada turno lleva
  `<user_location>ciudad, país</user_location>` (`ContextBlock.swift:86`), y nunca se piden permisos
  en un turno (`ContextSensors.swift:93-96`, "Never `prompting`").
- **La búsqueda cercana no respeta ese interruptor.** `NativeToolRunner.swift:326-332` llama a
  `location.current(prompting: true)` para "near me". El texto de Ajustes lo reconoce
  (`es.lproj/Localizable.strings:216`: "Apagado, deja de acompañarlos, pero una búsqueda de algo
  cerca todavía puede pedirle la ubicación a macOS").
- No hay coordenadas: el tipo no tiene dónde guardarlas (`UserLocation.swift:3-5`). Los logs solo
  registran el tipo de fallo (`CoreLocationCity.swift:51`, 110 y 115).
- La hora con desfase UTC va igual que en Incredible (`ContextBlock.swift:78`, 350-355).

### (c) Cambio mínimo para igualarlo

- **Paridad literal**: quitar la ubicación. Eso borra `CoreLocationCity`, el canal `.location` y la
  resolución de "near me", y vuelve a abrir el fallo de "Restaurantes cercanos" desde Fullerton que
  documenta `UserLocation.swift:72-74`. No se recomienda.
- **Paridad de comportamiento**, que es lo que parece preguntarse: que con el canal apagado no se
  mande nada y no se pida permiso. El cambio mínimo es pasar el estado del canal a
  `NativeToolRunner`: con el canal apagado, `prompting: false` y, si no hay ciudad en Ajustes,
  devolver `NearMe.needsCity`. Son unas 5 líneas en `NativeToolRunner.swift:326-332` más el cableado
  en `CompanionMainSensing.swift:83-86`.

### (d) ¿Debilita un invariante?

No. "Solo la ciudad, sin coordenadas y nunca en logs" se mantiene con las dos opciones. La segunda
lo refuerza, porque el interruptor pasa a significar lo que dice.

---

## 5. Tarjeta de opciones

### (a) Incredible

- **No tiene atajos numéricos.** El bloque de opciones pinta un badge con el número de la opción, pero es
  solo visual. Se buscaron comparaciones de tecla con dígitos en todos los chunks sin resultado; las
  teclas que sí se leen son Enter, Escape, espacio, flechas, Home, End y Tab. La página de atajos solo
  trae unos pocos atajos de captura y de voz.
- **Elegir tiene dos pasos.** Un clic selecciona (en la variante radio sustituye la selección) y un botón
  Confirmar envía. Hay multiselección y un campo para escribir una respuesta propia.
- **Adónde va la respuesta.** Al agente que preguntó, en contexto.
- **Tools tras elegir.** El agente conserva el acceso a todos los conectores. Responder no es un go: el
  orquestador separa lo "confirmado" (el go) de lo "respondido". Si después hay que mandar algo, el juez
  sigue pidiendo tarjeta de plan o borrador. **Lo que no se pudo determinar** es si el juez cuenta una
  respuesta como cobertura porque aparece en la conversación.

### (b) Companion hoy

- Los dígitos 1-9 solo funcionan cuando la tarjeta tiene el teclado, y la tarjeta solo lo toma tras
  un clic o un Tab: `IslandChoiceCard.swift:44-62` (`.focusable`, `.focused`,
  `.onKeyPress(phases: .down)` en la línea 58, "takes the keyboard only when she asks" en la 59).
  Lo decide `IslandChoiceKeys` (`IslandChoice.swift:33-71`): solo dígitos ASCII 0x31-0x39 y sin
  modificadores. `IslandView.swift:51` guarda `focusedChoiceID`.
- Elegir es un solo paso: la elección se manda como mensaje del usuario marcado
  (`ChatViewModel.swift:241-248`, `dispatch(text, origin: .choice)`, y
  `ChoiceBlock.swift:3-6`). El modelo la ve con `[elección en tarjeta]`
  (`ChoiceBlock.swift:104-111`, `ChatViewModelTurn.swift:60`).
- No cuenta como consentimiento ni como mención de app: `said = origin == .choice ? "" : text`
  (`ChatViewModelTurn.swift:11-17`). `AppToolRunner.noteTurn("")` deja el alcance en `.none`
  (`AppToolRunner.swift:143-154`), así que **la primera petición del turno no lleva tools de apps**.
  Las rondas siguientes del mismo turno vuelven a llevar el set completo (`AppToolRunner.swift:192-198`,
  `scope = .allConnected`).

### (c) Cambio mínimo para igualarlo

- **Atajos**: Incredible no tiene. Igualarlo sería quitar los dígitos, y no hace falta, porque
  Companion es un superconjunto: los dígitos solo funcionan con el foco pedido. Se puede dejar como
  está.
- **Confirmación en dos pasos**: añadir un botón Confirmar y que el clic o el dígito solo seleccionen.
  El cambio va en `IslandChoiceState.pick` (llamado desde `IslandChoiceCard.swift:94`).
- **Tools tras elegir**: igualarlo es ofrecer las tools de apps en la primera petición de un turno de
  elección. Basta con no estrechar el alcance: pasar `.allConnected` en vez de `.none` cuando
  `origin == .choice`, **manteniendo `said = ""`** para la compuerta de consentimiento
  (`ParentToolGate.approval(for:said:)`, `ParentTools.swift:320-322`).

### (d) ¿Debilita un invariante?

- Confirmar en dos pasos: no. Lo refuerza.
- Ofrecer tools tras elegir: no, siempre que el texto elegido no entre en `said`. "Una elección no
  cuenta como consentimiento" se sostiene con `said = ""`, y las escrituras `app:` siguen necesitando
  el clic en la hoja. Se pierde algo de reducción de superficie: si una salida de tool manipuló las
  opciones, esa opción tendría tools de apps a mano en la primera petición. Aun así, cualquier
  escritura seguiría necesitando el clic.

---

## 6. Feedback

### (a) Incredible

- **Destino: su propio backend, no correo.** El reporte y su paquete de diagnóstico se suben a su
  almacenamiento en Supabase, se registran en una tabla de subidas y disparan funciones de reporte y de
  notificación. El reporte queda guardado y las respuestas se hacen por Intercom. Si falla la subida del
  diagnóstico, se manda el reporte sin él. (referencia local para el detalle)
- **No verificable en el extracto local:** Supabase aparece en los bundles solo para la sesión y los
  eventos; ninguno lo liga al reporte de feedback. Lo verificable es la llamada nativa
  `bug_report_submit`.
- **Campos del modal:**
  - Ánimo: 5 opciones, de frustrado a "love it".
  - Temas: 6 chips (hablar, navegador, apps, tareas programadas, dictado, otro).
  - Texto: tope de 5000 caracteres.
  - **Capturas: hasta 3**, de 4 MB cada una como máximo. Se añaden con el selector de archivos o
    pegándolas.
- **Segundo paso, "¿incluir lo que pasó?":** omitir o incluir. Si se incluye el diagnóstico, el texto
  explica que incluye lo que dijo la usuaria, lo que hizo la app, lo que devolvieron las apps y los
  modelos y lo que miró en pantalla, sin editar nada, que se borra a los 30 días y enlaza a su política
  de privacidad.
- **Versión y SO.** La versión de la app va con el diagnóstico. **No se pudo determinar** si el reporte
  lleva la versión del SO; solo aparece junto a la telemetría de producto.

### (b) Companion hoy

- Destino: `mailto:` sin destinatario, o el servicio de compartir `composeEmail` si hay capturas o el
  texto no cabe (`SystemFeedbackDelivery.swift:10-27`, `FeedbackModel.swift:137-149`,
  `Feedback.swift:81-87`).
- Campos: ánimo (5: upset, bad, meh, good, love), 6 temas, texto de hasta 5000 caracteres y hasta 3
  capturas de 4 MB (`Sources/CompanionCore/Blocks/Feedback.swift:5-28`). **Nada de la máquina**
  (`Feedback.swift:16-19`: "no server of ours… nothing about the machine").
- Capturas: hasta 3, con el selector de archivos o pegándolas
  (`Sources/CompanionUI/Feedback/SystemFeedbackDelivery.swift:35-113`).

### (c) Cambio mínimo para igualarlo

- **Destino y diagnóstico**: no hay cambio mínimo. Hace falta un endpoint propio, almacenamiento,
  política de retención y consentimiento. Es una decisión de producto, no un ajuste.
- **Lo que se puede igualar ya**:
  - 6 chips de tema en `FeedbackDraft`, que se añaden al cuerpo.
  - Subir el tope de texto a 5000. El `mailto` ya corta y avisa
    (`Feedback.swift:59-79`, `maxMailtoLength`).
  - Pegar imágenes desde el portapapeles además del recorte.
  - Mantener el tope de 3 capturas, que ya coincide.

### (d) ¿Debilita un invariante?

Los chips, el tope y el pegado: no. Adjuntar un diagnóstico como el de Incredible (palabras, pantalla
y salidas de apps y modelos) sí toca los invariantes indirectamente. Si el paquete lleva logs, la
ciudad está protegida porque nunca se escribe en logs y el tipo no tiene coordenadas. Pero mandaría
el `<user_location>` que va en cada turno si incluye los turnos. Si algún día se hace, el paquete
tiene que excluir `ContextBlock` o recortar `<user_location>`.

---

## 7. Mermaid

### (a) Incredible

- **Versión:** 11.17.2 de la librería, cargada bajo demanda.
- **Configuración del chat** (se aplica una sola vez): sin render automático al cargar, nivel de
  seguridad estricto, **tema "base"**, la pila de fuentes del sistema, curva suave y padding moderado en
  los flowcharts, y ancho máximo sin actores espejo en los diagramas de secuencia.
- **Paleta:** oscura, con fondo transparente, tonos oscuros para nodos y clusters, bordes y líneas como
  velos de blanco, acento azul y una paleta de ocho colores para los pies con trazo del color del fondo
  (referencia local para los valores).
- **Qué es el tema "default".** Es el tema por defecto de la librería; el chat lo sobrescribe con "base" y
  no toca los límites de tamaño de texto y de aristas, que siguen en los valores por defecto de la librería.
- **Render.** Primero se valida el código y después se renderiza; el SVG se inserta en un cuerpo con rol
  de imagen y etiqueta "Diagram". Si falla, cae a un bloque de código.
- **Contenedor.** Figura con relleno, borde y radio como los demás visuales de la isla, con
  desplazamiento horizontal si no cabe y SVG que ocupa como máximo el ancho. No hay alto fijo: lo da el
  SVG.
- **Herramientas.** Arriba a la derecha, visibles al pasar el ratón: "Copy image" y "Download PNG", cada
  una con opción de fondo o transparente. Se rasteriza al doble con un margen y el archivo toma el
  título o el tipo del diagrama.
  - **No hay herramienta de ver, ampliar ni pantalla completa.**

### (b) Companion hoy

- No hay Mermaid. Un bloque de código con lenguaje `mermaid` se pinta como código
  (`AnswerBlocks.swift:85-92`: si no es `companion:choice` ni una carga de tarjeta, es `.code`).
- 16m-5b sigue pendiente de que se apruebe la dependencia
  (`docs/specs/wave-16m-isla-componentes.md:104-108`).
- El contenedor `visual` de las gráficas ya existe (`IslandVisualMetrics.swift`: padding 14/16/12,
  radio `innerRadius`, lienzo de 240 y 264). Su única herramienta es copiar como **CSV**
  (`IslandVisualTools.swift:4-12`), no como imagen.

### (c) Cambio mínimo para igualarlo

- 16m-5b tal como está en D3: `mermaid.js` 11.17.2 vendoreado con hash, en un `WKWebView` aislado
  sin red. `initialize` con la misma forma: `strict`, `base`, `startOnLoad:false` y paleta oscura con
  los tokens de la isla. `maxTextSize` y `maxEdges` se quedan por defecto.
- Si falla, se pinta como código, que es lo que ya hace hoy.
- Herramientas: copiar imagen y descargar PNG, con fondo o transparente, a 2x.
- Para igualar el resto de gráficas: copiar imagen además del CSV.

### (d) ¿Debilita un invariante?

No toca ninguno de los tres. El riesgo propio es el `WKWebView`. Con `strict`, mermaid sanea
etiquetas y quita `click`/JS, y con la vista sin red ni puente JS hacia la app, la inserción del SVG
con `innerHTML` queda contenida. Es lo mismo que ya pide D3.

---

## Tabla resumen

| Decisión | Incredible (evidencia) | Companion hoy | Cambio | Riesgo |
|---|---|---|---|---|
| 1. Aprobación MCP en voz | Interruptor por servidor para correr consultas sin preguntar; juez LLM para escrituras; tarjeta en la isla con confirmar y rechazar, y un go fijado a la versión mostrada; pin del manifiesto de tools. El sí hablado también vale | `require_approval:"always"` (`MCPTools.swift:42`); sin UI; el modelo pregunta en voz alta (`MCPTools.swift:53-66`, `RealtimeRuntime.swift:271-280`); el sí se resuelve por el HACK sin `SpokenYes` (`VoiceSessionApprovals.swift:47-58`) | Llevar la petición MCP a la hoja existente (seam de `ParentToolGuard`, `VoiceSession.swift:289-294`) y pasar el HACK por `SpokenYes.admits`. Opcional: interruptor de lecturas con `readOnlyHint` y pin del manifiesto | La hoja: ninguno. Aceptar el sí hablado como Incredible no viola el invariante `app:` al pie de la letra, pero reabre F-D sin el juez que Incredible tiene. No igualar esa parte |
| 2. Stop | Varios: el orbe o píldora corta solo el turno de voz y los agentes siguen; parar por tarea; parar la ejecución de un workflow; parar por voz, un agente a la vez ("parar todo" = parar cada uno); cancelar el conector en vuelo | Un freno único `.stop` (`SessionMachine.swift:251-264`, `450-472`): corta la voz y el hold, cancela job y cola (`JobQueue.cancelAll`, `stopEpoch`, `JobQueue.swift:93-100`) y deniega las aprobaciones pendientes; `stop_job` por voz solo cancela jobs (`VoiceSession.swift:254`) | Separar un freno de voz (`.cancelVoiceOutput`/`.stopListening`, sin `stop()`) del freno de tarea (`cancelJob`) | Ningún invariante. No perder la denegación de aprobaciones al parar la voz (`SessionMachine.swift:456-459`) |
| 3. Sí hablado | Un sí dicho en voz alta vale como go; la voz dice una frase corta y la tarjeta lleva el texto exacto; sin compuerta determinista: el orquestador interpreta y el juez comprueba la cobertura; el go por clic va fijado a la versión | `SpokenYes.admits`: nunca en realtime; en clásico solo tras anunciar y con dwell (`Acknowledgement.swift:52-58`); nunca `app:` (`VoiceSessionApprovals.swift:75-84`); la voz no pregunta (`:26-33`) | Igualar solo "la voz pregunta con una frase": llamar a `approvalAnnounced` en clásico | Igualarlo del todo **rompe** "el sí nunca aprueba `app:`". No hacerlo |
| 4. Ubicación | No existe: sin CoreLocation, sin permiso ni entitlement de ubicación, sin ajuste; al modelo solo le llega la hora local con desfase UTC; lo cercano va por conectores o por el navegador | Ciudad de Ajustes o de CoreLocation (`UserLocation.swift:55-70`); canal apagable (`ContextSettings.swift:82-85`); `<user_location>` (`ContextBlock.swift:86`); **la búsqueda cercana ignora el canal y pide permiso** (`NativeToolRunner.swift:326-332`) | Hacer que `findPlaces` respete el canal: apagado equivale a `prompting:false` y a `NearMe.needsCity` si no hay ciudad en Ajustes. La paridad literal (quitar la ubicación) no se recomienda | Ninguno; refuerza el invariante de ciudad |
| 5. Tarjeta de opciones | Sin atajos numéricos (el badge del número es visual); clic selecciona y Confirmar envía; multiselección y respuesta libre; la respuesta va al agente como "respondido", que no es go; el agente conserva todos los conectores | Dígitos 1-9 solo con foco tras clic o Tab (`IslandChoiceCard.swift:44-62`, `IslandChoice.swift:33-71`); un paso; va como mensaje `[elección en tarjeta]`; `said=""` (`ChatViewModelTurn.swift:16`), así que la 1.ª petición va sin tools de apps (`AppToolRunner.swift:154`) y las siguientes con todas (`:198`) | Opcional: paso Confirmar. Para igualar las tools: `.allConnected` en turnos de elección, manteniendo `said=""` | Ninguno si `said` sigue vacío; la elección sigue sin ser consentimiento y `app:` sigue pidiendo clic |
| 6. Feedback | Backend propio (almacenamiento, tabla de subidas y funciones de reporte), respuestas por Intercom; ánimo (5), temas (6), texto de 5000, **3 capturas** de ≤4 MB (archivo o pegar); diagnóstico opcional (palabras, pantalla, salidas; 30 días); SO no determinable | `mailto:` sin destinatario o share `composeEmail` (`SystemFeedbackDelivery.swift:10-27`); ánimo (5), temas (6), 5000 caracteres, 3 capturas; nada de la máquina (`Feedback.swift:7-14`) | Ya igualados: chips de tema, tope de 5000, pegar imágenes. El destino y el diagnóstico son una decisión de producto | Chips, tope y pegado: ninguno. Un diagnóstico mandaría `<user_location>` si incluye turnos: excluirlo |
| 7. Mermaid | Versión 11.17.2; en el chat: modo estricto, **tema "base"**, paleta oscura, flowchart con curva suave, secuencia sin espejo; los límites de texto y aristas son los de la librería; figura con desplazamiento horizontal; herramientas: copiar imagen y descargar PNG (con fondo o transparente, al doble); sin ver ni ampliar; cae a código si falla | Sin Mermaid; el bloque se pinta como código (`AnswerBlocks.swift:85-92`); 16m-5b pendiente de aprobar la dependencia; las gráficas solo copian CSV (`IslandVisualTools.swift:8-12`) | 16m-5b según D3 con esta misma configuración; herramientas de copiar imagen y descargar PNG | Ninguno de los tres; el riesgo del `WKWebView` se contiene con `strict`, sin red y sin puente |
