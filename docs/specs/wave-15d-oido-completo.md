# Wave 15d — Oído completo (lo que Incredible hace distinto)

**Estado: CERRADO (2026-09-24).** Done en vivo: transcripts completos ✓, hold sin voz a reposo ✓, `release→audio` p50 1,65 s ✗ (criterio 1,2 s; el tramo que falta es la boca, pasa a 15f). Original: Karen: "dale a la spec, tú orquestas". Modo depuración por variable de entorno en esta wave (sin UI); el interruptor de Ajustes llega con 15f. Sin commit.

15d-0..9 implementadas; revisión (code + security) con 12 hallazgos corregidos por TDD el
2026-09-24: 316 tests verdes, gates 0 fallos; instalada en `/Applications` con
`COMPANION_DEBUG_TRANSCRIPTS=1` a la espera de la prueba de §6. Regla que salió de la revisión
(§8): al bajar FN solo arranca lo local y reversible (mic, buffer, oído de Apple); la captura de
pantalla, el fan-out de contexto y cortar una respuesta en curso esperan al umbral de 250 ms
(`confirmed`) o al soltar; un tap antes del umbral se descarta en silencio.

Karen: "sigue siendo lento de a madre, no escucha bien todavía... mira a fondo el
funcionamiento de incredible... estamos haciendo algo mal".

Criterio de done: 10 holds "abre X" / "qué hora es" transcritos completos
(primera y última palabra incluidas), `release→audio` p50 ≤ 1200 ms, p90 ≤ 1800 ms;
un hold sin voz vuelve a reposo con el micrófono apagado; gates verdes.

---

## 1. Incredible, estudiado a fondo (4 agentes, 2026-09-24)

Fuentes: `~/Documents/Incredible-Debug/2026-09-04/{voice-traces,logs,perf-samples}`,
`~/.incredible/overlay.json`, `~/Library/Logs/Incredible/app.log`, bundle.

| Pieza | Incredible (medido) | Companion hoy (log 2026-09-24 15:44) |
|---|---|---|
| Micrófono al presionar | **+3 ms** (`StartMicCapture`, timings `stt_connect_started_at_ms`) | **+250 ms** de umbral tap/hold (`HoldKeyClassifier.tapThreshold`) + ~200 ms de arranque (`press→mic 196`) + ~100 ms al primer buffer: **~0.5 s de la frase perdidos** |
| Al soltar | **cola de 300 ms** antes de cortar (`committing after 300ms tail`) | corte inmediato (`release→commit 0`): la última sílaba se pierde |
| Oído | AssemblyAI streaming; si el final no llega en **1500 ms**, batch a **Groq** (falló el plazo 3/3 veces; final a +2.8 s) | Groq Whisper directo: final a +0.2–0.5 s (mejor) |
| Filtro de silencio | `voiced %`, `floor chars`, `peak rms` en el log; vacío → tarjeta "no te oí" 6 s y **a reposo** | energía + Apple (15c-7); vacío → `heardNothing` y el mic **se queda escuchando** |
| Cerebro | GLM-5.2 vía proxy Vercel, TTFT ~0.9 s | gpt-oss-120b Groq (límite 8k/min) / Cerebras si hay clave |
| Boca | Inworld WebSocket, `speaking_rate 1.1`; empuja la respuesta 1–3 ms tras el primer token; primer audio a +0.85 s | OpenAI PCM streaming por frase; primer audio a +0.7–3.5 s del primer token |
| Total release→audio | **5073 ms** (la única traza completa) | 1651–6814 ms |
| Contexto | `<time_since_last_interaction>`, `<current_time>`, "(Reply only in Spanish…)", nota de interrupción, texto AX de pantalla, visión Gemini en paralelo (6–9 s, no espera) | equivalente desde 15b |
| Idioma | "(Reply only in Spanish, regardless of the language on screen…)" delante del transcript | idioma en el system prompt |
| Transcripts | los guarda en claro (`metadata.json: user_transcript`) | nunca (por diseño) |

**Conclusión:** en números Incredible no es más rápida; su ventaja es que
**oye la frase entera**: abre el micrófono en el instante del press y deja
300 ms de cola al soltar. Nosotros recortamos ~0.5 s al inicio y la cola al
final, y por eso Whisper recibe "…bre Safa" y el cerebro contesta cosas raras.
Eso es lo que estamos haciendo mal. Lo segundo es la boca: nuestra primera
frase tarda hasta 3.5 s en sonar cuando el streaming debería dar < 1 s.

---

## 2. Decisión

| Decisión | Por qué |
|---|---|
| **Mic al key-down**, no al confirmar el hold: el tap (< 250 ms) descarta el audio sin enviar | Incredible +3 ms; hoy perdemos ~0.5 s |
| **Cola de 300 ms** tras soltar antes de cerrar el mic y mandar a Groq | Incredible; la última sílaba |
| Enviar a Groq el WAV a **24 kHz tal cual** (Whisper remuestrea en servidor) | quita el remuestreo lineal sin filtro (aliasing) y ~10 ms |
| **Hold sin voz → reposo con mic apagado** (tarjeta/estado "no te oí"), no `listening` | Incredible; hoy queda un mic caliente sin dueño (hallazgo previo) |
| **Boca: primer corte a la primera coma o a 40 caracteres, o a 400 ms sin corte** | Incredible empuja en 1–3 ms; nuestro `SentenceSplitter` espera ". " + 25 chars |
| **Modo depuración de transcripts, opt-in** (`COMPANION_DEBUG_TRANSCRIPTS=1`; el toggle de Ajustes llega en 15f): escribe `heard` y la respuesta en `~/Library/Logs/Companion-transcripts.log`, 0600, con aviso en la UI mientras está activo | sin esto no podemos saber qué entendió; Incredible los guarda siempre, nosotros solo cuando Karen lo enciende |
| Instrucción de idioma **delante del transcript**: "(Responde solo en español, sin importar el idioma de la pantalla)" | Incredible; el system prompt solo no basta con texto de pantalla en inglés |
| Medir en el timeline: `press→mic`, `release→earFinal`, `firstToken→audio` | hoy `commit→audio` mezcla oído, cerebro y boca |
| **Sesgo del oído**: `prompt` de Whisper con el nombre de Karen y los nombres de las apps abiertas/instaladas más usadas (≤ 200 chars), `temperature=0` | Incredible manda *keyterms* de contactos y vocabulario (`stt_bias.rs`, `keyterms=`) y usa `temperature=0` en Groq; "Safari", "Notas", "Slack" dejan de salir mal escritos |
| **Prompt de voz al estilo Incredible**: "eres un router con voz": 2 frases casi siempre, contracciones, empieza por la noticia, listas de máximo 3, nunca markdown ni emojis en voz, nunca afirmar que algo existe si el contexto no lo muestra | del prompt del orquestador de Incredible (binario); nuestras respuestas largas son lo que hace lenta la boca |

Fuera: AssemblyAI/Inworld, cambiar de cerebro (15c-7 ya puso Cerebras; falta
que Karen pegue la clave), visión, tarjetas de resultado.

---

## 3. Entregas

| # | Qué | Archivos |
|---|---|---|
| 15d-0 | Timeline con `release→earFinal` y `firstToken→audio` | `TurnTimeline`, `VoiceSessionPumps` |
| 15d-1 | Mic al key-down + descarte en tap | `HoldKeyTap`, `HoldKey`, `VoiceSession.hold` (795→ mover a extensión) |
| 15d-2 | Cola de 300 ms al soltar | `VoiceSessionPumps.completeHold`, `TurnMachine` |
| 15d-3 | WAV 24 kHz directo a Groq | `GroqTranscriber`, `AudioWAV` |
| 15d-4 | `heardNothing` → idle + mic off | `TurnMachine`, `VoiceSession`, test 12b actualizado |
| 15d-5 | Primer corte de la boca (coma / 40 chars / 400 ms) | `SentenceSplitter`, `ClassicRuntime` |
| 15d-6 | Modo depuración de transcripts opt-in por env | `Log`, `Config` |
| 15d-7 | Instrucción de idioma delante del transcript | `ContextBlock` / `ClassicRuntime` |
| 15d-8 | `prompt` + `temperature=0` en Groq Whisper con nombre y apps | `GroqTranscriber`, `ClassicRuntime` (apps del `DecisionWorld`) |
| 15d-9 | Reglas de voz del system prompt del hold (2 frases, noticia primero, sin markdown) | `ChatPrompt` |

## 4. TDD (rojo primero)

| # | Test | Espera |
|---|---|---|
| 1 | FN down 100 ms y up | mic arrancó al down; nada se envía; mic parado |
| 2 | FN down 400 ms, hablar, up | los frames desde +0 ms están en `HoldAudioBuffer` |
| 3 | release | Groq recibe frames hasta +300 ms; commit a +300 ms |
| 4 | WAV | cabecera 24 000 Hz; sin llamada a `resample` |
| 5 | hold sin voz | `.heardNothing`, estado `.idle`, `mic.stop` llamado |
| 6 | stream "Abrí Safari, y también…" | primera frase a la coma |
| 7 | stream de 60 chars sin puntuación | corte a los 40 |
| 8 | stream que se detiene 400 ms con 12 chars | se enuncia lo que hay |
| 9 | debug off | el log de transcripts no existe |
| 10 | debug on | archivo 0600 con `heard=` y `said=`; el log principal sigue sin texto |
| 11 | prompt | el turno de usuario empieza con la instrucción de idioma |
| 12 | request Groq | campo `prompt` ≤ 200 chars con nombre + apps, `temperature=0`; nunca el transcript anterior |
| 13 | system prompt del hold | contiene las reglas de voz; el del chat escrito no cambia |

## 5. Seguridad

- El modo depuración es opt-in, visible en la UI, archivo 0600 en `~/Library/Logs`,
  y nunca escribe claves. Se apaga solo al cerrar la app.
- El mic al key-down no envía nada en un tap; el audio se descarta en memoria.

## 6. Done (en vivo, Karen)

1. Modo depuración ON; 10 holds; el archivo muestra la frase completa en cada uno.
2. FN sin hablar: vuelve a reposo, sin "escuchando" pegado.
3. `release→audio` p50 ≤ 1200 ms con Cerebras.
4. Modo depuración OFF; el archivo se borra.

## 7. Aprobación

Sin preguntas abiertas. Si apruebas, la orquesto hasta dejarla instalada con
`COMPANION_DEBUG_TRANSCRIPTS=1` para la prueba de §6.

## 8. Hallazgos de la revisión (2026-09-24) y cómo quedaron

| # | Hallazgo | Corrección (test rojo primero) |
|---|---|---|
| 1 | Con el mic al key-down, un tap subía la captura de pantalla a la visión | `screen.begin` y el fan-out de contexto esperan a `confirmHold()` (umbral) o a `release()`; `HoldConfirmTests` |
| 2 | Un tap o un acorde durante una respuesta la cortaba | Press provisional durante respuesta/cola/realtime se difiere entero; solo `confirmed` corta y dirige (15b-10 intacto) |
| 3 | El desmontaje tardío del tap A mataba el hold B | Generación de escucha en `ClassicRuntime` (`listenGeneration`, `earStopping`) |
| 4 | Un hold fallido "recuperaba" a `listening` con mic caliente | `TurnMachine.failOrRecover`: hold → idle + `stopClassicIO`; manos libres reintenta una vez y luego `.error`; `HoldFailureTests` |
| 5 | Un turno cancelado sin voz emitía `heardNothing` y tiraba el siguiente hold | `Task.isCancelled` antes de `heardNothing`/`hangUp` |
| 6 | Tap dentro de la cola de 300 ms rompía el commit pendiente | Se difiere y la cola commitea; `discard` en la cola cancela el commit (`holdGeneration`) |
| 7 | `takeStalled` cortaba a mitad de palabra | Corte en el último espacio; `MouthFirstCutTests` |
| 8 | Log de transcripts: 0644, seguía symlinks, redacción solo por token entero | `open(O_NOFOLLOW)` + `fchmod 0600` en cada append; prefijos de clave en cualquier posición; `TranscriptDebugTests` |
| 9 | `RealtimeRuntime` y `VoiceAudit` logueaban el texto oído | Solo cuentas de caracteres; `UtteranceLogPrivacyTests` |
| 10 | Esc durante la cola no cancelaba | `SessionMachine.stop` en cola → `stopListening(commit:false)` |
| 11 | Instrucción de idioma lejos del transcript | Justo antes del transcript, después de `<context>`; `VoiceLanguageAndPromptTests` |
| 12 | Un press que reanuda en la cola borraba lo oído (`audit.consume`) | No se consume al reanudar |
| — | §5 prometía aviso visible del modo depuración | `ChatViewModel.debugTranscripts` → `StatusLine` + hover de la island (`Line.transcriptsDebug`, prioridad `keyBlocked` > aviso > pista de hold); `debug.transcriptsOn` es/en |

Desviaciones: el aviso en `StatusLine` no tiene test propio; un `confirmed` que llega después de
que la cola ya commiteó se trata como hold normal y corta la respuesta. Flakes vistos y no
tocados: `nativeExecutorRoundTests` (1/6). `UtteranceLogPrivacyTests` reordenó `Log.configure`
tras el `await` porque el sink es global al proceso (sin cambiar aserciones).
