# Suite estable: races en fakes, relojes reales y hooks globales

Estado: APROBADO (Karen, 2026-09-30).

## Objetivo

La suite completa falla en 3 o 4 de cada 10 corridas en paralelo, cada vez en
un test distinto, y a veces el proceso muere (SIGSEGV o "Index out of range")
sin resumen. Pasa igual en main. Cada sesion pierde corridas y comparaciones
descartando fallos que no son suyos, y un fallo real puede esconderse detras
de uno de estos.

## Diagnostico (investigacion 2026-09-30)

Se hicieron 10 corridas en paralelo, 1 en serie, corridas filtradas de
estres, ThreadSanitizer y la lectura de los crash reports.

**No es un bug de produccion: todo sale de los tests.**

1. **Races en fakes (el crash).**
   - `ScriptedVoiceTransport` (`Tests/CompanionTests/VoiceSessionFakes.swift:153`)
     es `@unchecked Sendable` con arrays sin lock.
   - `send()` escribe desde el hilo del actor y el test lee desde el main en `pumpUntil`.
   - TSan da 12 avisos, y los `.ips` del 2026-09-29 muestran SIGSEGV en
     `Array.append` justo ahi.
   - `ScriptedThread` ya se arreglo con `NSLock`; sus hermanos no.
   - `FakeWorkspaceOpener` (`ChatFakes.swift`) tiene la misma race.
   - Hay 253 `@unchecked Sendable` en el target de test.
2. **Relojes reales bajo carga.** Estos tests afirman sobre tiempo de pared
   y fallan cuando el main actor esta saturado:
   - `JobQueueTests.swift:67`: duerme 40 ms contra un job de 150 ms;
   - `Mention16m7SelectorTests.swift:255`: una demora de 250 ms;
   - `Diagram16m5bTests.swift:233`: `< 3 s`;
   - `JobStopByIDTests`: plazos de 3 y 10 s.
3. **Hook estatico global.** `DiagramMatte.onRun`
   (`Sources/CompanionServices/Deliverables/DiagramPNG.swift:95`,
   `nonisolated(unsafe) static var`) lo instala un test y lo dispara otro que
   corre en paralelo.
4. **Ruido, no fallo.** "leaked its continuation" lo producen a proposito
   `Diagram16m5bRound2Tests.swift:170,189` para simular una pagina colgada.
   Sale en todas las corridas.

## Cambio (en este orden, cada uno test primero)

1. **Races.**
   - Un `LockedBox<T>` generico en `TestKit.swift`.
   - `ScriptedVoiceTransport` y `FakeWorkspaceOpener` guardan su estado con el.
   - Barrido de los `@unchecked Sendable` que se escriben fuera del main y se
     leen en `pumpUntil`, priorizados por riesgo.
   - Prueba: `swift test --sanitize=thread --filter "mcpToolsTests|voiceSessionTests"` pasa de 12 avisos a 0.
2. **Relojes.**
   - En los tests del punto 2, sincronizacion determinista en vez de dormir: un
     executor retenido, como el `HoldExecutor` que ya existe, y un reloj o
     sleeper inyectado, como `AppsManualSleeper`.
   - Las cotas de pared (`< 3 s`) pasan a "termino sin esperar el trabajo colgado".
   - Prueba: `--filter "jobQueueTests|diagram"` falla hoy 3 de 3 y debe pasar 20 de 20.
3. **Hook global.**
   - `DiagramMatte.onRun` deja de ser estatico: el probe entra como parametro.
   - Es una costura de test en codigo de produccion, asi que se cambia la firma, no el comportamiento.
4. **Ruido (opcional).** Resolver esas continuations en el teardown.

Fuera de alcance: redisenar `runAsync` (bloquea el main con un semaforo).
Solo si 1-3 no bastan.

## Aceptacion

- 10 corridas completas en paralelo seguidas, verdes, sin crash.
- TSan en cero sobre los fakes arreglados.
- Mismo numero de tests: 1509.
- `scripts/gates.sh` verde.
- Opcional: `swift test --sanitize=thread` como gate, si su tiempo lo permite.

## Coordinacion

Solo toca `Tests/` y una firma en `DiagramPNG.swift`. b6 esta en la 21c
(recursos, `Sources/`): el unico choque posible es `DiagramPNG.swift`, y se
avisa antes.

## Lo que encontro la ejecucion (2026-09-30)

- **El diagnostico "no es bug de produccion" era incompleto.** Con los fakes
  ya protegidos, TSan destapa dos data races en produccion. Quedan fuera de
  este cambio: cada uno necesita su test en rojo y su propia revision.
  - `BridgeConnection.close()`
    (`Sources/CompanionServices/Bridge/BridgeListener.swift:276`) llama
    `onClosed?()` despues de soltar el lock.
  - `RealtimeRuntime.flushPendingUpdate`
    (`Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:156`)
    lee y escribe `pendingUpdate`/`voiceSent` sin aislamiento.
- **Patrones que haran flake despues** (QA), para la siguiente pasada:
  - stores globales que los tests reemplazan: `ContextPreference.store`,
    `UserPreferences.store`, `ElevenLabsVoiceSettings.store`;
  - cotas de pared ajustadas: `ApprovalsTests.swift:100` exige `< 5 ms`;
  - `Thread.sleep` dentro de tests;
  - `runAsync`.
- **TSan como gate:** viable como gate opcional, filtrado y con supresiones
  para los dos races de produccion. No como gate bloqueante hasta
  arreglarlos.
