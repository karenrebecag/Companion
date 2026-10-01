# Voz: corte de red mientras Companion habla (C2, silencio avisado)

Estado: EN CURSO (PR A). Aprobado por Karen el 2026-09-30.
PR A: comportamiento (puntos 1, 2, 4 y 5). PR B, el aviso en la isla (punto 3), la cierra.
Research: `docs/research/voz-reconexion-aislamiento.md`, decision C (APROBADO;
Karen eligio C2 sin C5). Va despues de #59 (fix/voice-reconnect).

## Objetivo

Si el socket de Realtime se cae a media respuesta y la reconexion funciona,
Karen oye lo que ya llego, se detiene, ve un aviso, y si dice "sigue" la voz
continua sin repetir. Nunca habla sola al reconectar.

## Hoy (tras #59)

- El player no se vacia al reconectar: el audio en cola termina y el drenaje
  (`playerDrained`) pasa la maquina a listening.
- `dropInFlightResponse()` borra `agentSpeech` sin guardarlo: lo dicho se pierde
  del hilo y el modelo nuevo no sabe que se corto.
- No hay aviso: para Karen es un silencio a media frase.
- Caso borde sin drenaje: la caida llega con la cola vacia pero la maquina ya en
  speaking (un `replyCompleted` o un delta de cero frames). No sale de speaking.

## Cambio (cada punto con test en rojo primero)

1. **Parcial al hilo.** `dropInFlightResponse()` devuelve el texto parcial antes
   de limpiar. Tras el drenaje, el actor lo enhebra en el hilo como respuesta del
   asistente marcada como cortada (mismo patron que el corte del pipeline clasico,
   `ClassicRuntime.swift:417`). Si el parcial esta vacio, no se enhebra nada.
2. **Nota de un solo uso.** El turno siguiente lleva una nota nueva en Core
   (no reusa `<steer>`, que dice que la usuaria interrumpio): "tu respuesta se
   corto por la red despues de: ...; si te piden seguir, continua sin repetir".
   Se consume en el primer turno y no vuelve.
3. **Aviso en la isla.** Cuando hubo corte a media respuesta, la isla muestra un
   aviso aunque la reconexion haya funcionado. Texto en el catalogo en/es (claves
   nuevas en `Localizable.strings`, paridad cubierta por `LocalizedTests`).
4. **Nunca `response.create` al reconectar.** Test que lo fija.
5. **Caso borde.** Si tras reconectar la maquina sigue en speaking y el player no
   tiene nada en cola, el actor aplica la salida de speaking. Test con el player
   scripted (que no drena solo): tras reconectar, el estado es listening.

## Limite conocido

`agentSpeech` es texto generado, no reproducido: el parcial puede incluir
palabras que no sonaron. Se acepta con un `HACK:` que nombra el techo y el
disparador: usar el conteo de muestras reproducidas del player (o
`conversation.item.truncate`) cuando se mida que la diferencia confunde al modelo.

## Fuera de alcance

C5 (linea hablada), ClassicRuntime, gate de TSan.

## Archivos (estimado 6-7, uno mas que el limite: el aviso de la isla y su
copy no se pueden separar del comportamiento sin dejar el PR a medias)

`RealtimeRuntime.swift`, `VoiceSession+Pumps.swift`, nota en Core (junto a la de
steer), modelo/vista del aviso en la isla, `en.lproj` y `es.lproj`,
`VoiceReconnectTests.swift`.

## Aceptacion

- Tests: parcial enhebrado tras drenaje; nota presente en el turno siguiente y
  ausente en el otro; aviso emitido; cero `response.create` al reconectar; caso
  borde termina en listening.
- `swift test --sanitize=thread --filter VoiceReconnect` sin avisos.
- `scripts/gates.sh` verde.
- code, security y QA.
- Prueba en vivo de Karen: cortar el wifi mientras Companion habla; oye lo que ya
  llego, ve el aviso, dice "sigue" y continua sin repetir.
