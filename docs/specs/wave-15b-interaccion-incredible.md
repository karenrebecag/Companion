# Wave 15b — La interacción de Incredible: FN habla, la pantalla se ve, la voz no espera

**Estado: APROBADA / EN CURSO (2026-09-23).** Karen: "listo, aprobado. hazte cargo de la spec, tú eres el orquestador". §11 resuelto: Opción derecha por defecto (Command derecho elegible). Entregas 0-11 + 7b implementadas; revisión de seguridad APPROVE, code review con 1 alto + 2 medios + 1 bajo corregidos test-first (interrupt clásico termina idle, pressedContext cancelado + prewarm sin duplicados, tecla de dictado se reconstruye al cambiarla, corte tras act). 299 tests, gates verdes. Pendiente: §10 en vivo. Sin commit.

Karen: "quiero la misma interaccion que plantea incredible. incredible
incluso puede mirar lo que ocurre en pantalla".

Criterio de done: mantener FN siempre habla con Companion (nunca pega); dictar
tiene su propia tecla; al pulsar ya se está mirando la pantalla y calentando la
voz; una orden que resuelve el router suena en ≤ 1500 ms desde que sueltas
(Incredible: 5073 ms); pulsar mientras Companion piensa o habla lo corta y el
siguiente turno sabe que lo corregiste; cada turno sabe cuánto hace del
anterior y qué hora es. Gates verdes.

Depende de: 12e (dictado), 13a (pantalla), 14 (roles), DM1c (router), 15a
(conversación efímera), y del arreglo del doble arranque del micro / fin del
hold en idle (ya aterrizado, sin commit, 2026-09-23).

---

## 1. El defecto, medido

### A. FN decide por el foco, no por la intención

- El modo por defecto es `.automatic`: `UserPreferences.swift:217`
  (`?? .automatic`) y `Config.swift:164`. Con un campo de texto enfocado, el
  hold **dicta** (`Dictation.swift:55-57`). En vivo pegó en Terminal lo que era
  una orden.
- El hold lee ese modo al pulsar: `VoiceSession.swift:376` →
  `DictationRouter.destination` (`:381`). En el clásico, al soltar se pega en
  `VoiceSessionPumps.swift:286-302`.
- Hay **una sola tecla**: `HoldKeyTap()` en `CompanionMain.swift:348`. El tap
  tiene `keyCode` parametrizable (`HoldKeyTap.swift:22-24`) pero el flag está
  cableado a FN (`:117`, `.maskSecondaryFn`) y **se traga** el soltar y el toque
  (`:135-140`): correcto para Globe, incorrecto para cualquier modificador.

### B. Al pulsar solo se abre el micro; mirar espera al transcript

- `hold()` (`VoiceSession.swift:337-366`): arranca la visión 13a solo con clave
  OpenAI y canal `.screen` (`:360-362`) y pide el micro clásico (`:365`).
- El contexto se sensa **después** del transcript: `ClassicRuntime.submit` →
  `senseVoice` (`ClassicRuntime.swift:117`), AX 150 ms + espera de visión
  **siempre** de hasta 2 s (`:245-256`).
- No hay texto de pantalla por AX: solo títulos y documentos
  (`ContextSensors.swift:268-281`). Incredible cosecha ~155 caracteres en
  378–442 ms **al pulsar**.
- Nada de voz ni de red se calienta al pulsar (`VoiceSession.swift:404-411`).
- "screen: skipped" (`ScreenSight.swift:57`): Grabación de pantalla sin
  conceder tras el reset de TCC. Paso manual (§10).

### C. La voz llega tarde, y no se mide

- El router decide `open_app` ~1.0 s después de soltar, pero el acuse tardó
  3.6 s: `respond` encola el texto completo (`ClassicRuntime.swift:238-240`) y
  `SpeechSynthesis.utter` **descarga el mp3 entero** antes de sonar
  (`SpeechSynthesis.swift:146-167`, `OpenAITTS.swift:25-36`).
- `PhraseCache` (≤ 80 caracteres, `PhraseCache.swift:5`, `:14`) no se llena por
  adelantado; su clave es solo el texto (`:28-30`) y el directorio no distingue
  voz (`CompanionMain.swift:236-238`).
- **No se mide soltar→primer audio en el clásico.** `.firstAudio` solo se marca
  en `.agentAudioStarted` (`VoiceSession.swift:448-450`, solo realtime); el
  `.chunkStarted` del sintetizador se ignora (`VoiceSessionPumps.swift:267-268`).

### D. Pulsar mientras piensa no corta nada

- `SessionMachine` `.pressed` no pide cancelar (`SessionMachine.swift:89-93`).
- `TurnMachine.holdPressed` clásico: `.thinking` → `[]`; `.speaking` → solo
  para el TTS (`TurnMachine.swift:74-76`, `:225-234`).
- El turno clásico no es una Task (`VoiceSession.swift:480-483`): el LLM sigue
  y sus frases se encolan. `SpeechSynthesis.begin()` vuelve a `stopped = false`
  (`SpeechSynthesis.swift:61-70`): un stream viejo puede sonar en el turno
  siguiente (a reproducir con test).
- El siguiente turno no sabe que hubo corte.

### E. El reloj del turno mide otra cosa

- `since_last_turn_s` (`ContextBlock.swift:51-53`) se calcula desde la última
  lectura del sensor (`ContextSensors.swift:92-98`), no desde la última
  interacción; los turnos del router no sensan.
- `at=` es minuto local sin zona ni día (`ContextBlock.swift:208-214`).
- La última interacción real ya existe: `ChatViewModel.lastActivity` (15a).

### Restricción medida

`VoiceSession.swift` tiene 794 líneas; el gate corta en 800
(`scripts/gates.sh:41-46`). Todo lo nuevo va en extensiones
(`VoiceSessionFanOut.swift`, `VoiceSessionSteer.swift`). Presupuesto de 15b en
ese archivo: **+4 líneas netas**.

---

## 2. Incredible, medido (no copiado)

Fuente: `~/Documents/Incredible-Debug/2026-09-04/logs/app.log` y
`voice-traces/22-50-43Z-voice--snazzy-beige-egret/timings.json`.

| Qué | Evidencia | Qué tomamos |
|---|---|---|
| FN = agente siempre; dictado con su propio detector | `app.log:94` "dictation chord detector installed" | Tecla de dictado propia |
| Al pulsar, en paralelo: TTS prewarm, STT, micro, visión, AX, docs | `timings.json` | Fan-out al armar el hold |
| Brillo de pantalla al escuchar | `app.log:161`, `:196` | No: la island ya pinta Listening |
| Soltar → cola 300 ms → commit | 14 §1 | No se toca (§7) |
| Siempre habla; soltar→audible 5073 ms | 14 §1 | Hablar siempre, ≤ 1500 ms en órdenes del router |
| Pulsar en vuelo cancela y avisa al siguiente turno | `app.log:202`, `:217` | Cortar + nota nuestra |
| `<time_since_last_interaction>` + hora | `app.log:238`, `:266` | El tag, con prosa nuestra |
| Aprobaciones solo enviar/borrar/pagar | FAQ del bundle | Ya es DM1 §2 |

Los prompts de Incredible no se copian: se toma el método, el tag y los números.

---

## 3. Decisión

### A. FN es del agente; dictar tiene su tecla

- **FN siempre va al agente**: `hold()` deja de leer `voice.mode`.
- **Tecla de dictado: mantener Opción derecha** (default), con un segundo
  `HoldKeyTap` y el mismo clasificador (arma a 250 ms; un acorde no es hold).
  Un solo modificador como FN; sola no escribe ni tiene atajo de sistema;
  Option+Space queda libre; mismo permiso de Accesibilidad. Se detecta por
  `keyCode 61` + bit derecho `0x40`.
- **El tap de dictado nunca se traga eventos** (un modificador tragado queda
  pegado): `swallowsRelease: false`.
- Sin campo o sin Accesibilidad, contrato de 12e: las palabras van a Companion.
- Configurable en conjunto cerrado: `off`, `rightOption`, `rightCommand`.
- La fila "Al mantener FN" se sustituye por "Tecla de dictado".

### B. Al pulsar se mira y se calienta; al soltar solo se decide

Fan-out en `hold()` en paralelo con el micro (`VoiceSessionFanOut.swift`):

| Canal | Qué | Cuándo se recoge |
|---|---|---|
| Contexto 10a | `sensor.sense(...)` en una Task | `senseVoice` la espera |
| Texto de pantalla AX | ventana enfocada de la última app ajena; roles de texto, nunca `AXSecureTextField`; ≤ 300 nodos, ≤ 600 caracteres, 0,25 s por llamada, ~450 ms total | En `ScreenSight`, como snippets etiquetados con la app |
| Captura + visión 13a | arranca al pulsar | Al commit, solo espera si la pregunta la necesita |
| Voz | frases fijas del acuse a caché; TLS a `api.openai.com` caliente | El acuse suena de disco |

**Visión solo cuando hace falta**: `ScreenNeed.wait(utterance:hasText:)` (Core,
puro) devuelve 2 s si la orden señala la pantalla ("esto", "aquí",
"pantalla", "lo que ves", "this", "here", "screen", "see"…) o si no hay texto
AX; si no, 0 s.

### C. Hablar como Incredible, más rápido

- **Medir primero** (15b-0): `.firstAudio` en el clásico al primer
  `.chunkStarted` de un hold soltado; `release→audio` en la línea.
- **Objetivos** (p50 de 10 holds, router encendido): orden del router
  `release→audio ≤ 1500 ms` (p90 ≤ 2000); camino del modelo informativo
  `≤ 3000 ms`.
- **Acuse desde caché** (`AckPolicy`, Core puro): la frase específica si está
  en caché; si no, "Listo." / "Done." y la específica se calienta para la
  próxima. El texto completo siempre va al hilo y a la island.
- **Precalentar al pulsar** `DecisionCopy.prewarmSet(lang)`. En boot no (leer
  la clave puede abrir un diálogo).
- **Conexión caliente**: `OpenAITTSClient.warm()` = `GET /v1/models` sin clave.
- **Caché por voz**: `tts/<voice>`.

### D. Pulsar en vuelo corta y avisa

- Pulsar con el clásico en `.thinking` o `.speaking` cancela el turno (stream,
  TTS, visión, `delegate` no lanzado): `classic.submit` corre en una Task propia.
- **Un encargo ya en marcha no se cancela** (se para con "para" o el botón).
- Lo ya dicho (`spokenSoFar()`) entra al hilo como respuesta del asistente.
- **Nota de corrección** en el siguiente turno, dentro de `<context>` (DATA):
  `<steer>` con prosa nuestra. Una sola vez.
- Una confirmación pendiente del router no se toca.

### E. Reloj por turno

- `<time_since_last_interaction seconds="7">hace 7 s</time_since_last_interaction>`
  y `<now>2026-09-23 mié 14:05 UTC-06:00</now>` en `<context>`, sustituyendo
  `since_last_turn_s`. Sin ubicación.
- Fuente: `lastActivity` (15a), leída antes de `appendUser`. Si toca rollover,
  `nil` y sin tag.

---

## 4. API

```swift
// Core — Config.swift
public enum DictationKey: String, Sendable, Equatable, CaseIterable {
    case off, rightOption, rightCommand
    public var keyCode: Int64? { get }      // 61 / 54 / nil
    public var deviceFlag: UInt64? { get }  // 0x40 / 0x10 / nil
}
public struct VoiceSettings { public var dictationKey: DictationKey /* = .rightOption */ }

// Services — HoldKeyTap.swift
public init(keyCode: Int64 = 63, flag: CGEventFlags = .maskSecondaryFn,
            swallowsRelease: Bool = true, tapThreshold: TimeInterval = 0.25, now: ...)

// Services — VoiceSession
public func hold(dictate: Bool = false) async

// Core — DecisionRouting.swift
extension DecisionCopy {
    public static func quickAck(_ language: AppLanguage) -> String
    public static func prewarmSet(_ language: AppLanguage) -> [String]
}
public enum AckPolicy {
    public static func choose(specific: String, specificCached: Bool,
                              language: AppLanguage) -> (speak: String, warm: String?)
}

// Core — VoicePorts.swift (defaults no-op)
extension SpeechSynthesizer {
    func isCached(_ phrase: String) async -> Bool
    func prewarm(_ phrases: [String]) async
    func warmConnection() async
}

// Core — ScreenNeed.swift (nuevo)
public enum ScreenNeed {
    public static func wait(utterance: String, hasText: Bool) -> Duration
}

// Core — TurnContext.swift
public enum ScreenTextSnippets {
    public static func snippets(from texts: [String], app: String) -> [ScreenSnippet]
}
public struct TurnContext { public var interrupted: Bool }

// Core — ChatPorts.swift
extension ConversationPresenting {
    func lastInteraction() async -> Date?
}
```

---

## 5. Entregas (≤ 5 archivos cada una, tests incluidos)

| Entrega | Qué | Archivos |
|---|---|---|
| 15b-0 | Medir soltar→audio en el clásico | `TurnTimeline`, `VoiceSessionPumps`, `TurnTimelineTests`, `HoldVoiceTests` |
| 15b-1 | Tecla de dictado propia; FN al agente | `HoldKeyTap` (+ `consumes` puro), `Config` (`DictationKey`), `VoiceSession` (`hold(dictate:)`, 0 netas), `CompanionMain` (segundo tap), `HoldVoiceTests` (casos 12e → `hold(dictate: true)`) |
| 15b-2 | Ajustes "Tecla de dictado" | `UserPreferences`, `HoldSettings`, strings en/es, `DictationTests` — misma sesión que 15b-1 |
| 15b-3 | Acuse del router desde caché | `DecisionRouting` (`quickAck`, `prewarmSet`, `AckPolicy`), `VoicePorts`, `SpeechSynthesis`, `ClassicRuntime`, `AckTests` |
| 15b-4 | Calentar voz al pulsar; caché por voz | `VoiceSessionFanOut` (nuevo), `VoiceSession` (+1), `OpenAITTS` (`warm`), `CompanionMain`, `FanOutTests` |
| 15b-5 | Sentir al pulsar | `VoiceSessionFanOut`, `ClassicRuntime` (`pressedContext`), `VoiceSession` (+1), `HoldVoiceTests` |
| 15b-6 | Texto de pantalla por AX | `AXScreenText` (nuevo), `ScreenSight`, `TurnContext`, `CompanionMain`, `ScreenTextTests` |
| 15b-7 | Visión solo cuando hace falta | `ScreenNeed` (nuevo), `ClassicRuntime`, `ScreenNeedTests` |
| 15b-8 | Reloj del turno (render) | `ContextBlock`, `ContextBlockTests` |
| 15b-9 | El reloj cuenta desde la última interacción | `ChatPorts`, `ChatViewModel`, `ClassicRuntime`, `InteractionClockTests` |
| 15b-10 | Cortar al pulsar | `TurnMachine`, `VoiceSessionSteer` (nuevo), `VoiceSession` (0 netas), `ClassicRuntime`, `SteerTests` |
| 15b-11 | La nota de corrección | `TurnContext`, `ContextBlock`, `ClassicRuntime`, `ContextBlockTests`, `SteerTests` |

### TDD por entrega (rojo primero)

- **15b-0**: `line()` con `released`+`firstAudio` → `release→audio N`; hold
  clásico → `firstAudio` una vez; anuncio sin hold no marca; camino del modelo
  marca `committed`.
- **15b-1**: FN con modo `.automatic` y campo → agente, inyector vacío;
  `hold(dictate: true)` con campo → pega; sin Accesibilidad →
  `dictationFailed(.needsAccessibility)`; `consumes` Opción derecha → false;
  FN solo → true; flag izquierdo `0x20` con keycode 61 → no arma.
- **15b-2**: `dictationKey` persiste, default `.rightOption`, valor raro → default.
- **15b-3**: `AckPolicy` en caché → específica; sin caché → `quickAck` + warm;
  `prewarm` guarda sin sonar; ya cacheado → cero fetch; `respond(.acted)` sin
  caché → sintetizador "Listo.", hilo "Abrí Safari."; > 80 caracteres → ni
  caché ni prewarm.
- **15b-4**: hold con clave → `prewarm`/`warmConnection` una vez; rebotado → no
  repite; sin clave → nada; `warm()` sin `Authorization` ni cuerpo; el micro no
  espera (`testTheProbeNeverDelaysTheMic`).
- **15b-5**: sensor de 150 ms, hold de 1 s → el commit no espera; `discard` →
  Task cancelada; sin sensor → igual que hoy.
- **15b-6**: 40 cadenas → ≤ 12 snippets ≤ 80, sin duplicados; escapado; sin
  confianza AX → `[]`; la visión gana; sin visión → AX + `pending`; el log solo
  cuenta.
- **15b-7**: "¿qué dice esto?" → 2 s; "abre Safari" con AX → 0; "resume la
  página" sin AX → 2 s; vacío → 0.
- **15b-8**: sin `sinceLastTurn` → sin tag; 7,9 s → `seconds="7"`; 3700 s →
  "hace 1 h"; `<now>` con día y UTC±; el reloj no se recorta.
- **15b-9**: hold a 7 s de un acuse → 7; a 6 min → sin tag, hilo nuevo;
  escrito a 20 s de un hold → 20; primer turno → sin tag; resultado de encargo
  hace 30 s → 30.
- **15b-10**: pulsar en `.thinking` → stream cancelado, cero `enqueue`; en
  `.speaking` → frases viejas no suenan tras `begin()`; cancelar antes del
  handoff → sin `onDelegate`; encargo en curso sigue; parcial al hilo;
  confirmación pendiente + "sí" → se confirma; holds existentes verdes.
- **15b-11**: `<steer>` sale en el turno siguiente y no en el otro; un turno del
  router lo consume; escapado.

---

## 6. Orden recomendado

| Sesión | Entregas | Por qué |
|---|---|---|
| 1 | 15b-0, 15b-1, 15b-2 | medir antes de optimizar; FN nunca pega |
| 2 | 15b-3, 15b-4, 15b-5 | la orden suena en ≤ 1,5 s |
| 3 | 15b-6, 15b-7, 15b-8 | ver la pantalla al pulsar; el tag |
| 4 | 15b-9, 15b-10, 15b-11 | cortar y la nota |

---

## 7. Fuera

| Qué | Disparador |
|---|---|
| TTS en streaming (PCM por chunks) | camino del modelo `release→audio` p50 > 3000 ms tras 15b-4 |
| Fan-out en el down físico (antes de 250 ms) | `press→mic` > 400 ms |
| Cola de 300 ms tras soltar en el clásico | última palabra cortada |
| AX y visión sin clave OpenAI | una usuaria sin clave lo pide |
| Captura libre de la tecla de dictado | alguien necesita otra tecla |
| Borrar `VoiceMode.automatic` | tras 15b-2, con refactor-cleaner |
| Cancelar encargos en marcha con FN | Karen lo pide |
| Caja de texto en Option+Space; brillo; tarjetas nuevas | otra wave |
| Manos libres (realtime) | 14f |

---

## 8. Seguridad

- El tap de dictado no consume eventos: ningún modificador queda pegado.
- El dictado conserva los contratos de 12e (nunca al log ni al modelo, nunca a
  `AXSecureTextField`, pid revalidado).
- El texto AX de pantalla es input no confiable: dentro de `<context>` (DATA),
  escapado, con topes, solo con canal `.screen` y confianza AX; excluye campos
  seguros y ventanas propias; nunca al log ni persistido.
- `warm()` no lleva clave, cuerpo ni datos.
- Caché de TTS por voz en directorio `0700`, solo frases del producto.
- `<steer>` y el reloj son prosa nuestra marcada como DATA; `<now>` sin ubicación.
- Cancelar un turno no cancela aprobaciones ni encargos.

---

## 9. Riesgos

- **15b-10 cambia la concurrencia del clásico** (el turno pasa a ser Task).
  Mitigación: después del arreglo del micro; holds existentes en verde.
- **Opción derecha en teclado español** hace @, #, [ ]: un Opción mantenido
  > 250 ms antes de la otra tecla abre y descarta el micro. Mitigación: el
  acorde descarta sin commit y la tecla es configurable.
- **El acuse corto puede sonar genérico** la primera vez por app y voz.
- **Presupuesto de `VoiceSession.swift`**: +4 líneas netas.
- **AX lento en apps pesadas**: timeout por llamada, tope de nodos, todo al pulsar.

---

## 10. Done (en vivo, Karen)

Prerrequisitos: Grabación de pantalla y Accesibilidad concedidas; "Decidir en
local" encendido; Ollama corriendo.

1. Cursor en Terminal, FN, "abre Safari": abre Safari y no pega nada.
2. Cursor en Notas, Opción derecha, "hola qué tal": se pega en Notas.
3. 10 holds "abre X": `release→audio` p50 ≤ 1500 ms, p90 ≤ 2000.
4. Delante de Safari, FN, "¿qué dice el titular?": cita un texto visible. Con
   "abre Mail", la visión no retrasa el turno.
5. FN mientras responde un párrafo, "no, más corto": se corta, no repite.
6. Encargo en marcha, FN y otra pregunta: el encargo sigue.
7. Dos holds a 7 s: `seconds="7"`. A los 6 min: hilo limpio, sin tag.
8. Gates verdes; `VoiceSession.swift` ≤ 800 líneas.

---

## 11. Aprobación

Una pregunta: **¿Opción derecha como tecla de dictado por defecto?** Un solo
modificador como FN, sin atajo de sistema, y Option+Space queda libre. Si usas
Opción derecha para @ o #, la alternativa es Command derecho. Las dos quedan
elegibles en Ajustes.

Decisiones del planner que Karen puede revertir: FN no cancela un encargo ya
en marcha; si el acuse no está en caché suena "Listo." primero; la visión sigue
subiendo al pulsar pero no se espera si la orden no señala la pantalla; el AX
de pantalla entra como snippets y en v1 solo con clave de OpenAI.
