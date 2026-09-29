# Wave 16h — Conversación al nivel de Incredible

**Estado: APROBADO (2026-09-28).** Firmado por delegación de Karen ("firma el resto cuando
finalicemos", al cierre del QA en vivo de 16k). Karen: "la calidad de incredible es excelente". Evidencia: los
transcripts de Companion del 2026-09-25 (`~/Library/Logs/Companion-transcripts.log`) y la sesión de
Incredible de las 17:23–17:25 (`~/.incredible/conversation.json`, solo tiempos y forma de los turnos;
nada de sus prompts).

## 1. Qué hace Incredible (medido) y qué hace Companion (medido)

| | Incredible | Companion |
|---|---|---|
| Acuse | Siempre, en 1,1–2,5 s: "Let me take a look at your screen", "Creating… prueba 1" | En trabajos largos, silencio: 32 s con "búscalo en Safari" |
| Trabajo largo | Un agente en segundo plano; la voz sigue libre; el resultado llega como aviso aparte | El especialista bloquea el turno |
| Lo hablado | Una frase; el detalle en una tarjeta (resultado) o un recibo con palomita | 18 s de restaurantes leídos en voz alta |
| "Listo" | Después de comprobar ("verificado, 0 bytes") | "Escribí … correctamente" sin mirar; falso |
| Contexto del pedido | Cada frase llega marcada con la app y la ventana del momento | Contexto aparte; "esto" y "aquí" fallan |
| Isla | El modelo sabe si una tarjeta se mostró, se cerró o se fue sola; si lo interrumpes, sigue sin repetirse | No lo sabe |
| Pedido compuesto | Hace las dos partes | "Abre Notas y dime qué hay en la primera" → solo abrió |
| Fugas | Ninguna vista | JSON (`{"goal":…}`) y la instrucción interna "El especialista respondió… Acusa en una línea…" dichos en voz alta |
| Texto | — | Frases pegadas sin espacio: "afternoon.Keeping", "pantalla.No contiene" |
| Lugar | — | "Restaurantes cercanos" → Fullerton (EE. UU.); luego Cuernavaca |

## 2. Criterio de done (medible, con los transcripts de hoy como banco de pruebas)

1. **Acuse < 2 s** en todo turno que delegue o use una herramienta de más de 1 s: una frase propia
   de qué va a hacer, antes del trabajo. Medido en `voice timeline` (`commit→audio`).
2. **La voz no espera al trabajo largo.** Lo que va al especialista corre en segundo plano; puedes
   seguir hablando; el resultado llega como un aviso que la voz dice en una frase.
3. **Una frase en voz, el resto en tarjeta.** Respuesta hablada ≤ 2 frases o ≤ 25 palabras cuando
   hay más contenido; el detalle va a una tarjeta en la isla (resultado) o a un recibo (acción hecha).
4. **"Listo" solo con prueba.** Una acción que cambia algo (escribir, crear, abrir, pulsar) se
   comprueba antes de afirmarse (leer el campo, existe el archivo, la app está al frente). Sin prueba,
   la frase dice lo que se intentó, no que salió bien.
5. **Pedidos compuestos completos.** "Haz A y dime B" termina con B; test sobre los 3 casos de hoy.
6. **Cero fugas.** Nada con forma de JSON, de instrucción al modelo o de marca interna llega a la
   voz ni a la isla. Un filtro único en el camino a la voz (no uno por caller), con los textos de hoy
   como casos.
7. **Frases con espacio.** Al unir trozos de respuesta, nunca "palabra.Palabra".
8. **Dónde estás.** Cada pedido lleva la app y la ventana de delante; "cerca" usa tu ubicación
   (ciudad del sistema o la que digas en Ajustes › Tú), nunca la del proveedor de búsqueda.
9. **La isla habla con el modelo.** Tarjeta mostrada, cerrada o ignorada, e interrupciones, entran
   como eventos al siguiente turno.

## 3. TDD (banco de transcripts)

Un archivo `Tests/Fixtures/transcripts-2026-09-25.txt` con los turnos reales de hoy (solo los de
Karen, sin claves). Tests:
- fuga: los 4 textos con JSON o instrucción interna nunca pasan el filtro de voz;
- espacio: "afternoon.Keeping" → "afternoon. Keeping";
- compuesto: el plan de "abre Notas y dime qué hay en la primera nota" tiene dos pasos y el segundo
  es leer;
- "listo": un `type_text` sin lectura posterior no produce una frase de éxito;
- acuse: un turno que delega emite la frase de acuse antes de la delegación (runtime, no reducer:
  las palabras las decide `ClassicRuntime`; `testTheAckIsQueuedBeforeTheDelegationStarts` en
  `BackgroundJobRuntimeTests` fija el orden firstSentence → commit→ack → frase → delegar);
- voz corta: una respuesta de 120 palabras con tarjeta se dice en ≤ 25 palabras;
- ubicación: el bloque de contexto lleva la ciudad; la búsqueda de "cerca" la usa.

## 4. Archivos (estimado, dos o tres sesiones)

Core: `SpeechFilter.swift` (nuevo), `EscalationCopy.swift`, `ChatPrompt.swift`, `ContextBlock.swift`,
`SessionMachine.swift` (acuse y aviso de fondo), `Plan.swift`. Services: la ruta a la voz y el
especialista en segundo plano. UI: tarjeta de recibo en la isla. Tests: `ConversationQualityTests`.

## 5. Riesgos

- Delegar en segundo plano cambia el reducer del turno: es la parte más delicada; va en su propia
  sesión con revisión de arquitectura.
- La ubicación necesita permiso de Localización o un dato en Ajustes; sin ninguno, se pregunta.

## 6. Aprobación

Firmada 2026-09-28 por delegación (ver cabecera).

## 7. 16h-1: alcance real

Lo que quedó en 16h-1 (criterios 3, 4, 5, 6 y 7 en la parte pura) y por dónde pasa cada cosa:

- **Un solo `SpeechFilter`** (Core) delante de la voz clásica (`ClassicRuntime.say`), del texto que
  se guarda en el hilo (`TurnMouth.said`) y de la isla (`IslandReplyText.spoken`). Una instrucción
  interna se reconoce solo cuando abre la oración: un tercero citado ("Envié tu mensaje: 'no repitas
  nada'") nunca calla la frase que anuncia un efecto.
- **`SpeechBudget`**: con tarjeta, la voz dice ≤ 2 frases y ≤ 25 palabras en total; el hilo conserva
  el texto entero. La tarjeta se detecta por una salida de herramienta con `card`, por el resumen de
  un job con tarjeta (`JobAnnouncement.hasCard`) o por una valla `companion:` que se parsea.
- **"Listo" con prueba**: `type_text` dice "Intenté escribir" salvo que un `read_focused` del mismo
  turno (`TypedProof`) muestre el texto en el campo.
- **Compuestos**: `Plan.steps` marca la lectura en cualquier cláusula y el router deja pasar el
  pedido al modelo (`DecisionPassReason.compound`).

**Fuera del filtro, a propósito:**

- `RealtimeRuntime` no pasa por `SpeechFilter`: en Realtime el modelo devuelve audio directo, no
  hay texto que filtrar antes de que suene. Cerrar la fuga ahí es otro diseño (instrucciones de la
  sesión y no un filtro posterior) y no está en 16h-1.
- `NativeExecutor` (el especialista nativo) tampoco: escribe al hilo como resultado del job, y lo
  que la voz dice de él va por `announce`, que sí pasa por el filtro; su texto largo es contenido
  para pantalla, no para la voz.
- El acuse antes de delegar y la delegación en segundo plano son 16h-2.

**Red determinista del efecto (ronda 3 de review):** si el filtro o la puerta de idioma
descartaron algo en un turno y lo dicho no contiene la línea de estado de una herramienta con
efecto (`ParentTool.changesSomething`), el runtime la dice y la enhebra (`sayMissingEffects`).
La línea sale del resultado real de la herramienta, nunca del texto del modelo: un tercero puede
provocar que se repita una verdad, no fabricar un efecto. "Escribí" exige una lectura base del
campo antes de teclear, el mismo pid y más apariciones después (`TypedProof`).

**Seguimiento anotado (no bloqueante, reviews de 16h-1):**

- La red cubre las herramientas del padre; las escrituras de apps conectadas quedan fuera de la
  voz (tienen hoja de aprobación con resumen y línea genérica en el hilo). Extenderla cuando cada
  tool conectada tenga copy de estado propio.
- El recorte del presupuesto no marca `filtered`: un efecto recortado por longitud no dispara la
  red (el hilo sí lo conserva). Y la línea de la red se dice fuera del presupuesto de 25 palabras:
  se prefiere un efecto dicho a una voz breve.
- La comparación "lo dicho contiene la línea" es exacta: una paráfrasis del modelo en un turno con
  descarte produce una repetición corta.

## 8. 16h-2: alcance real

Criterios 1 y 2 en la voz clásica (el hold). Dónde vive cada cosa:

- **El acuse vive en el runtime, no en el reducer.** Los reductores (`TurnMachine`, `SessionMachine`)
  deciden captura y chrome; las palabras las decide `ClassicRuntime`, igual que las respuestas
  propias del router (`respond`). La parte pura está en Core (`Acknowledgement`): la frase, cuándo
  hace falta (nada dicho aún en el turno) y el umbral de herramienta lenta (1 s).
- **Delegar**: `ClassicRuntime.acknowledge` encola la frase (la misma del router,
  `DecisionCopy.delegated`, que ya está en el set precalentado) ANTES de `onDelegate`; pasa por
  `SpeechFilter`, sale en el idioma de la app y se enhebra como respuesta. Si el modelo ya dijo
  algo hablable, no se añade nada (una frase por turno); una fuga filtrada no cuenta como dicha. El
  router ahora también encola antes de delegar (antes delegaba primero).
- **Herramienta lenta**: `actAcknowledging` corre la ronda de herramientas contra `slowToolWait`
  (1 s, inyectable) en un task group; si la ronda sigue viva y no se ha dicho nada, dice "Miro tu
  pantalla." (`look`/`see`) o "Dame un momento.". Estructurado: un hold que corta el turno cancela
  a los dos.
- **Medida**: `TurnTimeline` lleva `acknowledged` y la línea `commit→ack`, al lado de
  `commit→audio`.
- **El turno acaba tras el acuse**: con la frase encolada, la voz del hold termina con su
  `speechFinished` y vuelve a reposo; el encargo ya corría aparte (`VoiceJobBridge` en su propio
  Task). Antes, sin nada encolado, la voz se quedaba en `speaking` los 32 s del encargo.
- **Identidad del encargo** (ronda de review): cada evento de encargo viaja con su `JobID`
  (`SessionEvent.job(_:from:)`, `.jobFinished(ok:from:)`), acuñado por quien lo arranca
  (`VoiceJobBridge`, el chat), nunca por el ejecutor. `JobTimeline` lleva `id`, `approvedOnce` y
  `behindTurn`; la proyección suma `queued`. Un `.started` de otro id va a la cola sin renombrar la
  tarjeta activa; pasos de otro id nunca se pintan en su fila; al terminar el activo, el primero de
  la cola toma la fila; el "primer permiso aprobado" es del encargo, no se hereda. Sin id (tarjetas
  y permisos del propio padre, llamadores viejos) nil solo casa con nil. Toda la lógica vive en
  `SessionMachineJobs.swift`.
- **Dueño del permiso** (review ronda 3, BLOCKER 1): `ask(_:from:)` guarda `requestId → JobID`
  (`SessionMachine.approvalOwners`). Negar "la primera acción" para el encargo solo si el dueño de
  esa petición es el encargo que está en la fila (`isActiveJobs`): la concesión de sesión del
  puente, la puerta `open_url` del padre o una petición de un encargo que ya terminó nunca cuentan
  como la primera acción de otro. Una petición sin id no es de ningún encargo: tras un Stop NO se
  auto-niega (solo se niegan las de un id parado o terminado).
- **Ids terminados** (ronda 3, SHOULD 2): `finish` recuerda el id junto a los parados (misma lista
  acotada); un paso tardío de un id terminado nunca abre fila. El puente y el chat drenan su bomba
  (`sink.finish(); await pump.value`) ANTES de mandar `jobFinished`. Al terminar, sus permisos
  aún pendientes salen de la hoja con `resolveApproval(false)` (`dropApprovals(of:)`): la hoja
  nunca muestra una pregunta que nadie espera.
- **El chat solo habla por su encargo** (ronda 3, SHOULD 1): `startJob` devuelve el id y `runJob`
  lo captura para su bomba y para `finishJob(ok:id:)`; ya no se etiqueta con "el id del chat en el
  momento de entregar". `finishJob`, `cancelJob` y `answerApproval` solo registran en el hilo la
  fila de ese id (activa o en cola); un encargo de voz se registra cuando llega SU `jobFinished`
  por `receive`. `appendAssistant`/`appendStatus` ya no cierran ningún encargo: por ahí llegan
  también las respuestas de la voz, y cerraban la tarjeta del chat a mitad.
- **Un solo escritor de la proyección** (ronda 3, SHOULD 3): `scripts/gates.sh` falla si algo fuera
  de `SessionMachine.swift`/`SessionMachineJobs.swift` escribe `projection` (asignación, campo,
  `append`/`remove`/`insert`); fuera de Core solo vale copiar la salida entera
  (`SessionModel`: `= machine.projection`). El mismo gate falla ante cualquier
  `extension SessionMachine` fuera de esos dos archivos. `receiveJobEvent` ya solo existe con id.
- **Qué está delante** (`SessionMachine.jobInFront`, una sola regla): un turno que la usuaria abre
  con un encargo vivo (pulsar, chat, voz escuchando) marca `job.behindTurn` y muestra sus propias
  fases; `rest()`, `replyOrRestingKind()`, `observe` y `.started` preguntan lo mismo. En reposo
  vuelve la fila; poner `job = nil` borra la marca por construcción. Pulsar y soltar nunca emiten
  `cancelJob`.
- **Parar es un freno único y completo** (B1): `stop` para el encargo en curso Y los encolados
  (`JobRunner.cancel` → `JobQueue.cancelAll`: los que esperan reciben "parado" y nunca ejecutan).
  Solo el freno de la usuaria marca `JobResult.cancelled` (`QueueError.stoppedByUser`); un
  desmontaje o una cancelación de tarea sigue siendo un fallo. Un `is_error` que llega tras el
  freno cuenta como parado. Los eventos tardíos de un id parado no reabren nada (lista acotada).
  `stopEpoch` (ronda 3, MEDIUM): `cancelAll` lo incrementa; `submit` lo lee antes de `takeTurn` y,
  si cambió al despertar, suelta el turno y lanza `stoppedByUser`. Cierra el hueco del traspaso:
  el turno pasa al siguiente todavía ocupado, y un Stop que caía entre "te toca" y que B volviera
  al actor no veía ni cola ni trabajo en curso, así que B corría después del Stop.
- **El aviso de fin espera su hueco**: `VoiceSession.parkedAnnouncements` guarda el fin del
  encargo y `AnnouncementGap` (Core) decide cuándo puede sonar: en reposo, en la sesión tibia o en
  manos libres sin nadie hablando; nunca con la tecla abajo, el micro arrancando o un turno
  pensando o hablando. Se vacía en `apply` (cada cambio de la voz) y de uno en uno: el siguiente
  espera a que termine el audio del anterior o a que algo nuestro pare el sintetizador (`stopIO`,
  cortar el turno, Esc, pulsar), nunca solo al acabar su Task (ese acaba al encolar y el `begin()`
  del siguiente cortaría el audio). No suena con la voz cerrada por la usuaria, con la sesión
  cerrada ni en error: ahí se descarta y se cuenta. Caduca a los 120 s (`AnnouncementGap.maxAge`,
  HACK con disparador). Todo en `VoiceSessionAnnouncements.swift`.
- **Esc calla el aviso** (S2): la sesión publica `SessionEvent.announcing`; `stop` en reposo con un
  aviso emite `cancelVoiceOutput`, e `interrupt()` lo corta y vacía la cola. La sesión tibia no se
  cuelga mientras suena un aviso (se reprograma).
- **"Sí" hablado** (seguridad M1, reescrito en ronda 3 HIGH): `resolve_approval` lo llama el
  MODELO, así que su "sí" solo es de la usuaria si pudo oír la pregunta y luego eligió contestar.
  Una sola regla pura, `SpokenYes.admits` (Core), por la que pasan los permisos de encargo de
  `answerPendingApproval`:
  - realtime / manos libres (sin holds): siempre `needsClick`;
  - clásico: la voz tiene que haber DICHO la pregunta (`approvalAnnounced(requestId)` registra
    `announcedAt` en ese momento, no al recibir la petición) y el hold que lleva el "sí" tiene que
    haber empezado después, con al menos `ApprovalClickGuard.dwell` de margen
    (`timeline.pressed >= announcedAt + dwell`). Una petición que aparece con la tecla abajo
    nunca se anunció en ese hold: `needsClick`;
  - `app:`: el sí sigue siendo `needsClick` siempre (F-D).
  Todo esto aplica solo al "sí". Negar es la dirección segura: un "no" hablado resuelve sin clic,
  sea de un encargo, del padre o de `app:`.
  Hoy nada llama a `approvalAnnounced`: por la decisión de producto del 2026-08-22 la voz no
  pregunta los permisos, así que en la práctica todo "sí" hablado pide el clic. Es la costura para
  el día en que la voz vuelva a preguntar.
  **Rama MCP (provisional, HACK en el código)**: las llamadas a herramientas de los servidores MCP
  remotos de `mcp.json` / Ajustes que OpenAI ejecuta en la sesión realtime; con `requireApproval`
  ausente o `"always"` (por defecto) TODA llamada, lectura o escritura, pide aprobación. No tienen
  hoja, así que exigirles `SpokenYes` las dejaba inaprobables y colgadas en el servidor: conservan
  el camino hablado previo a 16h-2 (el sí hablado las resuelve). No es un agujero nuevo; el HIGH
  era sobre los permisos de encargos en segundo plano.
- **Segundo pedido**: `OneJobAtATime` intacto (se encola, no se para nada). El segundo turno
  también se acusa, y el "Queda en cola" del puente se dice al acabar ese turno.
- **Parar**: un encargo parado no se anuncia como fallo; el hilo conserva su línea.
- **Un press sobre el acuse** (código M1/L2): no suena nada después del press y el encargo no
  arranca, ni en el camino del modelo ni en el del router.
- **La ronda de herramientas informa, no escribe** (S3): `actRound` devuelve turnos, líneas de
  efecto, tarjeta y escrituras sin probar; el padre las absorbe al acabar la carrera. Un
  `slowToolWait` inyectado tiene que respetar la cancelación.

```
hold ─ release ─ thinking ─ [acuse encolado · commit→ack] ─ onDelegate ─ replyCompleted
                                                               │
                         speechFinished ─ idle (voz libre) ◄──┘    encargo corriendo (job en la proyección)
hold nuevo ─ listening ─ thinking(propio) ─ speaking ─ … ─ fin del encargo → parked
                                                      speechFinished ─ idle ─ aviso ("Listo…" + resumen)
```

**Lo que no quedó:**

- Realtime sigue igual: el modelo acusa con su propia voz tras `functionOutput`; no hay
  `commit→ack` ahí ni filtro (misma razón que en §7).
- El aviso encolado se pierde si se cuelga la sesión realtime (como antes); en clásico no hay
  colgado que lo borre.
- Un aviso cuyo sintetizador ni termina ni lo para nada nuestro (un fallo interno sin `.failed`)
  seguiría bloqueando los siguientes; hoy cada parada nuestra lo libera.
- `SessionEvent.stop` sigue siendo un único freno (ahora completo): con un encargo vivo, el botón
  de la isla y el menú paran la voz, el encargo y los encolados, aunque la usuaria solo quisiera
  cortar la respuesta del turno nuevo. Separar "calla" de "para el encargo" es decisión de producto
  de Karen.
- Negar la primera acción de un encargo también usa ese freno y para los encolados.
- Aprobar por voz un permiso de encargo queda apagado de hecho: en realtime siempre, y en clásico
  hasta que la voz anuncie las preguntas (falla cerrado; la hoja con clic sigue funcionando).
- **Decisión abierta para Karen** — aprobaciones MCP en realtime: hoja propia o "no" explícito;
  mientras tanto conservan el camino hablado previo.
- Tarjeta de recibo, ubicación y eventos isla→modelo: 16h-3.
