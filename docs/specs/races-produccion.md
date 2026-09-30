# Bridge y voz: tres bugs de concurrencia y reconexion

Estado: APROBADO (Karen, 2026-09-30; cada parte pasa por /research antes de codear).

## Objetivo

Arreglar tres bugs de produccion. Los destapo TSan una vez que los fakes de
test dejaron de hacer ruido (`suite-estable`). Dos pueden dejar la app muda o
inservible hasta reiniciarla.

## Hallazgos (analisis de solo lectura, verificado en el codigo)

### 1. El bridge puede quedar "ocupado" para siempre (TSan lo confirma)

- `BridgeConnection.init(fd:)` arranca el hilo de lectura
  (`BridgeListener.swift:253`) antes de que el listener le asigne
  `onClosed` (`:146`).
- Si el cliente ya cerro, el hilo llega a `close()`, marca el slot como
  liberado y lee `onClosed` todavia en nil, asi que el callback se pierde
  para siempre.
- El listener guarda entonces una conexion muerta como activa, y todo cliente
  posterior recibe `busy`.
- Efecto: el bridge con Claude Code o el relay del navegador quedan muertos
  hasta reiniciar la app.
- TSan lo marco dos veces en una corrida completa: hilo "bridge-connection"
  :276 contra "bridge-accept" :146.

### 2. Tras una reconexion, la voz pierde instrucciones, tools y voz (bug de logica)

- `reconnectRealtimeSession()` (`VoiceSession+Pumps.swift:~147`) reabre el
  transporte y reinicia los pumps, pero no llama `prepareSessionUpdate` ni
  `reset()`.
- Tras el primer flush, `pendingUpdate` ya es nil: la sesion nueva corre con
  los defaults del servidor, sin instrucciones, sin tools y sin la voz elegida.
- Si un envio habia fallado, `transportDown` sigue en true y todos los envios
  posteriores se descartan en silencio.
- Pendiente de verificar: si `startPumps` relanza el pump de eventos tras una
  reconexion (solo lo crea si `eventTask` es nil).

### 3. `RealtimeRuntime` no tiene aislamiento (hipotesis; TSan no lo marco)

- Es una `final class @unchecked Sendable` sin lock ni actor.
- Sus metodos `async` corren en el executor global, fuera del actor
  `VoiceSession`.
- El flush de apertura y el de `session.created` pueden solaparse y mandar el
  update dos veces: inocuo, porque es el mismo JSON antes de cualquier audio.
- `agentSpeech` se escribe en `handle` y se lee en el actor.
- `reset()` puede solaparse con un `handle` en vuelo.
- Hoy la probabilidad en produccion es muy baja, pero es la misma clase de
  bug que el 1.

## Cambio (cada uno con test en rojo primero)

1. **Bridge.** Separar el arranque del hilo del `init`: un `start()` que el
   listener llama al final. El orden queda: crear, asignar `onClosed`, marcar
   activa, `start()`, `onConnection`. `Thread.start` da el happens-before, asi
   que el callback no se puede perder.
   - Los tests que construyen `BridgeConnection` directo llaman `start()`.
   - Test: un socketpair con el cliente ya cerrado; asignar `onClosed`;
     afirmar que se llama exactamente una vez; 500 iteraciones.
   - Test a nivel listener: N conexiones que cierran al instante, y un cliente
     nuevo recibe `hello`, no `busy`.
2. **Reconexion.** `reconnectRealtimeSession` llama `reset()`,
   `prepareSessionUpdate` y `flushPendingUpdate` tras abrir, y limpia
   `transportDown`. Verificar y, si falta, relanzar el pump de eventos.
   - Test determinista: primer flush, reconexion simulada, afirmar que se
     reenvia un `session.update` con instrucciones y tools.
3. **Aislamiento.** Los metodos async de `RealtimeRuntime` pasan a
   `nonisolated(nonsending)` (Swift 6.2; tools 6.2 ya lo permite), para que
   corran en el executor del actor que los llama. Asi todo su estado queda
   confinado al actor `VoiceSession`, sin locks.
   - Test: dos flushes concurrentes desde un task group envian exactamente un
     update, 1000 iteraciones, con TSan como oraculo.
   - No se activa `NonisolatedNonsendingByDefault` en `Package.swift`: seria
     config raiz y mucho mas amplio.

## Fuera de alcance

Los fallos de `processRegistryTests` y `earReviewTests` vistos una vez bajo
TSan, y el resto de patrones de flake listados en `suite-estable`.

## Aceptacion

- Los tres tests nuevos en rojo antes y en verde despues.
- `swift test --sanitize=thread` sin avisos en `BridgeListener` ni en
  `RealtimeRuntime`.
- `scripts/gates.sh` verde.
- code-reviewer, security-reviewer (el bridge es frontera de confianza) y QA.
- Prueba en vivo de Karen: cortar la red durante una sesion de voz y
  comprobar que, al reconectar, Companion sigue respondiendo con su voz y sus
  tools.
