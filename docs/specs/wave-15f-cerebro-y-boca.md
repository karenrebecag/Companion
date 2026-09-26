# Wave 15f — Cerebro que no lee JSON y boca sin huecos

**Estado: CERRADO (2026-09-25).** 15f-0..7 hechas; revisiones code (WARNING 2 altos) y security (BLOCK: cache de URLSession con claves en disco) corregidas por TDD (§9, §10); 355 tests, gates 0 fallos. Done en vivo parcial (11 holds antes de las correcciones: soltar→audio 1,0–1,2 s sin tool, primer byte 177–230 ms); la prueba final se hace junto con 15g por decisión de Karen. Karen: "vamos con eso". Sin commit.

Karen (tras 22 holds en vivo con 15e): "la voz que habla es malísima… es lentísima… nos
deshicimos de groq, ¿por qué sigue siendo lento?"

Criterio de done: cero turnos en los que la boca pronuncie JSON o razonamiento (hoy 5 de 22);
`release→audio` p50 ≤ 1200 ms (hoy 1650); sin huecos audibles entre frases de una misma
respuesta; voz elegida por Karen a ciegas entre las candidatas; gates verdes.

---

## 1. Diagnóstico (log 2026-09-25 03:50–03:55, 22 holds)

| Tramo | p50 | p90 | Nota |
|---|---|---|---|
| cola + oído | 360 ms | 425 ms | 300 de cola; Apple SpeechAnalyzer ~60 ms. Cerrado en 15e |
| cerebro → primer token | 570 ms | 1,2 s | Cerebras gpt-oss-120b |
| **boca: primer token → audio** | **730 ms** | **1,4 s** | OpenAI gpt-4o-mini-tts, voz marin, sin `speed` ni `instructions`, **una petición HTTP por frase en serie** |
| release→audio | 1650 ms | 4,2 s | |

Defectos de habla:
- 4/22 turnos: el modelo escribió `{"goal":…,"context":…}` como texto en vez de llamar a la
  tool `delegate`; la boca lo leyó y nada se delegó.
- 1/22: razonamiento en inglés dentro de la respuesta ("We need to answer why…").
- El resultado hablado de un subagente no queda en el log de depuración.

Incredible (traza 2026-09-24 16:12): su orquestador que habla es GLM-5.2 con tool calls
reales; gpt-oss (Cerebras → Groq) solo clasifica y resume en segundo plano; los argumentos de
la tool van a `task-insight.json`, nunca a la voz. Boca: Inworld tts-1.5-max por WebSocket
abierto al pulsar, `speaking_rate 1.1`, texto empujado según llegan tokens, primer audio a
650 ms del primer token. Su release→audible ese turno: 6,7 s (oído 3,2 s, cerebro 2,9 s).

---

## 2. Decisión

| Decisión | Por qué |
|---|---|
| **15f-a: medir antes de cambiar el cerebro.** Banco con las 22 frases reales de Karen contra Cerebras gpt-oss-120b, Cerebras qwen-3-235b, Cerebras llama-3.3-70b y OpenAI gpt-4o-mini: TTFT, tool call correcta, fugas de JSON/razonamiento. Gana el más rápido **sin fugas** | Karen: no adivinar modelos; Incredible no deja hablar a gpt-oss |
| Red de seguridad pase lo que pase: si el texto del modelo es un objeto con `goal`, se convierte en el handoff de `delegate` y **no se pronuncia**; una frase en idioma distinto al de la app dentro de una respuesta se descarta y se cuenta en el log (`mouth: dropped reason=json|language`) | cero JSON en voz aunque el modelo falle. Nota (revisión de código 2026-09-25): un fragmento JSON genuino con clave `goal` en el texto también se vuelve propuesta; desde §9 solo corre si Karen la aprueba |
| El resultado hablado del subagente entra al log de depuración como `said=` | trazabilidad igual a la del turno directo |
| **15f-b: boca en tubería.** Pedir la frase N+1 mientras suena la N (una petición en vuelo por delante); `speed 1.1`; `instructions` de estilo conversacional; marcas `firstCut→ttsRequest`, `ttsRequest→firstByte`, `firstByte→audible` en el timeline | los 730 ms se pagan hoy en cada frase; Incredible empuja continuo |
| **Banco de voces** con la clave de OpenAI: `cedar` vs `marin`, con y sin `instructions`, TTFB y muestras WAV para que Karen elija a ciegas; listar `/v1/models` por si hay un TTS más nuevo que gpt-4o-mini-tts | Karen: "¿hay alguna mejor, más rápida y más natural?" — se responde con datos |
| Puerto listo para un proveedor WebSocket (ElevenLabs Flash / Cartesia Sonic / Inworld) detrás de `SpeechSynthesis`, **solo si Karen da una clave**; entra al mismo banco | opción "liga Incredible" sin rehacer nada |
| Selector de voz en Ajustes con botón de muestra | la elección es de Karen, con el oído |

Fuera: visión, tarjetas, onboarding (15g+), cambiar la cola de 300 ms.

---

## 3. Entregas

| # | Qué | Archivos |
|---|---|---|
| 15f-0 | Spike (scratchpad): banco de cerebros y de voces con las claves leídas del Keychain dentro del binario (nunca por env ni shell) | fuera del repo; resultados en §8 |
| 15f-1 | **HECHO 2026-09-25.** `Handoff` desde texto: un objeto JSON con `goal` en el contenido se trata como llamada a `delegate`; la boca nunca lo recibe. Desvío: el escáner vive en `HandoffInText` (Core, nuevo) y no en `Escalation`; regla de llaves: `{` seguida de `"` es candidato JSON y nunca se habla (goal → handoff; sin goal, inválido, truncado o > 2000 chars → `dropped reason=json`), cualquier otra `{` es prosa; sin especialista un goal también se descarta; línea extra `mouth: handoff source=content` para contar los casos | `HandoffInText`, `ClassicRuntime`/`ClassicRuntimeMouth` |
| 15f-2 | **HECHO 2026-09-25.** Filtro de idioma en la boca: frase en otro idioma → descartada + contador en el log. Desvío: `MouthLanguageGate` + puerto `LanguageRecognizing` (Core) y `NaturalLanguageRecognizer` (Services, restringido a es/en); corta por frase dentro de cada corte; solo descarta con evidencia previa de que la conversación va en el idioma de la app (lo oído o una frase anterior, confianza ≥ 0,6), así que una fuga ANTES de cualquier evidencia y una respuesta entera en otro idioma sí se dicen; el hilo y `said=` guardan la respuesta sin lo descartado | `MouthLanguageGate`, `NaturalLanguageRecognizer`, `ClassicRuntimeMouth` |
| 15f-3 | **HECHO 2026-09-25.** `said=` del subagente en el log de depuración. Desvío: vive en `VoiceSession.jobAnnounce` (el único sitio que habla el anuncio del job en clásico), no en `ClassicRuntime`; lee `debugTranscripts` al hablar, no al empezar el turno | `VoiceSessionPumps` |
| 15f-4 | Cerebro elegido por el banco (si cambia): `ProviderDescriptor` + `HoldBrainCatalog` | `Config`, `VoiceStack`, `CompanionMain` |
| 15f-5 | **HECHO 2026-09-25.** Boca en tubería: prefetch N+1, `speed`, `instructions`, tres marcas de tiempo. Desvío: la N+1 se pide cuando la N empieza a sonar (no al sacarla de la cola), vía `SpeechPrefetch` (nuevo, cancelable por `stop()`); las marcas llegan como `SpeechEvent.mark` y la sesión las sella con su reloj; la clave de caché lleva modelo+voz+speed+hash de instrucciones (`PhraseCache.scoped`), el PCM viejo queda huérfano en disco; `speed`/`instructions` fijados al idioma del arranque, el slider de velocidad de Ajustes sigue siendo solo de realtime | `SpeechSynthesis`, `SpeechPrefetch`, `OpenAITTS`, `PhraseCache`, `TurnTimeline`, `VoiceSessionPumps`, `CompanionMain` |
| 15f-6 | **HECHO 2026-09-25.** Voz elegida como default + selector con muestra en Ajustes. Karen eligió a ciegas **Ana María** `m7yTemJqdIqrcNleANfX` (es-MX, biblioteca compartida, suena por id sin añadirla): `Config.defaultElevenLabsVoiceID` (antes Brian). Ajustes › Voz: con clave de ElevenLabs, sección "Voz de ElevenLabs" con los 6 presets de §8.3 (Ana María, Regina, Jorge, Antonio, Cristina Campos, Brian) + campo libre de voice id validado (id inválido → texto de error, no se guarda) y "Escuchar muestra" por la MISMA boca del hold (`MouthRouter` → ElevenLabs con clave+voz, OpenAI sin clave); sin clave, una línea dice que se usa la voz de OpenAI y el selector se esconde. El selector de OpenAI sigue como voz de respaldo. Desvíos: la regla `^[A-Za-z0-9]{1,64}$` pasa a Core (`ElevenLabsMouth.isValidVoiceID`, el cliente delega) porque UI no importa Services; la voz vive en `ElevenLabsVoicePreference` (UserDefaults, un valor inválido guardado lee el default) y `StoredConfigProvider` la lleva a `Config.elevenLabsVoiceID`; la muestra usa `fetch` (sin reintento por OpenAI: si ElevenLabs falla, la muestra lo dice); vista nueva `SettingsElevenLabsVoice` dentro de `SettingsVoiceSection` (el selector de voz vive en Voz, no en `SettingsAppPane`) | `Config`, `VoiceStack`, `ElevenLabsTTS`, `UserPreferences`, `ElevenLabsVoiceSettings`, `SettingsElevenLabsVoice`, `SettingsVoiceSection`, `SettingsView`, `VoicePreview`, `StoredConfigProvider`, `CompanionMain`, `Localizable.strings` |
| 15f-7a | **HECHO 2026-09-25.** ElevenLabs: `SecretKey.elevenLabs` + fila en Ajustes › Claves (es/en); `ElevenLabsTTSClient` (Flash v2.5, `POST /v1/text-to-speech/{voice}/stream?output_format=pcm_24000`, clave al pedir, `cacheVariant` por modelo+voz); `MouthRouter` elige ElevenLabs con clave + voz y si falla antes del primer byte reintenta la frase una vez por OpenAI (`tts: elevenlabs failed status=N, openai fallback`), y el audio de respaldo nunca se cachea como ElevenLabs; `VoiceStackResolver` → `mouth=elevenlabs/eleven_flash_v2_5`. Voz por defecto: Brian `Gubgw9l4dtIoQA9YZHgx` (elección de Karen). Desvío: HTTP streaming por frase con la tubería de 15f-5, no WebSocket (misma latencia útil, un adaptador más simple); el agente se colgó al final y el orquestador cableó `MouthRouter` en `CompanionMain` y corrigió el test `testFallbackAudioIsNeverCachedAsElevenLabs` (hablaba dos veces sobre el mismo `SpeechSynthesis`, cuyo `events` es de un solo consumidor) | `Config`, `VoiceStack`, `ElevenLabsTTS`, `MouthRouter`, `KeysSettings`, `SettingsAppPane`, `Localizable.strings`, `CompanionMain` |
| 15f-7b | **HECHO 2026-09-25.** Selector de voz ElevenLabs (id + muestra) entregado en 15f-6; banco de voces es-MX hecho en §8.3. No hace falta adaptador WebSocket: el HTTP streaming ya da 180–210 ms al primer byte (§8.3) | `SettingsElevenLabsVoice`, `VoicePreview` |

## 4. TDD (rojo primero)

| # | Test | Espera |
|---|---|---|
| 1 | contenido `{"goal":"x","context":"y"}` sin tool call | `Handoff(goal:"x")`; la boca no recibe nada |
| 2 | contenido "Voy a pegarlo.{"goal":…}" | se habla "Voy a pegarlo." y el JSON se convierte |
| 3 | JSON truncado | no escala; se descarta; log `mouth: dropped reason=json` |
| 4 | "Listo. We need to answer why. Ya está." con app en es | se habla "Listo. Ya está."; log `reason=language` |
| 5 | subagente termina con texto | `said=` en el log de depuración |
| 6 | tres frases | la petición de la 2ª sale antes de que termine de sonar la 1ª; nunca más de una en vuelo por delante |
| 7 | cuerpo de la petición TTS | `speed` 1.1 e `instructions` presentes; `input` = solo la frase |
| 8 | timeline | `ttsRequest→firstByte` y `firstByte→audible` con valores; `firstToken→audio` sigue |
| 9 | selector de voz | cambia `Config.voice`; el botón de muestra pide la frase de muestra con esa voz |

## 5. Seguridad

- Las claves del banco se leen dentro del binario del spike desde el Keychain; jamás en argv,
  env ni logs. Las muestras WAV del banco de voces contienen solo la frase de muestra fija.
- El filtro de idioma y el de JSON solo cuentan; nunca escriben el texto descartado en el log
  principal.

## 6. Done (en vivo, Karen)

1. 20 holds con depuración ON: ningún `said=` con `{` ni frases en inglés.
2. `release→audio` p50 ≤ 1200 ms; sin huecos entre frases.
3. Karen eligió la voz a ciegas y suena así en la app.

## 7. Aprobación

Aprobada 2026-09-25 ("vamos con eso"). Pendiente de Karen: si quiere la opción WebSocket,
una clave de ElevenLabs, Cartesia o Inworld.

## 8. Resultados del banco

Spike 15f-0, 2026-09-25. Paquete desechable fuera del repo
(`scratchpad/brain-bench`, Swift 5.10, depende del `CompanionCore` del repo por ruta local para
que prompt y tools sean los del hold byte a byte). Claves leídas del Keychain dentro del binario
(`Companion` / `secrets.v1`); nunca en argv, env, archivos ni salida.

### 8.1 Banco A — cerebros

Petición reproducida: system = `ChatPrompt.system(voice: true, delegateEnabled: true,
parentToolsEnabled: true, language: .es)` con el catálogo de skills y la memoria reales
(7652 caracteres); tools en el orden de `ClassicRuntime`: `open_app, open_url, open_file,
list_apps, read_skill, find_places, delegate, stop_job, resolve_approval`; usuario =
`languageInstruction(.es)` + frase. `stream: true`, `tool_choice: auto`; gpt-oss con
`reasoning_effort: low` sin temperature; gpt-4o-mini con temperature 0.7 y `strict: true`
(escalón OpenAI del ladder). 22 frases (`heard=` del 2026-09-25) × 2 corridas, en serie,
timeout 20 s. **Límite:** cada frase va sola — sin historial ni bloque `<context>` de pantalla.

Cerebras `/v1/models` (esta cuenta): **`gpt-oss-120b`, `qwen-3.8-27b`**. `qwen-3-235b-a22b-instruct-2507`
y `llama-3.3-70b` ya no están listados: no se pudieron medir; se midió `qwen-3.8-27b` como
sustituto.

| Modelo | ok/runs | TTFT p50 | TTFT p90 | total p50 | tool-call | JSON en content | fuga razonamiento | chars prom. |
|---|---|---|---|---|---|---|---|---|
| cerebras gpt-oss-120b | 44/44 | 299 ms | 363 ms | 314 ms | 61% | 0 | 0 | 71 |
| cerebras qwen-3.8-27b | 44/44 | 642 ms | 1309 ms | 706 ms | 73% | 0 | 0 | 36 |
| openai gpt-4o-mini | 44/44 | 553 ms | 1117 ms | 765 ms | 25% | 0 | 0 | 102 |

Tool por frase (corrida 1 / 2; `txt` = solo texto):

| # | frase (etiqueta) | gpt-oss-120b | qwen-3.8-27b | gpt-4o-mini |
|---|---|---|---|---|
| 1 | ¿estás ahí? | txt / txt | txt / txt | txt / txt |
| 2 | abre Safari | open_app / open_app | open_app / open_app | open_app / open_app |
| 3 | Google en Safari | open_url / open_url | open_app+open_url / list_apps | open_app+open_url / open_app+open_url |
| 4 | config. de cuenta en Safari | delegate / open_app | open_app / open_app | txt / txt |
| 5 | crea nota en escritorio | read_skill / read_skill | read_skill / read_skill | txt / delegate |
| 6 | ¿quién fue el especialista? ábrelo | delegate / txt | list_apps / list_apps | txt / txt |
| 7 | restaurantes cerca | find_places / find_places | read_skill / find_places | find_places / find_places |
| 8 | abre mi navegador | open_app / open_app | open_app / open_app | open_app / open_app |
| 9 | restaurantes en el navegador | open_url / read_skill | read_skill+find_places / open_url | find_places / txt |
| 10 | audita tus tiempos (logs) | delegate / delegate | read_skill / read_skill | txt / txt |
| 11 | comparte reporte en ventana de terminal | txt / txt | read_skill / txt | txt / txt |
| 12 | ¿ves la ventana? | txt / delegate | txt / read_skill | txt / txt |
| 13 | terminal en primer plano | txt / txt | open_app / read_skill | txt / txt |
| 14 | no está en primer plano | txt / open_app | txt / open_app | txt / txt |
| 15 | ¿cuántas terminales? | delegate / delegate | list_apps / list_apps | txt / txt |
| 16 | dime los nombres | txt / list_apps | txt / txt | txt / txt |
| 17 | nombres de ventanas de Terminal | delegate / delegate | read_skill / delegate | txt / txt |
| 18 | abre la primera | txt / txt | list_apps / list_apps | open_app / txt |
| 19 | pega el reporte en la terminal | delegate / delegate | delegate / read_skill | txt / txt |
| 20 | escríbelo en la terminal | delegate / txt | txt / txt | txt / txt |
| 21 | hazlo y ya | txt / txt | stop_job / txt | txt / txt |
| 22 | escribe un carácter | txt / txt | txt / txt | txt / txt |

Lectura:
- **Veredicto: gpt-oss-120b sigue siendo el más rápido sin fugas** (TTFT p50 299 ms, la mitad que
  cualquier alternativa) y el que más delega cuando toca (10, 15, 17, 19). gpt-4o-mini contesta con
  texto donde hacía falta actuar (25% de tool calls); qwen-3.8-27b tarda el doble y abusa de
  `read_skill`/`list_apps` (y un `stop_job` sin encargo en la 21). **15f-4: no se cambia el cerebro.**
- Ningún modelo escribió JSON ni razonamiento en inglés en turnos aislados. Los 4 `{"goal"…}` y la
  fuga en inglés del vivo no se reproducen sin historial ni contexto de pantalla, así que dependen
  del turno largo: **la red de seguridad (15f-1, 15f-2) sigue siendo obligatoria**, no opcional.
- gpt-oss y qwen-3.8-27b emiten razonamiento en el campo `delta.reasoning` (44/44 corridas cada
  uno), nunca en `content`: la app no debe leer ese campo hacia la boca.

### 8.2 Banco B — voces

OpenAI `/v1/models` con tts/audio/realtime: `gpt-4o-mini-tts`, `gpt-4o-mini-tts-2025-03-20`,
`gpt-4o-mini-tts-2025-12-15`, `gpt-audio`, `gpt-audio-1.5`, `gpt-audio-2025-08-28`,
`gpt-audio-mini`, `gpt-audio-mini-2025-10-06`, `gpt-audio-mini-2025-12-15`, `gpt-realtime`,
`gpt-realtime-1.5`, `gpt-realtime-2`, `gpt-realtime-2.1`, `gpt-realtime-2.1-mini`,
`gpt-realtime-2025-08-28`, `gpt-realtime-mini`, `gpt-realtime-mini-2025-12-15`,
`gpt-realtime-translate`, `gpt-realtime-whisper`, `tts-1`, `tts-1-1106`, `tts-1-hd`, `tts-1-hd-1106`.
Ningún modelo TTS distinto de la familia gpt-4o-mini-tts; se midieron sus dos snapshots fechados.

`POST /v1/audio/speech`, `response_format: pcm` (24 kHz), 3 frases cortas × 3 corridas en serie
(la muestra fija y dos respuestas cortas). "audio s" = duración de la muestra fija.

| Modelo | Voz | Variante | ok | TTFB p50 | total p50 | bytes p50 | audio s |
|---|---|---|---|---|---|---|---|
| gpt-4o-mini-tts | marin | default | 9/9 | 698 ms | 1443 ms | 184800 | 3.85 |
| gpt-4o-mini-tts | marin | speed 1.1 | 9/9 | 556 ms | 1215 ms | 168098 | 3.50 |
| gpt-4o-mini-tts | marin | instructions | 9/9 | 531 ms | 1164 ms | 192000 | 4.00 |
| gpt-4o-mini-tts | marin | speed+instructions | 9/9 | 576 ms | 1235 ms | 165688 | 3.45 |
| gpt-4o-mini-tts | cedar | default | 9/9 | 600 ms | 1197 ms | 182400 | 3.80 |
| gpt-4o-mini-tts | cedar | speed 1.1 | 9/9 | 576 ms | 1203 ms | 163760 | 3.27 |
| gpt-4o-mini-tts | cedar | instructions | 9/9 | 638 ms | 1290 ms | 168000 | 3.50 |
| gpt-4o-mini-tts | cedar | speed+instructions | 9/9 | 548 ms | 1183 ms | 152674 | 3.18 |
| gpt-4o-mini-tts | alloy | default | 9/9 | 582 ms | 1240 ms | 228000 | 4.75 |
| gpt-4o-mini-tts | alloy | speed 1.1 | 9/9 | 568 ms | 1238 ms | 218226 | 4.09 |
| gpt-4o-mini-tts | alloy | instructions | 9/9 | 499 ms | 1151 ms | 182400 | 3.80 |
| gpt-4o-mini-tts | alloy | speed+instructions | 9/9 | 523 ms | 1063 ms | 168098 | 3.36 |
| gpt-4o-mini-tts-2025-03-20 | marin | default | 9/9 | 310 ms | 832 ms | 136800 | 2.85 |
| gpt-4o-mini-tts-2025-03-20 | marin | speed+instructions | 9/9 | 358 ms | 815 ms | 139660 | 2.91 |
| gpt-4o-mini-tts-2025-03-20 | cedar | default | 9/9 | 336 ms | 874 ms | 139200 | 2.90 |
| gpt-4o-mini-tts-2025-03-20 | cedar | speed+instructions | 9/9 | 365 ms | 826 ms | 130984 | 2.73 |
| gpt-4o-mini-tts-2025-12-15 | marin | default | 9/9 | 549 ms | 1180 ms | 175200 | 3.55 |
| gpt-4o-mini-tts-2025-12-15 | marin | speed+instructions | 9/9 | 525 ms | 1167 ms | 170508 | 3.55 |
| gpt-4o-mini-tts-2025-12-15 | cedar | default | 9/9 | 541 ms | 1242 ms | 189600 | 3.95 |
| gpt-4o-mini-tts-2025-12-15 | cedar | speed+instructions | 9/9 | 527 ms | 1136 ms | 157012 | 3.27 |
| gpt-4o-mini-tts-2025-03-20 | alloy | speed+instructions (v21) | 3/3* | 1150 ms | 1624 ms | 150746 | 3.14 |
| gpt-4o-mini-tts-2025-03-20 | alloy | default (v22) | 3/3* | 536 ms | 1106 ms | 177600 | 3.70 |

\* Seguimiento tras la escucha de Karen (timbre de alloy, ritmo de v15): solo la frase fija × 3
corridas, no las 3 frases. Con alloy el snapshot 2025-03-20 no repite la ventaja de marin/cedar
(310-365 ms); la cifra de v21 sale de 3 corridas y hay que volver a medirla antes de fijarla.

Lectura:
- `speed 1.1` **sí** actúa en gpt-4o-mini-tts: la muestra se acorta 9-14% (marin 3.85→3.50 s,
  cedar 3.80→3.27 s). `instructions` no cuesta TTFB medible.
- Con el alias actual, TTFB p50 ronda 530-700 ms en cualquier voz/variante: la diferencia entre
  voces es ruido, no una ganancia de latencia.
- **El snapshot `gpt-4o-mini-tts-2025-03-20` da el primer byte en ~310-365 ms (casi la mitad) y
  suena más corto (2.7-2.9 s para la misma frase).** Es el único candidato con ganancia real de
  latencia en OpenAI; que suene natural lo decide Karen escuchando.
- Veredicto provisional para 15f-5/15f-6: `speed 1.1` + `instructions` sobre la voz que Karen elija;
  si al oído gana una muestra del snapshot 2025-03-20, fijar ese id de modelo en vez del alias.

Muestras a ciegas: **`~/Desktop/companion-voces/`** — 22 WAV (`v01.wav` … `v22.wav`; v21-v22 añadidas después, solo la frase
de muestra fija) con los nombres barajados; `clave.txt` dice qué modelo/voz/variante es cada uno.

### 8.3 Banco C — voces ElevenLabs

2026-09-25, clave de ElevenLabs de Karen (Voices read/write) leída del Keychain dentro del
binario. Pool: `GET /v1/shared-voices?language=es&page_size=100&sort=usage_character_count_1y`
(más filtros `accent=mexican`, `accent=latin american`, `locale=es-MX`; 244 voces únicas) y
`GET /v1/voices` (22 en la cuenta, todas premade salvo una copia professional de Brian).
Elegidas: conversacionales, con `eleven_flash_v2_5` verificado en español, 3 mujeres y 2 hombres,
de las más usadas del último año. ElevenLabs etiqueta "latin american" con locale `es-AR` (es
su etiqueta genérica de español latino, no acento argentino).

Petición: `POST /v1/text-to-speech/{voice_id}/stream?output_format=pcm_24000`,
`model_id: eleven_flash_v2_5`, `language_code: es`; la frase fija y una respuesta larga
(~160 caracteres), 3 corridas cada una, en serie. TTFB = primer byte de audio.

| Voz | Acento (locale, género) | TTFB p50 fija / larga | total p50 fija / larga | añadida a la biblioteca | ok |
|---|---|---|---|---|---|
| Regina (Contact Center) | mexican (es-MX, F) | 194 / 187 ms | 351 / 584 ms | no | 6/6 |
| Ana María (Calm, Natural) | mexican (es-MX, F) | 183 / 185 ms | 325 / 520 ms | no | 6/6 |
| Jorge (Neutral Latin American) | mexican (es-MX, M) | 191 / 190 ms | 340 / 561 ms | no | 6/6 |
| Antonio (Confident, Gentle) | latin american (es-AR, M) | 209 / 195 ms | 328 / 536 ms | no | 6/6 |
| Cristina Campos (Friendly) | latin american (es-AR, F) | 189 / 182 ms | 325 / 531 ms | no | 6/6 |
| Brian (control, premade actual) | american | 196 / 189 ms | 329 / 582 ms | ya en la cuenta | 6/6 |

Lectura:
- **Las voces de la biblioteca compartida funcionan por `voice_id` sin añadirlas** a la cuenta:
  el spike probó cada una antes de `POST /v1/voices/add/...` y las cinco respondieron 200, así que
  no se añadió ninguna (la cuenta queda igual).
- **ElevenLabs Flash por HTTP da primer byte en ~180-210 ms**, contra ~530-700 ms de
  gpt-4o-mini-tts y ~310-365 ms de su snapshot 2025-03-20 (§8.2): es la boca más rápida medida,
  y la voz no cambia la latencia. Con eso 15f-7 (WebSocket) deja de ser prioridad para la
  latencia; la elección es de acento y timbre.
- El acento raro de Brian es esperable: es una voz americana hablando español. Las tres mexicanas
  (es-MX) son las candidatas naturales; que suenen bien lo decide Karen escuchando.

Muestras a ciegas: **`~/Desktop/companion-voces-eleven/`** — 12 WAV (`e01.wav` … `e12.wav`,
frase fija y respuesta larga por voz, nombres barajados); `clave.txt` da nombre, `voice_id`,
acento y modelo.

## 9. Revisión de seguridad (2026-09-25)

La revisión de 15f devolvió BLOCK. Cada hallazgo se reprodujo con un test en rojo antes del fix.

| Hallazgo | Qué pasaba | Fix | Test |
|---|---|---|---|
| CRITICAL-1 | `URLSessionConfiguration.default` guardaba en `~/Library/Caches/com.karen.companion/Cache.db` peticiones con `xi-api-key` / `Authorization` y cuerpos con `<context>` (pantalla, portapapeles, respuestas). También `URLSession.shared` en el transcriptor websocket y `web_fetch`, y `.default` en el websocket realtime. | `NoStoreSession` (ChatTransport.swift): `.ephemeral` con `urlCache = nil`, `requestCachePolicy = .reloadIgnoringLocalCacheData`, sin credential ni cookie storage; toda sesión de Sources sale de ahí. Al arrancar, `LegacyURLCachePurge.runAtLaunch` vacía `URLCache.shared`, lo cambia por uno de capacidad 0 y borra `Cache.db`, `-wal`, `-shm` y `fsCachedData` solo dentro de `Caches/<bundle id>` (rechaza ids con `/`, `.`, `..`; no sigue symlinks); log `cache: legacy url cache purged`. Gate 2 falla con cualquier `URLSession.shared`, `URLSessionConfiguration.default/.ephemeral`, `URLCache(` o sesión nueva fuera de `NoStoreSession`. | `URLCacheHygieneTests` (config sin cache; stub `URLProtocol` que permite cachear y `URLCache.shared` sigue vacío — en rojo la respuesta quedaba guardada; purga contra dir temporal: solo esos 4, idempotente, ids que escapan, symlink). |
| HIGH-1 | Un `{"goal":…}` en el TEXTO de la respuesta se convertía en encargo de Claude Code con la confianza de una llamada real a `delegate`; inyectable vía portapapeles/pantalla/resultado de herramienta leído en voz alta. | `HandoffProposal` (Core): (a) si el goal normalizado (recorte, mayúsculas, acentos, espacios) aparece en el contexto del turno (portapapeles, resumen y snippets de pantalla, documentos, app, bloque renderizado) o en un resultado de herramienta, se descarta: `mouth: dropped reason=json-echo chars=N`; (b) si no, es una PROPUESTA: la boca dice `¿Lo delego?` / `Delegate that?` y la petición entra por el mismo asiento que la hoja y el "sí" hablado (`ParentToolGuard.approvals` + `onRequest` → `noteApproval` → `resolve_approval`); solo con sí corre `onDelegate`. Sin asiento de aprobación: falla cerrado (`json-unapproved`). `toolName` = `delegate`, sin `ApprovalKey`: "recordar" nunca lo vuelve permiso fijo. La hoja muestra el goal (`ChatCopy.approvalDetail` lee `goal`). Una llamada real a `delegate` sigue directa. | `HandoffProposalTests` (eco de portapapeles, pantalla y tool result → descartado; goal propio → propuesta sin `onDelegate`; sí → un encargo; no y plazo vencido → nada, `mouth: proposal declined`; sin asiento → nada; `.handoff` real directo). En rojo los tres ecos delegaban. `MouthJSONTests` filas 1-2 adaptadas: delegan tras aprobar. |
| MEDIUM-1 | `TranscriptDebugLog.keyPrefixes` no tenía `sk_` (ElevenLabs): una clave dicha o repetida salía en claro al log de transcripciones. | `sk_` añadido. | `testElevenLabsKeysAreRedactedAnywhereInALine` (en rojo, 3 fallos). |
| LOW-1 | El `voice_id` se escapaba con `%` y se mandaba: un valor raro llegaba a la red. | `^[A-Za-z0-9]{1,64}$` tras recortar; si no, `ElevenLabsTTSClient.InvalidVoiceID` antes de leer el llavero y sin petición. | `testAMalformedVoiceIDIsRefusedWithoutARequest` (reemplaza `testTheVoiceIDCannotEscapeItsPathSegment`, que fijaba el comportamiento viejo): `%`, no ASCII, acento combinante, vacío, blancos, 65 chars; fetch y stream. |
| LOW-3 | `MouthRouter` leía el llavero en cada `cacheVariant` (≈3 lecturas por frase) y, si la clave cambiaba a mitad, guardaba audio de ElevenLabs bajo la variante de OpenAI. | `TTSFetching.resolved()`: el router decide la boca una vez por frase; `SpeechSynthesis` usa esa boca para buscar en caché, pedir y guardar (y la lleva `SpeechPrefetch` para la frase adelantada). | `MouthRouterDecisionTests`: una lectura por frase (en rojo 3 y 6), la variante guardada es la de la boca que produjo el audio, la decisión no cambia con el llavero. |

Cierre: `swift test` ×3 verde (347 tests, 1 known issue de `DecisionDatasetTests`), `scripts/gates.sh` 0 fallos.

## 10. Revisión de código (2026-09-25)

Cada hallazgo se reprodujo con un test en rojo antes del fix (salvo donde se indica).

| Hallazgo | Qué pasaba | Fix | Test |
|---|---|---|---|
| HIGH-A | El filtro de idioma descartaba cualquier frase en inglés con confianza: un error citado ("Dice: Cannot find module react…"), una línea de build ("Build succeeded with zero warnings.") o una traducción se cortaban enteras. | `MouthLanguageGate` solo descarta fugas de razonamiento: nunca tras una entrada que cita (la frase trae `:` o comillas « » " “ ” ' — un `'` entre letras es apóstrofo, no comilla —, o lo dicho justo antes termina en `:`, trae comillas o nombra lo que se lee: dice/decía/error/título/en inglés; says/reads/title); y además exige apertura de razonamiento (We need, We should, Let me, I need, The user, Wait,, Actually,, Hmm) o, con toda la respuesta hasta ahí en el idioma de la app, ≥ 6 palabras. | `MouthQuoteTests` con `NaturalLanguageRecognizer` (en rojo: error citado, línea de build, entrada en el corte anterior, "error" en la frase previa, comillas). La traducción ya pasaba en rojo; queda como regresión. La fuga "We need…" y "The user asked for the time." siguen saliendo. |
| HIGH-B | En clásico `jobAnnounce` mandaba a la boca la instrucción PARA EL MODELO (`jobDoneAnnouncement`/`jobFailedAnnouncement`), sin guarda JSON ni filtro de idioma. | `JobAnnouncement` (Core, `Escalation.swift`): realtime sigue mandando `instruction`; clásico dice `spokenLine` fija ("Listo, ya está en pantalla." / "Done, it is on screen."; "No pude terminarlo." / "I could not finish it."; en cola: "Queda en cola; lo hago en cuanto termine este.") y luego un turno de resumen (`ClassicRuntime.announce`, archivo nuevo `ClassicRuntimeAnnounce.swift`): prompt de sistema + un solo turno de usuario con el resultado en `<tool_result name="delegate">` (≤ 4000 chars) y la petición de ≤ 2 frases, sin tools, por `TurnMouth` (JSON contado y descartado, nunca propuesta; filtro de idioma). `said=` se escribe al terminar el audio (`.finished`/`.failed`) o al cortarlo una pulsación, con `spokenSoFar()`. | `SubAgentSaidTests` reescrito (en rojo: la boca decía la instrucción). `testHoldJobDoneIsSpoken` fijaba el comportamiento viejo (nombrar el encargo) y ahora exige la línea propia; `VoiceDecisionTests` "el modelo fuerte nunca ve el turno" se precisa: el resumen ve el resultado, nunca lo que dijo el usuario. `ScriptedChat.toolsPerCall` porque el resumen es una segunda llamada. |
| MEDIUM-A | `FallbackLedger` por texto: con dos frases iguales y un prefetch de respaldo, el PCM de OpenAI quedaba bajo la variante de ElevenLabs; una marca de un prefetch cortado por `stop()` nunca se consumía. | `MouthRouter.resolved()` devuelve un `ElevenLabsFirst` nuevo por frase que recuerda si cayó a OpenAI; `mayCache` lo pregunta a esa boca, que viaja con el stream y con `SpeechPrefetch`. `FallbackLedger` borrado. El router usado directamente responde `mayCache=false`. | `MouthProvenanceTests`: gemelas (en rojo: la caché de ElevenLabs guardaba `openai:Listo.`), stop durante el prefetch (en rojo: la frase buena no se cacheaba). |
| MEDIUM-B | Sin cortacircuitos: con ElevenLabs caído cada frase pagaba una petición fallida antes de OpenAI. | `ElevenLabsBreaker`: un fallo antes del primer byte pausa ElevenLabs 60 s (reloj y enfriamiento inyectables), una línea `tts: elevenlabs paused 60s status=N`; un 401 pausa hasta que cambia la clave (se compara un digest en memoria, no la clave) o se reinicia la app: `tts: elevenlabs paused until key changes status=401`. Desvío: la pausa es por tiempo, no "resto del turno + 60 s"; un turno dura menos que el enfriamiento. | `MouthProvenanceTests` (en rojo los dos): tras un 429 la 2ª frase va directa a OpenAI, a los 59 s sigue, a los 61 s vuelve ElevenLabs; 401 sigue en pausa una hora después y se reabre con clave nueva. `testFallbackAudioIsNeverCachedAsElevenLabs` recupera guardando otra clave. |
| LOW-1 | `{{"goal":"x"}}`: la primera llave convertía todo en prosa y el objeto se leía. | `HandoffInText`: una `{` tras una `{` sin comprometer pasa a ser el inicio del candidato; la exterior es prosa. | `testADoubledBraceNeverSpeaksTheObject` (en rojo); `testNonCandidateBracesAreProse` ajustado (la segunda `{` final espera y `finish()` la devuelve como prosa). |
| LOW-2 | `showStream(mouth.spoken)` y `act(said:)` llevaban frases que el filtro había descartado. | `showStream(mouth.said)` después del filtro; `act(said: mouth.saidPart(of: text))` en los tres sitios. | `testTheBubbleAndTheToolRoundOnlyCarryWhatWasSpoken` (en rojo: la segunda ronda y la burbuja llevaban "We need…"). |
| LOW-3 | Un error del llavero en el router caía a OpenAI en silencio. | `tts: keychain read failed` una vez por racha de fallos, sin clave ni detalle; cae a OpenAI. | `testAKeychainErrorIsLoggedOnceAndFallsToOpenAI` (en rojo). |
| LOW-4 | `said=` del job se escribía antes de sonar. | Cubierto por HIGH-B (se escribe al terminar o al cortar, semántica de `cutTurn`). | `testAPressOverTheAnnouncementLogsWhatAlreadySounded` (escrito tras el fix, sin rojo propio; el rojo de HIGH-B ya lo cubría). |
| LOW-5 | §2 no decía qué pasa con un JSON genuino con `goal`. | Nota en §2. | — |

Cierre: `swift test` ×3 verde (354 tests, 1 known issue de `DecisionDatasetTests`), `scripts/gates.sh` 0 fallos.
