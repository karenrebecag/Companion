# Wave 20 — Entregables y tarjetas de datos: documentos, hojas y gráficas como Incredible

**Estado: CERRADO EN CÓDIGO (2026-09-28).** Aprobada por Karen ("dale a la spec completa", 2026-09-28) con las recomendaciones de D1–D7; D7 = (a). Detalle y desviaciones en §10. No se pisa con 19 (isla rica, EN CURSO).

Pedido de Karen: "¿cómo genera PDFs y documentos, interactúa con spreadsheets e interfaces Incredible? Me gustaría sumarlo."

## 1. El fallo (ADR 001)

- **Documentos**: `premium-documents/SKILL.md` escribe Markdown y solo convierte si la Mac ya tiene `pandoc`. En una Mac normal, pedir "un PDF del informe" termina en un `.md` y una frase de disculpa.
- **Hojas**: `excel-live/SKILL.md` depende de `python3 -c "import openpyxl"`. Sin eso se para. No hay manera de tocar un Excel o un Numbers abierto.
- **Datos en pantalla**: el canal de tarjetas (`CardPayload`, `CompanionBlocks`) solo conoce `locations` y `gallery`. Una comparación de precios, un resumen con cifras o una serie temporal llegan como Markdown plano; no hay tabla con forma, métrica ni gráfica.

Los tres son capacidades del producto que hoy dependen de algo que la usuaria tendría que instalar. ADR 001: se absorben nativas.

## 2. Cómo lo hace Incredible (análisis estático, 2026-09-28; referencia local)

Evidencia: inspección en solo lectura de la app instalada (referencia local); nada de su código ni de sus nombres internos entra al repo.

- **Documentos**: clases de documento con el diseño horneado, que el modelo llama como API, no maqueta:
  - Presentaciones (`.pptx`) con portada, métricas, columnas, viñetas, tablas, imágenes y secciones.
  - Documentos PDF con encabezados, cuerpo, fila de métricas, tablas, callouts e imágenes.
  - Documentos Word (`.docx`) y hojas (`.xlsx`) con encabezado congelado, filas en bandas y anchos automáticos.
  - Gráficas como imagen con estilo fijo (título a la izquierda, ejes apagados).
  - La salida va a una carpeta propia con la fecha y el nombre, verificada antes de avisar.
- **Hojas en vivo**: automatización de Excel por Apple Events. Escribe rangos en una sola llamada, fórmulas y
  formato; guarda una versión antes y después de cada escritura; relee unas ~20 celdas para verificar. Sin tablas
  dinámicas ni formato condicional en Mac (no hay API). Google Sheets: no aparece.
- **Tarjetas**: el modelo no escribe HTML. Llama a una herramienta de presentar resultado con un título y
  bloques, y la app pinta bloques tipados: cifras (etiqueta y valor), tablas, gráficas (barras, líneas, pie,
  dona y dispersión), prosa en Markdown, recibos de estado y acciones de abrir enlace.
- **Coste**: ~1 GB de app, de los que el grueso es Python, FFmpeg y ONNX.

**Se toma**: el diseño horneado detrás de una API pequeña (el modelo elige contenido, nunca estilo), los bloques tipados, la verificación antes de avisar y la copia antes de escribir una hoja.
**No se toma**: el Python embebido, la librería de gráficas ni su carpeta de salida.

## 3. Lo que ya tenemos y se reusa

- `CardPayload` + `Card(source:)` (`CompanionBlocks.swift`): el canal de tarjetas que viaja fuera del contexto del modelo, con la distinción `tool` (confiable) / `model` (no verificado). Los bloques nuevos son casos de este enum, no un canal paralelo.
- `CardVocabulary.swift`: la única descripción de las tarjetas que leen todos los prompts. Se amplía ahí.
- Fences `companion:` como vía para cualquier proveedor, incluidos los modelos locales que fallan con tool calling y los especialistas CLI; un fence roto se degrada a bloque de código visible.
- `NativeTools` con su clasificación `safe` / `requiresApproval` y las hojas de aprobación.
- Las piezas de tarjeta de 16l/19 (`CardChrome`, `IncredibleCards`) y los tokens de la isla.

## 4. Decisiones (firma Karen)

- **D1 Tarjetas por fence, no por tool nueva.** Tres fences: `companion:stats`, `companion:table`, `companion:chart`. Funcionan con cualquier proveedor y con los especialistas. Una tool `present` (como `present_result`) queda como upgrade si el fence falla con los modelos grandes. Alternativa: tool primero; más fiable con OpenAI, inútil con Ollama pequeños y con Claude Code.
- **D2 Gráficas con Swift Charts** (sistema, macOS 13+), sin dependencia. Tipos: barra, línea, área, pastel/donut y dispersión. Una gráfica que llega de `source: .model` lleva la marca "sin verificar", igual que un pin.
- **D3 PDF por WebKit**: HTML con los tokens del DS → `WKWebView.createPDF` en un `WKWebView` fuera de pantalla. Plantillas en el bundle (informe, one-pager, factura/recibo). Las gráficas del PDF se renderizan con `ImageRenderer` de la misma vista de Swift Charts, así el PDF y la isla dibujan igual. Alternativa descartada: PDFKit + `NSAttributedString` (paginación y tablas a mano, M-L sin ganancia visible).
- **D4 La API del documento es un JSON de bloques, no HTML libre.** El modelo manda `{"title","subtitle","blocks":[cover|h|p|bullets|stats|table|chart|callout|image|divider]}` a una tool nueva `create_document(format, path?, spec)`; la plantilla pone el estilo. El HTML nunca lo escribe el modelo: así no hay inyección de scripts en el WebView (se carga con JavaScript apagado y sin red).
- **D5 Excel y Numbers en vivo por Apple Events desde la app**, no por `osascript` del especialista (que sigue en la lista negra). Tools: `sheet_read(app, range)` (safe) y `sheet_write(app, range, values|formulas)` (requiresApproval). Pide el permiso de Automatización por app la primera vez. Antes de cada escritura se guarda una copia del libro junto a él (`-backup-<hora>`); después se releen las celdas escritas y se reporta lo que quedó. Sin tablas dinámicas ni formato condicional (Mac no los expone).
- **D6 `.xlsx` por archivo en Swift**: un `.xlsx` es un zip de XML (SpreadsheetML); se escribe un subconjunto (hojas, celdas, fórmulas, encabezado en negrita, primera fila congelada, anchos) con `Compression`/`Archive` del sistema. `.docx` y `.pptx` quedan fuera de 20 (ver D7).
- **D7 `.docx` y `.pptx`**: tres caminos, uno a elegir.
  - (a) Fuera por ahora: el PDF cubre la entrega; `pandoc` sigue como camino opcional si ya está instalado.
  - (b) En Swift como `.xlsx` (zip de XML): `.docx` es M, `.pptx` es L.
  - (c) Un entorno Python opcional que se instala solo desde Ajustes, con consentimiento, en `Application Support/Companion/python` (python-docx, python-pptx). Contradice el espíritu de ADR 001 aunque sea opt-in; si se firma, se redacta un ADR nuevo.
  Recomendación: (a) en 20, y (b) para `.docx` si el uso lo pide.

## 5. Entregas

| # | Qué | Archivos |
|---|---|---|
| 20-0 | Core: `StatsBlock`, `TableBlock`, `ChartBlock` (series, unidad, tipo) con parser y límites (filas ≤ 200, series ≤ 8, puntos ≤ 500); `CardPayload` +3 casos; `CardVocabulary` es/en | `CompanionBlocks.swift` (o `DataBlocks.swift` si pasa de 400 líneas), `CardVocabulary.swift`, tests |
| 20-1 | UI: tarjetas `StatsCard`, `TableCard` (scroll horizontal, cabecera fija), `ChartCard` (Swift Charts) en la isla y en la ventana, con la marca "sin verificar" | `DataCards.swift`, `CardView.swift`, tests de proyección |
| 20-2 | Documento: `DocumentSpec` (Core, parser + validación), plantillas HTML con tokens, `PDFRenderer` (Services, WebKit sin JS ni red), tool `create_document` (requiresApproval: escribe en disco), recibo con "Abrir" y "Mostrar en Finder" | `DocumentSpec.swift`, `PDFRenderer.swift`, `Templates/*.html`, `NativeTools.swift`, tests |
| 20-3 | Hojas en vivo: `SheetBridge` (Apple Events a Excel y Numbers; detecta cuál está abierto), `sheet_read` / `sheet_write` con copia y relectura; entitlement y `NSAppleEventsUsageDescription` | `SheetBridge.swift`, `NativeTools.swift`, `Info.plist` vía `bundle.sh`, tests con un fake del puerto |
| 20-4 | `.xlsx` por archivo (`XLSXWriter`, subconjunto de SpreadsheetML) como formato de `create_document` y de `sheet_write` cuando no hay app abierta; skills `premium-documents` y `excel-live` reescritas sobre las tools nuevas | `XLSXWriter.swift`, `SKILL.md` ×2, tests que abren el zip y validan el XML |

Orden: 20-0 → 20-1 (se ve en el día a día) → 20-2 → 20-3 → 20-4. 20-3 puede ir en paralelo a 20-2.

## 6. Criterios de aceptación

1. Un fence `companion:table` con 3 columnas y 5 filas se pinta como tabla en la isla y en la ventana; uno con 201 filas se recorta a 200 con aviso; uno roto queda como bloque de código visible.
2. `companion:chart` de tipo `line` con dos series dibuja dos líneas con leyenda; un tipo desconocido cae a tabla con los mismos datos, nunca a nada.
3. Una tarjeta con `source: .model` muestra "sin verificar"; con `source: .tool`, no.
4. `create_document` con formato `pdf` y un spec con portada, métricas, tabla y gráfica produce un PDF de ≥ 1 página en la carpeta de trabajo (o Escritorio); el archivo existe y pesa > 0 antes del recibo; la hoja de aprobación muestra la ruta.
5. Un spec con `<script>` en un texto sale escapado en el PDF; el WebView no ejecuta JS ni hace peticiones de red (test del configurador).
6. `sheet_write` sobre Numbers o Excel abierto: pide aprobación, deja `-backup-<hora>` junto al libro, escribe el rango en una sola llamada, relee las celdas y el recibo dice lo que quedó. Denegada: el libro no cambia.
7. Sin la app de hojas abierta, `sheet_write` a una ruta `.xlsx` escribe el archivo con `XLSXWriter`; Numbers lo abre (verificación en vivo de Karen).
8. `premium-documents` ya no menciona `pandoc` como requisito; `excel-live` ya no pide `openpyxl`.
9. En vivo (Karen): "hazme un one-pager en PDF con las ventas de la tabla que te pegué, con una gráfica de barras" termina en un PDF que se abre, con la gráfica igual a la de la tarjeta.

## 7. Seguridad

- El modelo nunca escribe HTML ni JS: escribe un spec JSON que la plantilla escapa. WebView sin JavaScript, sin red (`WKContentRuleList` que bloquea todo) y con `baseURL` nil.
- `create_document` y `sheet_write` son escrituras: pasan por la hoja, la ruta se confina al directorio de trabajo con la resolución de symlinks que ya usa `NativeToolRunner`.
- Apple Events solo a `com.microsoft.Excel` y `com.apple.iWork.Numbers`; el entitlement lista esas dos apps (`com.apple.security.temporary-exception.apple-events` no aplica fuera de sandbox; se usa `NSAppleEventsUsageDescription` y el prompt de Automatización del sistema).
- Nada de fórmulas que llamen a red (`WEBSERVICE`, `IMPORTXML`, DDE): `sheet_write` las rechaza con `invalid_args`.
- Logs: tool, formato, filas/celdas contadas y bytes; nunca contenido.
- `security-reviewer` obligatorio en 20-2 y 20-3.

## 8. Riesgos

- **R1** El fence no se emite con fiabilidad con los modelos grandes → D1 deja la tool `present` como upgrade medido (misma estructura de datos, otro canal).
- **R2** `createPDF` pagina mal tablas largas → CSS `break-inside: avoid` en filas y cabecera repetida; si no alcanza, paginar tablas en el spec (≤ N filas por bloque).
- **R3** Apple Events a Excel en Mac es lento celda a celda (5–30 ms por llamada, medido por Incredible) → solo escrituras por rango y relectura por muestreo (~20 celdas).
- **R4** Numbers y Excel exponen diccionarios distintos → `SheetBridge` como puerto con dos adapters y un fake para tests; lo no soportado responde `unsupported` en vez de fallar a medias.
- **R5** Los tokens del DS en HTML se desvían de los de SwiftUI → las plantillas leen un CSS generado desde `Tokens.swift` en build (test que compara ambos).

## 9. Fuera de alcance

`.pptx`, `.docx` (salvo que D7 elija b o c), tablas dinámicas, formato condicional, Google Sheets, edición de PDFs existentes, OCR de PDFs (el de 16i-2 cubre regiones de pantalla), plantillas editables por la usuaria (después de v1).

## 10. Cierre en código (2026-09-28)

Rama `feat/20-entregables`. Gates verdes (479 tests). Revisión de código y de seguridad hechas; cada hallazgo entró con su test en rojo primero.

**Entregado**
- Tarjetas `companion:stats|table|chart` en el chat (Swift Charts: barras, línea, área, pastel, dona, dispersión; tabla con tope y aviso de recorte). Un tipo de gráfica desconocido cae a tabla.
- `create_document` (requiere aprobación, llave por carpeta como `write_file`): JSON de bloques → PDF por WebKit fuera de pantalla (JavaScript apagado, almacén desechable, una regla de bloqueo por esquema) o `.xlsx` escrito en Swift (zip sin compresión + SpreadsheetML, encabezado en negrita, primera fila congelada).
- `sheet_read` (safe) y `sheet_write` (aprobación) sobre Excel y Numbers por Apple Events desde la app; copia `-backup-<hora>` antes de escribir y relectura después. Un libro sin guardar no se toca.
- Skills `premium-documents` y `excel-live` v2 sobre las tools nuevas; ya no dependen de `pandoc` ni de `openpyxl`.

**Hallazgos de revisión y su test**
- Seguridad (CRITICAL): el setter de fórmulas de Excel trata `+`, `-` y `@` como `=`; una celda `+cmd|...` saltaba la lista. Ahora todo texto que empieza por esos caracteres pasa la misma lista, normalizada NFKC y sin ningún espacio (`SheetsTests.testEveryFormulaTriggerIsChecked`).
- Código (HIGH): `sheet_write` sin `app` recordaba la clave "active", que valía para cualquier libro que estuviera al frente después. Sin `app` explícita ya no se recuerda (`ApprovalMemoryTests`).
- Cobertura: fórmula prohibida en `.xlsx` queda como texto; configuración del PDF sin JavaScript y sin persistencia.

**Desviaciones de la spec**
- Las tarjetas de datos no entran en la isla: es territorio de 19.
- Sin botones Abrir / Mostrar en Finder en el recibo del documento: el recibo da la ruta.
- Sin modo "a archivo" de `sheet_write`: `create_document` con `.xlsx` lo cubre.
- Las gráficas del PDF son SVG generado en Core, no `ImageRenderer` (D3): no hace falta la UI para imprimir y el SVG pagina nítido.
- R5: la paleta del PDF es un espejo con test de paridad, no CSS generado en build (`HACK:` en `ChartSVG.swift` con su disparador).

**Verificación en vivo (Karen)**
1. "Hazme un PDF del informe de ventas con una gráfica": se aprueba, se abre, tiene páginas y texto seleccionable.
2. Mismo pedido en `.xlsx`: abre en Numbers y en Excel sin aviso de reparación.
3. Con un libro guardado abierto en Excel: "lee A1:C5" y luego "escribe estos totales en D2:D5"; aparece el permiso de Automatización la primera vez, queda la copia `-backup-` y el reporte relee lo escrito.
4. Lo mismo en Numbers.
5. Una respuesta con cifras, tabla y serie se ve como tarjetas en el chat, en claro y oscuro.
