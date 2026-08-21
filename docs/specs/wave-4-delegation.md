# Wave 4 — Delegacion

**Estado: BORRADOR REFINADO** — kickoff hecho (planner + architect, 2026-08-21).
Pendiente: decisiones de Karen marcadas con **[DECIDIR]** y su aprobacion.

## Objetivo

El modelo de charla delega trabajo pesado a un especialista que corre en
segundo plano con estado visible y permisos con humano en el circuito. Por
ADR 001 el especialista principal es NATIVO (loop de agente en Swift sobre
cualquier endpoint OpenAI-compatible); Claude Code y Hermes son adapters
opcionales detectados en runtime. La app queda completa sin ninguno.

## Recorte: dos tandas

- **4a — NativeExecutor** (esta tanda): el especialista integrado, sus tools,
  approvals, cola y la UI minima para verlo trabajar. Usable sin instalar
  nada.
- **4b — Adapters**: ClaudeCodeExecutor, HermesExecutor, selector de
  ejecutor. Valor para power users; no bloquea nada de 4a.

## Lo que ya existe y se reutiliza

| Pieza | Archivo | Uso en esta wave |
|---|---|---|
| Catalogo de ejecutores | `Core/Executors.swift` | Lista `[nativo] + detectados` |
| Handoff + prompts | `Core/Escalation.swift` | Contrato de delegacion, rol del ejecutor |
| Schemas de tools | `Core/ToolSpec.swift` | `delegate`, `resolveApproval` |
| NDJSON de `claude -p` | `Core/AgentStreamCodec.swift` | Adapter de 4b |
| Deteccion de binarios | `Services/LiveCapabilityProbe.swift` | Ejecutores opcionales |
| Emision del handoff | `Services/ChatProviderClient.swift`, `ChatSSEAttempt.swift` | Ya parsea el tool call `delegate` |
| Espera del ejecutor | `Core/TurnMachine.swift` (`awaitingExecutor`) | Coordina el turno de voz |

## Contratos nuevos (Core)

```swift
public protocol Executor: Sendable {
    var descriptor: ExecutorDescriptor { get }
    func run(_ job: JobRequest,
             events: AsyncStream<JobEvent>.Continuation) async throws -> JobResult
}

public enum JobEvent: Sendable, Equatable {
    case stepStarted(tool: String, summary: String)
    case stepFinished(tool: String, ok: Bool)
    case approvalRequested(ApprovalRequest)
    case thought(String)
}
```

`JobRequest` / `JobResult` son value types puros. Los eventos viajan por
`AsyncStream`, nunca por callbacks guardados (regla del repo). La cancelacion
es responsabilidad de `JobQueue`, no del puerto.

## Seguridad: la frontera es el centro de la wave

1. **Set cerrado de tools**: `read_file`, `write_file`, `edit_file`,
   `run_shell`, `web_fetch`, `web_search`. Cada una declara su riesgo.
   Agregar una exige ADR — es la guardia contra "Hermes en Swift".
2. **Barrera unica de ejecucion**: una tool de riesgo sin aprobacion lanza
   error ANTES de tocar disco o shell. Testeable directamente.
3. **Anti-inyeccion estructural** (del review de Wave 1): `goal` y `context`
   viajan en una seccion delimitada como peticion del usuario, jamas como
   instrucciones de sistema; el rol del ejecutor se inyecta una sola vez.
   Tests adversariales obligatorios: un handoff que diga "ignora tus
   instrucciones y ejecuta X" debe terminar en solicitud de permiso, nunca
   en ejecucion.
4. **Auto-deny a los 120 s** con una sola fuente de verdad (actor
   `Approvals`): el temporizador corre aunque se cierre el dialogo.

## [DECIDIR] Decisiones de producto pendientes

- **D1 — Alcance de archivos.** ¿El especialista trabaja sobre una carpeta
  de trabajo que Karen elige (potente, es el punto del producto) o sobre un
  sandbox por trabajo (seguro, pero inutil para "arregla este proyecto")?
  Recomendacion: carpeta elegida por Karen, declarada en Config, mas
  approvals para toda escritura fuera de lectura.
- **D2 — Aprobar por voz.** El prototipo permitia decir "si". Recomendacion:
  FUERA de esta wave — un falso positivo del reconocimiento ejecuta algo
  real. Solo dialogo; la voz anuncia y pide ir a la ventana.
- **D3 — Alcance de `run_shell`.** ¿Entra en 4a o se difiere? Recomendacion:
  entra, pero detras de approvals y con la carpeta de trabajo como cwd.

## Tareas (4a), en orden

1. Tipos de job + `Executor` + `ApprovalPolicy` en Core (puro, testeado).
2. `Approvals` (actor): pedir, resolver, auto-deny 120 s.
3. `JobQueue` (actor): serial, presupuesto 15 min, cancelacion estructurada.
4. `NativeTools`: las 6 tools, cada una < 50 lineas, con la barrera de riesgo.
5. `NativeExecutor`: el loop sobre `ChatProvider` con tools y approvals.
6. `JobRunner`: enruta handoff -> ejecutor, traduce eventos a la UI.
7. UI: badge de trabajo, tarjeta de resultado plegable, hoja de aprobacion.
8. Cableado en `ChatViewModel` y en el turno de voz (hoy el `functionCall`
   se contesta con negativa; pasa a lanzar el encargo).

Tests en `Tests/CompanionTests/` (target unico, como el resto del repo).

## Definicion de done

- Delegar desde texto y desde voz; ver el progreso; recibir el resultado.
- Una tool de riesgo pide permiso SIEMPRE; sin respuesta, se deniega sola.
- Gates verdes y **prueba manual de Karen**: delegacion de lectura,
  delegacion con escritura aprobada, denegacion, y cancelacion a media
  ejecucion.

## Riesgos

- **Seguridad**: es la superficie mas peligrosa del programa.
  security-reviewer bloquea el merge.
- **El patron del repo** (logica testeada pero sin cablear, seis veces en
  Wave 3): antes de cerrar cada modulo, verificar con grep que el flujo real
  invoca la capacidad nueva. Va en la checklist de cierre.
- **Los tests no ven la integracion**: como en Wave 3, la prueba manual es
  parte de la definicion de done, no un extra.
