# Wave 15g — Manos sobre la pantalla (type_text, press_key, focus_window)

**Estado: CERRADO (2026-09-25).** Código, revisión (§9) y gates hechos; falta la prueba en vivo de Karen (§7). 15f cerrada. El anuncio del encargo con palabras propias (15g-4) ya se hizo en la revisión de 15f (§10 HIGH-B). Karen: "me parece perfecto, vamos".
Sin commit.

Karen: "le pedí a companion que escribiera sobre mi terminal, sí pudo ponerla en primer plano
después de varios intentos, pero no pudo escribir. ¿Cómo es que Incredible lo logra? ¿Podemos
lograrlo?"

Criterio de done: "escribe hola en la terminal" y "dale Enter" funcionan en un turno cada uno,
con aprobación hablada/visible antes del Enter en una terminal; "pon la ventana de X en primer
plano" levanta esa ventana concreta; nunca se escribe en un campo seguro ni en Companion;
gates verdes.

---

## 1. Cómo lo hace Incredible (bundle 0.1.81, leído 2026-09-25)

- Sidecar Swift firmado `accessibility-helper` (daemon JSONL): `scan`, `click`, `set_value`,
  `set_focused`, `key`, `mouse_click`, `invoke_menu`, `scroll`, `screenshot`, `windows`,
  `wait_for_change`. Símbolos: `AXUIElementSetAttributeValue`, `AXUIElementPerformAction`,
  `CGEventCreateKeyboardEvent`, `CGEventKeyboardSetUnicodeString`, **`CGEventPostToPid`**.
- Actúa **en segundo plano sin robar el foco**: escribe con `set_value` y teclea al pid concreto.
  Lista blanca de teclas: Tab, Return, Backspace, Delete, flechas, Insert, F2, Esc (rechaza las
  que necesitan foco real). Reconoce `AXSecureTextField`.
- El modelo de voz (GLM-5.2) no toca la pantalla: solo `open_app`, `assign_task`,
  `ask_sub_agent_quick_question`, `stop_agent`. Teclea un worker (`computer-use-agent`, gpt-5.6)
  con 12 primitivas Python sobre el árbol AX, apagado por defecto por ejecución.
- Permisos TCC: Incredible = Accesibilidad + Grabación de pantalla + Automatización (System
  Events, Finder, Safari). Companion-next = Accesibilidad (la única que hace falta para teclear).

## 2. Por qué Companion no escribió (log 2026-09-25 03:53–03:56)

1. No hay tool de escribir: `ParentTool` = `open_app/open_url/open_file/list_apps/read_skill`
   + `delegate`; `AXTextInjector` (12e) solo lo usa la tecla de dictado.
2. "Primer plano" fue `open_app("Terminal")` (activa la app, no una ventana).
3. Los "pégalo / hazlo" salieron de gpt-oss como JSON en texto, sin llegar al executor (15f-1
   lo cubre). Y Claude Code arranca con `--allowedTools WebSearch,WebFetch`: sin manos ni
   permiso de Automatización. El prompt prometía "el especialista sí tiene la terminal".

---

## 3. Decisión

| Decisión | Por qué |
|---|---|
| **`type_text(text)`** como tool del cerebro sobre `AXTextInjector`: AX (`kAXSelectedText`/`set_value`) primero, pegado con restauración del portapapeles después; destino = pid de la app que estaba delante (`FrontmostAppSensor.lastOtherPID`), revalidado al inyectar | la mitad del código ya existe (12e); Incredible hace exactamente esto |
| **`press_key(key)`** con lista cerrada `return, tab, escape, up, down, left, right, backspace`, por `CGEventPostToPid` al mismo pid, sin modificadores | teclas de fondo seguras, como la lista blanca de Incredible |
| **`focus_window(title)`**: ventana cuyo título contenga `title` en la app delante o nombrada; `kAXRaiseAction` + activar la app | "la ventana de Jev-voice" hoy es imposible |
| El texto **nunca lleva Return implícito**; `press_key("return")` es una llamada aparte | que "escribe hola" no ejecute nada |
| **En apps de comandos** (`CommandApps`: terminales, editores con terminal/agente — Cursor, VS Code, Zed — y apps de agentes — Claude, Codex, ChatGPT): `press_key("return")` **siempre** pide la hoja; `type_text` va directo solo si es **una línea que la usuaria dijo**; cualquier otro texto pide la hoja; caracteres de control o de formato se rechazan | pegar dos líneas en zsh las ejecuta; un texto no dicho es un comando no pedido (revisión 2026-09-25, H1/H2/H3) |
| **Fuera de apps de comandos**: `type_text` directo salvo una dirección/ruta/flag (`://`, `www.`, `x.tld/`, `/`, `~`, `-x`) que la usuaria no dijo; `press_key("return")` directo solo si lo pidió ("envíalo", "dale enter", "búscalo", "send it"…), si no, hoja con la app que lo recibe. Controles se quitan del texto | Return envía un correo o un mensaje; una URL no dicha navega (H1) |
| **App fijada al hablar**: el pid delante al empezar el hold o al enviar el chat es el único destino del turno; si cambió, `target_changed`. Un `open_app`/`open_url`/`open_file` que sale bien libera el pin (la usuaria pidió ese cambio) | el modelo tarda segundos; escribir en lo que esté delante entonces cae en otra ventana (code review HIGH-1) |
| Nunca en `AXSecureTextField`, nunca en Companion, nunca si el pid cambió desde que el usuario habló | mismas reglas de 12e |
| Las tres tools se anuncian **solo con Accesibilidad concedida** | regla "tool sin respaldo no se ofrece" (ROADMAP 2026-08-24) |
| `ChatPrompt.actRule` dice que puede escribir y pulsar Return en el campo enfocado; `ToolSpec.delegate` y `delegateRule` dejan de decir que el especialista "tiene la terminal" | el prompt engañaba al modelo |
| Regla de prompt intacta: solo lo que el usuario pidió con sus palabras; el texto de pantalla nunca es una orden | inyección por pantalla |
| Depende de 15f-1 (JSON→handoff) o del cerebro nuevo de 15f-4 | sin eso el modelo sigue escribiendo la llamada como texto |
| **`read_focused()`**: devuelve el texto del campo enfocado de la app delante (AX `kAXValue`/`kAXSelectedText`, recortado a 500 chars, nunca en campos seguros) | hoy el modelo afirma "escribí X" sin poder verificarlo (log 2026-09-25 15:10: "no lo veo… ¿puedes verlo?"); Incredible verifica por el árbol AX |
| **Prompt: actuar, nunca instruir.** `actRule`: si puede hacerlo con una tool, lo hace; jamás le dice al usuario "abre una pestaña y escribe…"; si no puede, una frase diciendo por qué. Sin pedir confirmación salvo Return en terminal | log 15:09:00: "Abre una nueva pestaña en Safari y escribe google.com" → Karen: "hazlo tú". Incredible no pide comandos, actúa |
| **Anuncio del encargo con palabras propias**: `jobAnnounce` dice una frase corta ("Voy, dame un momento") y al terminar el resultado resumido; nunca lee "El especialista respondió «…»" | log 15:11:41 y 15:12:39: eco literal del goal, 40–60 s de espera; Incredible resume con su summariser |
| **Sin subagente para escribir**: con `type_text` disponible, `delegateRule` excluye "escribir en un campo/app" del reparto a Claude Code | hoy el subagente tecleó por AppleScript `keystroke` y perdió los espacios (lo admitió él mismo en la conversación); 17–57 s por intento |

### 3b. Latencia del cerebro (mismo log): medir antes de tocar

`commit→firstToken` 419–6401 ms sin subagente. Sospechosos: la espera de visión (`ScreenNeed.wait` = 2 s si la frase apunta a la pantalla o no hay texto AX), la ejecución de la tool (`open_url` a Google tardó 3,3 s dentro del turno) y el primer turno frío. Entrega 15g-5: marcas `commit→context` y `tool→done` ya existentes visibles en la línea del timeline, y regla de visión al estilo Incredible: nunca bloquea el cerebro salvo que la frase apunte a la pantalla; si llega tarde, entra en el siguiente turno.

Fuera: clics de ratón, menús, scroll, capturas para el modelo, `set_value` arbitrario por
selector, worker "computer use" aparte, Automatización/AppleScript.

---

## 4. Entregas

| # | Qué | Archivos |
|---|---|---|
| 15g-0 | `ParentTool.typeText/.pressKey/.focusWindow` + descripciones es/en; `NamedKey` y `KeyPressing`/`WindowRaising` (Core) | `ParentTools.swift`, `Dictation.swift` |
| 15g-1 | `AXTextInjector.focusedField(pid:)`, `press(_:pid:)` por `CGEventPostToPid`, `raiseWindow(title:pid:)`; detección de terminal por bundle id | `AXTextInjector.swift` (+ extensión si pasa de 800) |
| 15g-2 | `ParentToolRunner` ejecuta las tres tools con las reglas de §3 y la aprobación en terminales; anuncio condicionado a Accesibilidad | `ParentToolRunner.swift`, `CompanionMain.swift` |
| 15g-3 | Prompt: `actRule` con manos; `delegateRule`/`ToolSpec.delegate` sin "la terminal" | `ChatPrompt.swift`, `ToolSpec.swift` |
| 15g-4 | `read_focused` (AX valor/selección del campo enfocado, ≤ 500 chars, nunca seguro) + anuncio del encargo con palabras propias + `delegateRule` sin "escribir en un campo" | `ParentTools`, `AXTextInjector`, `ParentToolRunner`, `VoiceSessionPumps.jobAnnounce`, `ChatPrompt` |
| 15g-5 | Timeline: `commit→context` visible; visión no bloquea salvo frase que apunte a la pantalla (`ScreenNeed.wait` sin la rama `!hasText`) | `TurnTimeline`, `ScreenNeed`, `ClassicRuntime` |

### 4a. Estado (sesión 1, 2026-09-25)

- **15g-0 HECHA.** `ParentTool.typeText/.pressKey/.focusWindow/.readFocused` + `isHands`; `ParentTool.specs` sigue devolviendo solo las cinco de siempre y `handsSpecs` las cuatro manos (se declaran aparte). Esquemas y copia es/en de las manos en `CompanionCore/ParentToolHands.swift` junto con `HandsGate` (regla pura: Return o salto de línea en terminal → hoja). En `Dictation.swift`: `NamedKey` (lista cerrada + `parse`), `KeyPressing`, `WindowRaising`, `FocusedReading` (`focusedField(pid:)` + `read(pid:)`), `TerminalApps`, `WindowTitles.match` (sin mayúsculas ni acentos), `FocusedText.clip` (500).
- **15g-1 HECHA.** `CompanionServices/AXTextInjectorHands.swift`: `focusedField(pid:)`, `read(pid:)`, `press(_:pid:)` por `CGEvent.postToPid` (fuente privada, flags vacíos, down+up), `raise(titleContaining:pid:)` (`kAXWindows` + `kAXRaiseAction` + `activate`), `bundleID(of:)`, tabla `keyCode`. Rechaza el pid propio, el bundle propio y procesos muertos.
- **15g-2 HECHA.** `ParentToolRunner(hands: ScreenHands?)` + `ParentToolRunnerHands.swift`; `ParentToolExecuting` gana `approval(for:said:)` y `granted(_:)` (default = `ParentToolGate`, no-op) y los tres caminos (chat escrito, `ParentToolGuard` de voz, `DecisionGate`) preguntan al runner. Cableado en `CompanionMain` con el `AXTextInjector` del dictado y `frontmost.lastOtherPID`. `ChatCopy.approvalDetail` muestra la tecla, el texto solo en terminal, `chars=N` fuera.
- **15g-4 (mitad `read_focused`) HECHA.** El anuncio del encargo ya estaba (15f); `delegateRule` es de la sesión 2.
- **Desviaciones:**
  1. El pid se captura cuando la llamada llega al runner (en `approval(for:)` si hay hoja, si no en `execute`), no "al hablar": el runner no ve el turno. `lastOtherPID` excluye a Companion, así que hablarle no lo mueve; se revalida justo antes de cada puerto (`target_changed`).
  2. "Ya no es la app en la que estaba la usuaria" lo comprueba el runner (relee el sensor), no `focusedField(pid:)`: el adaptador no conoce el sensor.
  3. La aprobación de terminal usa un ticket de un solo uso (`ApprovalTickets`: `approval(for:)` lo aparca con el id de la petición, `granted` lo habilita, `execute` lo gasta). Un camino que se salte la hoja o una denegación → `approval_required`, nada escrito.
  4. El "esquema" de `press_key` es `NamedKey.parse` + la lista en la descripción: `ToolProperty` no tiene `enum` y `ToolSpec.swift` es de la sesión 2.
  5. `type_text` reutiliza `inject` del 12e tal cual: exige que la app destino esté delante (el pegado va al frente). Con Companion delante (chat escrito) devuelve `target_changed: the app is no longer in front`.
  6. `focus_window` busca solo en la app de delante; "o nombrada" queda fuera.

### 4b. Estado (sesión 2, 2026-09-25)

- **15g-3 HECHA.** `ChatPrompt.system` gana `handsEnabled`; `actRule` añade (es/en) `type_text`, `press_key`, `focus_window`, `read_focused`, "nunca le digas al usuario que lo haga" / "never tell the user to do it", una frase con el porqué si no puede, verificar con `read_focused` antes de decir que quedó escrito y confirmación solo para Return en una terminal. La cláusula 12e se conserva y ahora cubre también escribir ("ni nunca escribas un texto" / "never type text"). `delegateRule` y `ToolSpec.delegate` dicen "una shell"/"a shell" en vez de "la terminal".
- **15g-4 (mitad prompt) HECHA.** `delegateRule`: "Escribir en un campo o app no se delega" / "Typing into a field or app is never delegated"; `ToolSpec.delegate`: "Nunca para escribir en un campo o app" / "Never for typing into an app".
- **15g-5 HECHA.** `ScreenNeed.wait` espera 2 s solo si la frase apunta a la pantalla. `ScreenSight` ya no cancela la visión que pierde la carrera: la aparca (un solo hueco) y el siguiente `finish` que vuelva a perder la usa una vez, con `pending: false`, el resumen viejo y el texto AX de ahora por delante de sus snippets; una visión a tiempo o `cancel()` la descartan. `TurnTimeline.contextReady` + tramo `commit→context` (entre `commit→audio` y `commit→firstToken`), marcado en `ClassicRuntime` justo antes del primer `chat.stream`.
- **Tests:** `PromptHandsTests` (filas 10 y 12), `ParentToolPromptWiringTests` (manos solo con `type_text` declarada), `ScreenNeedTests` (fila 14), `TurnTimelineTests`, `SightCarryTests` (visión tardía en el turno N+1, uso único, `finish` respeta su espera, línea con `commit→context` tras un turno guionado).
- **Desviaciones:**
  1. Las frases de manos van detrás de `handsEnabled`, que `ChatSSEAttempt` deriva de que `type_text` esté declarada (regla "tool sin respaldo no se ofrece"): sin Accesibilidad el prompt no promete escribir. El prompt de realtime (`RealtimeRuntime.instructions`) no las recibe.
  2. La exclusión de escribir en `delegateRule`/`ToolSpec.delegate` es incondicional: el especialista escribe mal (AppleScript sin espacios) con o sin manos.
  3. Bug encontrado: `ScreenSight.race` era un task group cuyo hijo solo esperaba `task.value`; el grupo esperaba la visión entera dijera lo que dijera `wait` (el mismo defecto que ya documenta `DecisionGate.race`). Reescrito con una continuación de un solo `resume`, sin cancelar la visión que pierde (hace falta para arrastrarla).
  4. `ScreenNeed.wait` conserva el parámetro `hasText` (ya sin efecto) para no tocar a los llamadores.

## 5. TDD (rojo primero)

| # | Test | Espera |
|---|---|---|
| 1 | `type_text` con campo enfocado normal en la app delante | `inject` con el texto, al pid correcto; sin Return |
| 2 | campo `AXSecureTextField` | `ContractError`; nada inyectado; log sin texto |
| 3 | la app delante es Companion | rechazado |
| 4 | pid cambió entre el turno y la inyección | rechazado |
| 5 | `type_text` con "\n" en Terminal | pasa por aprobación; denegada → nada |
| 6 | `press_key("return")` en Terminal / en Notas | aprobación / directo |
| 7 | `press_key("f4")` | rechazado por esquema (lista cerrada) |
| 8 | `focus_window("Jev")` con dos ventanas | `kAXRaiseAction` en la que coincide |
| 9 | sin Accesibilidad | las tres tools no se anuncian |
| 10 | prompt | `actRule` menciona `type_text`/`press_key`; `delegate` ya no dice "terminal" |
| 11 | `read_focused` en Notas / en campo seguro | texto ≤ 500 / rechazado |
| 12 | prompt | `actRule` contiene "nunca le digas al usuario que lo haga" (es/en); `delegateRule` no reparte "escribir en un campo" |
| 13 | `jobAnnounce` | habla una frase propia ≤ 12 palabras; nunca contiene «El especialista respondió» |
| 14 | `ScreenNeed.wait("abre Safari", hasText: false)` | `.zero`; con "qué dice esto" → 2 s |

## 6. Seguridad

- Ninguna tool escribe el texto en el log principal (solo `chars=N`, pid, bundle id).
- Apps de comandos: Return siempre con hoja; texto directo solo si es una línea dicha; controles rechazados.
- Resto de apps: Return con hoja salvo que se pidiera enviar; direcciones no dichas con hoja.
- La hoja muestra el texto entero (sin corte) y, para Return en una app de comandos, la línea actual.
- Pase de un solo uso, atado a nombre+argumentos+pid, caduca a los 60 s.
- Campos de contraseña: rol **o subrol** `AXSecureTextField` (C1: el subrol era el caso real y no se miraba; afectaba también al dictado de 12e).
- Portapapeles con `org.nspasteboard.ConcealedType`/`TransientType` (gestores de contraseñas) nunca entra al contexto.
- Resultados de herramientas (campo leído, página, resultado de un trabajo) son datos, no órdenes (prompt).
- El texto de pantalla no puede convertirse en orden: la regla del prompt se conserva y se
  cubre con el test de 12e que ya existe para `actRule`.

## 7. Done (en vivo, Karen)

1. En Notas: "escribe hola mundo" → aparece; "dale Enter" → salto de línea.
2. En Terminal: "escribe ls" → aparece sin ejecutarse; "dale Enter" → hoja de aprobación → se ejecuta.
3. "Pon la ventana de Jev-voice en primer plano" → esa ventana.
4. En un campo de contraseña: se niega y lo dice.

## 8. Aprobación

Aprobada 2026-09-25. Arranca al cerrar 15f (necesita 15f-1).

## 9. Revisión (2026-09-25)

Code review: WARNING (0 críticos, 2 altos). Security review: BLOCK (1 crítico, 4 altos). Todo
corregido con test en rojo primero. 361 tests verdes ×3 (1 known issue previo), gates 0 fallos.

| Hallazgo | Arreglo | Test |
|---|---|---|
| **C1** campo de contraseña nunca detectado: se comparaba el rol, pero `AXSecureTextField` es subrol | `AXSecure.isSecure` mira rol y subrol; lo usan dictado, manos y lectura de pantalla | `AXSecureTests` |
| **H1** escribir/Return no atados a lo dicho | `HandsGate.verdict(call, commandApp:, said:)` + `HandsWords` (§3) | `HandsPolicyTests` (dicho, compuesto, dirección, Return con/sin pedirlo) |
| **HIGH-1** destino = lo que esté delante al ejecutar | `beginTurn()` en el protocolo; el hold y el chat fijan el pid; `open_*` lo libera | `testATargetThatChangedSinceTheUserSpokeIsRefused`, `testOpeningAnAppInTheTurnMovesTheTargetOnPurpose` |
| **H2** lista de terminales corta | `TerminalApps` → `CommandApps` con Cursor, VS Code, Zed, WezTerm, Hyper, Tabby, Warp Preview, Claude, Codex, ChatGPT, Alacritty (ambos ids) | `ScreenHandsTests` |
| **H3** solo se miraban saltos de línea | Cc/Cf rechazados en apps de comandos, Cc quitados en el resto | `testControlCharacters…` |
| **H4** portapapeles de gestores de contraseñas en el contexto | se salta con tipo Concealed/Transient | `ContextSensingTests` |
| **HIGH-2/M2** visión tardía sin app ni edad | aparcada con pid y hora; solo misma app y ≤ 30 s; marcada como vieja | `SightCarryTests`, `ContextBlockTests` |
| **M1** la hoja cortaba a 200 y no decía dónde iba Return | texto entero; Return con app y línea actual | `ScreenHandsTests` |
| **M** `read_focused` devolvía los primeros 500 | ventana alrededor del cursor (`kAXSelectedTextRange`) o el final | `testReadFocusedReturnsTheTextAroundTheCaret` |
| **M** barge-in no paraba el Return tras `type_text` | `act` comprueba cancelación entre llamadas | `testABargeInStopsTheRemainingCalls` |
| **M** chat escrito anunciaba manos con Companion delante | `selfInFront` oculta las manos | `testTheHandsAreHiddenWhileCompanionIsInFront` |
| **M3** resultados de tools como órdenes | la regla de datos cubre lo que devuelve una herramienta | `PromptHandsTests` |
| **L1** pase sin caducidad | 60 s; un park nuevo invalida el anterior | `testAnExpiredTicketIsNotSpendable` |
| **L** "Abriendo return…" | teclas y títulos no son objetivo mostrado; "Actuando…" | `testActingCopyNeverNamesAKeyOrATitle` |
| **L2** título de ventana y JSON crudo en el hilo | estado sin título; error de argumentos con tamaño, no el crudo | `testAWindowTitleIsNeverInTheStatusLine`, `testMalformedArgumentsAreNotEchoed` |
| **L3** Cmd-V del pegado al tap HID (lo oye la tecla del hold) | `postToPid` con fuente privada | sin test: necesita Accesibilidad real; se prueba en vivo (§7) |
| **L** realtime sin `handsRule` | se pasa `handsEnabled` cuando `type_text` está declarada | `ParentToolPromptWiringTests` |
| **L** se esperaba `axSnippets()` para un `hasText` ignorado | `ScreenNeed.wait(utterance:)` | cubierto por `ScreenNeedTests` |

Desviaciones:
- El preámbulo hablado "Escribo: <texto>" no se hizo: el estado se guarda en el hilo y L2 pide no
  guardar texto escrito ahí. El texto compuesto sin dirección se escribe en silencio; Return sigue
  necesitando que se pida.
- `focus_window` sobre una app **nombrada** queda abierto: tras `open_app` el pin se libera y
  `focus_window` actúa sobre la app abierta, que cubre "abre X y trae la ventana Y".
- Recordar una decisión de la hoja ("siempre") para Return en una app de comandos sigue siendo
  posible por el mecanismo general de aprobaciones; queda anotado para la wave de UX.
- Flakes vistos una vez, no relacionados: `sessionModelTests` (fase del trabajo) y
  `utteranceLogPrivacyTests` (captura del log); pasan en las 3 corridas siguientes.
