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
