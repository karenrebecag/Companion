# Wave 9i — Voz híbrida: el oído transcribe, el modelo lee y habla

**Estado: ENTREGADA (2026-08-25), con una desviación mayor decidida por
medición.** El diseño original ponía a Apple es-MX como oído; el entregado usa
**`gpt-live-transcribe`** (sesión realtime de solo transcripción) para el
pipeline realtime, y Apple queda como oído del clásico (sin key, sin red). La
cadena de evidencia que forzó cada giro, en orden:

1. La transcripción del speech-to-speech (`gpt-4o-transcribe`, generación que
   OpenAI ya no recomienda) devolvía basura coherente ("Mi madre no invierte")
   con el audio llegando entero (fwd=97, gated=1).
2. Apple es-MX transcribía bien en un probe aislado — pero en la app producía
   VACÍO: la cola de callbacks era la main queue (la UI la mataba de hambre) y
   el stream de parciales de un solo paso se agotaba. Cola dedicada +
   `currentText` como snapshot lo arreglaron… y Apple seguía fallando palabras
   inglesas ("Desktop" → "Stock").
3. Probe contra `gpt-live-transcribe` con la key real: mejor que Apple en el
   mismo audio y multilingüe nativo. Swap del oído por el puerto `Transcriber`,
   sin tocar turnos ni encargos.

**Tres causas raíz más cayeron al probar en vivo:** el gate anti-backchannel
ensordecía al oído al hablar sobre el agente (fwd=20/gated=85); cinco call
sites de `response.create` corrían sin dueño del ciclo de respuesta (turnos
huérfanos: "en mi desktop" nunca se procesó) — ahora hay un embudo con
prioridad (el turno del usuario preempta, lo demás espera); y el handshake del
websocket se comía los primeros fonemas ("hola" → "Ya.") — ahora los frames se
buffean hasta el ack de sesión. Además, el rol del especialista exige ACTUAR
con defaults razonables en vez de morir en preguntas aclaratorias — el motivo
por el que ningún archivo aterrizaba.

**Criterio de done, verificado en la Mac de Karen:** "crea un archivo de
prueba en mi escritorio" → `prueba.txt` real en el Desktop; "métele un cuento"
→ el especialista continúa el hilo y lo escribe; una tercera tarea encadenada
crea `SpecDriven_ElFaroQueEsperaba/`. 212 tests, gates verdes.

## 1. El principio, en una línea

> Interrumpir ≠ comprender. El barge-in solo necesita detectar que ARRANCASTE
> a hablar; entender las palabras es otra cosa. Así que OpenAI se queda con lo
> que hace bien (voz de salida + detección de interrupción) y Apple aporta lo
> que hace bien (el texto de tu instrucción).

## 2. El flujo

1. El mic va **en paralelo** a OpenAI (VAD/barge-in) y a Apple (texto). Ese tee
   ya existe: es la capa de audit, que se GRADÚA de microscopio a fuente.
2. `turn_detection: server_vad` con **`create_response: false`** y
   **`interrupt_response: true`**: el servidor sigue detectando inicio/fin de
   habla y sigue cortando al agente cuando hablas encima — pero **ya no arma la
   respuesta desde el audio**.
3. En `speech_stopped`: se toma el **texto final de Apple**, se
   `input_audio_buffer.clear` (descartar el audio que OpenAI habría usado), se
   `conversation.item.create` (role user, `input_text` = texto de Apple) y se
   `response.create`. El modelo responde por voz y delega desde el texto
   FIABLE.
4. Barge-in: mientras el agente habla, `speech_started` + `interrupt_response`
   cancela su audio (como hoy). Se repite desde el paso 3.

## 3. Archivos (5, dentro del límite)

- `RealtimeCodec.swift`: `turn_detection` gana `create_response:false` +
  `interrupt_response:true`; se **quita `input_audio_transcription`** (ya no lo
  usamos — y de paso desaparece el texto basura de pantalla); nuevo
  `userTextItem(_:)` (role user, input_text).
- `RealtimeRuntime.swift`: `.userTranscript` de OpenAI deja de escribir el hilo
  (ya no es la fuente); nuevo camino "commit con texto de Apple".
- `VoiceSession.swift` / `VoiceSessionPumps.swift`: el transcriptor Apple pasa
  de audit a fuente; al cerrar turno entrega su texto final; el hilo muestra
  ESE texto como tu mensaje.
- `TurnMachine.swift`: `serverSpeechStopped` emite un efecto nuevo
  `commitWithText` (en vez de dejar que el servidor responda solo).
- Los tests correspondientes.

## 4. Contrato de API (lo que cambia hacia OpenAI)

```
turn_detection: { type: server_vad, silence_duration_ms: N,
                  create_response: false, interrupt_response: true }
// input_audio_transcription: (removido)
// al cerrar turno:
conversation.item.create { item: { type: message, role: user,
                                   content: [{ type: input_text, text: <Apple> }] } }
response.create
```

## 5. Riesgos y decisiones

1. **Timing.** El texto final de Apple debe estar listo al `speech_stopped`.
   Apple da parciales en vivo (baja latencia), pero el final llega asíncrono:
   si al cerrar turno el último parcial está vacío, se espera un instante
   corto (p. ej. 300 ms) al parcial; si sigue vacío, se degrada (ver 2).
2. **Degradación honesta.** Si Speech no está autorizado o Apple no devolvió
   nada, se cae al comportamiento de HOY (audio a OpenAI, `create_response:true`)
   en vez de quedarse mudo. Nunca peor que ahora.
3. **Barge-in.** Hay que confirmar en runtime que `create_response:false`
   conserva `speech_started`/`interrupt_response`. La doc dice que sí; se
   verifica con el log (`voice: server speech_started` durante la respuesta).
4. **Turno vacío.** Texto de Apple vacío → no se crea respuesta (no gastar un
   turno en nada).
5. **Locale.** Apple ya en es-MX (`speechLocaleIdentifier`).

## 6. Fuera de alcance

- El pipeline clásico no se toca.
- OpenAI SIGUE dando la voz de salida (TTS/streaming). No se sustituye.
- El transcriptor de OpenAI (`gpt-4o-transcribe`) se retira, no se "mejora":
  ya no es la fuente.

## 7. Criterio de done

- Dices "crea un archivo de prueba en el escritorio" y el hilo muestra ESE
  texto (el de Apple), el goal dice eso, y el archivo cae en el escritorio.
- Interrumpes al agente hablando encima y se calla (barge-in intacto, visible
  en el log).
- Sin autorización de Speech, funciona como hoy (degradación).
- Gates verdes; TDD (efecto de TurnMachine y JSON de RealtimeCodec con test en
  rojo primero).
