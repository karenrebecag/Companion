# Wave 15e — Oído local (adiós Groq)

**Estado: CERRADO (2026-09-24).** Done en vivo (22 holds): `ear=apple-analyzer` en todos ✓, `release→earFinal` p50 360 ms ✓ (≤ 400), frases completas ✓, Ajustes solo OpenAI + Cerebras ✓; `release→audio` p50 1,65 s ✗ por la boca (15f). Original: Karen: "sube, no pasa nada" → plataforma mínima macOS 26, un solo oído, `SystemTranscriber` se borra. Sin commit.

Revisión code (WARNING: 1 alto, 5 medios, 3 bajos) + security (APPROVE, 3 bajos): los 12 hallazgos
corregidos por TDD (ver "Revisión" al final); 321 tests verdes ×5, gates 0 fallos; instalada en
`/Applications` el 2026-09-24 con `COMPANION_DEBUG_TRANSCRIPTS=1`, a la espera de §6.

Karen: "necesitamos deshacernos de ese maldito modelo de groq que vuelve todo lentísimo...
¿no podemos reemplazar groq por whisper nativo?"

Criterio de done: el hold no toca Groq en ningún tramo (oído ni cerebro); `release→earFinal`
p50 ≤ 400 ms (hoy 1067 ms con cola de 300 ms incluida); 10 holds reales transcritos
completos en el log de depuración; la clave de Groq desaparece de Ajustes y del onboarding;
gates verdes.

---

## 1. Spike (2026-09-24, M4 Max, macOS 26.5, 10 clips es-MX sintéticos)

Código en el scratchpad de la sesión (`ear-spike/`), no en el repo.

| | Apple SpeechAnalyzer | WhisperKit large-v3 turbo | Groq (log de hoy) |
|---|---|---|---|
| Latencia | **p50 54 ms · p90 59 ms** | p50 430 · p90 456 ms | 500–750 ms + red |
| Texto | 10/10 | 8/10: descarta clips < 1 s | bien; alucina en silencio |
| Sesgo | `contextualStrings` ok | `promptTokens` vacía la salida | `prompt` ok |
| Arranque | inmediato | 6.5 s por lanzamiento, 530 s la primera vez | — |
| Coste | modelo del sistema (52 s de descarga una vez) | 1.5 GB disco + RAM, dependencia SPM | clave + límite |

Decisión: **Apple SpeechAnalyzer**, plataforma mínima **macOS 26** (aprobado), `SystemTranscriber`
(SFSpeechRecognizer) se borra. WhisperKit descartado.
Cerebras no tiene transcripción, así que el "plan de pago de Cerebras" solo aplica al cerebro,
donde ya está desde 15c-7.

---

## 2. Decisión

| Decisión | Por qué |
|---|---|
| **Oído = `SpeechAnalyzer` + `SpeechTranscriber` (streaming)**: recibe los frames del mic desde el key-down, resultado volátil en vivo y final tras la cola de 300 ms con `finalizeAndFinishThroughEndOfInput` | 54 ms por clip; oye desde el primer frame; sin red |
| `contextualStrings[.general]` = nombre de Karen + apps abiertas + instaladas (misma lista que hoy va al `prompt` de Groq) | el spike lo confirma; sustituye el sesgo de Whisper |
| **`GroqTranscriber` se elimina** del flujo del hold; la clase se borra junto con `SecretKey.groq` en la UI de claves y el onboarding | Karen: fuera Groq |
| **Cerebro: catálogo rápido = `[cerebras]`**; si falla, la escalera cae a OpenAI gpt-4o-mini, nunca a Groq | Karen: fuera Groq; `maxAttempts 1` se mantiene |
| Silencio: el filtro de energía (15c-7) se queda; la comprobación "Apple vacío" pasa a ser la única | ya no hay Whisper que alucine "Gracias." |
| `Package.swift` → `.macOS(.v26)`; `SystemTranscriber` y `TranscriptFinalizer` se borran si nadie más los usa | un solo oído, menos código; nadie más usa la app |
| Primer arranque: `AssetInventory.assetInstallationRequest` para el idioma de la app se lanza al abrir la app (52 s, una vez) y al cambiar de idioma; un hold antes de que termine devuelve `""` con `ear=apple reason=assets` y el estado "no te oí" | que el primer hold no espere 52 s ni cuelgue |

Fuera: cambiar la boca (2.3 s `firstToken→audio`, va en 15e-b con su propia medición), visión,
tarjetas.

---

## 3. Entregas

| # | Qué | Archivos |
|---|---|---|
| 15e-0 | `AnalyzerTranscriber` (Services) implementa `Transcriber`: `SpeechAnalyzer` con `AsyncStream<AnalyzerInput>`, parciales volátiles, `stop()` → final; `contextualStrings` por closure de vocabulario; instala assets en background; `Package.swift` a macOS 26; `SystemTranscriber` borrado | `AnalyzerTranscriber.swift` (nuevo), `SystemTranscriber.swift` (borrar), `Package.swift`, `CompanionMain` |
| 15e-1 | `ClassicRuntime.finalTranscript` deja de llamar a Groq: energía → Apple final; `groqEar` y `GroqTranscribing` se borran | `ClassicRuntime`, `VoicePorts`, `VoiceSession` |
| 15e-2 | Borrar `GroqTranscriber`, `SecretKey.groq` de `KeysSettings`/`SettingsAppPane`, strings `settings.keys.groq.*`; `VoiceStackResolver` sin Groq | `GroqTranscriber.swift` (borrar), `KeysSettings`, `SettingsAppPane`, `VoiceStack`, `Localizable.strings` |
| 15e-3 | Cerebro: `fastBrain = makeChat([.cerebras], …)`; `ProviderDescriptor.groq` sale del catálogo del hold | `CompanionMain`, `VoiceStack` |
| 15e-4 | Timeline: `release→earFinal` ya existe; añadir `ear=apple-analyzer` / `ear=apple-legacy` al log | `ClassicRuntime` |

Tocamos ~8 archivos en dos sesiones (15e-0/1 primero, 15e-2/3/4 después) para respetar el tope
de 3–5 por cambio.

### Estado de las entregas

| # | Estado | Sesión |
|---|---|---|
| 15e-0 | hecho | 1 |
| 15e-1 | hecho | 1 |
| 15e-2 | hecho | 2 |
| 15e-3 | hecho | 2 |
| 15e-4 | hecho | 2 |

### Desviaciones

Sesión 1:
- El audio que llega antes de que el oído arranque va a `ClassicRuntime.earlyAudio`, con tope de
  10 s, y se entrega al oído antes del primer frame en vivo.
- Fila 4 leída como "final vacío = no se oyó nada; la energía solo elige la línea del log"
  (`ear=apple-analyzer reason=empty` con energía, `ear=none reason=silence` sin ella).
- `stop()` espera el final como mucho 0.5 s.
- Instalación de assets al cambiar de idioma: la dispara el primer `start()` en el idioma nuevo
  (ese hold termina en "no te oí"), no un observador del ajuste.

Sesión 2:
- `ear=apple-legacy` no existe: `SystemTranscriber` se borró en 15e-0, así que solo queda
  `ear=apple-analyzer` (en `ClassicRuntime`). Las líneas de assets/latencia de
  `AnalyzerTranscriber` siguen como `ear=apple …` (fila 5 las nombra así).
- `SecretKey.groq` se queda solo para limpieza: `KeychainSecretStore.retiredKeys` borra la clave
  de Groq del bundle en la primera carga de cada arranque y borra el item legacy por clave sin
  migrarlo. Sin esto la clave pegada antes de 15e quedaba en el Keychain sin fila para borrarla.
  Karen igual debe revocarla en la consola de Groq (§5).
- `ProviderDescriptor.groq` se borró del código: el chat escrito queda OpenAI → OpenRouter → Ollama.
  Un `providerOrder` guardado que nombre `groq` se ignora (ya lo hacía `route` con ids desconocidos).
- La escalera del hold (`HoldBrainCatalog.ladder`, Core) cambia el modelo de OpenAI a
  `gpt-4o-mini`; antes caía a `gpt-4o` del chat aunque el log dijera `gpt-4o-mini`.
- `HoldAudioBuffer` no se partió: el del hold se construye con `maxSeconds: 0` (solo energía) y
  `earlyAudio` sigue guardando PCM (10 s).
- El texto de privacidad de Ajustes conserva la mitad de Cerebras como
  `settings.keys.cerebras.privacy`; la mitad de Groq se fue con `settings.keys.groq.*`.
- `AudioWAV` (Core) se queda sin llamadores al borrar `GroqTranscriber`; no se borró, queda para
  decisión explícita.
- El observador del ajuste de idioma que llame a `AnalyzerTranscriber.prepare` no se hizo (opcional):
  obliga a pasar un callback de `SettingsAppPane` a la raíz de composición.

## 4. TDD (rojo primero)

| # | Test | Espera |
|---|---|---|
| 1 | frames al key-down → `stop()` | el final contiene lo dicho desde el primer frame (fake del analyzer) |
| 2 | `contextualStrings` | recibe nombre + apps, ≤ 50 entradas, nunca el transcript anterior |
| 3 | `finalTranscript` con voz | no crea `GroqTranscriber`; usa el final del analyzer |
| 4 | `finalTranscript` sin energía | `""` sin tocar el analyzer final (filtro de energía intacto) |
| 5 | assets no instalados | `stop()` devuelve `""`; log `ear=apple reason=assets`; no cuelga |
| 6 | `fastBrain` | catálogo `[cerebras]`; escalera sin `groq` |
| 7 | Ajustes | no existe fila Groq; guardar/borrar OpenAI y Cerebras sigue igual |
| 8 | `VoiceStackResolver` | `ear` nunca es groq; `brain` cerebras > openAI |

## 5. Seguridad

- El oído deja de mandar audio a terceros: solo OpenAI (boca) y Cerebras (cerebro) salen de la
  máquina. Menos superficie, una clave menos que guardar.
- `contextualStrings` lleva nombres de apps y el nombre de Karen, nunca texto de pantalla ni
  transcripts.
- Karen debe **revocar la clave de Groq** en su consola cuando 15e cierre (se pegó en el chat).

## 6. Done (en vivo, Karen)

1. 10 holds con depuración ON: frase completa en el log; `ear=apple-analyzer` en cada uno.
2. `release→earFinal` p50 ≤ 400 ms en el timeline.
3. Ajustes muestra solo OpenAI y Cerebras.
4. Un hold sin hablar: reposo, sin "escuchando" pegado.

## 7. Aprobación

Aprobada 2026-09-24 con plataforma mínima macOS 26 ("sube, no pasa nada").

## Revisión (2026-09-24)

Hallazgos del code review de 15e, cada uno con test en rojo primero. `swift test` ×5 sin fallos
(321 tests) y `scripts/gates.sh` verde.

| # | Qué | Fix | Test |
|---|---|---|---|
| H1 (alto) | El gate de assets usaba `AssetInventory.status`; con "missing" para un modelo ya en disco el hold quedaba sordo para siempre | Verdad = `assetInstallationRequest(supporting:) == nil` o `installedLocales` contiene el locale (`TranscriberAssets.isReady`); el actor recuerda los locales listos (`ready`) y ya no pregunta; `supportedLocale` cacheado por locale en `AppleSpeechEngine`; la línea `assets=missing` lleva `status=` crudo | `AnalyzerTranscriberReviewTests`: `testAStatusThatSaysMissingNeverDeafensAnInstalledModel`, `testAnInstalledLocaleIsEnoughWhenARequestStillExists`, `testAReadyLocaleIsNotCheckedAgainOnLaterPresses`, `testTheMissingLineCarriesTheRawStatus` |
| M1 (medio) | `stop()` podía devolver el texto del hold siguiente o "" si un `start()` entraba durante su espera; el dictado paraba el oído fuera de `stopEar()` | Transcript por generación (`CurrentTranscript` + `SegmentedTranscript` capturado en `start()`, leído por su `stop()`); la rama de dictado de `completeHold` pasa por `classic.stopEar()` | `testAStopWaitingOnItsFinalKeepsItsOwnText`; `EarReviewTests.testADictationStopNeverKillsTheNextHold` |
| M2 (medio) | `start()` no re-chequeaba la generación tras sus awaits: un `stop()` en el hueco dejaba un run vivo que nadie paraba | `generation` re-chequeada tras cada await; el run tardío se cancela; `stop()` actúa con `active` o con run presente | `testAStopDuringTheStartGapLeavesNoLiveRun`, `testOverlappingStartsNeverOrphanARun` |
| M3 (medio) | Carrera en `earlyAudio`/`audioBuffer` entre la bomba de frames (actor) y `submit` (fuera del actor): el audio temprano podía llegar dos veces | `ClassicHoldAudio`: ambos buffers tras un lock; `takeEarly()`/`takeSpeech()` leen y vacían en un paso | `EarReviewTests.testEarlyAudioReachesTheEarExactlyOnce` (10 rondas, ids por trozo) |
| M4 (medio) | `testFramesBeforeTheEarIsUpStillReachTheEar` verde por construcción: el fake aceptaba frames antes de `start()` | `ScriptedTranscriber.append` descarta sin `running`, como el actor real; caso nuevo donde `finish()` nunca vuelve (`finishNeverReturns`) | `HoldEarTests.testFramesBeforeTheEarIsUpStillReachTheEar`; `testAFinalizeThatNeverReturnsFallsBackToTheLastPartial` |
| M5 (medio) | Suite intermitente: 14 tests apuntaban el sink global del log a su archivo mientras otros corrían en paralelo (visto en `VoiceDecisionTests.swift:64`) | `Log.capturing(to:)` con `@TaskLocal`: las líneas de la tarea y sus hijas van a su archivo sin tocar el global; los 14 tests migrados; solo `logTests` mueve el global (el test de captura vive dentro de esa secuencia); la cosecha AX de `ScreenSight` pasa de `Task.detached` a `Task` para heredar la captura | `LogTests.testACaptureKeepsItsOwnLinesWhenTheSinkMoves` (rojo en `LogTests.swift:21-23`); `ScreenTextTests.testLogNeverCarriesScreenText` ahora exige la línea `screen: ax` |
| L1 (bajo) | El item legacy `groq` solo se borraba sin bundle | `deleteRetiredLegacyItems()` también en la primera carga con bundle (una vez por proceso, carga cacheada) | `KeychainSecretStoreBundleTests` (L1) |
| L2 (bajo) | Borrar una clave en Ajustes fallaba en silencio | `errorText = settings.keys.delete.error` (es/en), la fila se queda | `KeysSettingsModelTests` (L2, es y en) |
| L3 (bajo) | Hasta 10 s de PCM en memoria tras un hold que nunca vacía | `holdAudio.reset()` en `stopIO` y en `failListen`; el dictado vacía el audio temprano al oído | `testAFailedListenKeepsNoEarlyAudio`, `testADeniedListenKeepsNoEarlyAudio`, `testADictationHoldKeepsNoEarlyAudio` |
| L4 (bajo) | La línea del press decía `ear=gpt-transcribe` con clave de OpenAI | `VoiceStackResolver`: `ear=apple-analyzer` siempre que haya voz de Apple | `VoiceStackTests` |
| L5 (bajo) | Comentario "300 ms" desfasado; `finish()` no vaciaba el conversor | Comentario a 0.5 s; `StreamingResampler.drain()` (`.endOfStream`) antes de cerrar la entrada | `StreamingResamplerTests.testDrainHandsOverWhatTheFilterHeld` |
| L6 (bajo) | `AudioWAV` sin llamadores desde que se fue Groq | Borrados `Sources/CompanionCore/AudioWAV.swift` y `AudioWAVTests.swift`; comentario de `OpenAITTS` actualizado | — (código muerto; build + suite verdes) |

Desviaciones:
- M5: se migró a captura en vez de `.serialized` (en funciones `@Test` sueltas no serializa contra
  otros archivos). `testAnsweredByLogsTheRealProviderNeverTheWords` pasó a su propio `@Test` async
  (`chatAnsweredByLogTests`) porque `collectChat` corre en `Task.detached` y no hereda la captura.
- Tope de 800 líneas: `VoiceSessionTests.swift` (1147) cedió el arnés y los fakes a
  `VoiceSessionFakes.swift`; `HoldVoiceTests.swift` (1083) cedió el dictado a
  `HoldDictationTests.swift` y el sentir-al-pulsar a `HoldPressSenseTests.swift`. Movimiento
  mecánico, ningún test cambió. `ChatViewModelTests.swift` (953) queda fuera: no lo toca esta revisión.
