# Wave 19 — Isla rica: información, no comandos

Estado: APROBADO (Karen, 2026-09-28) — 19-1 EN CURSO
Fecha: 2026-09-28
Origen: pedido de Karen tras el primer E2E del puente ("no necesitamos ver
comandos, necesitamos mejorar la manera en la que la información hace
display"), con boring.notch (github.com/TheBoredTeam/boring.notch) como
referencia de motion, componentes, maquetación y estados.

## 1. Problema

La captura del E2E lo muestra entero: la hoja de aprobación imprime el id
crudo de la tool ("open_url") y la URL pelada en una caja tipo código; el
chip "Manos: Claude Code" es texto gris genérico y en reposo ni siquiera se
dibuja (el nudge va por el camino del composer y nunca pinta el chip); el
Listo final es una palabra y un punto, sin recibo de lo que pasó. La isla
informa como un log, no como un producto.

Hallazgos completos del inventario (agente, 2026-09-28) y del análisis de
boring.notch con file:line en la bitácora de esta wave. Lo que manda:

- `ApprovalSheet.swift:28` imprime `request.toolName` crudo; el detalle es
  la URL/comando/ruta sin formato; `request.summary` (que ya existe) se
  ignora para todo lo que no es bridge y además está en inglés hardcodeado.
- La hoja es ajena a la isla: superficies `Semantic` del tema, `width: 420`
  fijo y `cornerRadius: 8` literal (2 infracciones del baseline) dentro del
  panel negro de 492 con su propio padding.
- El título del bridge no dice quién pide ("quiere usar tus manos", sin
  cliente).
- Manos en reposo: `IslandState` fuerza `.nudge` pero ese tamaño renderiza
  el composer, nunca el chip ni la luz. La señal de "alguien conduce" en la
  isla no existe justo cuando más importa.
- Deriva de radios: 22 (`NotchShape`) vs 28 (`IslandInk.radius`) para la
  misma silueta; tarjetas en 8/12/16; métricas sueltas fuera de las rampas.
- Sin transición aprobación→respondida, sin feedback de negado/timeout, sin
  recibo en completed; las piezas 16l (`AnswerOption`, `CaptureCard`,
  `AnswerPopup`) están muertas sin call sites.

## 2. Principios (de boring.notch, adaptados a nuestro contrato)

boring.notch se siente rico por cinco cosas medibles; las adoptamos SIN
contradecir 16f (springs cerrados §4, M1-M8) ni 16n (Geist, rim 12%, negro):

- P1 **Información antes que datos.** Icono primero, número opcional;
  duraciones `m:ss`; "muted" en vez de "0%"; marquee en vez de truncar.
  Nuestro equivalente: frase humana antes que id de tool, host antes que
  URL, glifo de app antes que nombre crudo.
- P2 **Continuidad entre estados.** Lo que persiste entre tamaños se mueve
  con `matchedGeometryEffect` (su albumArt cerrado→abierto); el contenido
  entra desde el ancla superior y sale desvaneciéndose, asimétrico.
  Nuestro blur sale ≤3 (M5), no 30 como el suyo.
- P3 **El color viene del contenido.** Su aura nace del artwork con piso de
  brillo. Nuestro acento ya existe (rueda del glow); las tarjetas pueden
  teñir hairlines/glifos desde el estado (ámbar aprobación, azul manos)
  sin salirse de `IslandInk`.
- P4 **Respuesta directa.** Hover que engorda (sus wings +12pt, slider
  5→9pt), `contentTransition(.interpolate)` en símbolos y `.numericText()`
  en cifras. Todo cabe dentro de los budgets ya definidos.
- P5 **Transitorio breve y de una sola cosa.** Su peek dura 1.5s y su
  cadena de prioridad garantiza un solo contenido en el notch cerrado.
  Nuestro equivalente: el recibo de completed vive unos segundos y cede.

## 3. Alcance — cuatro sesiones

### 19-1 La hoja habla humano (la del screenshot)

- `ApprovalCopy` nuevo en Core: de `ApprovalRequest` tipado → título y
  detalle humanos por tool, en los tres idiomas vía `Localized` (hoy
  `summary` nace en inglés en `ParentToolPolicy/ParentToolHands/
  AgentStreamCodec`; deja de mostrarse texto que no pasó por el catálogo).
  - open_url → "Abrir **wikimedia.org**" + ruta secundaria en muted, glifo
    de enlace; nunca la URL entera como protagonista (se conserva
    seleccionable en secundario: la usuaria debe poder auditar).
  - type_text → "Escribir en **Notas**" + vista previa citada y truncada.
  - click → "Pulsar **Permitir** en **Safari**".
  - run_shell → "Ejecutar **npm run build**" + comando completo secundario.
  - bridge_session → "**Claude Code** quiere usar tus manos" (el cliente
    por fin en el título; viene en `inputJSON`, ya saneado).
- La hoja se re-viste con el lenguaje de la isla: `IslandInk` + `Radius`
  (fuera `width: 420` y `cornerRadius: 8` → el baseline BAJA 2).
- El id crudo de la tool desaparece del cuerpo; queda en el tooltip/detalle
  expandible para auditoría, no como primera línea.
- "Permitido, como antes: %@" (ChatCopy:118) también pasa a frase humana.

### 19-2 Continuidad y estados (motion fino)

- Transiciones asimétricas de contenido: entrar = opacity+move desde
  arriba; salir = opacity+blur(≤3). Hoy `contentOut` es un fade plano.
- `matchedGeometryEffect` para lo que persiste entre tamaños: la luz, el
  chip de manos, los slots de tareas.
- `.contentTransition(.interpolate)` en los glifos que cambian y
  `.numericText()` en contadores ("N pasos").
- Aprobación→respondida: la hoja no se corta; colapsa a una línea de
  veredicto ("Permitido · abrir wikimedia.org") que vive ~1.5s (P5) y cede.
  Negado y timeout tienen su línea propia.
- Todo dentro de M1-M8 y de los budgets existentes; cero curvas nuevas
  fuera de `Motion.swift`.

### 19-3 Manos visibles

- Arreglo del hueco: con manos prestadas en reposo la isla muestra el chip
  (hoy `.nudge` va al composer y lo omite). El chip gana glifo y color
  propio (azul de la rueda, no el gris genérico); el ámbar queda solo para
  aprobación pendiente.
- Recibo por acción: bajo el chip, la última acción en frase humana
  ("Pulsó Permitir en Safari"), reemplazándose con textSwap. La isla narra
  lo que las manos hacen — es UX y es seguridad.

### 19-4 Recibos y limpieza

- Completed con recibo: qué se hizo, una línea, glifo de la app tocada;
  vive unos segundos (P5) y vuelve al reposo.
- Unificar la deriva de radios de la silueta (22 vs 28 → un solo valor en
  tokens) y absorber las métricas sueltas que se toquen de paso.
- Borrar las piezas 16l muertas (`AnswerOption`, `CaptureCard`,
  `AnswerPopup`, `ReferentChip`) o dales call site real — nada de mockups
  (principio 16m).

## 4. API (resumen)

- Core: `ApprovalCopy.title(_:language:)`, `.detail(_:language:)`,
  `.receipt(_:language:)` — puras, testeables sin ventana; claves nuevas en
  los tres `Localizable.strings`.
- Core: `IslandState` gana el caso de manos en reposo (chip visible) y el
  veredicto post-aprobación como `Line` nuevo.
- UI: `ApprovalSheet` consume `ApprovalCopy`; pierde sus literales.
- Sin cambios de protocolo ni de Services (el puente no se toca).

## 5. Restricciones

- Tokens y ratchet: el baseline SOLO baja (hoy 55; 19-1 quita 2 mínimo).
- M1-M8 intactos; springs de 16f intactos; Geist/negro/rim de 16n intactos.
- Core puro: copy por catálogo, nada de strings de UI nacidos en inglés.
- La usuaria SIEMPRE puede ver el dato completo (URL/comando) — humano
  primero no es esconder: es jerarquía. La hoja sigue siendo el modelo de
  seguridad; nada se auto-aprueba ni se acorta el camino del "No".
- 16m sigue en borrador: esta wave no lo implementa, solo no lo contradice.

## 6. Riesgos

- `approvalDetail` alimenta también el chat/ventana: cambiarlo arrastra
  más pantallas de las que parece → 19-1 audita call sites antes de tocar.
- El catálogo crece en tres idiomas de golpe: pt/en necesitan revisión de
  Karen antes del cierre.
- matchedGeometry entre tamaños de la isla puede pelearse con la
  coreografía shape-first de 16f → prototipo primero en 19-2, con la
  grabación comparada como evidencia.

## 7. Criterios de cierre

- La captura del E2E rehecha: misma acción (open_url de Wikimedia) muestra
  frase humana + host, sin id crudo, hoja vestida de isla.
- Manos en reposo: chip visible con recibo de última acción.
- Recibo de completed visible unos segundos tras un encargo.
- Baseline del contrato ≤53 y radios de silueta unificados.
- Gates verdes; MotionBudgetTests verdes; grabación antes/después.
