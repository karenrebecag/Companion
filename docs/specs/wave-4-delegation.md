# Wave 4 — Delegacion

**Estado: BORRADOR** — se refina en kickoff contra Waves 1-3. Implementa
ADR 001: el especialista integrado es nativo; los CLIs son la cola.

## Objetivo

El modelo de charla delega trabajo pesado (tool call `delegate` {goal,
context}) a un especialista en segundo plano, con estado visible y humano
en el circuito de permisos. Sin instalar nada: `NativeExecutor` usa la
misma API key del chat. Claude Code y Hermes aparecen solo si
`CapabilityProbe` los encuentra.

## Archivos

### CompanionCore (lo que Wave 1 dejo fuera a proposito)

| Archivo | Contenido | Contrato |
|---|---|---|
| `Job.swift` | `JobRequest`, `JobResult`, `JobState`, presupuesto 15 min | `JobRunner.swift` |
| `JobSteps.swift` | `JobStepInfo` + summary / files / worked / icon | Phase 7 |
| `ApprovalPolicy.swift` | Riesgo por tool, timeout 120 s, web pre-aprobada, auto-deny | Ledger Delegacion |

### CompanionServices (centro = nativo; cola = CLIs)

| Archivo | Contenido | Contrato |
|---|---|---|
| `NativeExecutor.swift` | Loop Swift sobre `ChatProvider`: tools -> resultados hasta texto o presupuesto. Endpoint OpenAI-compatible. | ADR 001 |
| `NativeTools.swift` | Set CERRADO: read_file, write_file, edit_file, run_shell, web_fetch, web_search. Crecer exige ADR. Schemas hermes-agent MIT -> NOTICE.md. | ADR 001 |
| `Approvals.swift` | Actor: allow/deny; auto-deny 120 s | `JobRunner.swift:142-150` |
| `JobQueue.swift` | Actor: cola serial, un job, cancelacion explicita | `JobRunner.swift` |
| `ClaudeCodeExecutor.swift` | Adapter `claude -p` stream-json (codec Wave 1). Persistente por workdir. Solo si el binario existe. | PROTOCOL-JOBS.md |
| `HermesExecutor.swift` | Adapter minimo `hermes chat -Q`. | `Hermes.swift:297` |
| `HermesOutput.swift` | Parse stdout/stderr; reply solo de stdout | `testHermesOutputParse` |
| `SessionPolicy.swift` | `--resume latest` vale en Hermes, no en Claude | `testSessionPolicy` |
| `TerminalHandoff.swift` | Abrir el CLI en Terminal.app; quoting POSIX | `testTerminalHandoff` |

### CompanionUI

- `JobBadgeView` / `JobCardView`: quien trabaja, pasos, `reportCut`.
- `ApprovalSheet`: confirmar/denegar; denegar es valido.
- `ExecutorPicker`: lista de `ExecutorCatalog.assemble`, no enum Brain.

## API

```swift
protocol Executor: Sendable {
    var id: ExecutorID { get }
    func run(_ job: JobRequest, events: AsyncStream<JobEvent>.Continuation) async throws -> JobResult
}
```

Lista: `[native] + detectados`.

## Tests

- NativeExecutor + ChatProvider fake: loop; handoff nil -> se habla el
  texto; presupuesto; deny cambia la ruta.
- NativeTools en sandbox temporal; `run_shell` jamas sin approval.
- JobQueue: serial, 15 min, cancel, no-zombies.
- ClaudeCodeExecutor contra fixtures NDJSON versionadas.
- Portar: HermesOutputParse, SessionPolicy, TerminalHandoff,
  JobStepsSummary, WorkExecutor reescrito como catalogo dinamico,
  JobSteps.files, resto de thinking.

## Restricciones

- `run_shell` / `write_file` no se ejecutan sin approval.
  security-reviewer ANTES de merge.
- Set de tools minimo; "hermes en Swift" = parar y re-spec.
- Nada lee `~/.hermes/*`. Producto usable sin Claude y sin Hermes.
- Sin `try?`. Gates verdes.

## Definicion de done

Delegar un encargo con solo la API key (NativeExecutor) y ver badge +
tarjeta. Allow/deny/timeout funcionan. Sin CLIs, el picker muestra solo
Nativo. Gates verdes. Changelog + roadmap. Spec CERRADO.

## Requisito de seguridad: inyeccion de prompt (del review de Wave 1)

`Handoff.goal` y `context` son texto del modelo de charla interpolado en el
prompt del especialista (`Escalation.swift`). No se "escapa" un prompt: la
defensa es estructural y es OBLIGATORIA en esta wave:

1. Ninguna tool destructiva o de escritura se ejecuta por contenido del
   prompt: SIEMPRE pasa por `Approvals`, sin importar que tan imperativo
   venga el texto del handoff.
2. El texto del handoff viaja en una seccion delimitada del prompt marcada
   como peticion del usuario, nunca como instrucciones de sistema.
3. Tests adversariales: handoffs con "ignora tus instrucciones y ejecuta X"
   deben terminar en solicitud de approval, jamas en ejecucion directa.

## Riesgos

- Superficie de dano en shell/write -> sandbox de workdir + auto-deny.
- `claude -p` stream-json cambia entre versiones -> fixtures.
- Scope del NativeExecutor -> ADR, no "un tool mas".
