# Wave 3 — Voz

**Estado: CERRADO** — 2026-08-21, tras dos rondas de prueba manual en el
hardware de Karen. Voz de punta a punta, interrupcion por tap siempre y por
voz con audifonos, caidas visibles y con reconexion.
Kickoff planner + architect. Ledger de audio/AEC es contrato.

## Objetivo

Voz en tiempo real sobre OpenAI Realtime (WebSocket, 6 s), barge-in,
mute correcto, fallback clasico nativo. Mismo hilo que el texto.
WebRTC fuera.

## Desviaciones vs BORRADOR

1. `RealtimeCodec.appendAudio` no existia: se anade.
2. `VoiceSession` se parte: session + RealtimeRuntime + ClassicRuntime
   (tope 400).
3. `MicCapturing` y `PCMPlaying` son puertos Core (sesion testeable sin
   AVFoundation). El engine compartido es `AudioEngineHub` en Services.
4. `ConversationPresenting` en Core: ChatViewModel dueño del hilo;
   VoiceViewModel no duplica messages.
5. Realtime `tools: []` esta wave. Un `functionCall` se contesta con
   negativa; Executor es Wave 4.
6. Chat escrito no se lee en voz. Composer se cuelga mientras hay turno
   de voz; hang-up y luego se escribe.
7. Clasico: solo SFSpeech (sin Python). Sin permiso → no hay clasico.
8. ~~AEC default off~~ **REVOCADA en prueba manual (2026-08-21)**: sin AEC
   no se mandan frames en `.speaking`, luego el servidor no puede oir la
   interrupcion y el barge-in por voz no existe. Default ahora **on**; el
   watchdog de VP cubre el riesgo. Sigue sin mandarse durante el echo-guard.
9. Watchdog VP 1.5 s, reintento UNA vez, veto in-process (no UserDefaults).
10. `DeltaSink` (Wave 2) pasa a `actor`.

## Contratos no negociables (ledger)

- Mute + `speechOpen` → commit + `response.create`. Mute quieto no
  commitea. Unmute → clearAudio.
- Echo 350 ms. Voz no cambia tras el primer audio; speed si.
- Reconexion = sesion nueva, seed 6×200. Sin imagenes.
- Cadena: WS 6 s → clasico (mic + STT + ChatProvider + TTS).

## Puertos Core (resumen)

`VoiceTransport`, `MicCapturing`, `PCMPlaying`, `Transcriber`,
`SpeechSynthesizer`, `VoiceControlling`, `ConversationPresenting`.
`appendAudio(Data) -> String`.

`VoiceSession` actor interpreta `TurnEffect`. Reloj inyectable.

## UI

`VoiceViewModel` + `VoiceControlsView` (mic, fase, mute, nivel). Sin orb.
ChatViewModel gana metodos publicos del hilo.

## Tests

Fakes, cero `AVAudioEngine.start`, cero WS vivo. VoiceSession: barge-in,
mute, timeout 6 s → clasico, drop a mitad de conversacion. TTS: cache
<=80, orden, cancel.

## Construccion

1A ports+appendAudio || 1B DeltaSink actor.
2 paralelo: Speech | WS | PCM/mic/player | Voice VM.
3 VoiceSession. 4 vistas. 5 App.

## Definicion de done

Hablar de punta a punta con barge-in; matar la red a mitad de turno
cae a clasico con aviso. Gates verdes.

## Riesgos

AEC y TCC no los cubren los tests. Firma estable es Wave 5.

## Hallazgos del review de cierre (resueltos 2026-08-20)

code-reviewer: contratos del ledger verificados uno por uno con su test.
Hallazgo alto real: el watchdog de VP (desviacion 9) no existia — solo habia
reintento ante fallos detectables al arrancar; el caso del ledger (engine
arranca y el tap nunca dispara) quedaba sin recuperacion. Implementado con
regla pura `MicWatchdog.decide` + delay inyectable.

security-reviewer: dos hallazgos resultaron falsos al verificarlos (el deinit
del mic SI limpia; el hash del cache es de 64 bits, no 32). Aplicados:
permisos 0700 en cache/logs/conversaciones y validacion de endpoint en los
caminos de voz (WS y TTS), que se habian saltado las policies de Wave 2.
Rechazados con criterio: regex de formato de API key (el onboarding ya valida
con ping real y los prefijos de OpenAI cambian), borrado de la key en memoria
(impracticable con String en Swift; el Keychain ya protege en reposo),
FNV-1a → SHA256 (64 bits, colision despreciable) y rate limiting de TTS
(costo/UX, no seguridad).

Anadido fuera del spec: `scripts/bundle.sh` — sin Info.plist con usage
descriptions macOS no muestra el prompt de microfono, asi que la voz no se
podia probar desde `swift run`. Gate nuevo vigila que esas claves no se
pierdan.

## Segunda ronda de prueba manual (2026-08-21, cerrada)

Hallazgos en el hardware de Karen, todos con fix committeado:

1. Sesion zombi: el WS moria y el stream de eventos terminaba SIN error;
   la sesion quedaba en listening mandando audio al vacio. Ahora: error
   observable + reconexion unica sembrada + envio que se calla al primer
   fallo.
2. VPIO no inicializa en esta maquina (kAUInitialize -10875, dispositivo
   virtual de Teams en la cadena) y el intento envenenaba el engine simple.
   Ahora: veto PERSISTENTE (revoca la desviacion 9), espera de HAL con
   engines frescos, watchdog de silencio a nivel de sesion, y pin de ambos
   buses del VPIO al par integrado (tecnica documentada por Apple) antes de
   inicializar.
3. Salida sin eco (audifonos/bluetooth) habilita frames en .speaking sin
   AEC: barge-in por voz sin depender de VPIO.
4. Firma ad-hoc invalidaba TCC en cada rebuild: bundle.sh exige identidad
   estable y falla ruidoso si codesign falla.

Deuda declarada (post-v1, trigger PROBADO en esta maquina): transporte
WebRTC con AEC3 por software, el camino primario del prototipo — es la
solucion de fondo para AEC en Macs donde VPIO no levanta.
