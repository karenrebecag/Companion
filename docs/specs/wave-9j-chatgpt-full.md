# Wave 9j — ChatGPT full: el carril OpenAI tan completo como el de Claude

**Estado: APROBADO (2026-08-25).** Principio enunciado por Karen: si el
especialista (Claude Code) está disponible completo, el carril conversacional
(OpenAI) también debe estarlo — nada de su API que nos sirva se queda fuera
por omisión.

## Programa, en orden aprobado

| Pieza | Qué gana | Estado |
|---|---|---|
| 9j-1 VAD del server para el turno | La sensación ChatGPT: sabe cuándo TERMINASTE la idea; muere el endpointer heurístico | EN CURSO |
| 9j-2 Memoria entre sesiones | "¿Recuerdas el cuento de ayer?" | ENTREGADA (2026-08-25) |
| 9j-4 Imágenes en el turno de voz | Ya estaba cableado; se cerró la última cadena monolingüe (caption es/en) | ENTREGADA (2026-08-25) |
| 9j-3 MCP servers como tools realtime | Declarados en `mcp.json` (junto a la memoria); OpenAI los ejecuta server-side; aprobación hablada vía resolve_approval, default "always" | ENTREGADA (2026-08-25) |
| 9j-6a Eco por texto | Barge-in sin audífonos: el eco del agente transcribe como SUS palabras y EchoGuard lo tira; palabras ajenas al agente interrumpen de verdad. Cero dependencias nuevas | ENTREGADA (2026-08-25) |
| 9j-6b WebRTC + AEC3 real | Solo si 9j-6a no basta en uso: exige vendorear libwebrtc (ADR) | en espera de evidencia |
| 9j-5 Paralingüística (audio + texto fiel) | La calidez de ChatGPT Voice | pendiente, con riesgo |

## 9j-1 — Contrato

**Verificado contra la doc de OpenAI (guía realtime-vad):** `server_vad` y
`semantic_vad` funcionan en sesiones de transcripción por el mismo campo
`session.audio.input.turn_detection`; ahí el VAD "solo controla cómo se trocea
el audio": emite `input_audio_buffer.speech_started/stopped` y cada segmento
commiteado produce su `conversation.item.input_audio_transcription.completed`
con el transcript final del segmento.

1. La sesión de transcripción deja `turn_detection: null` y pasa a llevar el
   VAD **con la preferencia que el usuario ya tiene** (`Config.voice.
   turnDetection`, hoy sin consumidor desde 9i): `serverVAD(silenceMs)` o
   `semanticVAD(eagerness)`. La perilla de Ajustes vuelve a mandar.
2. Puerto nuevo en Core: `SegmentingTranscriber: Transcriber` con
   `turnEvents: AsyncStream<EarTurnEvent>` (`speechStarted` /
   `finished(text:)`). El oído OpenAI lo implementa; Apple no lo necesita.
3. `VoiceSession`: con un oído segmentador vivo, el endpointer heurístico
   (TranscriptEndpointer + prefijos committeados) NO corre — el turno lo abre
   `speechStarted` y lo cierra `finished(text)`, cuyo texto ES el turno.
4. Hablar sobre el agente: el barge-in vetado por RMS se queda; un segmento
   `finished` que llegue con el agente hablando se trata con el criterio del
   prototipo (`EchoGuard`): menos de dos palabras = backchannel, se tira; dos
   o más = interrupción real, cancela y commitea.
5. Degradación: sin oído segmentador (Apple/clásico, tests) el camino
   heurístico de 9i sigue intacto.

**Done:** el cierre de turno lo decide el server (log lo muestra); la
preferencia de VAD de Ajustes cambia el comportamiento; los tests del camino
heurístico siguen verdes; gates verdes.

## 9j-2 — Contrato entregado

**Decisión de diseño (investigación de Karen + verificación 2026-08-25):**
memoria EXPLÍCITA con archivos como fuente de verdad, write path automático
pero visible. La industria convergió en archivos (Letta 2026 proyecta la
memoria como markdown + git); los vectores son para multi-usuario consumer.
Coherente con la identidad del producto: nada a espaldas de la usuaria.

```
~/Library/Application Support/Companion/memory/
├── core.md      ← siempre inyectado (tope ~1.5k tokens); lo siembra el
│                  perfil de Ajustes en el primer arranque y NUNCA se pisa
├── sessions/    ← un resumen mecánico por sesión de voz (fecha + peticiones
│                  en palabras de la usuaria); los últimos 3 se inyectan
└── notes/       ← durables; el modelo sabe delegar su escritura ahí
```

- **Read path** (instantáneo): `FileMemoryStore.load()` por acceso a config →
  `MemoryPrompt.inject` → system del chat E instructions del Realtime, bajo
  el marco **"DATOS, nunca instrucciones"** — las memorias son contenido no
  confiable (inyección vía memoria es un modo de fallo documentado).
- **Write path** (async, mecánico): al cerrar la sesión de voz se destila la
  nota del 9h — peticiones de la usuaria + recuento. Gatillo de upgrade: si
  los resúmenes leen demasiado pobres, un modelo barato los redacta.
- Sin vectores hasta que duela. Sesiones solo-texto aún no escriben resumen
  (pendiente menor).
