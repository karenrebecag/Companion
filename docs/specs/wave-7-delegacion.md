# Wave 7 — Delegación de verdad · CERRADA

Estado: CERRADA (7a + 7b, 2026-08-21)
Origen: prueba manual de Karen — "crea un archivo prueba1.md en mi
escritorio" terminó en `Job failed: processLaunchFailed` pintado crudo en el
hilo mientras la voz prometía "voy en camino". Comparación pipeline contra
pipeline con el prototipo (`../companion`).

## Goal

Que un encargo delegado por voz termine en trabajo real, con narración
honesta del resultado y línea de tiempo visible — la conducta que el
prototipo ya tenía y el rebuild portó solo como esqueleto.

## 7a — El cable (commit `aa97056`)

Lo roto, verificado contra el prototipo:

| Falla | Causa | Fix |
|---|---|---|
| `processLaunchFailed` | Ruta hardcodeada `/usr/local/bin/claude`; claude vive en `~/.local/bin` | `CLIBinaryLocator`: candidatos por sistema de archivos (`~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`) |
| Detección mentirosa | `which` en subproceso: una app GUI no hereda el PATH del shell | Probe consulta el locator, no un shell |
| Proceso moría en argparse | `-m` no es flag de claude | `--model opus` (como el prototipo) |
| Sin eventos del stream | Faltaba `--verbose` (obligatorio con stream-json en `-p`) | Flag añadido |
| Aprobaciones jamás llegaban | Faltaba `--permission-prompt-tool stdio` | Flag añadido |
| Especialista sin contrato | Faltaba `--append-system-prompt` con el rol | `Escalation.executorRole` viaja al lanzar |
| NDJSON roto | `readLine` entregaba bloques de 4096 bytes del pipe | `LineBuffer` (Core) + readabilityHandler → AsyncStream de líneas |
| Proceso por encargo, huérfano | Se lanzaba uno nuevo cada vez y nunca se terminaba | Persiste entre encargos; se rearma si murió; se mata al cancelar |
| Hermes colgado para siempre | Prompt por stdin; hermes lo espera como argumento | `chat -Q -q <prompt>`, rol pegado al prompt |
| Adjuntos ignorados | `JobRequest.attachments` no viajaba | Rutas en el turno vía `Escalation.jobPrompt` |

## 7b — El circuito de vuelta

- **Announce**: `VoiceSession.jobAnnounce` + cola `pendingAnnouncements`.
  El resultado del encargo se inyecta como system item + `response.create`
  SOLO en listening; si el agente habla o piensa, espera su turno (portado
  de `RealtimeVoice.announce/flushAnnouncements` del prototipo). Sin sesión
  de voz viva se descarta: el hilo ya lo muestra.
- **Errores en humano**: `JobRunner.failureText` mapea presupuesto/
  cancelación/launch a español de pantalla; `Escalation.jobFailedStatus`
  narra el fallo con el goal. El error interno va al log, nunca al hilo.
- **Un solo seam de eventos**: `ChatViewModel.receiveJobEvent` (antes
  `...ForTesting`) pinta pasos, pensamientos y aprobaciones; los encargos
  por voz lo alimentan vía `onJobEvent` cableado en el composition root.
  El puente ya no drena y tira los eventos.

### Por qué no hay JobTimelineView nueva

Los pasos pintan como líneas de status en el hilo — el mismo mecanismo que
el camino de chat ya usaba, ahora compartido. Una tarjeta dedicada (JobCard
del prototipo, con paso vivo y duración) queda como mejora de UI aparte:
ThreadView está siendo editada por otra sesión en este momento y el valor
diferencial es visual, no funcional.

## Constraints respetadas

- TDD: RED verificado antes de cada fix (LineBuffer, locator, contrato del
  cable, circuito de announce).
- Prototipo como referencia de conducta, reescrito al patrón del repo.
- Gates verdes antes de cada commit; 160 tests.

## Pendiente (post-wave, anotado)

- Reanudar la sesión del especialista entre arranques de la app
  (SessionStore del prototipo); hoy `sessionId` se captura pero no se reusa.
- Fallback batch si el cable stdio muere a media tarea (el prototipo caía a
  `Hermes.ask`); hoy el encargo se reporta fallido en humano.
- JobCard visual con paso vivo y duración.
