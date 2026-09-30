# Wave 20d — Modos de autorización: replicar el action-gate de Incredible

**Estado: EN CURSO (Karen firmó con "vamos", 2026-09-29). Alcance: A, B, C.** D y E quedan fuera de este PR. Corre
como 20c: test primero, revisión triple, un PR; merge de Karen.

Origen: `docs/research/incredible-arquitectura.md` §Aprobaciones y `docs/research/ux-incredible-vs-companion.md`.
Incredible casi no pide permiso: **hace las cosas reversibles y locales al momento** ("Talk, and it
happens") y **solo espera aprobación antes de lo que llega a otras personas o no se puede deshacer**
(incredible.one/learn, tasks). El resultado se ve como una **tarjeta** con luz de estado (ámbar = te
necesita, verde = hecho), no como una recitación por voz. Companion, en cambio, tiene riesgo binario
(`ApprovalRisk` low/high) y **mete en hoja toda escritura** (crear documento, escribir en hoja,
`write_file`, `open_url`, cada llamada a un MCP propio, la sesión del puente). Por eso pide muchísimas
más hojas. 20d adopta el modelo de Incredible **sin soltar el freno de lo irreversible**.

## 1. El giro respecto a 20c (leerlo antes que nada)

20c endureció **quién** contesta una hoja y **qué** muestra. 20d cambia **cuándo hay hoja**: lo
reversible y local **deja de pedir hoja** y pasa a "corre y avisa" con deshacer. Lo que **no** cambia:

1. El modelo **nunca** contesta su propia pregunta de permiso para la banda *confirmar* o *crítica*.
2. La hoja **muestra lo que autoriza**.
3. **Procedencia**: lo que el modelo lee no cuenta como el "sí" de la usuaria (D1). Grants y destinos
   de confianza los fija la usuaria, jamás el modelo.
4. La banda **crítica** es **siempre** hoja + ticket de un uso: nunca por voz, grant, confianza ni
   plan. Es el corazón de 20c, intacto.

La banda *hacer* no viola (1): no es "el modelo se auto-aprueba", es que una acción reversible y
local **no requiere aprobación** — su seguridad es la tarjeta visible + el deshacer + la usuaria
mirando, no un gate previo. Exactamente el modelo de Incredible.

## 2. La raíz: tres bandas al estilo Incredible, asignadas leyendo el payload

`ApprovalRisk` (low/high) → `ActionRisk` con tres bandas. La banda la decide un clasificador que
**lee los argumentos** (payload policy). En la duda, **sube** de banda (fail-safe).

| Banda | Qué entra (según payload) | Cómo se autoriza |
|---|---|---|
| **hacer** (Incredible: *just do it*) | Lecturas (`look`, `see`, `read_focused`, `list_apps`, `read_skill`, `find_places`); **acciones locales no destructivas**: `click`/`type_text`/`menu`/`press_key`/`scroll`/`focus_window`/`open_app` cuando la familia de `HandsGate` es `none` y no es una terminal; **escrituras reversibles**: `create_document` a ruta nueva, `sheet_write` que solo agrega, `write_file`/`edit_file` a archivo nuevo dentro de la zona de trabajo, `open_url` | **corre sin hoja**; el resultado sale como **tarjeta** en la isla, con **deshacer** donde hay archivo detrás (§3) |
| **confirmar** (Incredible: *needs you*) | Lo que **llega a otras personas** o sale de la Mac: enviar/publicar/mensajear por una app o un MCP; una llamada de MCP propio que actúa fuera; abrir un flujo hacia terceros | **tarjeta de aprobación** (ámbar); **pre-autorizable** por grant (§4), destino de confianza (§5) o plan aprobado (§6) |
| **crítica** (Incredible: *cannot be undone*) | **Irreversible sin deshacer**: borrar, **sobrescribir** archivo/celda existente, pagar, cerrar sesión (familias destructivas de `HandsGate`, D3); **entregar los controles**: `run_shell`, `bridge_session`, `type_text` en terminal; cualquier tool sin clasificar | **hoja + ticket, siempre** (20c intacto) |

Escalada por payload (ejemplos): `create_document` sobre archivo existente → crítica (sobrescribir);
`sheet_write` que pisa celdas con valor → crítica; que solo agrega → hacer. `write_file` fuera de la
zona de trabajo → crítica; a archivo nuevo dentro → hacer; sobre archivo existente → crítica. Un
`menu`/`click` cuya familia destructiva resuelve (D3, sobre el título realmente resuelto) → crítica.
Una llamada de MCP que solo lee → hacer; que escribe fuera → confirmar; que borra → crítica.

**Frontera dura (línea de Incredible):** lo que llega a otras personas va en *confirmar* (pre-autorizable
por decisión explícita de la usuaria, como sus conectores/autopilot); lo irreversible-sin-deshacer y
la entrega de controles van en *crítica* y **no se pre-autorizan nunca**.

## 3. Banda *hacer*: corre y avisa, con deshacer donde hay archivo

La acción **corre** y el resultado aparece como **tarjeta** en la isla (present_result de Incredible):
"Creé `Brief.docx` · Deshacer 5 s", "Abrí figma.com". La voz **apunta a la tarjeta**, no la recita
(regla 15d-9). Luz verde = hecho.

- **Deshacer donde el acto produce archivo** (no se finge un undo que no existe):
  - `create_document` (ruta nueva): a la **Papelera** (no `rm`).
  - `sheet_write` (solo-agregar): restore del backup que D4 ya escribe.
  - `open_url`: cerrar la pestaña que abrió, si el adapter puede; si no, tarjeta informativa.
- **Clicks / type / navegación no llevan deshacer** — Incredible tampoco los deshace, los **hace**. Su
  seguridad es que son no destructivos (uno destructivo lo sube `HandsGate` a crítica), la tarjeta
  visible y la usuaria mirando. No hay hoja ni undo: se hacen, como en Incredible.
- La ventana de deshacer, el "hecho" y el botón son **estado de la isla** (wave 19). El modelo no
  puede correr, cancelar ni pulsar deshacer nada de esto: solo mira el resultado.
- Un **destino de confianza** (§5) silencia la tarjeta de un objetivo: la acción sigue corriendo, deja
  de avisar.

## 4. Grants con alcance y caducidad (solo banda *confirmar*)

Pre-autoriza acciones de *confirmar* dentro de un alcance acotado y por un tiempo. Nunca toca *crítica*.

- Alcance = (familia de tool) × (destino: **app** | **conector/MCP** | **carpeta**). Ej.: "enviar por
  Slack para esta tarea", "actuar en Figma 10 min".
- Caducidad por tiempo o turnos, lo que se cumpla primero. En memoria (actor `Grants`), **nunca en
  disco**, **nunca escribible ni inferible por el modelo**.
- Se ofrece en la **tarjeta de aprobación** junto a Aprobar/Denegar: "Permitir para esta tarea" /
  "Permitir <destino> 10 min", con el alcance y la duración de una lista corta.
- **Revocable desde la isla**: panel con los grants activos (qué, dónde, cuánto queda) y Revocar. Al
  expirar/revocar, la siguiente acción de ese alcance vuelve a pedir aprobación.

## 5. Destinos de confianza (los fija la usuaria, en Ajustes)

Lista curada por la usuaria, no por el modelo (el equivalente de "configurar el conector una vez" de
Incredible): apps y carpetas donde *hacer* no avisa, conectores/MCP de confianza cuyas acciones de
*confirmar* corren sin tarjeta.

- Aplican a *hacer* (silencia la tarjeta) y *confirmar* (corre sin aprobación). **Nunca** a *crítica*.
- Se editan solo en Ajustes; el modelo los **lee**, jamás los escribe. Persisten en Keychain/config
  del usuario (como las claves de D6), ligados al destino resuelto.

## 6. Aprobar el plan, no cada paso (el espinazo de Incredible)

Incredible muestra el trabajo como **una tarea con un plan** que apruebas una vez. 20d hace igual:
cuando un turno tiene varios pasos, una **sola** tarjeta muestra el plan (pasos y su banda).

- Aprobado el plan: los pasos de *hacer* corren con su tarjeta y los de *confirmar* corren sin volver
  a preguntar, dentro de ese turno.
- Un paso **crítico** dentro del plan **vuelve a pedir su hoja** con su ticket al momento de correr:
  aprobar el plan no aprueba lo irreversible.
- Un paso nuevo que no estaba en el plan aprobado se trata por su banda, no como aprobado.

## 7. Estados de la isla (para que "hacer" no necesite hoja)

Replicar el feedback que le permite a Incredible no preguntar: **luz de estado** (ámbar = te necesita,
verde = hecho), la **tarjeta de resultado** bajo el campo, y la voz que **apunta** a la tarjeta en vez
de recitarla. Es lo que hace seguro correr sin gate: se ve lo que pasó y se puede deshacer/parar. Se
apoya en la isla rica (wave 19) y en las tarjetas de resultado.

## 8. Entregas (una rama por PR; test en rojo primero; revisión triple)

| PR | Cubre | Prioridad |
|---|---|---|
| A | §2 `ActionRisk` de 3 bandas + clasificador por payload (reemplaza `ApprovalRisk`); sin cambio de comportamiento aún, solo clasifica | **obligatorio** (raíz) |
| B | §3 banda *hacer*: lo reversible/local **corre sin hoja**, tarjeta de resultado + deshacer; adapters de undo (Papelera, restore, cerrar pestaña) | **obligatorio** (el grueso de la fricción) |
| C | §7 luz de estado + tarjeta de resultado + la voz apunta a la tarjeta | **obligatorio** (hace seguro no preguntar) |
| D | §4 `Grants` (actor, alcance+TTL, revocar desde la isla) + opciones en la tarjeta de aprobación | recomendado |
| E | §5 destinos de confianza en Ajustes + §6 aprobar el plan del turno | recomendado |

A+B+C = el modelo de Incredible operativo. D+E lo afinan.

Superficie (orientativa): `ApprovalRisk.swift` → `ActionRisk` (Core, puro); clasificador junto a
`ParentToolPolicy`/`HandsWords` (lee argumentos); la ruta de ejecución de la banda *hacer* que corre
sin `ApprovalRequest`; `Grants` actor paralelo a `ApprovalMemory`; isla (wave 19) para tarjetas de
resultado, deshacer, luz de estado y panel de grants; adapters de undo en Services; Ajustes +
Keychain para destinos de confianza.

## 9. Criterios de aceptación

1. `create_document` a ruta nueva **corre sin hoja**, deja tarjeta con Deshacer que manda el archivo a
   la Papelera al pulsarla.
2. `create_document` sobre archivo existente **sí** pide hoja (sobrescribir = crítica).
3. `sheet_write` solo-agregar corre con tarjeta; el que pisa celdas con valor pide hoja.
4. Un `click`/`type_text` **no destructivo** corre sin hoja (como Incredible); uno destructivo (Borrar,
   Enviar, Cerrar sesión, resuelto por D3) pide hoja + ticket.
5. Enviar por una app/MCP (llega a otros) muestra tarjeta de aprobación; con un grant o destino de
   confianza vigente, corre sin ella; al expirar/revocar, vuelve a pedirla.
6. `run_shell`, borrar, sobrescribir, `bridge_session` y una escritura de MCP fuera de la Mac **siempre**
   piden hoja + ticket, aunque haya grant, destino de confianza o plan.
7. Un grant/destino nunca aparece por algo que el modelo dijo; grant = clic de la usuaria en la tarjeta;
   destino = Ajustes.
8. Con un plan aprobado de N pasos, solo los pasos críticos vuelven a pedir hoja.
9. El modelo no corre la banda *hacer* saltándose la tarjeta, ni pulsa deshacer, ni cancela la ventana,
   ni crea/revoca un grant.

## 10. Riesgos

- **R1: una acción de *hacer* que en realidad llega a otras personas.** El clasificador debe ser
  conservador: cualquier envío/publicación/mensaje sube a *confirmar*; en la duda, sube. `open_url` es
  el borde (dominio de tracking): se cubre con la tarjeta visible; se endurece a *confirmar* si la
  evidencia lo pide.
- **R2: sobrescribir disfrazado de agregar.** El payload policy de `sheet_write`/`write_file` decide
  agregar-vs-pisar leyendo el estado real (celda con valor, archivo existente), no la intención del
  modelo. Pisar siempre es crítica.
- **R3: grants y destinos inertes para el modelo.** En memoria/config del usuario, revocables, con
  caducidad, ligados al destino resuelto; un test los caza si el modelo alguna vez los puede escribir o
  inferir.
- **R4: la banda *hacer* corre sin gate, así que la tarjeta y el deshacer son la seguridad.** Si la
  isla no muestra el resultado o el deshacer falla, la acción no debió estar en *hacer*: sin tarjeta
  fiable, sube a *confirmar*. Por eso C (isla) es obligatorio, no opcional.
- **R5: no re-abrir 20c.** Cada PR corre revisión de seguridad que confirma que *crítica* sigue siendo
  hoja+ticket y que los invariantes §1 se sostienen.

## 11. Decisiones de implementación (20d A-C)

Donde la implementación afinó la spec, siempre hacia pedir más, nunca menos:

- `open_url` corre sin hoja solo si la usuaria dijo el host (`ParentToolGate.saidIt`); un host que
  no dijo sigue en *confirmar*. Es el sumidero de exfiltración que 10a ya cerró; el punto
  intermedio de R1 se resuelve por el lado seguro.
- `write_file` en *hacer* solo para nombres de datos (`txt md markdown csv json log`) en carpetas
  visibles, dentro de la carpeta de trabajo (no las carpetas de skills). Un script, un hook de git,
  un Makefile o un archivo oculto piden hoja: es como una inyección planta algo que corre después.
- Al construir la banda se encontró y cerró un hueco previo: un archivo NUEVO bajo un directorio
  que es symlink hacia fuera de la carpeta pasaba la barrera de escritura (`resolvingSymlinksInPath`
  no resuelve lo que aún no existe). Ahora se resuelve el ancestro que existe y se conserva la cola.
- Quedan fuera de este PR: el cierre de la pestaña que abrió `open_url` como deshacer, y la voz que
  apunta a la tarjeta en vez de recitarla (la tarjeta y la luz sí están). D y E siguen pendientes.
