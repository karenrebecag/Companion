# VoiceSession: sacar las decisiones a Core

Estado: APROBADO (Karen, 2026-09-30; medido 2026-09-30).
Research: `docs/research/voicesession-division.md` (APROBADO).

## Objetivo

`VoiceSession` es un actor de ~2180 lineas en 14 archivos, con 76 miembros y
12 Tasks. El riesgo no es el tamano sino la correccion: reentrada, carreras y
la admision de permisos hablados viven mezcladas con pumps e I/O. El objetivo
es que las decisiones de seguridad sean puras, sincronas y testeables sin el
harness de voz.

## Forma (opcion 3 del brief, envuelta en la 1)

- **Un solo actor.** No se crea ningun `actor` nuevo en `Voice/Session`. Varios
  actores convertirian cada lectura cruzada en `await`: puntos de reentrada
  nuevos en la admision del "si" hablado y saltos por frame en el pump de
  audio (buffer de 2048 muestras, ~43 ms).
- **Tres structs puros en Core**, `Sendable`, sin frameworks ni `async`, con
  tests propios:
  - `ApprovalLedger`: aprobaciones armadas, cerradas y oidas; decide si un "si"
    hablado se admite.
  - `AnnouncementQueue`: anuncios aparcados y cuando salen.
  - `HoldGate`: generaciones de hold y lo oido en cada una.
- El actor muta el struct en una funcion sincrona y ejecuta el efecto
  despues. Nunca un `await` entre leer y escribir; todo `await` que quede en
  codigo de permisos va seguido de revalidar id y generacion.
- Lo que no es puro (pumps, I/O, los 12 handles de Task) se queda en el actor.
  Si mas adelante se saca a helpers, con parametro `isolated VoiceSession`
  (SE-0313), no con actores propios.

Reduce quiza 300-400 lineas; no se midio funcion por funcion. La ganancia que
importa es la de correccion, no la de tamano.

## Lo que no toca

- `reconnectRealtimeSession`, `pumpEvents` ni el aislamiento de
  `RealtimeRuntime`: los fija `fix/voice-reconnect`, que va primero.
- `Package.swift`.
- El camino de `pumpFrames`: ningun salto nuevo; se registra el tiempo por
  frame antes y despues.

## Tests

- Paso 1 de cada cluster: los tests existentes siguen verdes sin editarse. El
  actor expone propiedades computadas que reenvian los internals que leen
  los tests (~150 accesos en 20 archivos).
- Paso 2: cada test migra a su version pura en Core y la propiedad de
  reenvio se retira.
- El test de carrera con `receivedBufferDelay` (`HoldVoiceTests`) sigue
  cubriendo el mismo hueco.

## Secuencia

1. `fix/voice-reconnect` integrado.
2. `tests-por-modulo` integrado (los tests de voz ya caen en su target).
3. Un PR por cluster, de 3 a 5 archivos: `ApprovalLedger` primero (es el de
   seguridad), luego `HoldGate`, luego `AnnouncementQueue`.

Antes de arrancar: releer el diff de `fix/voice-reconnect` y ajustar esta
spec a lo que haya fijado para `RealtimeRuntime` y `ClassicRuntime`.

## Aceptacion

- Ningun actor nuevo; `VoiceSession` sigue siendo el unico dominio del turno.
- Los tres structs en Core con tests que no usan `makeVoiceHarness`.
- `swift test --sanitize=thread --filter Voice` sin avisos en `Voice/Session`.
- `scripts/gates.sh` verde con `CI=true`, sin `try?` nuevo en Core o Services.
- Tiempo por frame de `pumpFrames` igual o menor que antes.

## Decisiones de Karen (2026-09-30)

1. Direccion aprobada: structs puros en Core, un solo actor, sin actores nuevos.
2. `NonisolatedNonsendingByDefault` se evalua aparte; aqui se usa
   `nonisolated(nonsending)` por metodo, como `fix/voice-reconnect`.
