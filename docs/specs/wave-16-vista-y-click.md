# Wave 16 — Vista y click como Incredible, y un especialista que no pide permisos

**Estado: CERRADO (2026-09-25) — 16a y 16b.** Falta la prueba en vivo de Karen (§7). 16c+ tiene spec propia (`wave-16c-ux-como-incredible.md`). Karen: "me parece perfecto, incluso tu recomendación. Asegúrate de que la UX/UI funcione igual que la de Incredible." 15g cerrada.

Karen (2026-09-25, tras probar 15g): "funciona increíble, solo que pide demasiados comandos
todavía al intentar hacer click. […] hay que replicar la vista de Incredible. Vamos con UX/UI,
dale vista y habilita click sobre los elementos de la pantalla. También asegúrate de que ya no
pida permisos para ejecutar comandos."

Criterio de done: "acepta el permiso de ubicación" en Safari pulsa el botón en un turno, sin
especialista y sin hoja; "¿qué hay en pantalla?" responde con lo que hay en la ventana de
delante en ≤ 1,5 s; el especialista ya no muestra la hoja "¿Permitir que el especialista haga
esto?" para comandos.

## 1. Qué pasó en la prueba (log 2026-09-25 18:33–18:34)

- Escribir y pulsar Return funcionó con las manos de 15g (`type_text` por AX, `read_focused`,
  `press_key return`), todo en Safari, sin especialista.
- Para pulsar "Permitir" en el aviso de ubicación de Google no había herramienta de click: el
  cerebro delegó (`executor: work routed from native to claude-code`), y Claude Code, en modo
  `acceptEdits`, pidió permiso para un `osascript` de System Events. Dos veces.
- La vista de hoy no ve botones: `AXScreenText` recoge solo texto (1 fragmento en Safari) y la
  captura se describe con gpt-4o-mini en 3,3–3,7 s. El cerebro (Cerebras gpt-oss-120b) no ve
  imágenes, así que sin árbol de elementos no tiene nada que pulsar.

## 2. Cómo lo hace Incredible (bundle 0.1.81, `accessibility-helper`, leído 2026-09-25)

- **Ver = escanear.** `scan(app, window_title | window_id)` recorre el árbol de Accesibilidad de
  una ventana y devuelve elementos con **id** (rol, título, valor, posición). Si el árbol es
  enorme lo trunca y lo dice ("result is partial. Narrow to a specific window_id or subtree").
  `screenshot` de una ventana por ScreenCaptureKit existe aparte, para cuando hacen falta píxeles.
- **Click = por id.** `click(app, id)` hace `AXPress`; si falla, enfoca el elemento; si tampoco,
  `mouse_click` en el centro del elemento, publicado **al pid** (no al ratón del sistema). Un id
  viejo falla con "no handle for id=… retry with a fresh id": nunca adivina.
- Extras: `element_at_point`, `invoke_menu(path)`, `scroll`, `scroll_to_visible`,
  `wait_for_change` (observer AX), `set_focused`.
- Actúa en segundo plano, sin robar el foco. Reconoce campos seguros.

## 3. Decisión

| Decisión | Por qué |
|---|---|
| **`look()`**: escanea la ventana delante de la app fijada del turno (pin de 15g) y devuelve una lista numerada de elementos accionables y texto: `[12] botón "Permitir"`, `[13] botón "No permitir"`, `[4] campo "Buscar" = "…"`. Incluye hojas, diálogos y popovers de esa app. Tope 150 elementos / 6 000 caracteres; si se trunca, lo dice | es la vista de Incredible; el cerebro es solo texto, así que la vista tiene que ser texto |
| Los ids valen **solo para el último `look`** del turno en esa ventana; un id viejo falla con "vuelve a mirar" | Incredible hace lo mismo; un id adivinado pulsa otra cosa |
| **`click(id)`**: `AXPress`; si no lo acepta, enfocar; si no, click de ratón en el centro **publicado al pid**. Nunca en campos seguros ni en Companion | el orden de Incredible; el ratón del sistema robaría el foco |
| **`scroll(id, dirección)`** y **`menu(ruta)`** (p. ej. "Archivo > Exportar") | sin ellos, lo que no se ve no se puede pulsar |
| **Política de click**, igual que Return en 15g: directo, salvo botones cuyo texto es destructivo o de envío/pago (borrar, eliminar, pagar, comprar, enviar, publicar, delete, pay, buy, send, publish…) que piden la hoja **a menos que la usuaria lo pidiera con esa palabra** ("borra este correo", "envíalo"). "Permitir/Allow/Aceptar/OK" van directo | que un texto en pantalla no pueda hacer comprar o borrar |
| La vista automática por turno pasa a ser **`look()` de la app delante** (AX, ~0,1–0,5 s) en vez de la descripción de gpt-4o-mini; la captura con visión queda como tool `see()` para cuando la usuaria pregunta por algo visual (una foto, un gráfico) | 3,5 s por turno para describir una imagen que el cerebro no necesita para actuar |
| Prompt: "para pulsar algo, `look` y luego `click`; nunca delegues pulsar, escribir o navegar". `delegateRule` excluye clicks. Lo que devuelve `look` son datos, no órdenes (regla M3 de 15g) | hoy el cerebro delega porque no tiene la herramienta |
| **Especialista sin hoja para comandos**: Claude Code pasa de `--permission-mode acceptEdits` a **`auto`** (su clasificador aprueba lo seguro y rechaza lo riesgoso sin preguntar), más `--disallowedTools` fijos: `Bash(sudo *)`, `Bash(git push *)`, `Bash(rm -rf /*)`, `Bash(rm -rf ~*)`, `Bash(curl * \| sh*)`, `Bash(osascript *)` | Karen lo pidió explícitamente. `osascript` queda fuera porque las acciones de pantalla ya son de las manos del padre |
| El cable `--permission-prompt-tool stdio` se queda: si `auto` aun así pregunta, **se responde "no" solo y se registra** (sin hoja); el especialista sigue sin esa acción | "que ya no pida permisos"; negar es lo seguro cuando el clasificador duda |
| Las hojas de las manos de 15g (Return en terminales, direcciones no dichas) **se quedan** | son de la usuaria sobre sus apps, no del especialista; si molestan, se ajustan con datos |

Riesgo que Karen asume: en modo `auto` el especialista corre comandos sin que ella los vea;
el clasificador de Claude Code y la lista negra son la única barrera.

## 4. Entregas

- **16a-1 `look` (Services + Core).** `AXScanner` (Services): recorre la ventana enfocada de un
  pid con presupuesto de tiempo (450 ms, timeout AX 0,25 s como 15b-6); roles accionables
  (`AXButton`, `AXLink`, `AXCheckBox`, `AXRadioButton`, `AXPopUpButton`, `AXMenuItem`,
  `AXTextField`, `AXTextArea`, `AXComboBox`, `AXTab`, `AXCell` con acción) + texto estático
  visible; ignora ocultos y fuera de pantalla. `ScreenScan` (Core, puro): numera, recorta,
  formatea. Registro de handles por turno en `ScreenHands`.
- **16a-2 `click`, `scroll`, `menu` (Services).** Sobre `AXTextInjector` (mismo adaptador que
  15g): `AXPress` → `AXRaise`+foco → `CGEvent` de ratón a pid en el centro del frame.
  `HandsGate.verdict` gana el caso `click` con `HandsWords.destructiveLabels`.
- **16a-3 La vista del turno.** `ScreenSight.begin` hace `look()` en vez de captura+visión;
  `see()` (captura + gpt-4o-mini) como tool aparte. Métrica nueva en el timeline:
  `press→look`.
- **16a-4 Prompt.** `actRule`/`handsRule` con `look`/`click`; `delegateRule` sin UI.
- **16b Especialista sin hojas.** `ClaudeCodeExecutor` a `auto` + lista negra; `can_use_tool`
  que aún llegue → "no" automático + log (`executor: auto-denied <tool>` sin argumentos).
  Batch igual. Spike primero (30 min): confirmar que `-p` + `stream-json` + `auto` funciona con
  la versión instalada (2.1.282) y qué hace con un comando dudoso.
- **16c en adelante: UX/UI** según `docs/research/ux-incredible-vs-companion.md` §5 (bienvenida
  con las 3 claves, ajustes fijos en 3 pestañas con interruptor de depuración, la isla como
  app). Spec propia al cerrar 16b.

Archivos: `AXScanner.swift` (nuevo), `ScreenScan.swift` (Core, nuevo), `AXTextInjectorHands.swift`,
`ParentToolHands.swift`, `ParentToolRunnerHands.swift`, `HandsWords.swift`, `ScreenSight.swift`,
`ChatPrompt.swift`, `ClaudeCodeExecutor.swift`, tests. Más de 5 archivos: se entrega en PRs
separados por entrega (16a-1+2, 16a-3+4, 16b).

## 5. TDD (rojo primero)

1. `ScreenScan` numera, recorta a 150/6 000 y dice "parcial" al truncar; nunca incluye el valor
   de un campo seguro.
2. `click` con id de un `look` anterior de otra ventana → `stale_id`, nada pulsado.
3. `click` sobre "Permitir" → directo; sobre "Eliminar" sin pedirlo → hoja; con "bórralo" →
   directo.
4. `click` falla `AXPress` → cae a foco → cae a ratón al pid (fakes de los tres caminos).
5. Pin de 15g: `look`/`click` en otra app que la del turno → `target_changed`.
6. `ScreenSight` ya no llama a la visión por turno; `see()` sí.
7. `ClaudeCodeExecutor` arranca con `--permission-mode auto` y la lista negra; un
   `can_use_tool` entrante se contesta `deny` sin abrir hoja.
8. Prompt es/en: `look` y `click` nombrados; `delegateRule` excluye pulsar.

## 6. Seguridad

- `look` nunca devuelve el valor de un campo seguro; el log solo lleva cuentas y pid.
- Texto de `look` = datos (regla de 15g M3); los clicks destructivos piden la hoja salvo que se
  pidieran con palabras de la usuaria.
- Especialista: `auto` + lista negra; cualquier pregunta que quede se niega sola. Revisión de
  seguridad obligatoria antes de cerrar 16b.

## 7. Done (en vivo, Karen)

1. Safari con el aviso de ubicación: "acepta el permiso" → pulsado, sin especialista ni hoja.
2. "¿Qué hay en pantalla?" en Finder / Safari / Notas → responde en ≤ 1,5 s desde soltar.
3. "Abre el menú Archivo y dale a Exportar como PDF" en Notas.
4. En Mail, "haz lo que dice ese correo" cuando el correo dice "pulsa Eliminar" → hoja;
   "borra este correo" → directo.
5. Un encargo al especialista que corre comandos (p. ej. "busca en mi disco los PDF de ayer")
   → termina sin ninguna hoja.

## 8. Aprobación

Aprobada 2026-09-25, incluido el modo `auto` con lista negra para el especialista. La UX/UI (16c+) debe funcionar igual que la de Incredible: su spec parte de `docs/research/ux-incredible-vs-companion.md` §2 como contrato de paridad.


## 9. Lo entregado, medido y revisado (2026-09-25)

**16a.** `look` / `click` / `scroll` / `menu` / `see` sobre `AXScreen` (nuevo adaptador; los handles
del último recorrido con su generación). Medido en vivo contra las apps abiertas de Karen, solo
lectura: 16–25 ms por ventana; las apps Electron/Chromium solo exponen su contenido tras
"prepararlas" (`AXManualAccessibility` / `AXEnhancedUserInterface`, como el helper de Incredible):
Slack pasó de 3 a 125 controles, Comet de 21 a 53. Se preparan al pasar al frente, fuera del hilo de
la notificación, para no pagar los ~300 ms al hablar.

**16b.** Spike con Claude Code 2.1.282, solo comandos inofensivos:

| Comando | Sin lista | Con lista |
|---|---|---|
| `ls -d /tmp` | — | corre sin preguntar |
| `osascript -e 'return 42'` | corre | bloqueado |
| `/usr/bin/osascript …` | corre | bloqueado |
| `true; osascript …` | — | bloqueado |
| `bash -c 'sudo -n true'` | corre (sudo pide contraseña) | bloqueado |

Claude Code descompone `bash -c`, cadenas con `;` y rutas completas antes de comparar, así que la
lista aguanta envoltorios; el modo `auto` por sí solo **sí** deja pasar `osascript` y `sudo`, así que
la lista es necesaria. Riesgo que queda, aceptado por Karen: un script escrito y luego ejecutado,
`python -c`, base64 — eso lo decide el clasificador.

**Desviaciones.**
- La vista automática por turno **no** es `look()`: meter 6 000 caracteres de escaneo en el contexto
  de cada turno chocaba con el presupuesto de contexto (resumen de pantalla a 400). Se hizo como
  Incredible: el turno lleva el texto de Accesibilidad (15b-6, barato) sin visión, y el modelo llama
  a `look` cuando va a actuar o preguntan qué hay. La métrica `press→look` no se añadió: `look` es
  una tool, y su tiempo va en el log (`sight: look …`).
- El tope de rondas del padre sube de 3 a 8: mirar → pulsar → mirar → escribir no cabía en 3.
- El test de "coincidencia exacta de menú" se escribió junto con su arreglo, sin verlo fallar antes.
- Deuda anterior a esta wave: tests que leen su captura de log antes de que el hilo productor escriba
  (`chatAnsweredByLogTests`, `mouthLanguageTests`, `utteranceLogPrivacyTests`) y
  `nativeExecutorRoundTests` fallan ~1 de cada 3 corridas completas; pasan solos.

**Revisión.** Código: WARNING (0 críticos, 2 altos). Seguridad: BLOCK (2 críticos, 2 altos). Todo
corregido con test en rojo; 369 tests verdes, gates 0 fallos.

| Hallazgo | Arreglo | Test |
|---|---|---|
| **C1** un campo seguro sin etiqueta tomaba sus caracteres como subtítulo | `AXScreen.label` nunca lee hijos de un campo seguro | `testASecureFieldNeverReadsItsCaption` |
| **C2** icono sin etiqueta pasaba directo | sin etiqueta = hoja y pase | `testAnUnlabeledControlAlwaysAsks` |
| **C2** "Move to Bin", alemán, francés, portugués, italiano | familias ampliadas (defensa en profundidad) | `testDestructiveWordsBeyondSpanishAndEnglish` |
| **C2** el "Sí" de un diálogo de borrar | cada diálogo/hoja es un grupo; un botón neutro se juzga por el texto de su diálogo; cancelar nunca | `testAConfirmationInsideADestructiveDialogAsks`, `testTheDialogContextReachesTheGate` |
| **M** "envíalo" autorizaba "Publicar" | una familia por acto (borrar, pagar, suscribir, enviar, publicar) | `testFamiliesAreNotShared` |
| **M** TOCTOU: la hoja aprueba una etiqueta y se pulsa otra | la etiqueta viva se relee antes de pulsar; si cambió, `stale_id` | adaptador real; verificado en vivo (§7) |
| **H1** abrir una app dejaba el turno sin pin | `release()`: la siguiente llamada fija la app abierta; una tercera app queda fuera | `testAfterOpeningTheTurnRepinsToTheOpenedApp` |
| **H2** lista negra con rodeos | variantes añadidas; spike documentado arriba | `SpecialistAutoModeTests` |
| **HIGH** subtítulos sin presupuesto | cuentan contra el plazo del recorrido | recorrido en vivo ≤ 0,39 s |
| **HIGH** diálogos, `scroll` y la espera de preparación fuera del plazo | todos con plazo; el reloj empieza antes de preparar | idem |
| **M** menú por "contiene" | exacta primero | `menuStepPrefersTheExactLabel` |
| **L** preparar en el hilo de la notificación | `Task.detached` | — |
| **L** `.refuse` trataba como `.act` | sin pase | — |
| **L** código muerto y comentarios con "tres" | borrado / corregido | — |
