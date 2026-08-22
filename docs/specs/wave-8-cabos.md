# Wave 8 — Cabos sueltos medidos

**Estado: CERRADA — 2026-08-22.** Aprobada entera por Karen ("vamos con
todo el spec"). Las seis piezas entregadas; gates en 0 fallos y 0 avisos,
168 tests. Lo unico pendiente es lo que solo ella puede dar: el veredicto
visual de 8-5 y la prueba manual de delegacion.

Origen: auditoria 2026-08-22 con gates verdes (0 fallos, 164 tests)
comparando codigo real contra lo que los docs afirman. Ninguna pieza es
craft nuevo: son cables que faltan, deuda anotada en Wave 7 y docs que
mienten.

## Lo entregado

| Pieza | Estado | Prueba |
|---|---|---|
| 8-1 Aprobaciones por voz | CERRADA | `VoiceApprovalTests` (5 casos) |
| 8-2 Sesion del especialista | CERRADA | `ExecutorSessionTests` (7 casos) |
| 8-3 Fallback batch | CERRADA | `ExecutorFallbackTests` (4 casos) |
| 8-4 Docs honestos | CERRADA | `git ls-files` vs NOTICE/ROADMAP/ADR |
| 8-5 JobCard | CERRADA (falta veredicto visual) | `JobTimelineTests` (5 casos) |
| 8-6 Higiene | CERRADA | gates sin avisos |

Desviaciones, dichas y no calladas:

1. **8-1**: `onResolveApproval` devuelve `Bool` (no `Void`) para que el acuse
   no le diga al modelo "permiso concedido" cuando ya no habia solicitud
   viva. El sheet sigue siendo el camino visual y el de respaldo.
2. **8-2**: hermes guarda el sentinel `latest`, no un id: su id durable viaja
   por stderr y este adapter no lo lee. Es exactamente para lo que el
   prototipo invento el sentinel.
3. **8-3**: el reintento batch es del MISMO CLI (`claude -p --output-format
   text` reanudando la sesion), nunca `Hermes.ask` universal ni degradar al
   NativeExecutor a mitad de encargo.
4. **8-5**: la tarjeta cubre la ESPERA (paso vivo, reloj, chip de resumen);
   el informe final sigue siendo mensaje de asistente con `reportCut`. Los
   pasos dejaron de pintarse como lineas de status sueltas — el test de
   caracterizacion de Wave 7 se actualizo a la nueva costura, no se borro.
5. **8-6**: partir el actor exigio bajar de `private` a `internal` varias
   propiedades de `VoiceSession` y de `ChatViewModel`. Se acepta: es
   visibilidad de modulo, la API publica sigue siendo de solo lectura, y en
   el actor quien protege el estado es el aislamiento, no el modificador.

Fuera de este spec, por decision explicita:

- **Programa DS (01-12)**: tiene su propio flujo de aprobacion atomica en
  `docs/specs/ds/README.md`. No se mezcla.
- **Notarizacion**: requiere cuenta de Apple + Xcode (deuda con trigger ya
  anotada en ROADMAP).
- **WebRTC**: post-v1 (trigger ya disparado, pero es transporte nuevo, no
  cabo suelto).
- **Migrar a Swift Testing**: trigger externo (instalar Xcode).
- **Prueba manual** "crea un archivo prueba1.md en mi escritorio": es de
  Karen, no de un agente.

## Orden de despacho

Un agente por pieza, solo los archivos de su pieza, TDD con RED verificado.

```
8-1 (bug funcional)  ──┐
8-4 (docs, paralelo) ──┼─→ 8-2 ─→ 8-3 ─→ 8-5 (visual) ─→ 8-6 (higiene)
```

8-4 no toca codigo: puede correr en paralelo con cualquiera. 8-3 depende
de 8-2 (el fallback reanuda con el sessionId persistido).

---

## 8-1 Aprobaciones por voz: el cable que falta · CERRADA

**El patron de bug documentado en REFERENCE.md, otra vez.**
`ToolSpec.resolveApproval` y `RealtimeCodec.approvalToolJSON()` existen y
estan testeados, pero sus unicos llamadores son los tests.
`RealtimeRuntime.prepareSessionUpdate` declara
`tools: canDelegate ? [ToolSpec.delegate] : []` — el modelo de voz jamas se
entera de que existe `resolve_approval`. Consecuencia real: en manos
libres, una solicitud de permiso del especialista muere en el auto-deny de
120 s (`Approvals.swift`) sin que la voz diga una palabra.

### Portar (del prototipo)

- Declarar la tool de approval junto a `delegate` en el session.update
  (`../companion/Sources/RealtimeVoice.swift:86`).
- El flujo de resolucion con `call_id` para el ack
  (`RealtimeVoice.swift:386`, `onResolveApproval`): decision → ack del tool
  call → `response.create`.
- `approvalDecision(fromArguments:)` (`RealtimeVoice.swift:117-119`): JSON
  malformado o sin campo → nil → NO se resuelve nada (ni concede ni
  deniega; el sheet sigue vivo).
- El anuncio hablado de la solicitud usa el mecanismo que ya existe:
  `VoiceSession.jobAnnounce` + `pendingAnnouncements` (solo inyecta en
  listening; si el agente habla, espera).

### Fuera

- El sheet de chat (`ApprovalSheet` via `ChatViewModel.receiveJobEvent`) no
  se toca: sigue siendo el camino visual y el de respaldo.
- Auto-conceder por silencio. El default sigue siendo deny a los 120 s.

### Reescribir (al patron del repo)

- Cero callbacks guardados: el `JobEvent.approvalRequested` ya llega a
  `VoiceSession` — hoy solo lo reenvia a `onJobEvent`. Ahi mismo se encola
  el anuncio hablado.
- La decision del modelo (function_call `resolve_approval`) →
  `JobRunner.resolveApproval(requestId:approved:)` que ya existe
  (`JobRunner.swift:64`).
- Copy del anuncio en `Escalation` (Core, puro, testeable): que pide el
  especialista, en espanol de pantalla, sin volcar el comando crudo.

### Archivos

`RealtimeRuntime.swift`, `VoiceSession.swift`, `Escalation.swift`,
`VoiceCopy.swift` (si hace falta copy nuevo). Tests en
`RealtimeCodecTests`, `VoiceSessionTests`, `EscalationTests`.

### TDD (RED primero)

1. `prepareSessionUpdate(canDelegate: true)` → el JSON declara `delegate` Y
   `resolve_approval`; con `canDelegate: false` → ninguna.
2. `approvalRequested` con sesion en `speaking` → anuncio en cola, no
   inyectado; al volver a listening se inyecta una sola vez.
3. function_call con `{"approved": true}` y requestId vigente → llega a
   `ApprovalsProvider.resolve`, se manda ack con el call_id.
4. Arguments malformados → no se resuelve, no crashea, el pending sigue.
5. Sin sesion de voz viva → la solicitud solo pinta en el hilo (conducta
   actual intacta).

### Done

Los cinco tests verdes + gates + **grep de cableado**: cada simbolo nuevo
tiene un llamador fuera de Tests (la regla que esta wave existe para
honrar).

---

## 8-2 La sesion del especialista sobrevive al reinicio · CERRADA

Deuda anotada al cierre de Wave 7: `ClaudeCodeExecutor` captura `sessionId`
(`ClaudeCodeExecutor.swift:18,69`) y jamas lo reusa. Cada arranque de la
app es un especialista amnesico.

### Portar (del prototipo)

`SessionStore` (`../companion/Sources/SessionStore.swift`): un id por
ejecutor, persistido; la cicatriz del sentinel `latest` — claude NO
entiende `--resume latest`, se mapea a nil (sesion fresca) en vez de pasar
un flag que falla y se queda pegado en el store.

### Fuera

- `UserDefaults.standard` accedido directo desde el executor: viola "nada
  lee el entorno fuera de Config".
- Resucitar sesiones entre workdirs distintos (el prototipo tampoco:
  proceso persiste "si el workdir no cambio").

### Reescribir

- Puerto en Core (`Executors.swift` o archivo nuevo
  `ExecutorSessionStore`): protocolo con `session(for:)` / `set(_:for:)`,
  keyed por id de ejecutor + workdir.
- Adapter en Services sobre el mismo mecanismo de persistencia que ya usa
  `ConversationStore` (no inventar un segundo).
- `ClaudeCodeExecutor`: si hay id guardado y el workdir coincide →
  `--resume <id>` en args; el id nuevo que el stream reporta se persiste.
  Si el proceso muere EN EL ARRANQUE con resume → un (1) reintento limpio
  sin el flag, y se borra el id podrido.
- `HermesExecutor`: igual, con `latest` permitido como sentinel.

### TDD

1. Id persistido se relee tras recrear el store (round-trip).
2. Workdir distinto → no se pasa `--resume`.
3. `latest` con claude → nil; con hermes → viaja.
4. Arranque fallido con resume → reintento sin flag, id borrado, un solo
   reintento.
5. El id que llega por el stream pisa al guardado.

### Done

Tests + gates. Verificacion manual (Karen): encargo, cerrar app, abrir,
"¿en que estabamos?" al especialista.

---

## 8-3 Fallback batch cuando el cable stdio muere · CERRADA

Deuda de Wave 7: si el proceso stream muere a media tarea, hoy el encargo
se reporta fallido. El prototipo caia a batch (`JobRunner.swift:167-179`
del original, `fallbackClaude` → `Hermes.ask` conservando session).

### Portar

La conducta: un proceso muerto a media tarea NO pierde el encargo; se
reintenta una vez en modo batch reanudando la sesion.

### Fuera

- Degradar a `NativeExecutor` a mitad de encargo: pierde el contexto de lo
  ya hecho y cambia las capacidades a espaldas de la usuaria (la escalera
  de ADR 001 se elige al delegar, no a mitad).
- `Hermes.ask` como via universal (era el acople que ADR 001 mato).

### Reescribir

- El fallback es del MISMO ejecutor: `claude -p` en modo batch (sin
  stream-json) con `--resume <sessionId>` de 8-2; para hermes, el batch ya
  es su unico modo — el fallback es relanzar con resume.
- Un solo reintento; cancelacion de la usuaria NO dispara fallback.
- El resultado (o el fallo final) llega por el mismo seam
  (`receiveJobEvent` / announce de 7b) con narracion honesta: "se cayo el
  canal, lo termine por la via lenta" vs "se cayo dos veces, lo dejo".

### Archivos

`JobRunner.swift`, `ClaudeCodeExecutor.swift`, `HermesExecutor.swift`,
`VoiceFailureMapping.swift` / copy. Tests: `JobRunnerTests`.

### TDD

1. Proceso muere con encargo vivo → un intento batch con resume.
2. Batch tambien falla → fallo en humano, sin bucle.
3. Cancelacion → cero fallbacks, proceso terminado.
4. Resultado del batch pinta pasos/announce igual que el stream.

---

## 8-4 Docs honestos: NOTICE, ROADMAP, ADR 002 · CERRADA

Tres afirmaciones falsas hoy en el repo, las tres auditables con grep:

1. **NOTICE.md** dice "No Rive (ADR 003)" — ADR 003 se revirtio:
   `Package.swift` vendorea `vendor/RiveRuntime.xcframework` (15 MB, 58
   archivos en git) y `Mascot.swift` lo importa. Falta la atribucion de
   RiveRuntime (licencia MIT de Rive) y la mencion del binario vendoreado:
   version exacta, origen (release oficial de rive-app/rive-ios) y por que
   va en el repo.
2. **ROADMAP.md** afirma "cero dependencias externas" y compara "~10.600
   lineas contra 15.300". Medido 2026-08-22: 16.828 de Sources contra
   15.307, 13.622 de tests contra 1.228, y una dependencia binaria.
3. **ADR 002** argumenta contra Sparkle con "el repo se clona y compila
   sin descargar nada de terceros: no hay cadena de suministro que
   auditar". Ya no es cierto. No se reabre la decision (sigue sin Sparkle);
   se anota la excepcion: que binario entro, con que ADR, y como se audita
   (pin de version + checksum del xcframework anotado en NOTICE).

Ademas, hallazgo para anotar (no codear): los specs DS 01-12 siguen todos
en BORRADOR pero `981ed19` (orb/mascota) y `9f1558a` (idle) ya tocaron esas
zonas por la via de Wave 6b. Anotar en `docs/specs/ds/README.md` que 06/09
parten de ese estado, para que el agente de DS no "restaure" trabajo bueno.

### Archivos

`NOTICE.md`, `docs/ROADMAP.md`, `docs/DECISIONS.md`,
`docs/specs/ds/README.md`. Cero codigo. Done: ningun claim del repo
contradice `git ls-files` ni `Package.swift`.

---

## 8-5 JobCard: el encargo con paso vivo y duracion · CERRADA (falta veredicto visual)

Anotada al cierre de Wave 7 ("el valor diferencial es visual"). Hoy los
pasos del encargo pintan como lineas de status en el hilo; el prototipo
tiene `JobCard.swift` (8.8k): tarjeta plegable con quien trabaja, paso
vivo, duracion y resultado.

### Portar

Composicion y jerarquia de `../companion/Sources/JobCard.swift` +
`JobSteps.swift` (resumen "2 busquedas · 1 archivo").

### Fuera

- Cualquier control del sistema sin estilo propio (principio rector 6b).
- Tocar el seam de eventos: `receiveJobEvent` ya recibe todo lo necesario;
  esto es solo presentacion.

### Reescribir

Tokens `Semantic`/`Space`/`Radius`/`Elevation`, motion con `Motion.swift`
del rebuild, reduce-motion respetado. Estado de la tarjeta derivado de los
`JobEvent` ya existentes — sin estado paralelo nuevo.

### TDD

Decisiones puras (Core/UI sin instanciar vistas): mapeo JobEvent →
JobStepInfo, resumen de pasos, formato de duracion. La tarjeta en si:
**veredicto visual de Karen con las dos apps abiertas** (criterio 6b).

---

## 8-6 Higiene con los gates · CERRADA

Los tres avisos vigentes de `gates.sh` — partir sin cambiar conducta:

| Archivo | Lineas | Corte natural |
|---|---|---|
| `TokensChoices.swift` | 516 | por familia de token |
| `ChatViewModel.swift` | 442 | ya existe `ChatViewModelAttach`; extraer el manejo de JobEvent |
| `VoiceSession.swift` | 470 | ya existe `VoiceSessionAttachments`; extraer announce/eventos de encargo |

Regla: refactor puro, tests intactos, cero simbolos publicos nuevos.
Despachar AL FINAL: partir estos archivos antes crearia conflictos con
8-1/8-3, que los editan.

---

## Constraints transversales

- TDD con RED verificado antes de cada fix; gates verdes antes de commit.
- Cero dependencias nuevas.
- Al cierre de CADA pieza, el check anti-patron del repo: grep de cada
  capacidad nueva y confirmar quien la invoca desde el flujo real.
- Hallazgo nuevo → se anota en esta spec, esa pieza vuelve a BORRADOR, se
  re-aprueba. No se avanza callado.
