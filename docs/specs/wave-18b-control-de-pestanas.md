# Wave 18b — Pestañas bajo control, como Incredible

**Estado: APROBADO (2026-09-29).** Firmado por Karen con D1-D5 tal cual («dale»). Resuelve el M1 abierto de la wave 18 (#41): hoy cualquier llamador, también un agente por el puente MCP, lee cualquier pestaña de fondo (correo, banco) sin hoja.

## 1. Cómo lo resuelve Incredible (código de la extensión 1.17.3)

- **Arrendamiento por pestaña** (`src/ownership.js`, `authorizeTabOperation`): toda lectura o escritura exige que el id del llamador coincida con el dueño de la pestaña. Sin dueño → "Tab N is not controlled by Incredible right now… claim it with `tabs.get(N)` or open the address in a fresh tab". Otro dueño → denegado; se puede tomar solo si ese dueño la dejó quieta 120 s (`TAB_TAKEOVER_AFTER_MS`).
- **Listar no es leer** (`REVIEWERS.md`, permiso `tabs`): la lista de pestañas (URL y título) sirve solo para localizar la que el usuario nombró; todo lo demás, solo sobre pestañas controladas.
- **El control se ve** (`tabGroups`): las pestañas del agente van a un grupo propio, azul y con título, a la izquierda de la barra; al soltarlas vuelven a su sitio (`tabs.move` a su índice original). Los grupos del usuario no se tocan. Una pestaña que el agente abrió él mismo nace controlada.
- **Pestañas hijas** (`spawnedTabOwner`): una pestaña que abre una página controlada es del agente si nació ≤10 s después de que actuó; una `chrome://newtab` nunca.
- **Al desconectar** se sueltan todas (`planReleaseOnDisconnect`).
- No pide hoja para tomar una pestaña: la señal es visual (la pestaña se mueve al grupo del agente).

## 2. Qué se toma

| Incredible | Companion 18b |
|---|---|
| `tabs.open(url)` → pestaña nueva controlada | **`browser_open(url)`** (escritura): pestaña nueva **de fondo** en el grupo *Companion* |
| `tabs.get(N)` reclama una existente | **`browser_take(tab)`** (escritura): mueve la pestaña al grupo *Companion* y queda controlada |
| Soltar al terminar la tarea | **`browser_release(tab)`** + suelta sola tras 10 min sin uso, al desconectar y en *Quitar* |
| Dueño = `agent_invocation_id` | Dueño = llamador: `chat` o la sesión del puente (id por conexión) |
| Lista solo para localizar | `browser_tabs` sigue listando título y URL sin query ni fragmento (ya es así) |

`browser_read/click/type/navigate` pasan a exigir que la pestaña esté controlada **por ese llamador**; si no, `not_controlled` con la guía de Incredible ("tómala con `browser_take` o ábrela con `browser_open`"). Otro dueño activo → `busy`; se puede tomar si lleva 120 s quieta.

## 3. Decisiones (firma Karen)

- **D1** Tomar una pestaña **en el chat** no pide hoja (como Incredible: la señal es el grupo). **Por el puente, `browser_take` pide hoja** ("Claude Code quiere controlar la pestaña «Gmail»"): el agente del puente no es quien te está hablando. `browser_open` pasa la misma puerta que navegar: sin hoja solo si nombraste el sitio (la pestaña nueva lleva tus cookies).
- **D2** El grupo se llama *Companion*, azul, a la izquierda. Se añade el permiso `tabGroups` (Chrome no pide confirmación nueva a una extensión sin empaquetar). Sin `debugger`, sin `tabs`.
- **D3** Soltar devuelve la pestaña a su índice y la saca del grupo; si el usuario la movió entretanto, no se toca.
- **D4** Pestañas hijas: regla de Incredible (≤10 s tras la última acción, nunca `newtab`).
- **D5** Fuera de 18b: task card en la página, cursor dibujado, favicon marcado, varios agentes del puente a la vez (hoy el puente tiene una sola sesión).

## 4. Dónde vive

- **Extensión** (`lib/wire.js` puro + `background.js`): `tabGroups`, mover/soltar, índice original, hijas por `chrome.tabs.onCreated` con `openerTabId`. Tests node sobre las funciones puras (`groupPlan`, `releasePlan`, `spawnOwner`).
- **Core**: `BrowserTool` + `open`, `take`, `release`; `BrowserLease` (puro: `authorize(owner:caller:lastActed:now:)`, `takeoverAfter = 120 s`, `idleRelease = 600 s`), copy es/en con la guía de reclamo.
- **Services**: el arrendamiento vive en `BrowserHost` (compartido por los dos runners, porque la pestaña es una sola); cada runner pasa su id de llamador. `bridgeRunner` pide hoja en `take`.
- **Protocolo**: tres comandos nuevos (`open`, `take`, `release`) y `tabs` marca `controlled`.

## 5. Criterios de aceptación

1. `browser_read` de una pestaña no tomada → `not_controlled` y la extensión no recibe `read`.
2. `browser_open(url)` → pestaña nueva de fondo, en el grupo *Companion*, legible al instante.
3. `browser_take` en el chat → sin hoja, la pestaña entra al grupo; por el puente → hoja; denegada → la pestaña no se mueve.
4. La pestaña tomada por el chat es `busy` para el puente hasta 120 s de inactividad.
5. `browser_release`, 10 min sin uso, desconexión o *Quitar* → la pestaña vuelve a su índice y fuera del grupo.
6. Una pestaña abierta por un clic del agente (≤10 s) nace controlada; una `newtab` del usuario no.
7. En vivo (Karen): en Comet, el agente abre Salesforce en una pestaña nueva de fondo y lee el picklist; tu pestaña de Gmail no se puede leer sin tomarla.

## 6. Entregas

Una sola PR: 18b-0 Core (`BrowserLease`, tools, copy) + 18b-1 extensión (grupos, hijas, comandos) + 18b-2 runners/host + SKILL.md. TDD, tres revisiones, gates.

## 7. Desviaciones

- **H1 (revisión de seguridad):** `browser_open` pasa la misma puerta que `browser_navigate` (`BrowserPolicy.navigateVerdict` sin origen previo). Sin hoja solo si el usuario nombró el host; por el puente siempre pide hoja. El ticket queda atado a la URL exacta. Antes abría sin pedir, con las cookies del usuario (exfiltración por query, lectura de una página autenticada que nadie pidió).
- **H2:** una pestaña hija se hereda solo si su origen es el del opener (la URL del opener sale del mismo listado); una hija de otro origen no se adopta y se reclama con `browser_take` o `browser_open`.
- **M1:** el id `bridge` es compartido por todas las sesiones del puente, así que al empezar y al terminar una sesión se sueltan sus pestañas (y se avisa a la extensión).
- **M2:** el dueño "vivo" cuenta el reloj: una entrada ociosa 600 s no salta la hoja de `browser_take`.
- **L2:** una pestaña que el listado ya no muestra, o que la extensión contesta `stale_id` al leerla, deja de tener dueño. `stale_id` de un elemento (click/type) no suelta la pestaña: solo dice que la página cambió.
