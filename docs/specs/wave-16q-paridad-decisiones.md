# Wave 16q — Paridad de decisiones con Incredible

**Estado: 16q-1 y 16q-2 CERRADAS (2026-09-29).** Karen aprobó el 2026-09-29 "todo lo que funcione igual
que Incredible". Fuente de verdad: `docs/research/auditoria-decisiones-incredible.md`
(decisiones 1, 2 y 3, auditadas contra el código real de Incredible). Este documento no copia
código, prompts ni textos de Incredible: cita la auditoría y describe qué hace Companion.

## 16q-1 — Aprobaciones y stop de voz iguales a Incredible

### Decisiones

**D1. Aprobaciones de MCP en voz realtime: una hoja, no una pregunta hablada.**
Evidencia (auditoría, decisión 1): en Incredible lo que decide el usuario es una tarjeta con
Confirmar y Rechazar en la isla. Antes de 16q-1 Companion no tenía hoja para esta petición y un
sí hablado la resolvía por una rama provisional (`HACK`, `VoiceSessionApprovals`).
- La petición `mcp_approval_request` del realtime va a la misma hoja que las puertas del padre:
  `VoiceSession.noteMCPApproval` la lleva por `ParentToolGuard.decide` (un único punto que
  devuelve la `ApprovalResponse`), que publica `.job(.approvalRequested)` para la hoja y espera
  en el mismo actor `Approvals`, con Permitir/Rechazar y el auto-deny de 60 s
  (`ApprovalTiming.autoDeny`). El servidor solo oye la respuesta cuando la usuaria la dio.
- Sin proveedor de aprobaciones, la petición se rechaza (falla cerrado).
- Se quitó la rama `HACK`. Su disparador ("cuando exista una hoja para las aprobaciones MCP")
  se cumplió.
- **Un sí hablado NO aprueba una herramienta MCP en realtime** (`answerPendingApproval` devuelve
  `.needsClick`). Incredible acepta un sí hablado porque detrás tiene un juez de IA
  (`judge_actions`) y un go fijado a una versión de la tarjeta; Companion no tiene ninguno de
  los dos, y la salida de un servidor puede plantar palabras delante del modelo (F-D). Ese
  invariante no se afloja.
- Un **no** hablado sí rechaza: retira la petición del actor (`ParentToolGuard.withdraw`), la
  hoja recibe `.approvalSettled` y el servidor oye el rechazo.
- El aviso al modelo (`MCPServerConfig.approvalPrompt`) ya no le pide preguntar ni resolver con
  la decisión: le dice que hay una tarjeta, que lo diga en una frase corta sin leer el detalle y
  que no llame `resolve_approval` con `approved: true` para ella.
- Varias peticiones MCP a la vez: el no hablado rechaza la MÁS NUEVA (la que el modelo acaba de
  preguntar); las anteriores siguen en la hoja y se rechazan con su clic. Un id repetido (el id lo
  pone el servidor remoto) falla cerrado: `Approvals.request` rechaza al recién llegado sin tocar al
  original, y `noteMCPApproval` rechaza al original (una sola respuesta al servidor). La hoja se
  limpia sola cuando la petición termina por clic, no o auto-deny (`.approvalSettled`); un clic tardío
  no añade una segunda respuesta al cable.
- No entra (opcional en la auditoría, sin pedido de Karen): interruptor por servidor "lecturas
  sin preguntar" con `readOnlyHint`, y pin del manifiesto de tools.

**D2. Stop: no hay un freno único.**
Evidencia (auditoría, decisión 2): el orbe de Incredible (`UserPressedAbort`) interrumpe el
turno del orquestador y los agentes siguen ("reports remain queued"); cada tarea tiene su stop
(`UserStoppedTask{agent_id}`); por voz, `stop_agent` para uno y los demás siguen; su abort sí
cancela la aprobación pendiente del turno.
- **`SessionEvent.stopVoice`** (el chip/orbe de la isla cuando lo que está delante es la voz): corta
  la voz y el hold, cierra un turno escrito y **deniega las peticiones pendientes del turno**
  (las que no son de ningún encargo: herramienta MCP, puertas del padre, concesión del puente).
  **No cancela ningún encargo**, ni el que corre ni los encolados; las peticiones de un encargo
  siguen en la hoja (son suyas y el encargo vive). Deja `interruption = .userStopped` y la fila
  del encargo vuelve al frente.
- **`SessionEvent.stopJob(JobID)`**: el stop propio de un encargo. El reductor lo saca de la
  fila o de la cola, recuerda el id como parado (sus eventos tardíos no reabren nada, mismo
  mecanismo que `stoppedJobs`), niega solo las peticiones que ese encargo dejó en la hoja y
  emite `.cancelJobByID(id)`; el siguiente encargo sube. Un id desconocido no hace nada.
- **Cancelación por id, que no existía.** `JobRunner.cancel()` era `cancelAll` y ningún
  `cancelJob` recibía un `JobID`. Ahora el id que acuña quien inicia el encargo (el puente de voz
  y el chat) viaja hasta la cola (`JobSubmitter.submit(_:as:events:)`,
  `JobRunner.cancel(job:)`, `JobQueue.cancel(job:)`): el que corre se cancela y su fin es de la
  usuaria (`stoppedByUser`); el que espera sale sin ejecutarse; los demás conservan su sitio.
  Corrección análoga a `stopEpoch`: los ids parados se guardan aunque el encargo aún no haya
  llegado a la cola o esté en el traspaso del turno, así que un stop nunca se pierde entre dos
  `await` (lista acotada, `HACK` con disparador en `JobQueue`). Un submitter sin stop propio cae
  al freno total: parar de más es el fallback honesto; un stop que no para nada, no.
- **UI.** La tarjeta del encargo ya tenía un chip "Parar", pero era el freno total. Ahora
  `IslandStop.brake(for:)` decide: con la tarjeta del encargo delante, el stop es de ese
  encargo (`ChatViewModel.cancelJob(_ id:)`); con la voz delante, `stopVoice`. Un encargo sin id
  (sin etiqueta) cae al freno total.
- **Negar la primera acción de un encargo** ahora para ESE encargo (`stopJob(dueño)`), no la cola
  entera: el freno total queda para lo que no tiene dueño y para el menú de la barra. El encargo
  encolado sube y sigue.
- **Los frenos viven en `SessionMachineBrakes.swift`** y los helpers de reposo y `observe` en
  `SessionMachineResting.swift` (extensiones del reductor; el gate "la proyección solo la escribe el
  reductor" y el de extensiones los incluyen). `stopVoice` y `.stop` actúan aunque
  la isla esté en reposo si hay una petición sin dueño en la hoja (concesión del puente, MCP), y
  `stopVoice` solo cuenta "la usuaria interrumpió" cuando había algo que interrumpir.
- **La sesión de voz refleja la hoja.** El reductor emite `approvalClosed(requestId)` por cada petición
  que sale de la cola, por cualquier vía (clic, "resuelta en otro sitio", descartada, `stopJob`,
  fin del encargo, freno total, no hablado); `SessionModel` lo reenvía al puerto de voz
  (`VoiceControlling.approvalClosed`, sin default a propósito: un default ganó el overload al método
  del actor y la llamada no hacía nada) y `VoiceSession` olvida `pendingApproval`. El auto-deny del
  actor no avisa a nadie, así que la petición caduca por el mismo reloj (`ApprovalTiming.autoDeny`).
  Una pregunta en cola sobre una petición que ya no existe no se dice.
- **Sin cambio**: `.stop` (menú de la barra, "Parar todo") sigue siendo el freno total y completo;
  `stop_job` por voz sigue parando un encargo (`JobRunner.cancel()`).
- Correctitud conservada: `stopEpoch` y `approvalOwners` no cambian de semántica; todo pasa por
  el reductor (el gate "la proyección solo la escribe el reductor" sigue verde).

**D3. "Sí" hablado: la voz pregunta en una frase, la tarjeta lleva el detalle.**
Evidencia (auditoría, decisión 3): en Incredible la voz dice una frase corta y la tarjeta lleva el
texto exacto; nombres de archivo y rutas no se dicen.
- **Clásico**: cuando un encargo pide permiso, la voz dice una sola frase fija nuestra
  (`Escalation.approvalAskedSpoken`) por el mismo carril que los avisos de fin de encargo
  (`JobAnnouncement.Outcome.asking`, espera su hueco, `AnnouncementGap`). No lleva nada de la
  petición: un payload de herramienta no puede poner palabras en la boca de la voz.
- La petición se marca anunciada (`approvalAnnounced`) **cuando termina el audio**
  (`VoiceSession.markQuestionSaid`, desde el `.finished` del sintetizador), no al encolarse. Un
  hold que la corta, un fallo o un stop la dejan sin decir: el sí siguiente pide el clic. Si la
  hoja se contestó antes de que la pregunta sonara, no se pregunta. Así `SpokenYes.admits`
  funciona como ya estaba diseñado (anunciada antes del hold, más el dwell de 0,6 s).
- Esto revierte para clásico la decisión de producto del 2026-08-22 ("la voz no pregunta los
  permisos"), con la aprobación de Karen del 2026-09-29.
- **Solo cuenta un sí que ella dijo** (revisión de seguridad M3, endurecida en la ronda 2). El tiempo
  no basta: el modelo puede llamar `resolve_approval(true)` en el hold siguiente diga ella lo que
  diga, y la salida de un especialista puede pedírselo. `SpokenYes.admits` exige además que la
  transcripción de ESE hold (`ClassicRuntime.onHeard`, antes de que corra el modelo) sea
  `SpokenYes.affirms`: una **lista permitida cerrada** es/en (ronda 3; la lista de bloqueo se quitó
  porque nunca acababa: dejaba pasar "ok que tal", "is it ok", "está bien", "cannot", "maybe ok").
  Solo afirma si se cumple TODO:
  - **De 1 a 4 palabras dichas** (`maxWords`), contadas al partir por espacios, no las que deja un
    tokenizador de letras. Un guion o puntos sueltos no cuentan como palabra pero sí ocupan lugar.
  - **Sin dígitos, sin `?` ni `¿`**, y sin símbolos ni emoji sueltos ("ok 1 2 3", "ok 5000", "sí 👍").
  - **Cada palabra** (minúsculas, sin acentos, sin puntuación en los bordes) **está en la lista**:
    sí, sip, dale, adelante, hazlo, permítelo, aprobado, apruébalo, claro, vale, ok, okay, ándale, sale,
    va, órale, perfecto, yes, yeah, yep, sure, approved, alright; las cortesías (please, por favor); y
    las frases que se leen como unidad: de acuerdo, por favor, go ahead, do it, allow it, sounds good,
    claro que sí. "que" solo existe dentro de "claro que sí". "bueno", "fine" y "está bien" quedan
    fuera a propósito: también abren una pregunta o una duda.
  - **Al menos una palabra es un sí de verdad**: la cortesía sola ("please", "por favor") no vale.
  - **"si" sin acento solo vale como la respuesta entera** ("si", "sí, sí"): con algo más es el
    "si" condicional.
  - Sigue siendo un `HACK` declarado: el juez de 16q-3 lo sustituirá.
- **Un sí pertenece a SU hold** (ronda 2, S2). `heardThisHold` guarda las palabras junto con el
  `pressed` con el que ARRANCÓ el hold que las oyó (`HeardInHold`; viaja por `onHeard(text, pressed:)` y se
  descarta si ya no es el `timeline.pressed`, y un submit cancelado reporta vacío) y `answerPendingApproval` exige que sea el
  `timeline.pressed` del hold que contesta. Además se borra: en un press nuevo (no un rebote), al
  empezar un turno escrito (`.typedSubmit`), en `noteApproval` (petición nueva = pregunta nueva),
  en `approvalClosed` (la hoja cambió), en el camino del hold cancelado antes de su transcripción
  final (`ClassicRuntime.submit` avisa `onHeard("")`) y al consumirse (un sí, una petición). Cadena
  probada: sí sin consumir, petición nueva anunciada, hold nuevo cancelado antes de su transcripción,
  `resolve_approval(true)` inyectado: `.needsClick`.
- **Carrera cierre/anuncio** (ronda 2, C2): `approvalClosed` y `noteApproval`/`askApprovalAloud` son
  tareas sin orden. La sesión recuerda los últimos 64 ids cerrados (`closedApprovalCap`, `HACK` con
  disparador) y esas dos no rearman ni preguntan un id cerrado. Un id repetido en el reductor se
  ignora (`ask`), sin apilar una segunda tarjeta ni quitarle el dueño a la primera.
- **Invariantes intocables**: el sí hablado nunca aprueba escrituras `app:` ni MCP (aunque la voz
  las haya preguntado); en realtime `SpokenYes` sigue en `false` y la voz no pregunta; un no
  hablado siempre se acepta.
- **Hueco cerrado en esta ronda** (lo halló la spec de 16q-3): `answerPendingApproval` emitía
  `.approvalSpoken(approved:)` sin id y el reductor resolvía la PRIMERA de la cola. Inalcanzable
  mientras nadie anunciaba; con el anuncio, un sí admitido para el permiso de un encargo podía
  resolver una escritura `app:` del chat que estuviera primera en la hoja (salto de F-D). Ahora
  `.approvalSpoken(requestId:approved:)` lleva la petición admitida y el reductor resuelve
  exactamente esa; si ya no está pendiente no resuelve nada.

### Criterios de aceptación y pruebas

Cada uno tiene un test que falló primero (rojo con aserción) y una mutación que lo hace caer.

| # | Criterio | Tests |
|---|---|---|
| 1 | La petición MCP realtime llega a la hoja, espera el clic, viaja aprobada o rechazada, muere en el auto-deny y sin actor falla cerrada | `Approvals16q1Tests` (`testAnMCPRequestReachesTheSheet…`, `…AllowSends…`, `…DenySends…`, `…AutoDeny`, `…FailsClosed`) |
| 2 | Un sí hablado nunca aprueba MCP; un no hablado lo rechaza y vacía la hoja | `testASpokenYesNeverApprovesAnMCPTool`, `testASpokenNoRefusesAnMCPTool` |
| 3 | El freno de voz deniega la petición MCP pendiente | `testStoppingTheVoiceDeniesThePendingMCPRequest` |
| 4 | `stopVoice` corta voz y hold, deniega lo del turno, deja intactos encargos, cola y peticiones de encargo | `StopParity16qTests` (`testStopVoice…`) |
| 5 | `stopJob` para solo ese encargo, niega solo sus peticiones, el siguiente sube y sus eventos tardíos no reabren nada | `StopParity16qTests` (`testStopJob…`, `testALateEvent…`) |
| 6 | La cola para un encargo por id (corriendo, esperando, antes de entrar, en el traspaso) sin tocar a los demás; el freno total sigue total | `JobStopByIDTests` |
| 7 | El stop de la isla elige el freno correcto de extremo a extremo | `testTheIslandsStopReachesTheRightBrake`, `testTheOrbStopsTheVoice…`, `testTheJobCardsStopIsThatJobs`, `testCancellingOneJobByID…` |
| 8 | Clásico: la voz pregunta una vez, en una frase; se anuncia al terminar el audio; cortada no cuenta; app: nunca se aprueba con un sí | `testTheClassicVoiceAsks…`, `testAQuestionCutByAPress…`, `testAnAppWriteIsAskedAloud…` |
| 9 | El sí hablado resuelve exactamente la petición que nombra | `testASpokenYesResolvesExactlyTheRequestItNames`, `testASpokenYesNeverTouchesAnAppWriteThatIsFirstOnTheSheet` |
| 10 | Un sí admitido exige palabras claras de ESE hold; inyección: el modelo dice sí y ella otra cosa, no se aprueba | `SpokenYes16qTests`, `testAnAnnouncedYesNeedsTheUsersOwnWords`, `testAnInjectedResolveWithOtherWordsResolvesNothing` |
| 11 | La sesión de voz no anuncia ni contesta lo que ya salió de la hoja (clic, stopJob, caducidad); frenos con la isla en reposo; `stopVoice` sin voz no reporta interrupción | `testEveryRequestThatLeavesTheSheetIsReported`, `testAResolvedRequestIsNotAnnouncedOrAnswered`, `testStoppingTheJobDropsItsAnnouncedPermission…`, `testStopVoiceWithAnIdleChromeStill…` |
| 12 | MCP: dos peticiones, id repetido, clic tardío tras el auto-deny, prompt | `testTwoMCPRequestsASpokenNoRefusesTheNewest`, `testADuplicateMCPIDFailsClosed`, `testALateClickAfterTheAutoDenyAddsNoSecondAnswer`, `testTheMCPPromptForbidsAnApprovingResolve` |
| 13 | Ningún camino de producción crea un encargo sin id; el tope de 32 ids parados | `testEveryBridgeEventCarriesTheJobsID`, `testTheChatsJobIsTaggedFromItsFirstEvent`, `testTheStoppedListKeepsThe32NewestAndDropsTheOldest` |
| 14 | Un sí no sobrevive a su hold, a una petición nueva, a un cambio de hoja ni a un turno escrito; el sí no es pregunta ni pasa de 4 palabras; una pregunta que falló no se dijo; un id cerrado no se rearma | `Approvals16q1Round2Tests`, `SpokenYes16qTests` (lista permitida cerrada), `Approvals16q1Round3Tests` (las palabras de un hold cancelado no se prestan al siguiente; los ids cerrados no se repiten en la cola), `SessionReducer16qRound2Tests` (id repetido, freno en la cola de release) |

### Prueba en vivo para Karen

Instalar con `./scripts/bundle.sh release` (cerrar la app antes).

1. **MCP en realtime.** Con un servidor MCP remoto configurado y la voz realtime abierta, pídele algo
   que use una herramienta del servidor. Esperado: aparece la hoja (Permitir/Rechazar, anillo de
   60 s), el modelo dice una frase corta y no lee el detalle. Di "sí" en voz alta: NO se aprueba
   (el modelo te manda a la hoja). Clic en Permitir: corre. Repite y di "no": se rechaza y la
   hoja se va. Repite y no toques nada 60 s: se rechaza sola.
2. **Stop de voz no mata encargos.** Lanza un encargo largo por voz ("busca vuelos…"), y mientras
   corre pregunta otra cosa para que la voz hable; pulsa el orbe/chip mientras habla. Esperado: la
   voz calla, el encargo sigue y su tarjeta vuelve al frente. Si había una hoja de una herramienta
   del turno, se rechaza; la de un encargo se queda.
3. **Stop propio del encargo.** Con la tarjeta del encargo delante, pulsa su "Parar": solo ese
   encargo se para (se registra en el hilo); si había otro encolado, sube. "Parar" del menú de la
   barra sigue parándolo todo.
4. **Sí hablado en clásico.** Con la voz clásica, lanza un encargo que pida permiso. Esperado: la
   voz dice una frase ("Hay un permiso en la tarjeta: ¿lo permito?") sin nombrar rutas ni comandos.
   Con la tecla abajo di "sí" después de oírla: se resuelve. Si pulsas la tecla mientras la pregunta
   suena, o dices "sí" sin haberla oído, pide el clic. Si el permiso es de una app conectada
   (`app:`), el "sí" nunca lo aprueba: siempre el clic.

### Decisiones abiertas

- **Aprobaciones de encargos en realtime**: la voz no pregunta (el sí hablado sigue en `false`
  ahí). Igualar a Incredible pediría una frase corta también en realtime; no está en la
  aprobación y no aporta el sí, así que queda fuera. ¿Se quiere el aviso hablado sin sí?
- **Peticiones de encargo tras el stop de voz**: se quedan en la hoja (el encargo vive) y mueren
  en el auto-deny de 60 s si nadie las mira. Incredible cancela "la aprobación de celda en
  curso" de su turno; aquí esa aprobación es del encargo, no del turno de voz.
- **`stop_job` por voz** sigue siendo `cancelAll` (para el que corre y los encolados). Incredible
  para un agente y "para todo" es parar cada uno; con la cola serial de Companion son lo mismo,
  pero no hay "para el segundo" por voz.
- **Concesión del puente** (`bridge_session`, sin dueño): el freno de voz la deniega, como
  cualquier petición sin encargo. Es fail-closed; si estorba, se le da dueño propio.
- **Tarjetas de encargos encolados**: la UI solo muestra la fila del que corre, así que un
  encolado solo se para con el freno total o subiendo a la fila.

## 16q-2 — Ubicación, tarjeta de opciones y comentarios

**Estado: APROBADO (2026-09-29).** Karen: "todo lo que funcione igual que Incredible".
Fuente de verdad: `docs/research/auditoria-decisiones-incredible.md`, decisiones 4, 5 y 6. No se
leyó ni se copió código de Incredible; los nombres y textos son propios.

### Ubicación (decisión 4)

Incredible no tiene ubicación; aquí la función se queda. Lo que se iguala es que nunca pida
permiso por su cuenta.

- `NativeToolRunner.findPlaces` respeta el canal "Tu ciudad" (`locationChannelOn`, leído en cada
  llamada; `ParentToolRunner` lo reenvía; `CompanionMainSensing` lo cablea a
  `ContextPreference.channels`).
- Canal apagado: solo la ciudad escrita en Ajustes (`UserLocationSource.typedCity()`); si no hay,
  `NearMe.needsCity`. No se abre el diálogo de macOS y **tampoco se lee la ciudad del sistema**
  (ver decisiones abiertas).
- Canal encendido: igual que antes (`current(prompting: true)`).
- El texto de Ajustes ya no dice que una búsqueda puede pedir la ubicación con el canal apagado.

### Tarjeta de opciones (decisión 5)

- **Dos pasos.** Un clic, Espacio o un dígito 1-9 solo seleccionan; el botón Confirmar envía.
  Return selecciona la opción del cursor y, con algo ya seleccionado, confirma.
- **Selección múltiple**: `"multiple": true` en la fence. La respuesta lista las etiquetas en el
  orden de las opciones, separadas por ", "; el hilo la lee de vuelta por subconjuntos (una etiqueta
  puede llevar coma). Sin la bandera, la fence es la de siempre.
- **Respuesta libre**: `"allowText": true`. Es la alternativa a las opciones (escribir vacía la
  selección y al revés). Tope `ChoiceBlock.maxAnswer` = 500, una línea, sin escalares invisibles.
  Una respuesta libre cierra la pregunta sin marcar opción.
- Una bandera mal tipada se lee como apagada; no rompe la fence.
- **Diferencia deliberada**: Incredible no tiene atajos numéricos. Aquí siguen, pero solo
  seleccionan, por accesibilidad de teclado.
- **Tools**: un turno de tarjeta usa `ParentToolExecuting.noteChoiceTurn()`, que deja
  `.allConnected` (antes `.none` en la primera petición). Entrada aparte para que la etiqueta
  jamás llegue a `noteTurn` como palabras suyas.
- **Invariante intacto**: `said = ""` para la compuerta y para `noteTurn`; una elección nunca es
  consentimiento y cada escritura de app sigue pidiendo su hoja. Los grants mueren al empezar el
  turno de tarjeta.
- El vocabulario de tarjetas enseña las dos banderas al modelo.

### Comentarios (decisión 6)

- 5 ánimos (`upset, bad, meh, good, love`, de peor a mejor; los cuatro anteriores conservan
  nombre) y 6 temas (`voice, screen, apps, errands, dictation, other`), multiselección.
- Tope de texto 5000. Tope de mailto 6000 sin cambio: 5000 caracteres sin nada que escapar caben
  con ánimo y temas; un texto normal (espacios y acentos se codifican a 3-6 caracteres) no cabe, y
  entonces sale **completo** por el servicio de compartir, o se corta y se avisa si no hay
  servicio. El corte solo come texto: ánimo y temas quedan.
- Hasta 3 capturas de 4 MB o menos (`maxCaptureBytes`), desde archivo (selector), pegadas
  (imagen del portapapeles a un archivo privado) o la captura de región. El tope de 3 es para
  el conjunto. Se rechaza lo que no es imagen, lo ilegible y lo que pesa más (con su aviso).
- Solo se borra lo que la app escribió (región y pegadas). Un archivo elegido por ella nunca se
  borra, ni al quitarlo ni al cancelar. Tras enviar no se borra nada (el correo puede estar
  leyendo).
- Destino sin cambio: `mailto:` / `composeEmail`. **No se construye** backend, diagnósticos ni
  metadatos de la máquina (decisión de producto de Karen). Si algún día se adjunta un paquete de
  turnos, debe excluir `<user_location>`.

### Decisiones abiertas

1. Canal apagado sin ciudad escrita: se pidió `prompting: false`; se implementó "no leer el
   sistema" (más estricto). Volver a `current(prompting: false)` es una línea si Karen prefiere
   usar una ciudad ya en caché.
2. Las capturas de región no pasan por el tope de 4 MB (solo archivo y pegado).
3. Pegar solo por botón, no con Cmd+V: `onPasteCommand` podría interceptar el pegado de texto.
4. Los tres textos ("Al límite", temas) son propios; Karen puede cambiarlos sin tocar lógica.
5. Los archivos pegados quedan en la carpeta temporal hasta que macOS la limpie.
