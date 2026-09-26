# Wave 15c — Tubo rápido (estilo Incredible)

**Estado: APROBADA / EN CURSO (2026-09-23).** Karen: "bien, vamos". 15c-0..6 implementadas test-first; seguridad APPROVE, code review APPROVE (pendiente MEDIUM: la escalera de respaldo puede reintentar Groq con backoff en 429 si Groq es la única clave; LOW: el dictado no usa el oído Groq). 305 tests, gates verdes, instalada. Pendiente §9 en vivo. Sin commit.

Karen: "vamos con el estilo incredible". Queja medida: "abre Safari" contesta
"estás en la Terminal"; "abre una nota en blanco" pregunta qué app; la voz
"tarda más en pensar que en responder".

Criterio de done: 10 holds "abre X" con `release→audio` p50 ≤ 1500 ms y
p90 ≤ 2000 ms; "abre Safari" desde Terminal abre Safari; gates verdes.

---

## 1. El defecto, medido (log 2026-09-23 19:48, 6 holds)

| Tramo | Hoy | Causa |
|---|---|---|
| Oído | frase cortada | `SystemTranscriber.stop()` toma el parcial y cancela (`:108`) sin `endAudio` ni esperar el final; cada hold loguea `recognition failed (No speech detected)` al soltar |
| Router N1 (qwen3:4b) | 0.15–0.9 s, 0 aciertos | con la frase cortada devuelve `arbitrate` y N2 no está cableado → `pass reason=failed/ignored` en los 6 |
| Cerebro | ~2 s | escalera del chat escrito (`ChatProviderClient`); sin preferencias guardadas = OpenAI `gpt-4o`. La línea `voice stack: brain=gpt-4o-mini` es decorativa (`VoiceSessionPumps.swift:331`, nadie lee `lastStack`) |
| Boca | ~2–2.5 s | ya parte por frases (`ClassicRuntime.swift:179`), pero cada frase descarga el mp3 entero antes de sonar (`OpenAITTS.swift:33`) |
| **release→audio** | **3.85–5.9 s** | |

Además: `ProviderDescriptor.groq.model = "llama-3.3-70b-versatile"`
(`Config.swift:63`) ya no existe en Groq (lista de modelos del 2026-09-23).

## 2. Incredible, medido (`~/Documents/Incredible-Debug`)

| Pieza | Incredible |
|---|---|
| Oído | AssemblyAI streaming + **final por Groq** (`stt_final_provider: groq`) |
| Clasificador / respuesta rápida | **`groq/openai/gpt-oss-120b`** (fallback Cerebras) |
| Tareas largas | Gemini 3.5 Flash Lite, 6–9 s por llamada |
| Boca | Inworld TTS por websocket (streaming) |

## 3. Groq, medido con la clave de Karen (2026-09-23)

| Llamada | Tiempo total (red incluida) |
|---|---|
| `whisper-large-v3-turbo`, "abre Safari y busca el clima" (es) | 0.47–0.60 s, texto exacto |
| `openai/gpt-oss-120b`, `reasoning_effort: low`, 5 palabras | 0.52–0.73 s |
| `openai/gpt-oss-120b` + tool `open_app` → `{"name":"Safari"}` | 0.47 s |

Presupuesto objetivo: oído final 0.5 + cerebro al primer token/tool 0.5 +
primer audio 0.3–0.5 ≈ **1.3–1.5 s**.

---

## 4. Decisión

| Decisión | Por qué |
|---|---|
| **Oído final = Groq Whisper turbo** sobre el PCM del hold; Apple sigue dando parciales (isla, fan-out) | texto exacto en 0.5 s; es lo que hace Incredible |
| Sin clave Groq o si Groq falla/tarda > 1.5 s: Apple **con `endAudio` + espera ≤ 300 ms al final** | el arreglo del corte vale también sin Groq |
| **Cerebro del hold = rol `brain` del `VoiceStack`**, ya no la escalera del chat. Con clave Groq: `openai/gpt-oss-120b`, `reasoning_effort: low` | el rol existía (14a) pero nunca mandaba; el chat escrito no cambia |
| Si el cerebro Groq falla **antes del primer token**: cae a la escalera de hoy | un hold nunca se queda mudo por un proveedor |
| Tareas largas: **sin cambio**, siguen por `delegate` al ejecutor | ya existe; el "modelo inteligente" de Incredible es eso |
| **N1 local no corre si el cerebro es Groq** (toggle intacto; corre sin Groq) | Groq ya elige la herramienta en 0.47 s; N1 sumó hasta 0.9 s y no acertó ninguna |
| **Boca en streaming**: `response_format: "pcm"` (24 kHz, 16-bit, mono) reproducido mientras llega | quita la descarga completa por frase; la caché guarda el PCM al terminar |
| Log verdadero: proveedor + modelo que contestó, `commit→firstToken`, `ear=groq/apple` | hoy el log mintió y nos costó un diagnóstico |
| `ProviderDescriptor.groq.model` → `openai/gpt-oss-120b` | el actual da 404 |

**La clave:** Karen la pega en Ajustes → Claves (Keychain, `secrets.v1`).
Nunca en código, spec, log ni env. Recomendado rotarla en Groq: quedó en el
transcript de esta conversación.

---

## 5. Entregas

| # | Qué | Archivos principales |
|---|---|---|
| 15c-0 | Log verdadero (`ear`, proveedor/modelo real, `commit→firstToken`) — va primero para medir lo demás | `VoiceSessionPumps`, `ClassicRuntime`, `TurnTimeline` |
| 15c-1 | Apple: `endAudio` + espera ≤ 300 ms al final | `SystemTranscriber` |
| 15c-2 | `GroqTranscriber` (nuevo): PCM del hold → WAV 16 kHz mono → `whisper-large-v3-turbo`; tope 60 s de audio; timeout 1.5 s → Apple | `GroqTranscriber` (nuevo), `VoiceSessionPumps` (acumular PCM), `CompanionMain` |
| 15c-3 | Cerebro por rol: `VoiceStackResolver` pone Groq primero para `brain`; `ClassicRuntime` recibe un `ChatProvider` fijado al rol, con caída a la escalera antes del primer token; `groq.model` actualizado | `VoiceStack`, `Config`, `ClassicRuntime`, `CompanionMain` |
| 15c-4 | N1 se salta con cerebro Groq (`pass reason=fastBrain`) | `DecisionRouting`, `VoiceSessionDecision` |
| 15c-5 | TTS streaming PCM → `AVAudioPlayerNode` incremental; `stop()` corta a media frase; caché al terminar | `OpenAITTS`, `SpeechSynthesis`, `PlayerGate` |
| 15c-6 | Ajustes → Claves: campo para Groq (y reemplazar la de OpenAI), escribe por `SecretStore`, nunca muestra la clave guardada (solo "guardada"), botón para borrar; línea de privacidad "el audio del hold se transcribe en Groq" | vista de Ajustes, strings, test |

`VoiceSession.swift` está en 795/800: nada entra ahí; lo nuevo va a
extensiones (`VoiceSessionPumps` / archivo nuevo).

**Desviación (2026-09-23):** la spec daba por hecho una sección Claves en Ajustes; no existe (solo el onboarding escribe la de OpenAI, `ChatViewModel.swift:214`). Se añade 15c-6 porque sin ella la decisión de §4 no se puede cumplir.

## 6. TDD (rojo primero)

| # | Test | Espera |
|---|---|---|
| 1 | Apple `stop()` con final que llega a 120 ms | devuelve el final, no el parcial |
| 2 | Apple `stop()` sin final | a los 300 ms devuelve el parcial |
| 3 | Groq transcribe OK | texto de Groq; el parcial Apple no se usa |
| 4 | Groq 500 / timeout 1.5 s / sin clave | cae a Apple; log `ear=apple reason=…` sin texto |
| 5 | hold de 90 s | se envían solo 60 s |
| 6 | WAV generado | cabecera RIFF válida, 16 kHz, mono, 16-bit |
| 7 | resolver con Groq + OpenAI | `brain=groq/openai/gpt-oss-120b`; `mouth`/`sight` siguen OpenAI |
| 8 | resolver solo OpenAI | `brain` = hoy (escalera) |
| 9 | cerebro Groq lanza antes del primer token | la escalera contesta el mismo turno |
| 10 | cerebro Groq lanza después del primer token | no reintenta (no duplica audio) |
| 11 | request Groq | `model=openai/gpt-oss-120b`, `reasoning_effort=low`, tools = padre + delegate |
| 12 | cerebro Groq + toggle local ON | `DecisionGate` no se llama; log `pass reason=fastBrain` |
| 13 | TTS: 3 chunks PCM | el player recibe el 1.º antes de que llegue el 3.º |
| 14 | TTS `stop()` a media frase | nada más suena; no se cachea el parcial |
| 15 | caché | frase completa queda cacheada y se reproduce sin red |
| 16 | log | nunca contiene utterance, texto transcrito ni clave |

## 7. Fuera

- "Abre una nota en blanco": necesita una acción (atajo ⌘N en Notas) → es
  DM1d (ejecutores volume/shortcut/type_text), no esta wave. Hoy el cerebro
  solo puede abrir la app.
- AssemblyAI / Inworld (otra clave, otro proveedor).
- Manos libres (Realtime) sin cambio.
- Cerebras como fallback de Groq.
- Visión de pantalla: sigue esperando el permiso de Grabación de pantalla.

## 8. Seguridad y privacidad

- El audio del hold va a Groq (tercero) cuando hay clave Groq: lo decide
  Karen al pegarla; Ajustes lo dice en una línea.
- Clave leída al presionar, nunca al arrancar; nunca en logs.
- `EndpointPolicy` debe aceptar `api.groq.com` (ya está en el catálogo).
- Tope de 60 s de audio por hold (coste y tamaño).

## 9. Done (en vivo, Karen)

1. Clave Groq pegada en Ajustes.
2. Cursor en Terminal, FN, "abre Safari": abre Safari. Log `ear=groq`,
   `brain=groq/openai/gpt-oss-120b`.
3. 10 holds "abre X": `release→audio` p50 ≤ 1500, p90 ≤ 2000.
4. Wi-Fi apagado a mitad: el hold cae a Apple + escalera y contesta igual.
5. Gates verdes; `VoiceSession.swift` ≤ 800.

## 10. Aprobación

Sin preguntas abiertas: las decisiones de §4 siguen lo que pediste
("el más rápido... rutear a un modelo inteligente"). Si apruebas, lo
orquesto igual que 15b hasta dejarlo instalado para la prueba de §9.

---

## 11. Addendum 15c-7 (2026-09-24, aprobado por Karen: "ya apliqué config de cerebras ... continue")

**Medido en vivo (2026-09-23 21:16-21:19):**
- Silencio: 3 holds sin voz, Apple `No speech detected`, Groq Whisper devolvió "Gracias." / "Dios no me siente." (alucinación conocida) y el cerebro contestó.
- Groq free tier en `gpt-oss-120b`: **8 000 tokens/min** (`x-ratelimit-limit-tokens`). Con 2-3 rondas por turno se agota; `RetryPolicy` reintenta el 429 con backoff dentro del cliente fijado y luego cae a `gpt-4o`: turnos de 9 s y 24 s.
- Developer tier de Groq: "temporarily unavailable" (captura de Karen).

**Cerebras, medido con la clave de Karen (2026-09-24):** `gpt-oss-120b` tool call `open_app("Notes")` en 0.27 s (no stream) / TTFB 0.39 s (stream, mismo body que `ChatSSEAttempt`); límite **500 000 tokens/min**.

| Decisión | Por qué |
|---|---|
| Cerebro rápido = **Cerebras `gpt-oss-120b`**, luego Groq, luego la escalera | 60x el límite de Groq y más rápido |
| El cerebro rápido **no reintenta**: 1 intento por proveedor, un 429 pasa al siguiente al instante | el backoff era el origen de los 8-24 s |
| La escalera de respaldo del hold **excluye** Cerebras y Groq | ya se intentaron en el mismo turno (hallazgo MEDIUM del review) |
| Oído sigue en Groq Whisper (límite propio) con **filtro de silencio**: sin energía de voz Y Apple vacío → no se llama a Groq; `verbose_json` con `no_speech_prob` alto → se descarta | Whisper alucina en silencio |
| `SecretKey.cerebras`, fila en Ajustes → Claves; las claves guardadas se muestran enmascaradas (`csk-••••hm`), "Borrar" discreto | Karen: "no se le entiende nada a tu interfaz" |
| Cerebras **no** entra al catálogo del chat escrito | el chat escrito no cambia en esta wave |
