# Spec: manos que no mienten (escribir, leer y apuntar como Incredible)

Estado: APROBADO (Karen, 2026-10-05).

## Por que

El 2026-10-05 otra sesion (atom-mcp-d8) uso el MCP de Companion para llenar un formulario de dos
campos en Comet (dashboard de Clerk: un input y un editor CodeMirror) y no pudo:

1. `type_text` respondio "typed 10 chars (not read back)" y el campo siguio con su placeholder.
2. `read_focused` dio `no_focused_field` justo despues de un clic correcto en el campo.
3. `target_changed` en cadena: look, focus_window y type_text fallaron igual hasta un `open_app`.

Causas en el codigo (triage del 2026-10-05):

- `AXTextInjector.inject` da exito si `kAXSelectedText` devuelve `.success`; Chromium lo acepta y lo
  ignora. "10 chars" es el largo del argumento, no lo que entro (AXTextInjector.swift:53-63,
  ParentToolRunnerHands.swift:423). El camino del MCP nunca relee.
- `read_focused` solo lee `kAXValue`/`kAXSelectedText` del elemento enfocado y cualquier vacio o
  error es `no_focused_field` (AXTextInjector+Hands.swift:27-39).
- El objetivo es un pid fijado por turno contra "la ultima app no-Companion activada"
  (ParentToolRunnerHands.swift:96-115, 296-302; ContextSensors.swift:64-74). Manejado desde Claude
  Code, la terminal al activarse mueve esa marca y cada llamada siguiente falla igual.
- La extension de Companion no estaba cargada en Comet, asi que el modelo solo tenia las manos de
  accesibilidad.

Como lo hace Incredible (analisis locales, nunca se suben al repo:
`~/Desktop/incredible-ref/audits/extension-1.17.9-analisis.md` y
`~/Desktop/incredible-ref/audits/incredible-app-navegador-y-manos.md`):

- Sin extension no actua sobre la web: dice que hay que conectar el navegador.
- Antes de escribir comprueba ventana exacta, foco y caret; despues responde verificado o "revisa
  antes de reintentar". Nunca un "escrito" pelado.
- Apunta a una ventana exacta o a un `tab_id`, no a "la app del frente". Si pierde el objetivo, el
  error dice al agente que rehacer ("descubre la aplicacion de nuevo").

## Alcance: cuatro PRs, en este orden

Paso 0 (Karen, sin codigo): cargar la extension de Companion en Comet con Load unpacked.

### PR 1: la web solo por la extension

- Si la app objetivo es un navegador Chromium conocido (la lista de `AXScreen`) y la extension no
  esta conectada para ese navegador, `type_text` y `read_focused` no actuan: devuelven
  `error[browser_not_connected]` con el nombre del navegador y que hacer ("carga la extension de
  Companion en <navegador>").
- Con la extension conectada, el modelo ya tiene las herramientas `browser_*`; `type_text` sobre un
  navegador responde que use `browser_type`.
- Tests: navegador sin extension -> error claro, nada se escribe; navegador con extension ->
  redirige; app nativa -> sin cambios.

### PR 2: escribir en apps nativas, verificado

- Antes: comprobar que el elemento enfocado sigue siendo un campo editable de la ventana objetivo.
- Escribir: el camino actual (selected text, luego pegar).
- Despues: releer el campo (mismo criterio que `TypedProof.verifies`, que hoy solo usa la voz) y
  responder uno de tres resultados:
  - `typed N chars (verified)` cuando el texto aparece;
  - si no aparece tras el primer camino, intentar pegar una vez y releer;
  - si sigue sin aparecer: `error[not_landed]: el texto no entro en el campo; mira la pantalla antes
    de reintentar`.
- "N" es lo que entro, no el largo del argumento.
- Tests (fakes del inyector y del lector): set aceptado e ignorado -> pega -> verificado; ambos
  ignorados -> `not_landed`; campo que no se puede releer -> resultado "no verificado" explicito,
  nunca exito.

### PR 3: el objetivo es la ventana, no "la app del frente"

- Cada accion apunta a la ventana que `look` devolvio (pid + id de ventana). El pin por turno deja de
  compararse con `lastOtherPID`.
- Si esa ventana ya no existe o no esta al frente: `error[target_lost]: la ventana ya no esta; llama a
  look de nuevo`. Una llamada a `look` vuelve a fijar el objetivo; ya no hace falta `open_app`.
- Se mantiene: una tercera app nunca hereda el turno (tests H1 y `testATargetThatChangedSinceTheUserSpokeIsRefused`
  siguen verdes); Companion al frente sigue siendo `self_in_front`.
- Tests: la terminal se activa entre dos llamadas -> la segunda sigue en la ventana objetivo; la
  ventana se cierra -> `target_lost`, y `look` lo recupera; otra app distinta toma el frente -> se
  rechaza como hoy.

### PR 4: read_focused dice la verdad

- Distinguir "campo vacio" (devuelve texto vacio y el rol) de "no hay campo enfocado".
- En navegador con extension, leer por la extension (`browser_read` del elemento con foco).
- Tests: campo vacio con placeholder -> vacio, no error; sin foco -> `no_focused_field`; campo
  seguro -> sigue sin leerse.

## Restricciones

- Tests primero en cada PR (rojo y luego verde); reviewers code, qa y security con huella.
- Nada de codigo ni texto de Incredible en el repo; los analisis viven solo en incredible-ref.
- Los textos de error en ingles y tecnicos (los lee un agente, no la usuaria); los avisos en la isla,
  si alguno, en el catalogo es/en.
- Campos seguros: nunca se escriben ni se leen (regla actual, no se toca).
- Maximo 5 archivos por PR.
- Lo implementa MiniMax por PR; Companion1 revisa, corre los reviewers y entrega al orquestador.

## Fuera

- Extension en la Chrome Web Store (DK3).
- Perfiles multiples de navegador y la vista del navegador en la isla (van con el modulo Navegador).
