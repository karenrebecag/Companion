# Wave 4 — Delegacion

**Estado: CERRADO (4a)** — 2026-08-21. El especialista nativo funciona de
punta a punta desde texto y desde voz. Falta la prueba manual de Karen y la
tanda 4b (adapters de Claude Code y Hermes).

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

## Decisiones tomadas

- **D1 — Alcance de archivos: carpeta de trabajo elegida por la usuaria.**
  Es el punto del producto ("arregla este proyecto"), no un sandbox de
  juguete. Vive en `Config.workdir`; NUNCA se lee del entorno ni se
  hardcodea una ruta personal (el repo es publico). Sin carpeta configurada,
  el especialista puede leer y buscar, pero no escribir ni ejecutar.
  Toda ruta fuera de la carpeta de trabajo se rechaza antes de tocar disco.
- **D2 — Aprobar SOLO por dialogo en esta wave.** El prototipo permitia
  decir "si"; con lo aprendido en Wave 3 sobre reconocimiento de voz, un
  falso positivo ejecutaria algo real. La voz anuncia que hay un permiso
  pendiente y pide ir a la ventana. Reevaluar despues de v1.
- **D3 — `run_shell` entra en 4a**, detras de approvals y con la carpeta de
  trabajo como directorio de ejecucion.

## Requisito heredado del tramo 1 (obligatorio en el tramo 2)

`PathValidator` (Core) valida de forma LEXICA: resuelve `..` y exige que la
ruta caiga dentro de la carpeta de trabajo. Eso no basta: un symlink dentro
de la carpeta que apunte fuera pasaria la validacion. Como Core es puro y no
puede consultar el disco, la segunda barrera vive en Services, al ejecutar
la tool: resolver la ruta real (`resolvingSymlinksInPath`) y volver a exigir
que siga dentro de la carpeta. Doble barrera, con test que cree un symlink
en un directorio temporal y confirme el rechazo.

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

## Cierre de 4a (2026-08-21)

Entregado: nucleo de encargos (tipos, puerto, cola serial con presupuesto y
cancelacion), registro cerrado de seis tools con doble barrera de rutas,
actor de permisos con auto-denegacion, loop del agente nativo, coordinador,
y cableado real desde texto y desde voz con hoja de aprobacion.

Correcciones sobre lo entregado por los agentes, todas por revision con grep
y lectura (los tests verdes no las mostraban):
- La cola descartaba el resultado del encargo (delegar no devolvia nada), no
  se podia cancelar y el presupuesto solo corria si llegaban eventos.
- Los permisos estaban cableados a denegar siempre ("mock por ahora").
- El loop no podia invocar tools contra el proveedor real, y el ciclo de
  tool calling viajaba sin el identificador que exige la API.
- La UI mostraba "esperando aprobacion" sin ninguna forma de aprobar: todo
  terminaba en la auto-denegacion a los 120 s.
- La voz seguia contestando que la delegacion no estaba disponible.
- Un test dormia 120 s reales y tumbaba pruebas de voz ajenas.

Pendiente de prueba manual: delegar una lectura, aprobar una escritura,
denegar, y cancelar a media ejecucion.
