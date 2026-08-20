# Wave 3 — Voz

**Estado: BORRADOR** — se refina en kickoff. LEER el ledger completo de
audio/AEC y Realtime antes de tocar nada: es la wave con mas cicatrices.

## Objetivo

Conversacion por voz en tiempo real sobre OpenAI Realtime (WebSocket), con
barge-in, mute correcto y fallbacks nativos. El mismo hilo que el texto:
cambiar de modo no pierde contexto.

## Alcance

### CompanionServices
| Archivo | Contenido | Ledger |
|---|---|---|
| `MicCapture.swift` | AVAudioEngine + Voice Processing (AEC). Watchdog 1.5 s si no llegan buffers -> apagar VP y reintentar UNA vez (con limite, a diferencia del original). | Audio/AEC |
| `RealtimePlayer.swift` | Player PCM 24 kHz; engine compartido con el mic cuando hay AEC (`ownsEngine`). Conteo de buffers con aislamiento de actor, no NSLock parcial. | Audio/AEC |
| `RealtimeWSTransport.swift` | Puerto `VoiceTransport` sobre URLSessionWebSocketTask, async/await, timeout de apertura 6 s. Usa `RealtimeCodec` de Wave 1. | Realtime |
| `VoiceSession.swift` | `actor` que corre el reducer `TurnMachine` (Wave 1) ejecutando efectos: es el reemplazo del AppDelegate-orquestador del original. Cancelacion estructurada, no contador `generation`. | Anti-patrones |
| `SpeechSynthesis.swift` | TTS clasico: OpenAI `gpt-4o-mini-tts` primario, `AVSpeechSynthesizer` fallback offline (ADR 001). Cache de frases <=80 chars. | TTS |
| `SystemTranscriber.swift` | SFSpeechRecognizer on-device (unico STT local; cero Python). | ADR 001 |
| `Endpointer` (Wave 1) | Se usa solo en el pipeline clasico; en Realtime manda el VAD del server. | Endpointing |

### CompanionUI
- `VoiceControlsView.swift`: mic, estado del turno, nivel, mute. Visual
  minimo (el orb bonito es Wave 5).
- `VoiceViewModel.swift`: `@Observable`, refleja `TurnState`.

## Contratos criticos (del ledger, no negociables)

- Mute manda commit + response.create; no basta callar.
- Echo guard ~350 ms tras audio del agente.
- La voz no cambia tras el primer audio; la velocidad si.
- Reconexion = sesion nueva sembrada con 6 turnos / 200 chars.
- Cadena: Realtime WS -> pipeline clasico (mic + STT + chat + TTS). WebRTC
  queda explicitamente FUERA de esta wave (post-v1 en el roadmap).

## Tests

- Reducer ya cubierto en Wave 1; aqui: VoiceSession con transporte fake
  (guion de eventos Realtime -> secuencia esperada de efectos), incluido
  barge-in, mute y caida del WS a mitad de turno.
- SpeechSynthesis: cache, orden de frases, cancelacion.

## Definicion de done

Conversar por voz de punta a punta con barge-in; matar la red a mitad de
turno degrada al pipeline clasico con aviso claro. Gates verdes.

## Riesgos

- AEC es la zona mas fragil del original: presupuestar iteracion manual con
  Karen probando en su hardware. Los tests no cubren CoreAudio real.
- TCC (permiso de mic) exige firma estable entre builds.
