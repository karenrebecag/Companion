# Wave 15a — Conversación efímera

**Estado: APROBADA / EN CURSO (2026-09-23).** Karen: "perfecto, implementa. totalmente limpia" — §10 resuelto: al volver a la ventana tras 5 min, ya limpia (se queda el disparo en `applicationDidBecomeActive`). Sin commit.

Karen: "la responsabilidad del agente default es completar tareas… después
de n minutos, limpiar la conversación… no quiero tener que abrir una nueva
conversación cada que quiera abrir una ventana."

Criterio de done: hablar o escribir tras 5 min sin actividad arranca con el
modelo en limpio; dentro de los 5 min se conserva el seguimiento; gates verdes.

---

## 1. El defecto, medido

**A. El hilo resucita en cada arranque.** `onAppear` / `acceptLocalBase` →
`loadMostRecent()` (`ChatViewModelStartup.swift:15`, `:66`, `:71`) restaura
**siempre** el hilo más reciente (`ChatViewModel.swift:623-631`), sin mirar
cuánto hace de él: `restore()` descarta `record.updatedAt`
(`ChatViewModel.swift:633-641`).

**B. Todo ese hilo va al modelo.** `windowedTurns()`
(`ChatViewModel.swift:570-602`) manda hasta `historyWindow = 20` turnos
(`Config.swift:203`) más una nota de compactación. Los tres caminos leen del
mismo hilo:

| Camino | Dónde entra el turno | Qué historial manda |
|---|---|---|
| Escrito | `startTurn` (`ChatViewModel.swift:331-347`) | `sensedHistory` → `windowedTurns` |
| Hold FN (texto, 14b) | `ClassicRuntime.submit` → `thread.appendUser(heard, context:)` (`ClassicRuntime.swift:118`); router `thread.appendUser(heard)` (`:223`) | `thread.historyTurns()` (`:119`) |
| Manos libres (realtime) | `RealtimeRuntime.commitWithText` → `thread.appendUser` (`RealtimeRuntime.swift:181`) | semilla en `instructions` al abrir: `VoiceSession.swift:555-558` → `prepareSessionUpdate(history:)` (`RealtimeRuntime.swift:123-135`) |

`thread` es el mismo `ChatViewModel` (`CompanionMain.swift:289`, `:338`).

**C. Cerrar no limpia.** Cerrar la ventana no cierra la app
(`CompanionMain.swift:453-457`): el hilo en memoria sigue. Cmd+Q y reabrir lo
restaura desde disco (A).

**D. Lo único que limpia es manual.** `newConversation()`
(`ChatViewModel.swift:240-251`), desde el header (`HeaderView.swift:197-203`),
el menú (`AppMenu.swift:115` → `CompanionMain.swift:437-440`) y el atajo
(`CompanionRootView.swift:179-181`). Archiva vía `persist()` y abre un id
nuevo; el archivo queda en `ConversationStore` (tope 30) y en el Historial.

**E. El reloj persistido ya existe.** `persist()` escribe `updatedAt: Date()`
en cada mutación (`ChatViewModel.swift:653`), guardado en el JSON
(`ConversationStore.swift:173`). No hace falta campo nuevo.

**No es contexto residual del hilo:** la memoria entre sesiones (9j-2,
`FileMemoryStore`), inyectada en el prompt de sistema
(`StoredConfigProvider.swift:48-52`). Existe a propósito; no se toca.

---

## 2. Incredible, medido (no copiado)

- Lleva contexto entre holds y le dice al modelo el hueco
  (`<time_since_last_interaction>… 7 seconds ago…`,
  `Documents/Incredible-Debug/2026-09-04/logs/app.log:238`, `:266`).
- La superficie es un **panel por activación** con tarjetas (`:277`), no un
  transcript de chat persistente.
- **No se observa regla de reset** (la captura cubre ~20 s). Los 5 min son
  decisión de producto nuestra.

---

## 3. Decisión

**Contexto efímero por inactividad: el hilo viejo se archiva y la vista
arranca limpia.**

| Decisión | Por qué |
|---|---|
| `idleLimit = 300 s`, constante en Core, sin UI | Karen pidió n minutos; Settings no aporta hasta que alguien pida otro valor |
| Reloj = última escritura del hilo (`updatedAt` / `lastActivity`) | ya persistido; una respuesta o un resultado de encargo reinician el reloj |
| Se evalúa al **entrar un turno** y **al arrancar**, no con un timer | el turno ve lo que un timer no (encargo vivo, aprobación) |
| **Archivar** (id nuevo, hilo vacío), no "log visible con contexto cortado" | reutiliza `newConversation` y el Historial sin campo nuevo; cortar solo el contexto deja en pantalla lo que el modelo ya no sabe; Incredible pinta un panel fresco por activación |
| El rollover **no** llama `persist()` | si re-estampara `updatedAt`, un arranque sin hablar renovaría el hilo viejo y **nunca caducaría** |
| Conserva `draft` y `pendingAttachments` | son del turno que dispara el rollover |
| `newConversation()` manual: sin cambios | sigue siendo el reset inmediato |

**Guardas (bloquean el rollover):**

| Guarda | Fuente | Por qué |
|---|---|---|
| encargo corriendo | `session.projection.job != nil` (`SessionTypes.swift:51`) | el resultado llega por `thread.appendAssistant` (`VoiceJobBridge.swift:60`) |
| aprobación pendiente | `!session.projection.approvalQueue.isEmpty` (`SessionTypes.swift:54`) | la hoja respondería en otra conversación |
| turno escrito en curso | `busy` | no pisar el `conversationId` de un `inFlight` |
| sesión realtime viva | `pipeline == .realtime && voice ∈ {.live, .muted}` | el servidor ya tiene la semilla; se evalúa al abrir la siguiente |
| voz en curso (solo al activar la app) | `kind ∉ {.idle, .hover}` | desde el embudo, el turno de voz es quien llama |

**Confirmación por voz (DM1c):** `DecisionGate.pending` vive en su actor y no
lee el hilo; su TTL (60 s) es menor que `idleLimit`. **Invariante:** si
`confirmationTTL` sube por encima de `idleLimit`, esta spec se revisa.

---

## 4. API (Core, pura)

```swift
public struct ConversationActivity: Sendable, Equatable {
    public var lastActivity: Date?
    public var turnInFlight: Bool
    public var jobRunning: Bool
    public var approvalsPending: Bool
    public var liveRealtime: Bool
}

public enum ConversationRollover {
    public static let idleLimit: TimeInterval = 300
    /// nil lastActivity, any open work, or a clock that went backwards → false.
    public static func shouldRollover(
        _ activity: ConversationActivity, now: Date,
        limit: TimeInterval = idleLimit
    ) -> Bool
}
```

ChatViewModel: reloj inyectado `now` (default `Date()`); `lastActivity`
(lo fija `persist()` y `restore(record)`; `nil` con hilo vacío);
`private func rollOver()` (id nuevo, `messages = []`, `streaming = ""`,
`lastActivity = nil`, log sin contenido, sin `persist()`). Disparos:
`startTurn`, `appendUser(_:context:)` (con `appendUser(_:)` delegando en él),
`historyTurns()` (semilla realtime), `loadMostRecent()` y
`rolloverIfIdle()` desde `applicationDidBecomeActive` (pendiente de §10).

VoiceSession: en `openRealtimeSession`, la semilla (`historyTurns`) se lee
**antes** de contar `sessionStartTurns` (`VoiceSession.swift:555-558`, dos
líneas reordenadas) para que el resumen de memoria al colgar no se salte la
sesión nueva.

---

## 5. Archivos (tope 5)

| Archivo | Qué |
|---|---|
| `Sources/CompanionCore/ConversationRollover.swift` | nuevo: política pura |
| `Sources/CompanionUI/ChatViewModel.swift` | reloj, `lastActivity`, `rollOver`, disparos (~30 líneas) |
| `Sources/CompanionServices/VoiceSession.swift` | reordenar 555 ↔ 556-558 (sin crecer) |
| `Sources/CompanionApp/CompanionMain.swift` | `rolloverIfIdle()` al activar (sale si Karen elige la otra opción) |
| `Tests/CompanionTests/ConversationRolloverTests.swift` | nuevo |

---

## 6. TDD (rojo primero)

| # | Test | Espera |
|---|---|---|
| 1 | `lastActivity == nil` | false |
| 2 | 299 s / 300 s | false / true |
| 3-5 | 1 h idle + encargo / aprobación / turno en curso / realtime vivo | false |
| 6 | reloj hacia atrás | false |
| 7 | escrito a +6 min | id nuevo; hilo viejo en `store.list()` con su `updatedAt` original |
| 8 | escrito a +2 min | mismo id, seguimiento con contexto |
| 9 | `appendUser` (ambas firmas) a +6 min | rollover por el mismo embudo |
| 10 | encargo empezado y +6 min | sin rollover; tras el resultado: +2 min no, +6 min sí |
| 11 | aprobación en cola y +6 min | sin rollover |
| 12 | arranque con registro de hace 10 min / 1 min | hilo vacío / restaurado |
| 13 | arranque caducado sin hablar, segundo arranque | `updatedAt` del viejo intacto |
| 14 | `historyTurns()` caducado | `[]` |
| 15 | manos libres tras caducar: abrir, intercambio, colgar | resumen de memoria escrito |
| 16 | rollover con draft y adjunto | sobreviven |
| 17 | `rolloverIfIdle()` con `kind == .processing` / `.idle` | no / sí |
| 18 | realtime `.live` / `.connecting` | no / sí |
| 19 | `newConversation()` manual | igual que hoy |

---

## 7. Fuera

UI de Settings para N; timer en segundo plano; memoria entre sesiones;
cortar una sesión realtime viva; `<time_since_last_interaction>` (otra
tanda); cambiar `historyWindow`, compactación o `ConversationStore`; tocar
`DecisionGate`.

---

## 8. Seguridad

- El log del rollover no lleva texto, título ni id: solo el hecho.
- No borra nada: el hilo viejo sigue en disco con la poda de hoy.
- Ninguna aprobación ni encargo cambia de conversación (guardas).
- Un reloj atrasado solo impide un rollover, nunca lo fuerza.

---

## 9. Done

1. "Abre Safari" por FN; 6 min después "¿y ahora qué abriste?": hilo nuevo,
   el anterior en Historial.
2. Lo mismo a los 2 min: responde con contexto.
3. Cmd+Q y reabrir tras 6 min: ventana limpia sin tocar "Nueva conversación".
4. Encargo de más de 5 min: el resultado llega a su hilo; seguimiento a los
   2 min con contexto.
5. Hoja de permiso abierta 10 min: sigue en su conversación.
6. Gates verdes.

---

## 10. Aprobación

Una pregunta: **al volver a la ventana después de 5 min, ¿la quieres ya
limpia (lo anterior queda en Historial) o que el hilo viejo siga visible
hasta que hables o escribas?** Propuesta: limpia.
