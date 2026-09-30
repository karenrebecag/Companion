# Wave 20c — Endurecimiento: una aprobación la contesta la usuaria, no el modelo

**Estado: APROBADO (2026-09-29).** Karen: "dale todo" — A–G en un worktree dedicado, secuencial, un PR al final.

Origen: auditoría de seguridad de la superficie mergeada (2026-09-29, VERDICT WARNING critical=0 high=4) y auditoría del harness. Cada hallazgo entra con su test en rojo primero (regla de la casa), nunca fix directo.

## 1. La raíz

Los 4 HIGH son una sola idea: **donde el propio modelo puede contestar la pregunta de permiso, la respuesta no vale.** Una inyección desde una página, una pantalla que `see`, una celda de Excel o el texto de un conector puede empujar al modelo a auto-aprobarse. Y donde la hoja sí la contesta la usuaria, a veces no muestra lo que autoriza.

## 2. Los fallos (archivo:línea en `47aa09d`)

| # | Fallo | Evidencia |
|---|---|---|
| F1 (H1) | En la voz, `resolve_approval` deja que el modelo apruebe la petición de la cola. El único freno es el prefijo `app:`; pasan `run_shell`/`write_file`/`create_document`/`sheet_write` de un job, un click destructivo, un `type_text` en terminal y **la hoja del puente que entrega las manos**. La nota `pendingApproval` no se limpia al aprobar por clic, así que un `resolve_approval(true)` inyectado más tarde aprueba lo primero de la cola. | `VoiceSessionApprovals.swift:28-58` (guard solo `app:` en :47); `VoiceSession.swift:249-284` (nunca limpia la nota); `SessionMachine.swift:95-98` (resuelve el PRIMERO de la cola, no la nota); `RealtimeCodec.swift:197`; la hoja del puente entra a la misma cola (`BridgeHost.swift:36-38`) |
| F2 (H2) | Los permisos de los MCP propios no tienen hoja: se aprueban con el booleano del modelo y corren del lado de OpenAI. `requireApproval:"always"` lo satisface el propio modelo. | `RealtimeRuntime.swift:269-282`; `VoiceSessionApprovals.swift:31-36`; `MCPTools.swift:42` |
| F3 (H3) | `menu` no tiene puerta destructiva. `click` en Borrar/Enviar/Pagar pide hoja; `menu("Finder > Vaciar papelera")`, "Enviar", "Cerrar sesión" corren sin hoja. Alcanzable desde el puente, chat y voz. | `ParentToolRunnerSight.swift:162-171` (sin ticket ni familia); `ParentToolHands.swift` (`default` → `.act`) |
| F4 (H4) | La hoja de `sheet_write` corta `values` a 200 caracteres de hasta 5.000 celdas; la promesa de "la hoja muestra lo que corre" (`ChatCopy.swift:598`) no se cumple. "Recordar" la vuelve un cheque en blanco por rango, compartido chat/voz, y no nombra el libro. | `Sheets.swift:171-184`; `ApprovalMemory.swift:45-52` |
| F4b (M4) | La lista negra de fórmulas deja pasar `IMAGE(` (exfiltra por URL), `STOCKHISTORY(`, `COPILOT(` y referencias externas `='/Users/x/[secreto.xlsx]'!A1` o `\\host\share` (lee otros archivos y los devuelve en la relectura). `XLSXWriter` escribe como fórmula viva cualquier celda que empiece con `=`. | `Sheets.swift:99-100`; `XLSXWriter.swift:148-149` |
| F4c (M6/M7) | `create_document` sobrescribe un `.pdf`/`.xlsx` existente sin backup; "recordar" es por carpeta (`dir/*`). `sheet_write` lee la ruta y escribe en dos Apple Events distintos contra "active sheet": el libro activo puede cambiar en medio, y el backup puede ser de otro libro. | `NativeToolRunnerDeliverables.swift:8-38`; `ApprovalMemory.swift:53-57`; `AppleEventSheets.swift:32-47` |

Los MEDIUM restantes (M1 estado del puente por conexión, M2 timeout/cool-down/peer pid, M3 ticket de click ligado a nodo+etiqueta+generación, M5 tokens a Keychain, M8 idempotencia+presupuesto de lecturas, M9 allowlist del puente) y los LOW van en D5–D7.

## 3. Decisiones (firma Karen)

- **D1 (F1) — La ruta hablada solo resuelve lo de bajo riesgo, y siempre por la petición exacta.**
  - `resolve_approval` (voz/modelo) solo puede resolver peticiones de bajo riesgo (`open_url` a un host dicho, `find_places`, lecturas). **Nunca** `bridge_session`, escrituras (`write_file`/`edit_file`/`create_document`/`sheet_write`), `run_shell`, entregables, click destructivo, `type_text` en terminal, ni `menu` destructivo: esas exigen clic en la hoja.
  - La respuesta se liga al `requestId` exacto que muestra la hoja, no a "la última nota".
  - La nota se limpia en cualquier resolución (clic incluido).
  - La confirmación hablada se valida contra lo que se oyó (`SpokenConfirmation.reading`), no contra un booleano del modelo.
  - Alternativa descartada: ampliar el guard `app:` a más prefijos. Es una lista negra; la volvemos allowlist de bajo riesgo.
- **D2 (F2) — Los MCP propios pasan por la misma hoja.** Nada de booleano del modelo. Una llamada a un MCP propio abre la hoja de siempre (o exige confirmación hablada verificada). Se ignora `requireApproval:"never"` venido del archivo.
- **D3 (F3) — `menu` pasa por la puerta de `click`.** Los últimos componentes del path se corren por la misma `destructiveFamily` y el mismo ticket; si coincide, pide hoja. Igual desde el puente.
- **D4 (F4+F4b+F4c) — La hoja de hojas y documentos muestra lo que autoriza.**
  - `sheet_write`: la hoja muestra los valores completos (o un resumen con hash + conteo de celdas), nombra el **libro** (ruta) y verifica que sigue siendo el mismo al escribir.
  - "Recordar" en escrituras: la clave incluye el hash de los valores y la ruta del libro, o se desactiva "recordar" para escrituras.
  - Fórmulas: se pasa de lista negra a **allowlist** de funciones seguras; se rechazan `[`, `!`, `'` y referencias externas; `IMAGE`/`STOCKHISTORY`/`COPILOT` fuera. En `.xlsx` el texto va como cadena en línea salvo que la usuaria pida fórmula.
  - `create_document`: no sobrescribe en silencio — hace backup primero (como `sheet_write`) o rechaza; la clave de "recordar" incluye el nombre del archivo.
- **D5 (M1/M2/M3) — Puente y tickets robustos.** Estado de autenticación por conexión (no por proceso); reset de política síncrono antes de liberar el slot; timeout de inactividad de la sesión; cool-down o auto-apagado tras N denegaciones; el peer pid + firma en la hoja del puente; el ticket de `click` liga nodo + etiqueta + generación del scan.
- **D6 (M5/M8/M9) — Config y presupuesto.** Endpoint de `companion-apps` y tokens MCP al Keychain, la clave ligada al host; el puente deduplica por `(conexión, id)` y cubre las tools de estado; presupuesto separado de lecturas/`see`; el puente pasa de lista negra a **allowlist** con un test que falla cuando aparece una tool nueva.
- **D7 (LOW) — Limpieza.** Borrar `VoiceAuditReport.verdict` (código muerto que loguea transcripción literal); sanear los strings de wire y de error antes de loguear; la clave de `open_url` incluye esquema y puerto; rotación/tope del log.

## 4. Entregas (una rama por PR; test en rojo primero)

| PR | Cubre | Prioridad |
|---|---|---|
| A | D1 (H1) — la raíz | **obligatorio** |
| B | D2 (H2) | **obligatorio** |
| C | D3 (H3) | **obligatorio** |
| D | D4 (H4+M4+M6+M7) | **obligatorio** |
| E | D5 (M1+M2+M3) | recomendado |
| F | D6 (M5+M8+M9) | recomendado |
| G | D7 (LOW) | oportunista |

A–D cierran los 4 HIGH. Cada PR: revisión de código + seguridad, cierre de hallazgos con test, y merge de Karen. Se pueden correr A–D en paralelo sobre worktrees (tocan zonas distintas: voz-aprobaciones, MCP-realtime, menu-sight, sheets/documentos), y luego E–G.

## 5. Criterios de aceptación

1. Un `resolve_approval(true)` inyectado con un `write_file`/`sheet_write`/`bridge_session` primero en la cola **no** lo aprueba; exige clic.
2. Tras aprobar una hoja por clic, un `resolve_approval(true)` posterior no aprueba nada de la cola.
3. Una llamada a un MCP propio abre hoja; el booleano del modelo por sí solo no la corre.
4. `menu` a un ítem destructivo pide hoja; `menu` de navegación no.
5. La hoja de `sheet_write` muestra el libro y los valores (o su hash+conteo); cambiar de libro entre aprobar y escribir aborta.
6. `=IMAGE("http://…")` y `='/ruta/[otro.xlsx]'!A1` se rechazan; en `.xlsx` una celda `=…` no permitida queda como texto.
7. `create_document` sobre un archivo existente hace backup o rechaza.
8. (E) Una segunda conexión al puente sin `hello` válido no hereda la sesión abierta.
9. (F) Añadir una tool nueva al `ParentToolRunner` la deja fuera del puente y un test lo caza.

## 6. Riesgos

- **R1** D1 puede volver la voz más pedigüeña (más hojas por clic). Es el precio: el modelo no se auto-aprueba lo sensible. Lo de bajo riesgo sigue por voz.
- **R2** El allowlist de fórmulas (D4) puede rechazar una fórmula legítima poco común. Se parte de un conjunto amplio de funciones seguras y se amplía con evidencia.
- **R3** Mover tokens al Keychain (D6) necesita cuidado con las migraciones de claves ya guardadas.
