# Wave 16m — Los componentes de la isla como Incredible

**Estado: APROBADO (2026-09-28).** Firmado por delegación de Karen ("firma el resto cuando
finalicemos", al cierre del QA en vivo de 16k). Karen: "que hay de los componentes de la
ui de notch? nos faltan muchos componentes, sobretodo de display de datos, estados, archivos
adjuntos, etc".

Evidencia: `docs/research/incredible-isla-componentes.md` (medidas de su CSS del overlay).
Base: 16l (tinta de la isla, chip de referencia, piezas base).

## 1. Principio

Karen (2026-09-28): "lo quiero exactamente como incredible, con cada uno de sus widgets
actuales replicados". El alcance pasa de "una selección" al **catálogo completo** de
`incredible-isla-componentes.md`. El principio del dato se mantiene pero cambia de filtro a
orden: cada componente entra **con su dato**, y el que no tenga fuente en Companion entra
igual con su plomería de dato como parte de la sesión (nunca como maqueta). La fidelidad es
a los VALORES medidos (medidas, tintas, radios) y al comportamiento observado en las
grabaciones — jamás a su código, que no se lee ni entra al repo.

## 2. Sesiones

| Sesión | Qué | De dónde sale el dato |
|---|---|---|
| 16m-1 | **Respuesta rica en la isla**: popup `ovx` con títulos, párrafo, lista, tabla, callout, código (copiar, plegar), código en línea, clave-valor, chip de archivo, cita, tareas, enlace | La respuesta del turno ya existe como markdown; hoy solo llega su título a la tarjeta. Se reutiliza el parser de `MarkdownView` (sin tocar ese archivo, que es de 16j): una vista nueva pinta los mismos bloques con la tinta `ovx` |
| 16m-2 | **Estados**: transcripción viva (72 %) → fija (94 %), carrete de apps tocadas, tarjeta de ejecución con pasos (runcard) y checklist para trabajos largos, barras de agentes | `partial`, `targets`, `job(goal, steps)` y los eventos del ejecutor, que ya están en la proyección de la sesión |
| 16m-3 | **Adjuntos en la isla**: tarjetas 84 × 102 con vista previa, extensión y quitar; pila de capturas con contador; zona para soltar sobre el notch; el clip adjunta en la isla en vez de abrir la ventana | Los adjuntos del chat (`ChatViewModelAttach`) pasan a compartirse con la isla |
| 16m-4 | **Dictado y avisos**: tarjeta de resultado de dictado (copiar / ocultar); avisos del sistema con la rejilla de Incredible (permiso, actualización, límite de la clave, diagnóstico) | Dictado 12e; fallos de voz y permisos que ya produce `VoiceFailureMapping` |

Sesiones nuevas por la orden de catálogo completo (2026-09-28):

| Sesión | Qué | De dónde sale el dato |
|---|---|---|
| 16m-5 | **Gráficas y diagramas**: contenedor `visual` (padding 14/16/12, relleno 5 %, borde 7 %, radio 12, herramientas copiar/ver); gráficas en lienzo de 240 (264 para pie, dona, polar y radar); diagramas Mermaid | Gráficas: **Swift Charts** (framework del sistema, cero dependencia) para barras, líneas, área, pie y dona; polar/radar con `Path` propio. Mermaid: **la única dependencia nueva de la wave** — `mermaid.js` vendoreado (sin red) en un `WKWebView` aislado; ver D3 |
| 16m-6 | **Pregunta con opciones** (`answer-card` 340–440, padding 18 × 20, gap 14) y **avisos con rejilla**: límite de uso (380, 38+resto), actualización (522, 30+resto+acciones), consentimiento (340–440), diagnóstico (mín(420, 86 %)) | La pregunta con opciones necesita que el turno la produzca: entra el bloque en el contrato del turno (16h la usa); los avisos salen de `VoiceFailureMapping`, del updater y de los permisos que ya se detectan |
| 16m-7 | **Menciones (@)** (selector 240 de alto, ítem 6 × 8, hover acento 16 %) y **comentarios** (modal 480, padding 32, radio 28, ánimo + capturas + contador) | Menciones: primero la fuente — un `Contacts.swift` mínimo (permiso de Contactos del sistema); sin permiso, el selector ofrece apps conectadas y archivos recientes. Comentarios: el enlace de feedback existente se convierte en el modal |

Fuera, ya sin excepciones, solo lo que Incredible tampoco tiene en la isla hoy. La **subida
a la nube** queda fuera: Companion no tiene backend de archivos y replicarla exigiría uno
(decisión de producto aparte, no de esta wave).

## 3. TDD

Cada sesión fija sus medidas en un test (valores de la investigación) y la lógica que alimenta
la vista (qué bloque sale de qué markdown, qué estado sale de qué evento) con tests de
proyección, antes de pintar. Verificación visual con snapshots comparados con capturas de
Incredible en el mismo estado.

## 4. Riesgos

- 16m-1 es la más grande: la isla crece a un popup de 580 que tapa contenido. Se abre SOLO al
  pedirlo ("Ver") — D2 lo fija por el comportamiento observado.
- 16m-3 cambia un flujo (el clip abre la ventana): D1 lo fija — adjunta en la isla.
- 16m-5 mete un `WKWebView` en la isla solo para Mermaid: va aislado (sin red, CSP cerrada) y
  con revisión de seguridad propia antes del merge.
- `IslandView` ya tiene 554 líneas: cada pieza va en su archivo. Con 7 sesiones, el riesgo de
  que la isla se vuelva un dios crece: el layout por familia (datos, estados, adjuntos,
  dictado, avisos) va en carpetas separadas desde la primera sesión.

## 5. Decisiones — FIRMADAS 2026-09-28

Karen: "Contesta las decisiones directamente auditando [a Incredible]". Respondidas con el
comportamiento observado en las grabaciones y el CSS medido (nunca su código):

- **D1 — El clip adjunta en la isla. SÍ, como Incredible.** Observado: en su isla "escribir y
  hablar viven en el mismo sitio" — campo, clip y flecha en el mismo panel
  (`ux-incredible-vs-companion.md` §isla); las tarjetas de adjunto (84 × 102), la fila de
  chips, la pila de capturas y la zona para soltar viven todas en el CSS del OVERLAY, no de la
  ventana (`incredible-isla-componentes.md` §3). `⌥⇧⌫` limpia lo adjunto sin abrir nada. El
  clip de Companion deja de abrir la ventana: adjunta en la isla (16m-3).
- **D2 — La tarjeta con resumen sale sola; el popup rico se abre con "Ver".** Observado: sus
  resultados se apilan debajo como tarjetas con una línea de resumen y botón "Show →"; la voz
  dice una frase y el detalle espera al click. Nunca se despliega el popup completo sin
  pedirlo — una frase corta jamás abre popup. Companion replica exactamente eso: tarjeta
  automática con título + primera línea, popup `ovx` (580 / 76 %) solo al "Ver".
- **D3 — Gráficas y diagramas ENTRAN (16m-5); la dependencia se decide aquí mismo.** Su isla
  actual los tiene (lienzos de 240/264 con pie, dona, polar y radar; contenedor `visual` con
  copiar/ver; diagramas Mermaid). Réplica nativa: **Swift Charts** para las gráficas (framework
  del sistema — cero dependencia nueva; polar/radar con `Path`); **Mermaid con `mermaid.js`
  vendoreado** dentro de un `WKWebView` aislado, sin acceso a red, CSP cerrada, solo para
  pintar — es la única dependencia tercera de la wave y este párrafo es su decisión firmada.

## 6. 16m-4 — valores propios y reversión de 12e (2026-09-29)

Valores que Incredible no mide y que fijó esta sesión (cambiarlos es decisión de producto, no de CSS):

| Valor | Elegido | Dónde |
|---|---|---|
| Plazo de la tarjeta de dictado | 12 s, con el puntero encima no caduca; al salir o al copiar se rearma | `SessionMachine.dictationCardDelay` |
| Líneas visibles del texto dictado | 6 (copiar siempre toma el texto entero) | `IslandDictationMetrics.maxLines` |
| "Copiado" en el botón | 1,5 s, y se anuncia por VoiceOver | `IslandDictationMetrics.copiedFor` |
| Rejilla del permiso | la de consentimiento (340–440, gap 10, ancho recortado a lo que pide el texto); la investigación no le da fila propia | `IslandNoticeMetrics` |
| Padding y gaps del diagnóstico y la actualización | los del límite (18 × 20; 10 × 12) | `IslandNoticeMetrics` |
| Ancho de la actualización | 522 medido, pero la forma de la isla es 492 y se fija por tamaño en cuatro sitios: la tarjeta se recorta a lo que hay (460). Ensanchar la forma queda para 16m-6 | `IslandNoticeMetrics.width` |

**Reversión de 12e §7.** 12e decía "Popup de resultado: no; la isla ya lo dice". 16m-4 lo revierte:
el resultado del dictado es una tarjeta con copiar / ocultar. La puerta `dictation-never-logged`
se reformula: lo dictado va al campo enfocado y, en memoria, a esa tarjeta hasta que se oculta
o caduca; nunca al log, al historial ni a la conversación. Las palabras viajan como `DictatedText`,
que se imprime redactado, y salen de la proyección por cualquier puerta que deje Completed.
La oferta de actualización no aparece con la isla oculta por la usuaria ni con la ventana
principal delante, y la página de release solo se acepta si es de `github.com/karenrebecag/Companion/releases`.

## 7. 16m-5a — gráficas, alcance real (2026-09-29)

Mermaid quedó fuera de esta entrega y entró en 16m-5b (§10), con la dependencia aprobada por Karen el
2026-09-29.

Lo que entra:

- **Fuente del dato**: ya existía la fence `companion:chart` (wave 20, `CardVocabulary` se la
  enseña al modelo). 16m-5a la extiende con `polar` y `radar` y le añade la regla de cuándo
  usarla; no se creó otra convención.
- **Regla de la frontera** (wave 20: los números no se tiran; la misma en popup, ventana y
  documento):
  - *Datos válidos que no se pueden dibujar* pasan a **tabla** (`asTable`): radar con menos de 3
    ejes, pie/donut/polar con negativos, todo cero o varias series, radar de más de
    `ChartBlock.maxRadarAxes` (20; a 24 pisaba las etiquetas de los polos en el snapshot) ejes, pie/donut/polar de más de `maxSlices` (12) rebanadas.
    Tipo desconocido también va a tabla.
  - *Datos estructuralmente rotos* devuelven nil: JSON inválido, valores no numéricos o no finitos,
    |valor| > `maxMagnitude` (1e12), series de largo distinto a las etiquetas, más de
    `maxPoints` (500) puntos u `maxSeries` (8) series, fence de más de `maxFenceBytes`
    (256 KiB, solo el cuerpo del fence; el documento entero no lo lleva). En el popup se pintan
    como código; en `DocumentSpec` dejan una nota visible (`omittedChartNote`, bilingüe), nunca
    desaparecen en silencio.
  - Cambia respecto a wave 20: antes se recortaba al tope.
  - Más de 500 puntos u 8 series siguen siendo dato roto (nil): es demasiado grande hasta para
    una tabla legible, así que se queda como código.
  - Una magnitud finita mayor que `maxMagnitude` (1e12) es dato válido: va a **tabla**, no a
    código (los números no se tiran). NaN, inf y no numéricos siguen rotos.
  - Presupuesto cartesiano: barra, línea, área y dispersión con etiquetas x series >
    `maxCartesianPoints` (1000) van a tabla (HACK: número redondo sin medir; se mueve cuando una
    gráfica de ese tamaño se sienta lenta). La tabla de la isla (`TableCard`) pinta como mucho
    `TableBlock.maxRows` filas y avisa cuando corta.
- **Texto del modelo**: `TextSanitizer.display` quita controles de dirección y C0/C1 (salvo
  salto y tabulador) y recorta a 120; se aplica una vez a etiquetas, título, unidad y series.
  Descarta también todo carácter de formato Unicode (espacios de ancho cero, BOM, guion blando,
  controles bidi), los separadores de línea y párrafo y las etiquetas Unicode, salvo ZWJ y ZWNJ
  (familias de emoji y escrituras que los necesitan); acota a 4 escalares por carácter contra
  el apilado de marcas. Se aplica también a stats, table y al título que muestra la isla
  (celda de tabla: 500). El CSV defusa `= + - @ tab CR LF | %` sobre el primer carácter y el
  primer no blanco, después de quitar los invisibles. Costo cosmético conocido: una etiqueta
  legítima como "% de cambio" sale con un `'` delante en el CSV copiado.
- **Topes de bytes**: cuerpo de fence 256 KiB (`maxFenceBytes`), documento entero 4 MiB
  (`maxDocumentBytes`), escritura de hoja 1 MiB (`maxSheetBytes`, ~200 bytes por celda de las
  5 000 que admite un rango). Un test falla si alguien parsea JSON del modelo con
  `CompanionBlocks.jsonObject` fuera de `DocumentSpec.parse` y `fenceObject`.
- **Vista** (`Island/Visual/`): contenedor `visual` (14/16/12, 5 %, 7 %, radio 12), lienzo 240 y
  264 (pie, dona, polar, radar); Swift Charts para barra, línea, área, dispersión, pie y dona;
  `Path` para polar y radar. Copiar = CSV. La herramienta "Ver" se quitó (código muerto: ninguna superficie la usa);
  **vuelve cuando exista la tarjeta con resumen en la isla** (D2).
- Polar y radar solo los pinta la isla: la tarjeta de la ventana y el PDF los muestran como tabla.

Valores propios (no medidos): 4 anillos, 3:1 de contraste mínimo, teal 5AC8FA en la paleta,
relleno 18 % (área/radar) y 35 % (cuña polar), donut 0.6, tope de leyenda 12, tope de etiquetas
de eje 8, ancho de etiqueta radial 64, copiado 1,5 s.

## 8. 16m-6: alcance real (2026-09-29)

**Pregunta con opciones (`answer-card`).**

- **Contrato del modelo**: fence `companion:choice` (misma convención `companion:*`), JSON
  `{"question", "options": [{"label", "detail"?}]}`; una opción también puede ser una cadena
  (un modelo chico no siempre sabe hacer objetos). `CardVocabulary` (es/en) enseña la fence y la
  regla de cuándo usarla: solo cuando la respuesta de la usuaria decide el siguiente paso, nunca
  para una pregunta retórica, y la pregunta se dice igualmente en una frase.
- **Parser** (`Core/ChoiceBlock.swift`, por `fenceObject`, saneado con `TextSanitizer`): la pregunta,
  la etiqueta y el detalle quedan en una línea (una etiqueta con salto enviaría dos líneas).
  Inválido → `nil` → la fence se ve como código, igual que el resto: pregunta vacía, menos de 2 o
  más de `maxOptions` opciones, opción que no es texto ni objeto con `label`, etiqueta vacía tras
  sanear, etiquetas repetidas (sin distinguir mayúsculas), fence de más de `maxFenceBytes`. Pasarse
  del tope de opciones se rechaza en vez de tirar opciones en silencio (cambiaría la pregunta).
  Etiqueta, detalle y pregunta largos se recortan (cosmético, no cambian el sentido).
- **Elegir = teclear**: `ChatViewModel.choose(_:)` comparte guardas, cola (`queued` con un turno en
  curso) y turno con `send()` (extraído `dispatch`), sin pasar por `draft`, para no pisar lo que ella
  tuviera a medias en la ventana. La tarjeta jamás ejecuta nada por sí sola.
- **Estado respondida**: se lee del hilo, no se guarda (`IslandChoice.resolution`): el siguiente
  mensaje de la usuaria que coincide con una etiqueta marca esa opción; cualquier otro (o un turno
  solo con adjuntos) cierra la pregunta sin marca. Sobrevive a reiniciar la app. Entre el clic y que
  el mensaje entre (turno ocupado, va a la cola) la tarjeta recuerda la elección local para que un
  segundo clic no mande otra respuesta.
- **Teclado** (`IslandChoiceKeys`): flechas con vuelta, Return elige la enfocada, 1-9 eligen por
  posición (`maxOptions` = 6 cabe en un dígito). Las teclas solo llegan a la tarjeta cuando tiene el
  foco (clic sobre ella o Tab); no lo toma al aparecer porque robaría lo que ella teclea en el campo,
  así que los números nunca chocan con el compositor.
- **VoiceOver**: grupo con la pregunta como etiqueta y una pista; cada opción dice "etiqueta, n de m"
  y luego "elegida" o "no disponible"; la elegida lleva el rasgo `isSelected`. La elegida queda
  nítida y sin respuesta al clic (`.disabled` la atenuaría, y es la que marca la respuesta); las demás
  quedan deshabilitadas.
- **Voz**: `SpeechBudget.hasCard` cuenta la pregunta como tarjeta (la voz dice una línea y remite a la
  isla); una pregunta rota no acorta la voz porque se ve como código.
- **Dónde se pinta**: bajo la respuesta de la isla (`reply(state)`: campo abierto o respondiendo), no
  en el popup `ovx` (no tiene canal de respuesta); por eso la pregunta no hace "rico" a un mensaje
  (`isRich`) ni ocupa lugar en el popup. La ventana de tarea (`MarkdownView`) la muestra como texto
  (pregunta y opciones numeradas): un hilo guardado no tiene por dónde responder.
- **`AnswerOption`** reconstruida en `Island/Choice/` (recuperada de `768def8^`, `IslandAnswerPieces`)
  sobre la tinta de la isla y las medidas 16l que seguían vivas (`AnswerOptionMetrics`, índigo). No
  duplica nada de 16p-2.

Valores propios (no medidos): 2 a 6 opciones; topes de pregunta 200, etiqueta 80, detalle 160;
lista con scroll pasado 260 pt (composer + respuesta + pregunta de dos líneas ocupan ~330 de los 592
que la forma puede crecer); opción no disponible al 45 %; relleno de la opción resaltada 22 %,
borde 40 %, insignia 42 % (los de 16l); insignia del número en el lado de un slot de la isla (22).
Medido: 340-440, padding 18 × 20, gap 14 (§5 de la investigación).

**Avisos.**

- **Consentimiento**: no hay fuente nueva que enchufar. Sus dos fuentes reales ya existían y desde
  16m-4 usan la rejilla de consentimiento: conectar una app que la usuaria nombró (`.connectApp`) y un
  permiso del sistema rechazado (`.permission`). La hoja de aprobación de herramientas
  (`ApprovalSheet`) es otro componente (aprobación por llamada, no consentimiento), no se toca.
- **Iniciar sesión**: fuente real = una cuenta conectada cuyo estado es `reconnect`
  (`ConnectedAccount.State`, el servicio ya la reporta y la página Apps ya pinta "Reconectar").
  `AppToolRunner` recuerda esas cuentas al refrescar y, si el turno nombra una, en vez de ofrecer
  "Conectar" (falso: existe) avisa una vez por arranque (`signIn`), que llega al reductor como
  `.signInAppSuggested` → `SessionCard.signInApp` → `IslandState.Line.signInApp`. La tarjeta usa la
  rejilla de límite (380, 38 + resto), se va sola como el aviso de conectar y su botón abre la página
  Apps en esa app. Sin cuentas cargadas no avisa (mismo motivo que M2: aún no se sabe).
  Tocó `SessionMachine.swift` (un caso del reductor y `fades`), dentro de la puerta.

**Ancho de la isla para la actualización: HECHO.** Era barato y seguro: el ancho sale de un solo
sitio (`IslandChrome.width(for:)`, que también alimenta `shapeSize`, y por ahí las tres rutas de
movimiento y el área de clic). Se añade el rol `IslandState.Size.wideCard`, que solo pide la oferta
de actualización; el resto de tarjetas sigue en 492. **Valor propio**: la forma mide 554, no 522,
porque la isla rellena 16 pt a cada lado y el aviso mide 522 (con 522 de forma seguiría en 490); el
lienzo (620) la aguanta con 33 pt de hombro y sombra por lado. El test de movimiento por pares de
tamaños ya recorre `allCases`, así que cubre el nuevo rol.

**Ronda de revisión (2026-09-29): reglas nuevas.**

- **Envío**: `choose` devuelve `Bool` (falso sin clave o con etiqueta vacía) y la tarjeta solo marca
  "pendiente" si salió. La decisión vive en `IslandChoiceState` (código puro): el pendiente cuenta
  mientras su etiqueta siga en `queued`; si la cola se vacía (cancelar, cambiar de conversación) y el
  hilo no la tiene, la tarjeta vuelve a abierta. El estado se lee en vivo al hacer clic (no del último
  render), así un dígito justo tras un clic no manda una segunda respuesta.
- **Turno fallido**: el mensaje que topa con un estado de fallo (`ChatMessage.isFailure`) no responde
  la pregunta; vuelve a abierta y el reintento la resuelve. La cola guarda el origen (`QueuedMessage`).
- **Adjuntos**: una elección nunca se lleva `pendingAttachments`; se quedan en el compositor.
- **Resolución**: gana el primer mensaje de la usuaria tras la pregunta; la etiqueta se compara exacta
  (`rápido` en minúsculas cuenta como otra respuesta: solo lo que manda la tarjeta marca una opción);
  la etiqueta recortada a 80 resuelve con el mensaje recortado; adjuntos sin texto cierran la pregunta.
- **Obsoleta**: una pregunta de una conversación leída de disco (`ChatMessage.restored`) sin respuesta
  se muestra sin opciones activas.
- **Foco**: la tarjeta con foco cuenta como "componiendo" (`IslandComposing.active(choiceFocused:)`)
  y `islandResignedKey` lo suelta. Al tomar foco el cursor cae en la primera opción (foco visible) y los
  atajos solo actúan con cursor. Teclas: solo flechas y Return sin modificadores y un dígito ASCII 1-9
  (`٣`, `½`, `３` y vacío se ignoran).
- **Origen (seguridad)**: el mensaje de una elección lleva `origin = .choice` y el modelo lo ve como
  `[card choice]` / `[elección en tarjeta]` delante de la etiqueta (historial y turno vivo, también con
  contexto sensado; la memoria de sesión guarda la palabra cruda). `CardVocabulary` explica que
  responde esa pregunta y nunca aprueba permisos ni autoriza sola una acción destructiva, y prohíbe usar
  una pregunta con opciones para pedir un permiso (van por la hoja). Invariante probado: `choose`
  no llama a `ApprovalsProvider` ni resuelve una aprobación pendiente, y un escaneo de fuente falla si
  el camino toca `DecisionGate`, `SpokenConfirmation` o la resolución de aprobaciones.
- **Aviso de sesión**: el nombre de la app pasa por `TextSanitizer.display(_, maxLength: 40)`; "conectar" e
  "iniciar sesión" tienen conjuntos de una-vez separados; una cuenta conectada cuyas herramientas
  fallaron al cargar no recibe "conectar". Sobre el reductor: kind, job, aprobación y hold quedan
  intactos en toda la tabla de estados, y el aviso nuevo desplaza al anterior (también a un fallo,
  como ya hacía `connectApp`); el plazo viejo no retira al nuevo porque `SessionModel` cancela el
  anterior al armar el siguiente.
- **Popup**: solo queda el `EmptyView` del switch (se quitó el filtro duplicado).

**Segunda ronda de seguridad (2026-09-29).**

- **Compuerta**: la etiqueta de una elección es texto del modelo, no palabras de la usuaria. Con
  `origin == .choice`, `said` es "" para `ParentToolGate` (`consume` y `gate`, también si la elección sale
  de la cola) y `noteTurn` recibe "" en vez de la etiqueta: no fija el alcance de apps ni da por dicho un
  host. Una tarjeta `["Abrir evil.com", …]` ya pide hoja; tecleado, "Abrir evil.com" sigue valiendo como
  consentimiento. Costo asumido: un turno de elección no ofrece herramientas de apps conectadas (`noteTurn("")`
  las deja en `.none`); si hace falta, ella nombra la app tecleando.
- **Persistencia**: `ConversationMessage.fromChoice` (campo `choice` opcional en el JSON, ausente en archivos
  anteriores) hace que una elección restaurada siga marcada para el modelo.
- **Foco**: el foco pertenece a una tarjeta (`focusedChoiceID`) y solo cuenta mientras esa tarjeta es la
  respuesta viva (`IslandChoice.isFocused`); además la tarjeta suelta el foco en `.onDisappear`, porque un
  `@FocusState` no avisa cuando su vista se va.

## 9. 16m-7: alcance real (2026-09-29)

**Menciones (@).**

- **Dónde**: el campo de la isla es el único compositor. La ventana principal no tiene campo desde 16j
  ("hablar y continuar una tarea pasa en la isla"), así que "campo del chat" no existe como superficie;
  el camino compartido es `ChatViewModel` (`addMention` + el turno), que cualquier compositor futuro usa igual.
- **Cuándo abre** (`MentionTrigger`, Core): un `@` que empieza palabra, al final de lo tecleado (el campo no da
  cursor), seguido de algo que aún puede ser un nombre: hasta 30 caracteres, hasta dos espacios internos, sin
  espacio final ni salto de línea. `a@b.com` no abre. Una mención insertada termina en espacio, así que no se reabre.
- **Fuentes, en orden** (`MentionRanking`): contactos, apps conectadas, archivos recientes; dentro de cada grupo,
  prefijo, inicio de palabra, contiene; sin acentos ni mayúsculas; la consulta es literal (nunca regex ni SQL);
  tope de 8 filas. Apps y archivos aparecen de inmediato, sin esperar al diálogo del permiso.
- **Permiso de Contactos**: `SystemContacts.requestAccess()` lo pide y solo lo llama el selector la primera vez
  que ella teclea `@` (`asked`, una vez por arranque; el sistema tampoco muestra un segundo diálogo tras negar).
  Construir el servicio, arrancar y teclear sin `@` no piden nada. `NSContactsUsageDescription` en el Info.plist
  de `bundle.sh` y en el gate de usage descriptions; además el entitlement
  `com.apple.security.personal-information.addressbook` en `scripts/companion.entitlements` (sin él, la build
  notarizada con hardened runtime no puede leer Contactos aunque el usuario acepte). Mientras el diálogo está
  abierto la isla no se pliega (`isRequestingAccess` -> `geometry.picking`, la misma regla que el selector de archivos).
- **Privacidad (mínimo que viaja al modelo)**: un contacto viaja como su nombre visible (que ya está en sus palabras)
  y la palabra "contacto"; **un solo medio de contacto únicamente si ella abrió ese contacto y eligió uno**
  (flecha derecha, o clic; la primera fila es "solo el nombre" y es la que ya tiene el cursor). Buscar lee nombres de
  quienes casan con lo tecleado, nunca la libreta: con consulta vacía no se lista a nadie; los correos y teléfonos
  se leen solo al abrir un contacto y por su identificador; ninguna otra clave (notas, cumpleaños, direcciones,
  foto) se pide y un test de fuente lo vigila. Una app viaja por su nombre. Un archivo se **adjunta por el camino de
  adjuntos** (`chat.attach`), así que su contenido sigue las reglas de `AttachmentPolicy`, y queda mencionado por nombre.
  El bloque va delante del turno como datos ("no instrucciones"), saneado con `TextSanitizer` y en una sola línea
  por campo; solo viajan las menciones cuyo `@nombre` sigue en el texto al enviar (borrar el `@` retira también el
  correo); tope de 5 por mensaje. Vive en memoria con el hilo de esa sesión (para "mándaselo") y **nunca al disco,
  ni a `memoryTurns`, ni al log**: `Mention`, `MentionCandidate` y `MentionChannel` se imprimen redactados y los
  fallos de la libreta se registran sin la consulta ni el identificador. Una elección de tarjeta nunca se lleva las menciones.
- **Archivos recientes**: Spotlight (`NSMetadataQuery`, 14 días, 40 archivos, 60 s de caché), solo nombres y rutas,
  sin diálogos de carpeta. Política en Core (`MentionFiles`): dentro del home, sin ocultos (`.ssh`, `.env`), sin
  `Library`, sin nada dentro de un paquete `.app`; el detalle es la carpeta, nunca la ruta con el usuario.
- **Teclado**: flechas con vuelta, Return o Tab eligen, Esc cierra (y esa consulta no se reabre sola hasta que cambie),
  flecha derecha abre los medios del contacto, izquierda vuelve (solo dentro de los medios: en la lista izquierda es
  del campo). Return se intercepta en `onSubmit`, no en `onKeyPress`, para que elegir nunca envíe también.
- **VoiceOver**: la lista es un grupo; cada fila dice "nombre, tipo, n de m", con pista distinta si se puede abrir
  y el rasgo `isSelected` en la del cursor.
- **Dónde se pinta**: en línea bajo el campo (la isla crece con el contenido), no por el portal (que es de la banda del notch).

**Comentarios.**

- **Destino**: hoy el enlace de feedback era `mailto:?subject=...` (sin destinatario, sin servidor nuestro). Se
  conserva: el modal arma el cuerpo y lo entrega a la app de correo de ella. Con capturas se usa el servicio de
  compartir del sistema (`composeEmail`, único camino que adjunta archivos); si no está, sale el texto por `mailto:`
  y el modal avisa que las capturas se quedaron. No se inventó backend. **Decisión abierta**: si producto quiere un
  destinatario fijo o un endpoint propio, es una decisión aparte (hoy el correo sale sin "Para").
- **Contenido del mensaje**: sus palabras, el ánimo que eligió y cuántas capturas añadió. Nada de la máquina (sin
  versión, sin rutas). **Decisión abierta**: añadir la versión de la app ayudaría a soporte y es un dato más.
- **Dónde vive**: en la ventana principal (un modal de 480 no cabe en el panel de la isla); la entrada "Enviar
  comentario" de la isla abre la ventana y publica `.companionOpenFeedback`; la barra lateral abre lo mismo.
- **Capturas**: solo con el botón (`addCapture`); reusa `ScreenRegionGrabber` de la isla; máx. 3; cancelar no es error;
  sin permiso de pantalla lo dice. Cerrar sin enviar borra las capturas; tras enviar se quedan en la carpeta temporal
  de capturas (la app de correo puede seguir leyéndolas). **Pendiente conocido**: limpiar esa carpeta al arrancar.
- **Ánimo**: cuatro estados con símbolos SF (sin emoji), tocar el elegido lo quita. **Contador**: quedan n / n de más;
  el campo recorta a 1000 caracteres (por carácter, no por byte).

Valores propios (no medidos): 30 caracteres de consulta y 2 espacios internos; 8 filas; 60 caracteres de nombre y
80 de detalle; 5 menciones por mensaje; 6 medios por contacto; 14 días, 40 archivos y 60 s de caché de recientes;
1000 caracteres y 3 capturas en comentarios; 4 estados de ánimo. Medidos: selector padding 4, 240 de alto, radio 11;
ítem 6 × 8, radio 7, 13 px, hover acento al 16 %; modal 480, padding 32, radio 28.

Limitaciones: el selector asume el cursor al final del campo (SwiftUI no lo expone); la instantánea del modal muestra
un placeholder amarillo donde va el `TextEditor` (`ImageRenderer` no dibuja vistas de AppKit), en la app se ve normal.

**Ronda de revisión 16m-7 (2026-09-29): contratos y decisiones.**

- **Paquetes y enlaces**: tres capas. `MentionFiles` rechaza un paquete (`.app`, `.bundle`, `.framework`,
  `.photoslibrary`...) en cualquier componente, también el último; la consulta de Spotlight excluye
  `com.apple.package` y `public.folder` por `kMDItemContentTypeTree`; y `AttachmentStore.adopt` exige archivo
  regular y no enlace simbólico, lo que cubre también drops y el selector de archivos. Costo asumido: arrastrar un
  symlink a un archivo inocente ya no se adjunta (la ruta no dice lo que hay detrás).
- **RecentFiles**: una sola consulta en vuelo, sin dueño (no hereda la cancelación de quien pregunta); un resultado
  fallido o que no terminó a tiempo no se cachea.
- **Contrato del cursor (4)**: mientras ella no lo mueva, el cursor sigue a la fila de arriba; una vez que lo mueve
  (flechas o puntero), se conserva por id de fila al repintar. Return o Tab eligen la fila resaltada en ese instante,
  sin esperar al diálogo de permiso. Una fila de una consulta anterior no se elige mientras llega la nueva.
- **Fuentes**: apps, archivos y contactos se publican cada una al llegar. Un solo diálogo de permiso, compartido y
  sin dueño; cualquier tecla durante el diálogo espera a esa misma respuesta y busca con su propia consulta.
- **Contrato de menciones repetidas (12)**: mismo tipo y mismo nombre es una mención; gana la que trae el medio
  elegido, en cualquier orden; sin medio, la última. **Tope (13)**: pasadas 5, viajan las primeras en orden de
  aparición en el texto (no de elección), salvo que una mención con medio elegido nunca se pierde por una sin
  medio; la salida va en el orden del texto.
- **Cursor a mitad de texto (14)**: el campo no da cursor, así que el token es lo que termina el borrador. Si sigue
  escribiendo después de un nombre, la consulta ("Ana y luego") deja de casar con nadie y el selector se cierra
  solo; `inserting` jamás toca un borrador que ya siguió escribiendo. Límite documentado: editar en medio del texto
  no abre el selector. Borrar el `@` lo cierra.
- **Menciones pendientes**: siguen al campo (`syncMentions`): borrar el `@nombre` las suelta con su medio y
  escribirlo a mano después no las resucita. Un archivo que no se pudo adjuntar no deja ni `@nombre` ni mención.
- **Comentarios**: `addCapture` no reentra y, si el modal se cerró o se llenó mientras el selector de captura
  estaba abierto, borra el archivo que llega. La carpeta de capturas se vacía al arrancar (solo la propia; si es un
  enlace no se toca). El enlace de correo tiene tope de 6000 caracteres (valor propio: mil emoji dan ~28 000): pasado
  el tope sale completo por el servicio de compartir; sin servicio se corta por carácter, con puntos suspensivos, y
  el modal lo dice. La decisión vive en `FeedbackDeliverer`, con las llamadas del sistema inyectadas.
- **Petición de comentarios**: `FeedbackRequest` guarda la petición hasta que la ventana la lee al aparecer.

## 10. 16m-5b: alcance real (2026-09-29)

**Diagramas Mermaid en la isla.** Dependencia aprobada por Karen el 2026-09-29 ("install de mermaid"); es la
única nueva de la wave y no es una dependencia de SwiftPM: es un archivo vendoreado.

- **Fence** (`companion:diagram`, misma convención que `companion:chart`): el cuerpo es el **texto de Mermaid**,
  sin JSON. `CardVocabulary` (en y es) lo enseña con la regla de cuándo: solo cuando las conexiones son lo que
  importa (flujo, secuencia entre partes, estados, clases/ER, línea de tiempo), nunca para lo que una lista o una
  tabla dice igual; sin directivas `%%{`, sin líneas `click`, sin HTML en etiquetas. Llega como
  `AnswerBlock.diagram(DiagramBlock)`; abre el popup (`isRich`); la voz no lo lee (`SpeechBudget.hasCard`).
- **Topes**: 16 KiB de bytes del cuerpo (`DiagramBlock.maxSourceBytes`; más es nil, nunca se recorta; cuenta bytes,
  no caracteres). Más el tope de 256 KiB de la fence, que ya existía. Vacío tras sanear es nil.
- **Saneado** (`TextSanitizer` + `DiagramSource`): controles bidi, invisibles y C0/C1 fuera (como toda tarjeta);
  se quitan las directivas `%%{ ... }%%` (una o varias líneas), el frontmatter `---` cerrado y las líneas `click`,
  porque el tema y el nivel de seguridad los fija la página, no el modelo. El HTML del modelo **no se quita**:
  viaja como texto y la CSP más `strict` lo neutralizan. Una fence rota o vacía sigue visible como código.
- **Vendor** (`Sources/CompanionServices/Diagram/`): `mermaid.min.js` **11.17.2** (la de Incredible; la última
  mayor, 12, no se adoptó), SHA-256 `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8`,
  3 572 661 bytes (bundle IIFE con todos los diagramas), `LICENSE` MIT y `VENDOR.md` con cómo se obtuvo
  (`npm pack mermaid@11.17.2`). El renderer **se niega a cargar** un script cuyo hash no sea el fijado;
  `diagramVendorTests` falla si el archivo, `VENDOR.md` y `DiagramPage.mermaidSHA256` discrepan. `Package.swift`
  solo suma `.copy("Diagram")` al recurso de Services.
- **Aislamiento** (`DiagramPage` en Core, puro y probado; `WebKitDiagramRenderer` en Services es el único WebKit de
  la app y la UI lo consume por el puerto `DiagramRendering`):
  1. `loadHTMLString(_, baseURL: nil)`, sin esquema propio ni archivo: no hay origen que servir.
  2. CSP: `default-src 'none'`; `script-src` solo por hash de los dos scripts en línea (vendor y arranque), sin
     `unsafe-inline` ni `unsafe-eval` en scripts (un `onerror` del modelo no corre); `style-src 'unsafe-inline'`
     porque Mermaid pone estilos en el SVG; `connect/img/font/media/object/frame/worker/form-action/base-uri`
     en `'none'`.
  3. Regla de contenido de WebKit que bloquea toda URL con esquema y `//`; si no compila, el renderer falla
     cerrado (`unavailable`). Dos capas independientes; el test real prueba cada una **sola** (ver abajo).
  4. Navegación: solo `about:blank` (la carga inicial); ventanas nuevas, nunca. Almacén no persistente, JS sin
     abrir ventanas, sin medios, sin selección, sin scripts inyectados.
  5. El texto entra como el **argumento** `source` de `callAsyncJavaScript`, jamás interpolado en script ni en
     HTML; `mermaid.parse` antes de `render`; `securityLevel: 'strict'`; `suppressErrorRendering` (valor propio).
  6. Un web view nuevo por diagrama, descartado después; un diagrama a la vez; caché de 8 dibujos por texto y ancho.
- **Fallo, tiempo y "sin error mudo"**: `DiagramOutcome` = imagen o `failed(invalid | timeout | unavailable)`.
  Tope de **10 s** (`DiagramPage.renderTimeout`; `DiagramTimeout` deja de esperar aunque el JS ni siquiera
  se cancele, y descarta la respuesta tardía). En cualquier fallo el popup muestra una nota ("No pude dibujar
  este diagrama. Aquí está su texto." / "...tardó demasiado...") y **el mismo texto como bloque de código**; sin
  renderer inyectado, igual. El mensaje de error de Mermaid no va al log (puede citar el texto del modelo).
- **Vista** (`Island/Visual/`): mismo contenedor `visual` que las gráficas (extraído a `islandVisualSurface()` y
  `IslandVisualCopyButton`, compartidos): padding 14/16/12, relleno 5 %, borde 7 %, radio 12. La imagen se muestra
  como PDF (nítido) de 504 de ancho (580 - 2x22 del popup - 2x16 del contenedor), **a su tamaño**: por debajo de 580
  el contenedor hace **scroll horizontal** en lugar de encogerla, y no hay tope de alto (el popup ya hace scroll
  vertical). VoiceOver: etiqueta "Diagrama" y el texto de Mermaid como valor.
- **Herramientas, iguales a las de Incredible** (auditoría de decisiones, decisión 7): **copiar imagen** y **descargar
  PNG**, cada una **con fondo o sin fondo**, a **2x**; hay además un interruptor de fondo que vale para las dos
  (nace con fondo). No hay "ver" ni zoom (Incredible no los tiene). El copiar-texto de la primera versión se quitó: el
  fallback a código conserva su propio botón de copiar.
  - El renderer entrega en el mismo dibujo el PDF de pantalla y los dos PNG (`DiagramImage.png`, `.pngTransparent`),
    a 1008 px de ancho en sRGB. El PNG con fondo es una captura de la misma página; el transparente se hace por
    **matting de diferencia** (la página sobre blanco y sobre negro: alfa = 1 - (blanco - negro)/255, color
    premultiplicado = el negro), porque la captura pública de WebKit no tiene alfa y la alternativa era una clave
    privada por KVC. Exacto en bordes suavizados. Si un PNG falla, solo esa herramienta deja de ofrecerse.
  - Copiar deja PNG y TIFF en el portapapeles (ambos con alfa). Descargar abre un **panel de guardar del sistema**
    (`IslandSavePanel` en App, con la misma activación y devolución de teclado que el selector de archivos; la isla
    no activa y un panel desde una app inactiva se abre detrás), por lo que no hace falta el permiso de la carpeta
    Descargas. Cancelar el panel no es descarga.

**Valores tomados de Incredible** (solo valores, del frontend extraído en el scratchpad de la sesión
`inc16k/firstRun-*.js`, la llamada `mermaid.initialize`; nada de código ni de textos): versión 11.17.2 (cadena de
versión en `mermaid.core-*.js`); `securityLevel: "strict"`; `theme: "base"`; `startOnLoad: false`; `fontFamily`
(pila del sistema); `flowchart {curve: "basis", padding: 14, useMaxWidth: true}`; `sequence {useMaxWidth: true,
mirrorActors: false}`; `themeVariables`: darkMode true, background transparent, fontSize 13px, primaryColor
#1e1e26, secondaryColor #191920, tertiaryColor #15151b, bordes blancos al 18/12/10 %, primaryTextColor 94 %,
textColor 82 %, lineColor 32 %, edgeLabelBackground #14141a, cluster 3 % / 10 %, notas #23232c (texto 90 %, borde
14 %), primaryColorAccent #4a9cff, pie1-8 (#4a9cff #8b80ff #4cc2b4 #f0a93b #f06b9b #56c596 #c08bff #ffd166),
pieStroke #14141a 2px, textos de pie 94 % / 96 %. Del CSS: el SVG a `max-width: 100%` con alto automático y centrado
(`.ovx-mermaid-body`); contenedor `.ovx-visual` ya medido en §7.

**Valores propios (no medidos)**: 16 KiB de tope de texto; 10 s de tope de dibujo; 504 de ancho; 8000 de alto
máximo del SVG antes de hacer imagen; caché de 8; 3 timeouts seguidos apagan el renderer; 2x en los PNG; `suppressErrorRendering`; relleno de página `rgb(26, 26, 28)` (WebKit pinta el PDF sobre blanco
y el tema es de tinta clara, así que la página pinta el relleno del contenedor, 5 % de blanco sobre el popup
rgb(14,14,16); un test lo ata a los valores de la UI). Consecuencia: la imagen es opaca y solo se funde con
el contenedor mientras la superficie de la isla siga siendo la misma (hoy oscura en ambas apariencias).

**Limitaciones conocidas**
- Solo la isla pinta el diagrama: la ventana principal y el PDF lo muestran como código (`MarkdownView` no
  conoce `companion:diagram`).
- Con las `themeVariables` de Incredible (que no tocan todos los tipos) `mindmap` y `gantt` salen menos pulidos
  que flowchart o sequence (mindmap con nodos negros; gantt con etiquetas de eje que se pisan a este ancho).
- El diagrama es imagen: no hay selección de texto dentro de él.
- Un `ImageRenderer` no pinta el contenido de un `ScrollView`: la instantánea estrecha (380) sale con el lienzo vacío; el
  scroll horizontal solo se ve en la app.
- Si el JS de una página se cuelga, el timeout deja de esperar y suelta el web view, pero el proceso de contenido
  de WebKit puede tardar en morir.
- Una fence ```` ```mermaid ```` plana (sin `companion:`) sigue siendo código, como cualquier fence con lenguaje.

**Pruebas**: `Diagram16m5bTests` (fence, topes, saneado, CSP, configuración de Mermaid, navegación, reglas de red,
argumento vs código, timeout, vendor y hash, configuración del web view, modelo, copiar, textos en en/es, medidas) y
`Diagram16m5bSnapshotTests` (real, con `COMPANION_SNAPSHOTS`): diez diagramas en claro y oscuro, fallback por
sintaxis rota y por timeout, caché, texto hostil directo a la página, y **la prueba de que nada sale**: un
`NWListener` en loopback cuenta conexiones; una página permisiva **sí** las produce (control) y la página real,
la CSP sola y las reglas solas producen cero con fetch, XHR, `Image`, `img`/`script`/`link`/`iframe` dinámicos,
`sendBeacon` y `WebSocket`.

**Prueba en vivo para Karen** (`./scripts/bundle.sh release`, con la app cerrada antes):
1. Pídele a Companion "hazme un diagrama de flujo de cómo decides si automatizar una tarea". Esperado: una tarjeta
   automática y, al "Ver", el popup con el diagrama dentro del contenedor "Diagrama", con copiar arriba a la derecha.
2. Pide una secuencia (tú, Companion, un servicio) y un diagrama de estados: deben dibujarse en menos de un par de
   segundos (el primero tarda más: carga los 3,6 MB).
3. Copiar: pega en Notas o en un chat y debe ser la imagen. Alterna el fondo (primer botón) y vuelve a copiar; en un
   editor con fondo claro se nota la diferencia. Descargar: elige dónde guardar; el PNG sale a 2x.
4. Con la red apagada, todo igual (no hay red en el dibujo).
5. Pídele un diagrama con sintaxis inválida a propósito ("escribe un flowchart con una flecha rota"): el popup debe
   decir que no pudo dibujarlo y mostrar el texto como código, sin espacio en blanco mudo.
6. Un diagrama enorme (más de 16 KiB de texto) debe salir como código.

**Decisiones abiertas**
1. Aceptar también ```` ```mermaid ```` plano (los modelos lo escriben de forma natural): hoy solo `companion:diagram`
   para no romper la regla "solo `companion:*` es interfaz" de `ConversationMemory`.
2. Pintar diagramas también en la ventana principal (hoy código) y en el PDF (imagen desde el mismo renderer).
3. `themeVariables` por tipo (mindmap, gantt) más allá de los valores de Incredible.
4. Subir a Mermaid 12 (mayor) cuando se decida; el cambio es la versión, el hash y `VENDOR.md`.
5. Ancho del renderer: 504 fijo; si el popup baja de 580 (pantalla chica) hay scroll horizontal, no se re-dibuja.

**Ronda de revisión 16m-5b (2026-09-29): contratos.**

- **Cola** (`DiagramScheduler`, Core, con dibujo inyectable para probarla sin web view): un dibujo a la vez; dos
  peticiones idénticas en vuelo comparten un dibujo; quien se va (cerrar el popup, cambiar de bloque) cancela el
  dibujo **solo si nadie más lo espera**, y lo cancelado en cola nunca dibuja; el plazo (`DiagramTimeout`, ahora
  también sensible a la cancelación de quien espera) corta aunque el JS no se pueda cancelar; 3 timeouts seguidos
  apagan el renderer (`unavailable`; sin enfriamiento, HACK) y un éxito reinicia la cuenta. Se cachean imágenes y
  `.invalid` (determinista), nunca timeout ni unavailable.
- **Streaming**: un mensaje llega al historial entero (el texto en curso vive en `chat.streaming`, que el popup no
  lee). Aun así, una fence en la que el texto **termina** (corte del modelo) es código, no diagrama
  (`MarkdownSplitter.endsInsideFence`), y el render se lanza por bloque terminado.
- **Página**: se suelta por `webView` (nunca por un local) para que `tearDown` libere una página colgada; el proceso
  de contenido caído es `.unavailable`, no `.invalid`; los fallos de navegación se registran sin datos del modelo; un
  SVG de más de 8000 de alto se rechaza antes de `pdf()`.
- **Saneado**: CR y CRLF se normalizan antes de sanear (un CR suelto pegaba las líneas); `click` tras `;`, y
  `link`/`links` de secuencia y `link`/`callback` de clases, se quitan o, si van tras `;`, la fence se rechaza
  entera (queda como código, visible); un nodo llamado `link` no se toca; `%%{` sin cerrar rechaza la fence en lugar de
  borrar el resto del diagrama en silencio.
- **Pruebas**: el aislamiento del render real se prueba por `WebKitDiagramRenderer.render` con un script de
  sustitución (sin los 3,6 MB) y el `Beacon` de loopback, siempre (no solo con la galería): render completo, solo las
  reglas (página sin CSP) y la configuración y el delegado de la página real. Los tests con esperas propias corren
  bajo `watched`, que convierte un cuelgue en un rojo con nombre.

**Ronda 3 (2026-09-29).**

- **Cola**: un llamador cancelado nunca cuenta como timeout ni para el apagado (tres popups cerrados a mitad de
  dibujo ya no apagan los diagramas); un flight cancelado que termina tarde no borra al flight nuevo de la misma
  clave (limpieza por identidad); los flights ya encolados vuelven a mirar el apagado antes de dibujar.
- **Matting fuera del MainActor** y con aritmética directa por píxel: 1008 x 6000 (un diagrama de 3000 de alto) pasó
  de 5,8 s bloqueando el hilo principal (build de debug) a 0,07 s en un hilo aparte, con el hilo principal sin
  pausas de más de 6 ms (medido en la galería; la prueba siempre activa fija solo que el bucle corre fuera del
  hilo principal, porque el de 3000 de alto, corriendo con toda la suite, hacía fallar tests de tiempo ajenos).
- **Descargar** distingue `saved | cancelled | failed`; un fallo muestra una nota (es/en) bajo el diagrama y el log
  lleva dominio y código del error, nunca la ruta (`DiagramFileWriter`).
- **Saneado**: un nodo llamado `click` (`click --> B`) ya no se borra: `click` se trata como `link`, con un nombre
  después.

