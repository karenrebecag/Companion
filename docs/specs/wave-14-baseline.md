# Wave 14 — Baseline de voz: roles de producto, trabajo intacto

**Estado: PROPUESTA (2026-09-07).** Sin implementar. Espera aprobación
de Karen. Sin commit.

Cierra el hueco que las waves 3 / 9i / 12c / 13a dejaron abierto: el hold
FN **funciona**, pero el cerebro y la boca son el mismo tubo OpenAI
(`gpt-realtime`), una cuota mata el turno, el oído no tiene SLA, y el TTS
no se precalienta. Incredible se siente mejor no porque GLM-5.2 sea mágico,
sino porque el hold es un **stack de roles**. Companion ya tiene lo que
ellos no: ruteo de trabajo a CLI (`WorkRouting` + `Handoff`). Esta wave
afina el baseline **sin tocar ese carril**.

Tesis de facturación (Karen, turno anterior): **A — BYOK.** El producto
elige el modelo por rol; las claves son las del Keychain; no hay proxy
nuestro. Si OpenAI está en cero y no hay Groq/Ollama, el hold se cae **por
rol**, no con “no hay proveedor”.

---

## 0. Cómo se midió (no se adivinó)

Seis subagentes de exploración, 2026-09-07, solo lectura. Código gana a
docs. Trazas de Incredible: únicamente
`~/Documents/Incredible-Debug/2026-09-04/` (app 0.1.81,
cuatro holds, onboarding). `2026-09-05/` es RSS idle, sin pipeline.
`Documents/Incredible-Agent/` está vacío. **No hay dump del POST del
orchestrator** (`llm_request_bytes` siempre null).

| Auditor | Qué |
|---|---|
| Incredible voice stack | topología STT→LLM→TTS, modelos, timings, fallbacks |
| Incredible turn composition | qué ve el cerebro, JPEG vs texto, inyecciones |
| Incredible 09-05 | nada nuevo de pipeline |
| Companion voice baseline | hold real vs spec 9i (esta miente) |
| Companion work routing | contrato que 14 no puede romper |
| Companion perception | 10a + 13a vs método Incredible |

Prompts de Incredible **no se copian**. Esta spec toma método, caps,
paralelismo y números. La prosa nuestra.

---

## 1. Incredible, medido

Un hold no es speech-to-speech. Timeline del hold audible
(`22-50-43Z-voice--snazzy-beige-egret`):

```
FN down (t=0)
  +3 ms   TTS prewarm
  +4 ms   STT connect (AssemblyAI stream)
  +~0     mic + JPEG/visión + AX screen-text + open-docs
FN up     t=4633 ms
  +300 ms cola de commit STT
  +1500 ms deadline del primario → Groq batch (siempre, en esta captura)
STT final groq     t=7417
CallOrchestrator   t=7903   texto, no audio
LLM first token    t=8858   TTFT 955 ms   (GLM-5.2 vía proxy)
TTS first audible  t=9706   +848 ms tras el token
release→audible    5073 ms
```

Roles en `timings.json` (idénticos en los tres traces con timings):

| Rol | Primario | Fallback visto / configurado |
|---|---|---|
| Orchestrator (habla) | `vercel/zai/glm-5.2` | `glm-4.7` |
| Planners / data | `gpt-5.6-luna:priority` | Fireworks GLM-5.2-fast, Gemini 3.6 Flash |
| Summariser | Cerebras `gpt-oss-120b` | Groq gemelo |
| Classifier | Groq `gpt-oss-120b` | Cerebras |
| Visión (runtime, no el `[]` de settings) | Gemini 3.5 Flash Lite (Vercel) | OpenRouter → Claude Sonnet 5 → MiniMax |
| STT | AssemblyAI stream | Groq batch a 1500 ms |
| TTS | Inworld 1.5-max / Lauren t=1.4 r=1.1 | ElevenLabs v3 (otro camino caliente) |

Hechos que **corrigen** la lectura anterior de este hilo:

1. **El classifier no rutea el turno de voz.** Corre ~12 s *después* del
   habla, evento PostHog `task_description`, tags `summarize_content` +
   `file_open`. El hold audible tuvo `owning_agent: "orchestrator"` y
   `live_sub_agents=0`. Tratarlo como “barato → especialista” es
   **inventar**. En Companion el ruteo de trabajo ya existe y es mejor
   (`delegate` → `WorkRouting`).
2. **La visión casi nunca entra al primer LLM.** JPEG 86–157 KB, 6.5–8.9 s,
   sidecar. El orchestrator arranca con `screenshot=(none)` y
   `reports_preludes=0B`. “El cerebro ve SUMMARY+SNIPPETS” es el *diseño*;
   en esta captura **no se inyectó**. Companion 13a espera ≤2 s en el
   commit: más fiel a usar el brief que ellos en estos holds.
3. **STT primario perdió siempre.** Los parciales son AssemblyAI; el final
   que llega al cerebro es Groq. Un oído sin SLA no es su baseline.
4. **Vacío / `"."` no llama al LLM.** Overlay “couldn't hear”, 6 s. La
   visión *sí* corre igual.
5. **Claves locales `MISSING`.** Todo pasa por
   `https://db.incredible.one/functions/v1/llm-proxy` tras login.
   Plan `free`. Eso no se recrea en tesis A.
6. **Subagentes son config, no evidencia de spawn** en este dump. Cancelar
   FN manda `CancelForegroundSubAgents`; no vimos un planner vivo.

Inyecciones (método, no texto):

- Candado de idioma **delante del utterance**, según el habla (`auto`), no
  según la pantalla.
- Identidad (nombre, email, TZ) + reloj en el `context=` del STT final.
- Interrupción: cancelar LLM/TTS/STT/subagentes + una línea “no te
  repitas, retoma” en el *siguiente* body.
- `<time_since_last_interaction>` en holds 2+.

Fan-out en key-down, commit en release + 300 ms. PCM 16 kHz. AX
`screen-text` ~378–442 ms / 155 chars (Companion no tiene ese canal).
`open-folders` se tira a 300 ms (siempre, aquí).

---

## 2. Companion, medido (el código, no la spec 9i)

La spec 9i dice: oído Apple, `create_response:false`, VAD en la sesión de
conversación. **Mentira respecto a lo shipped.**

Hold con clave OpenAI (camino caliente):

```
teclado: 250 ms de arm (HoldKeyClassifier.tapThreshold)
         island/puntero: press inmediato
hold() → preferRealtime = hay clave
       → screen.begin si canal .screen (default ON)
openRealtimeSession (tope 6 s)
  mic + player + WS conversación gpt-realtime
  oído aparte: gpt-transcribe (?intent=transcription)
  PCM → oído; realtime.append NUNCA se llama en Sources/
release → mic off + commitWithText
  250 ms de settle; audit.turnText()
  userTextItem + response.create  ← gpt-realtime PIENSA y HABLA
```

| Pieza | Hecho |
|---|---|
| Cerebro del hold | `gpt-realtime` (audio out + tools + `ChatPrompt.system`) |
| Oído del hold | `gpt-transcribe`, no Apple |
| Picker de Settings | **no** elige el hold. Solo chat escrito y clásico |
| Clásico | STT Apple → `ChatProvider` (escalera) → `gpt-4o-mini-tts` |
| Clásico + `delegate` | **no.** `ClassicRuntime` traga `.handoff` con `continue` |
| Prewarm boot | mic (si ya hay grant) + `isOnline`. Cero STT, TTS, socket, Keychain |
| SLA oído | no existe. 1500 ms es el techo de silencio del VAD del *transcribe* |
| Apple | solo clásico (sin clave, o realtime open falló *online*) |
| Visión 13a | JPEG → `gpt-4o-mini`; nunca `imageItem`; ≤2 s en commit; se cancela en discard/vacío/dictado |
| Cuota primer hold | `failOrRecover` → `.error`. No cae a clásico |
| Handshake 429 | se lee como red y *puede* caer a clásico |
| `VoiceSession.swift` | 795 líneas + pumps 268 + attachments 57 ≈ 1120 |

Delegación hoy: solo realtime. El modelo llama `delegate`; `Handoff.parse`;
`VoiceJobBridge` → `JobRunner` → `WorkRouting`. El picker de ejecutor no
elige con quién hablas. Native nunca declara `.web`. CLI instalado se
lleva el trabajo aunque el picker diga nativo. Eso **se conserva**.

Percepción hoy: `<context>` DATA en el turno de usuario (app, docs,
pantalla, clipboard off). Identidad vive en el system prompt, no en el
turno. Idioma = Settings, no auto-por-habla. Interrupción = barge-in de
audio, sin prosa “no te repitas”. Sin `screen-text` AX (títulos/paths a
150 ms; el harvest de ellos de 400 ms no cabe).

---

## 3. El defecto

No es “falta GLM” ni “falta el picker en voz”. El hold caliente es un
**solo tubo OpenAI** que oye (otro socket), piensa y habla. El clásico
*ya es* STT → texto → TTS, pero es el camino frío, sin `delegate` y sin
sidecar de pantalla. Por eso Incredible (texto + TTS especializado + SLA
de oído + inyecciones) se siente producto, y Companion se siente API.

El ruteo CLI no se usa para tapar eso: el usuario pulsa FN para hablar,
no para abrir un ejecutor.

---

## 4. Decisión

**El hold FN es un stack de roles de producto. El trabajo sigue siendo
otro carril.**

```
hablar  = oído → (opcional steering) → cerebro de texto → boca
actuar  = tools del padre (10b), inline, ≤3 rondas
trabajar = Handoff → WorkRouting → Native / Claude / Hermes
```

Realtime deja de ser el cerebro. Si sobrevive, es boca y/o VAD de manos
libres — no el hold. El hold es push-to-talk; el VAD de conversación ya
está anulado (`NSNull()`).

Tesis A: cada rol elige el primer endpoint **rápido** que tenga clave, en
este orden de producto (no el desplegable):

| Rol | Primario | Fallback |
|---|---|---|
| Oído | `gpt-transcribe` (ya) | Apple `SystemTranscriber` a **1500 ms** sin final |
| Vista | `gpt-4o-mini` (13a, ya) | sin brief; el turno sigue (`pending` o omitir) |
| Cerebro | `gpt-4o-mini` vía `ChatProvider` **fijo**, no el picker | Groq → OpenRouter → Ollama (los que tengan clave / probe) |
| Boca | `gpt-4o-mini-tts` (ya existe) | `AVSpeech` (ADR 001, ya) |
| Trabajo | `WorkRouting` **sin cambios** | nativo siempre |

No se añade Inworld, AssemblyAI, Gemini, ni proxy. No se copian prompts.

Classifier barato **antes** de `delegate`: **fuera de 14.** Incredible no
lo hace en el turno de voz (telemetría). Companion ya deja que el cerebro
llame `delegate`. Inventar un clasificador ahora es otra tesis, otra wave.

---

## 5. Turno objetivo (hold)

```
FN down (tras el arm de 250 ms del teclado; island = inmediato)
  en paralelo:
    mic start
    oído connect (transcribe WS o el que esté caliente)
    boca prewarm (TTS HTTP/sesión, no esperar al token)
    screen.begin (13a, si canal on y hay clave de visión)
    AX 10a sigue en commit (150 ms) — no se mueve a press en 14

FN up
  cola 250 ms (ya; no subir a 300 salvo que midamos cola cortada)
  oído final; si a 1500 ms no hay final → Apple batch/stream sobre el
    mismo PCM o un segundo pass (ver 14c)
  vacío / basura ("." / < 3 chars) → heardNothing, sin cerebro, sin boca
    (la visión se cancela, como 13a en vacío)
  senseVoice: AX 150 ms + visión ≤2 s (13a, se queda)
  steering nuestro (14d) envuelve el utterance
  cerebro ChatProvider (mini) con tools: padre + delegate + stop/resolve
    si hay jobs — el clásico HOY no las tiene; 14b las porta
  si delegate → VoiceJobBridge + WorkRouting (igual que ahora)
  si padre → loop ≤3 (como clásico ya hace)
  boca: primer sentence-split al TTS precalentado
```

Manos libres (`start()`, no hold): **fuera de 14a–14c.** El atajo actual
sigue en realtime o se anota 14f. No mezclar.

---

## 6. Invariantes (no se tocan)

De ADR 001, 4, 7, 10b, WorkRoutingTests:

1. Hablar ≠ trabajar. El picker de ejecutor no elige el cerebro.
2. Native siempre existe; CLI es probe de PATH.
3. Native no declara `.web`. CLI se lleva el trabajo si está instalado.
4. `selectExecutor(for:)` ignora el texto del `Handoff`.
5. Override visible (`WorkRouting.overrides`).
6. Padre = abrir/mirar; especialista = leer/escribir/shell.
7. `Handoff.parse` nulo no escala. Goal vacío no arranca job.
8. No anunciar `delegate` en un camino que no pueda correrlo.
9. JPEG nunca a disco ni a `imageItem`. Cancelar visión en discard.
10. `<context>` es DATA, un turno, compact en historia.
11. Tests listados por el auditor de work routing no se borren.

El desplegable de **chat escrito** se queda. El hold no lo lee. Copy de
Settings: una línea que lo dice (14a).

---

## 7. Fuera (esta wave y para siempre en 14)

- Copiar instruction de visión, user-note, candado de idioma, o
  “previous turn was interrupted…” de Incredible.
- Proxy `db.incredible.one`, login, claves nuestras.
- Dependencias nuevas (Inworld, AssemblyAI, Groq STT SDK, Gemini).
- Classifier → especialista como si fuera su método.
- JPEG al cerebro. OCR local (13b si acaso).
- AX `screen-text` de 400 ms (otro presupuesto; 14 no lo mete en 150 ms).
- `open-folders` a 300 ms (ellos lo tiran siempre aquí).
- Email/TZ en el turno (producto sensible; identidad = nombre que ya
  tenemos en `UserProfile`, 14d opcional).
- Reescribir `WorkRouting`. Elegir ejecutor por keywords.
- Git, deps, configs raíz, migraciones.
- Manos libres / socket caliente en boot (D8 de 12c): se mide, no se
  decide aquí.

---

## 8. Tandas (3–5 archivos cada una)

Cada tanda espera “vamos” propia si cambia el contrato de voz. 14a es
la primera implementable tras aprobar **esta** spec.

### 14a — El stack existe, el picker no manda el hold

**Objetivo.** Un tipo de producto describe oído / cerebro / boca / vista.
`VoiceSession.hold` lee ese stack, no `ProviderPreference.order`. Tests
rojos primero: cambiar el desplegable a Ollama no cambia los ids del hold.

**API (Core)**

```swift
public struct VoiceStack: Sendable, Equatable {
    public var ear: VoiceRole
    public var brain: VoiceRole
    public var mouth: VoiceRole
    public var sight: VoiceRole
}

public struct VoiceRole: Sendable, Equatable {
    public var id: String          // "gpt-transcribe", "gpt-4o-mini", ...
    public var provider: String    // "openai", "apple", "avspeech"
}

public enum VoiceStackResolver: Sendable {
    /// Product defaults + which secrets/probes are present.
    /// Does not read the chat picker.
    public static func resolve(
        secrets: [SecretKey: Bool],
        appleSpeech: Bool,
        localModel: String?
    ) -> VoiceStack
}
```

Resolver (tesis A): cerebro = `gpt-4o-mini` si hay OpenAI; si no Groq
llama; si no OpenRouter; si no Ollama tag; si no, hold no arranca cerebro
y el fallo es **`.noProviders` del rol**, no un 429 disfrazado de red.
Oído = transcribe si OpenAI, si no Apple. Boca = mini-tts si OpenAI, si
no AVSpeech. Vista = mini si OpenAI, si no desactivada.

**Archivos (tope 5)**

| Archivo | Qué |
|---|---|
| `Sources/CompanionCore/VoiceStack.swift` | tipos + resolver puro |
| `Tests/CompanionTests/VoiceStackTests.swift` | picker no entra; cadenas; sin clave |
| `Sources/CompanionServices/VoiceSession.swift` | log `voice stack: ear=… brain=…` al hold; aún no cambia el tubo |
| copy Settings (el archivo de modelos que ya existe) | una línea: el hold ignora este desplegable |
| test de caracterización en `HoldVoiceTests` o `VoiceSessionTests` | el log / snapshot del stack no sigue a `providerOrder` |

14a **no** apaga realtime. Solo nombra roles y deja evidencia en log.
Sin esto, 14b mezcla tesis y cableado.

**TDD**

| # | Test | Espera |
|---|---|---|
| 1 | OpenAI presente | ear `gpt-transcribe`, brain `gpt-4o-mini`, mouth `gpt-4o-mini-tts`, sight `gpt-4o-mini` |
| 2 | solo Groq | brain Groq; ear Apple si `appleSpeech`; mouth AVSpeech; sight off |
| 3 | solo Ollama | brain = tag local; mouth AVSpeech |
| 4 | nada | stack con roles vacíos / `nil` explícito; no inventa ids |
| 5 | `providerOrder` permutado | **mismo** stack (el picker no es input del resolver) |

### 14b — El cerebro es texto; la boca es TTS; `delegate` vive ahí

**Objetivo.** El hold caliente deja de llamar `response.create` en
`gpt-realtime` como pensador. Camino: oído → `ChatProvider` (rol cerebro)
→ `SpeechSynthesizer` (rol boca). **Portar** al camino caliente lo que
hoy solo tiene realtime: padre + `delegate` + `stop_job` /
`resolve_approval` + `VoiceJobBridge` + anuncio ≠ éxito + visión 13a.

Realtime en el hold: **no se abre.** El socket de `gpt-transcribe` (oído)
sí, si el rol oído lo pide. Manos libres no se migran en 14b.

Esto es el clásico **como camino caliente**, no un fallback. El clásico
actual no puede trabajar; el nuevo sí. Si 14b no porta `delegate`, el
CLI desaparece del FN — inaceptable.

**Archivos (tope 5, probable split 14b.1 / 14b.2 si el diff explota)**

| Archivo | Qué |
|---|---|
| `ClassicRuntime.swift` (o rename `TextVoiceRuntime`) | tools = padre **+** delegate si `jobs != nil`; `.handoff` llama `onDelegate`; ya no `continue` |
| `VoiceSession.swift` | hold con clave usa el runtime de texto; `jobAnnounce` también en ese pipeline |
| `VoiceJobBridge.swift` | anuncio no exige `pipeline == .realtime` |
| `ChatPrompt.swift` | `delegateRule` no dice “OpenAI realtime” |
| tests | hold+delegate sin WS de conversación; clásico/texto con jobs; sin jobs no anuncia delegate |

`RealtimeRuntime` se queda para manos libres y para no romper tests
hasta 14f. Hold tests que hoy afirman `conversation.item.create` +
`response.create` **se reescriben**: el hold ya no manda eso.

Prewarm de boca: en `hold()`, no en boot. Test: `synthesizer.prewarm`
(puerto; si no existe, se añade al protocolo `SpeechSynthesizer` — cuenta
como archivo si hay que tocarlo: entonces Settings copy de 14a ya está
fuera y el tope se respeta moviendo copy a 14a solo).

**TDD**

| # | Test | Espera |
|---|---|---|
| 1 | hold+release con texto | `ChatProvider.stream` del rol cerebro; **cero** `response.create` |
| 2 | stream emite `delegate` | `Handoff` llega a `JobSubmitter`; WorkRouting igual |
| 3 | `jobs == nil` | tools sin `delegate`; no hay handoff |
| 4 | padre `open_app` luego texto | ≤3 rondas, no es job |
| 5 | job termina | anuncio en el hilo; el modelo no afirma éxito solo |
| 6 | prewarm en hold | boca tocada en press, no en `prewarm()` de boot |
| 7 | canal `.screen` | `screen.begin` en press (ya); `finish` en commit (ya) |

**Riesgo.** MCP HTTP de OpenAI realtime **muere en el hold**. Completions
no ejecuta MCP server-side. 14b lo anota: MCP en hold = diferido (10c ya
vive en realtime). No reimplementar MCP aquí.

### 14c — SLA del oído

**Objetivo.** Recrear el método 1500 ms: si `gpt-transcribe` no entrega
final, Apple transcribe el mismo turno. Vacío / `"."` → `heardNothing`,
sin cerebro.

No hay Groq STT (deps). Apple es el fallback nativo (ADR 001).

**Archivos**

| Archivo | Qué |
|---|---|
| `VoiceAudit.swift` / oído | deadline 1500 ms tras release+cola; `fallbackEar` |
| `SystemTranscriber` o un `FallbackEar` en Services | segundo pass; no pide Speech si ya está denegado |
| `TurnMachine` / `VoiceSession.commitTurnFromNative` | no commitea cerebro si el texto no pasa el umbral |
| tests | final a tiempo no llama Apple; silencio 1500 ms sí; `"."` no llama chat |

Umbral de basura: trim, sin alfanuméricos o `< 3` graphemes → vacío.
Test de caracterización con `" ."` y `""`.

PCM: hoy el oído OpenAI es WS; Apple quiere su propio tap. Si no hay PCM
compartido sin rediseñar `AudioEngineHub`, el fallback es **segundo
reconocimiento en vivo** (Apple `start` en press junto al WS, se descarta
si OpenAI llega a tiempo). Eso es más fiel a “dos oídos en paralelo” que
a su batch sobre los mismos samples — se anota como desviación medida,
no como copia.

### 14d — Dirección de producto (prosa nuestra)

**Objetivo.** El turno lleva steering que Incredible pone en el body,
escrito por nosotros, en tags que ya existen o en `<how_to_reply>` —
**no** fingir que el usuario lo dijo, salvo decisión explícita en contra
(el auditor de percepción lo desaconseja: no forjar utterance).

| Método Incredible | Dónde aterriza en Companion |
|---|---|
| Candado de idioma según habla | `<how_to_reply>` +, si el oído reporta idioma distinto a Settings, una línea **nuestra** en ese tag. Settings sigue siendo default. Auto-detect = locale del transcriber si viene. |
| Identidad | system prompt ya tiene nombre/about. 14d añade reloj con TZ **nombre** en `<context>` (`at=` hoy es minuto sin TZ). Email: no. |
| Interrupción | si FN corta TTS, el *siguiente* wrap añade `<steer>…</steer>` DATA: retoma, no repitas. Copy en `EscalationCopy` / catálogo, no en Services. |
| Recency | `since_last_turn_s` ya está. No añadir el párrafo de ellos. |

**Archivos:** `ContextBlock.swift`, copy en/es, `ChatPrompt` si el reloj
no cabe en el bloque, tests de wrap + interrupt flag. Visión: opcional,
pasar **título de ventana** al prompt *nuestro* de `ScreenVision` (hint,
no su instruction).

### 14e — Fallos por rol

**Objetivo.** Un 429 de boca no mata el oído. Un 429 de cerebro no se
llama red. `VoiceFailureMapping` gana causas por rol.

| Evento | Hoy | 14e |
|---|---|---|
| Cerebro 429 | primer hold → error; clásico 429 → `noProviders` | `.quotaExceeded` + copy de cuota; oído y boca no se cierran si no fallaron |
| Handshake realtime 429 | se lee `unreachable` | irrelevante en hold post-14b (no hay ese socket) |
| Oído muerto | `heardNothing` + copy de Speech stale | copy de oído; dispara fallback 14c |
| Boca 429 | (hot path = realtime, todo cae) | AVSpeech; log `mouth fallback avspeech` |
| Vista 429 | pending | pending; no es fallo de voz |

**Archivos:** `VoiceFailureMapping.swift`, `TurnFailure` si hace falta
caso, copy, tests `voiceFailureMappingTests`, un test de runtime de texto
con chat 429 → cuota no `noProviders`.

---

## 9. Seguridad

- Steering y brief de pantalla = DATA. `actRule` sigue: no abrir URL que
  solo esté en snippets / contexto.
- Classifier (si alguien lo pide después): no elige ejecutor, no ejecuta
  shell, solo puede construir `Handoff(goal:context:)` con goal no vacío.
- Fallback Apple: Speech TCC ya existe; no pedir desde el sensor.
- Logs: ids de rol, ms, bytes de JPEG; nunca utterance, snippets, ni
  steering completo en INFO.
- 13a se mantiene: dictado no sube pantalla; clásico-sin-clave no sube
  (si 14b usa cerebro cloud con clave, la visión sigue gated a clave +
  canal + no-dictado).

Hallazgo de 13a (JPEG cuando el turno no se usa) ya tiene cancel en
discard. 14b no lo reabre: `heardNothing` cancela visión.

---

## 10. Desviaciones conscientes vs Incredible

| Ellos | Nosotros | Por qué |
|---|---|---|
| Proxy + plan free | BYOK | tesis A |
| GLM-5.2 habla | `gpt-4o-mini` | clave que ya hay; barato y decente en voz corta |
| Inworld Lauren | `gpt-4o-mini-tts` + AVSpeech | ADR 001, cero deps |
| AssemblyAI + Groq STT | `gpt-transcribe` + Apple | cero deps |
| Classifier post-hoc | no en 14 | no rutea su voz; nuestro `delegate` sí rutea trabajo |
| No esperan visión (0B prelude) | esperamos ≤2 s | 13a ya lo hace; si no, el brief no sirve |
| Language prefix en el utterance | tag `<how_to_reply>` | no fingir habla del usuario |
| Subagentes luna/priority | CLI + NativeExecutor | lo que ellos no tienen |

---

## 11. Done (producto)

Tras 14a–14e, un hold FN con clave OpenAI:

1. Log `voice stack:` con cuatro roles; mover el picker no lo cambia.
2. Cero `response.create` en el hold (tests).
3. “crea un archivo de prueba en el escritorio” sigue creando el archivo
   (regresión 9i / 7) vía `delegate` + WorkRouting, **sin** realtime.
4. Soltar FN en silencio no habla.
5. Cortar TTS con FN y hablar de nuevo: no repite el párrafo a medias.
6. Cuota de TTS → voz del sistema, no “no hay red”.
7. Pantalla: igual que 13a (brief o pending); JPEG fuera del cerebro.

Comparar con Incredible en el mismo gesto (resumir el escritorio):
latencia release→audible y si cita lo visible. No copiar su frase de
onboarding.

---

## 12. Aprobación

Esta spec es el mapa. La primera tanda a implementar, si Karen dice
vamos, es **14a** (tipos + log + tests; el tubo aún es realtime). 14b
es el corte de verdad y pide un “vamos” aparte: apaga el cerebro
realtime del hold.

Pregunta única si algo no está cerrado: ninguna de tesis (A ya). Si el
MCP en hold duele, se anota como 14f, no se cuela en 14b.
