import CompanionCore
import Foundation
import Testing

@Test @MainActor func markdownTests() {
    testMarkdownBlocks(); testMarkdownTables(); testCompanionBlocks()
    testLocatorPayload(); testReportCut(); testPlainText(); testSources()
    testTurnNumbering()
}

@MainActor func testMarkdownBlocks() {
    // Encabezados, lista y párrafos tienen que salir como bloques, no un río.
    let text = """
    Resumen de lo hecho.

    # Plan ejecutado
    1. Busqué archivos.
    2. Leí el más reciente.

    - PID 64090
      - anidado

    > cita del especialista

    ---
    Cierre.
    """
    let kinds = MarkdownSplitter.split(text).map(\.kind)

    expect(kinds.contains { if case .heading(1, "Plan ejecutado") = $0 { true } else { false } },
           "markdown: el # es un heading")
    expect(kinds.contains { if case .list(true, let items) = $0 { items.count == 2 } else { false } },
           "markdown: la lista numerada trae sus dos items")
    expect(kinds.contains { if case .list(false, let items) = $0 {
        items.count == 2 && items[1].depth > 0 } else { false } },
           "markdown: la viñeta anidada conserva profundidad")
    expect(kinds.contains { if case .quote("cita del especialista") = $0 { true } else { false } },
           "markdown: el > es una cita")
    expect(kinds.contains { if case .rule = $0 { true } else { false } },
           "markdown: --- es una regla")
    let proseCount = kinds.filter { if case .prose = $0 { true } else { false } }.count
    expectEq(proseCount, 2, "markdown: dos párrafos sueltos, no uno gigante")

    // Un fence sin cerrar (streaming a medias) sigue siendo código.
    let streaming = MarkdownSplitter.split("hola\n```swift\nlet x = 1")
    expect(streaming.contains { if case .code("swift", _) = $0.kind { true } else { false } },
           "markdown: fence sin cerrar no revienta")

    // Prosa plana no gana estructura inventada.
    let plain = MarkdownSplitter.split("una línea normal")
    expectEq(plain.count, 1, "markdown: prosa plana queda intacta")
}

@MainActor func testMarkdownTables() {
    // Header + separador + filas: la anatomía GFM completa, con prosa alrededor.
    let text = """
    Antes de la tabla.

    | Fecha | Hito |
    |-------|:----:|
    | 1995 | Se conocen |
    | 1997 | Dominio |

    Después de la tabla.
    """
    let kinds = MarkdownSplitter.split(text).map(\.kind)
    expect(kinds.contains { if case .table(let h, let r) = $0 {
        h == ["Fecha", "Hito"] && r.count == 2 && r[0] == ["1995", "Se conocen"]
    } else { false } }, "tabla: header, separador con alineación y filas")
    let proseCount = kinds.filter { if case .prose = $0 { true } else { false } }.count
    expectEq(proseCount, 2, "tabla: la prosa alrededor sobrevive")

    // La Grid de la UI exige filas parejas: corta se rellena, larga se recorta.
    let ragged = MarkdownSplitter.split("""
    | A | B |
    |---|---|
    | solo |
    | uno | dos | tres |
    """)
    expect(ragged.contains { if case .table(_, let r) = $0.kind {
        r.count == 2 && r[0] == ["solo", ""] && r[1] == ["uno", "dos"]
    } else { false } }, "tabla: filas cortas se rellenan y largas se recortan")

    // Un | suelto en prosa no es tabla: sin separador no hay estructura.
    let loose = MarkdownSplitter.split("esto | no es | una tabla")
    expect(loose.allSatisfy { if case .prose = $0.kind { true } else { false } },
           "tabla: un | suelto sigue siendo prosa")
}

@MainActor func testTurnNumbering() {
    expectEq(Turn.numbered("hola", []), "hola",
             "numerado: sin adjuntos el texto queda igual")

    let img = AttachmentRef(name: "foto.png", path: "/tmp/foto.png", kind: .image)
    let doc = AttachmentRef(name: "notas.txt", path: "/tmp/notas.txt", kind: .file)
    let out = Turn.numbered("¿cuál te gusta?", [img, doc])
    expect(out.hasPrefix("[Imagen 1] [Archivo 2: notas.txt]"),
           "numerado: cada adjunto queda nombrado y en orden")
    expect(out.hasSuffix("¿cuál te gusta?"), "numerado: el texto va después")

    expectEq(Turn.numbered("", [img]), "[Imagen 1]",
             "numerado: turno sin texto queda solo con las etiquetas")
}

@MainActor func testCompanionBlocks() {
    // Decode del formato que le enseñamos al especialista.
    let good = """
    {"title":"2 tiendas","locations":[
      {"id":"ldn","name":"Osmo — London","eyebrow":"London",
       "address":"16 Horner Sq","lat":51.5196,"lng":-0.0754,
       "url":"https://osmo.supply"},
      {"name":"Sin id","lat":50.8,"lng":-0.14}]}
    """
    let block = CompanionBlocks.locations(good)
    expectEq(block?.locations.count ?? 0, 2, "locations: decodifica ambas")
    expectEq(block?.locations[1].stableId ?? "", "50.8,-0.14",
             "locations: sin id hay identidad estable")

    // javascript: y otros schemes maliciosos deben rechazarse.
    let malicious = #"{"locations":[{"name":"trap","lat":0,"lng":0,"url":"javascript:alert(1)"}]}"#
    expect(CompanionBlocks.locations(malicious) == nil,
           "locations: scheme javascript se rechaza con degradación")
    let httpPlain = #"{"locations":[{"name":"inseguro","lat":0,"lng":0,"url":"http://example.com"}]}"#
    expect(CompanionBlocks.locations(httpPlain) == nil,
           "locations: scheme http se rechaza con degradación")

    // Campo faltante no rompe; JSON roto y coordenadas imposibles → nil.
    expect(CompanionBlocks.locations("{no es json") == nil,
           "locations: JSON roto degrada a código")
    expect(CompanionBlocks.locations(
        #"{"locations":[{"name":"x","lat":123.0,"lng":0}]}"#) == nil,
        "locations: lat imposible degrada a código")
    expect(CompanionBlocks.locations(#"{"locations":[]}"#) == nil,
           "locations: vacío degrada a código")

    let gallery = CompanionBlocks.gallery("""
    {"images":[{"path":"/tmp/a.png","caption":"A"},
               {"url":"https://x.com/b.jpg"},
               {"url":"http://inseguro.com/c.jpg"}]}
    """)
    expectEq(gallery?.images.count ?? 0, 2,
             "gallery: http plano se filtra, path y https quedan")
    expect(CompanionBlocks.gallery(#"{"images":[{"caption":"solo texto"}]}"#)
           == nil, "gallery: sin nada renderizable degrada a código")

    // Path traversal must not render: ../../etc/passwd, ../x, relative paths all blocked.
    let traversal = CompanionBlocks.gallery("""
    {"images":[{"path":"../../etc/passwd","caption":"evil"},
               {"path":"/tmp/legit.png","caption":"good"}]}
    """)
    expectEq(traversal?.images.count ?? 0, 1,
             "gallery: path traversal se filtra, path absoluto legítimo permanece")
    expect(traversal?.images[0].path == "/tmp/legit.png",
           "gallery: el item renderizable es el absoluto legítimo")

    let relative = CompanionBlocks.gallery(#"{"images":[{"path":"images/photo.png"}]}"#)
    expect(relative == nil,
           "gallery: path relativo (sin /) se rechaza con degradación")
}

@MainActor func testLocatorPayload() {
    // Payload del mapa: ids estables, orden del bloque, solo campos que el JS usa.
    let block = CompanionBlocks.locations("""
    {"locations":[
      {"id":"ldn","name":"Osmo — London","lat":51.5196,"lng":-0.0754},
      {"name":"Sin id","lat":50.8,"lng":-0.14}]}
    """)
    let json = block?.locatorJSON ?? ""
    expect(json.contains(#""id":"ldn""#), "locator: conserva el id explícito")
    expect(json.contains(#""id":"50.8,-0.14""#),
           "locator: sin id viaja la identidad estable")
    expect((json.range(of: "ldn")?.lowerBound ?? json.endIndex)
           < (json.range(of: "Sin id")?.lowerBound ?? json.startIndex),
           "locator: el orden del bloque se conserva")
    expect(!json.contains("eyebrow"), "locator: solo viaja lo que el JS usa")

    // Incrustado en <script>: un "</" malicioso cerraría el tag.
    let evil = CompanionBlocks.locations(
        #"{"locations":[{"name":"x</script><script>y","lat":1,"lng":2}]}"#)
    let escaped = evil?.locatorJSON ?? ""
    expect(!escaped.contains("</"), "locator: ningún </ sobrevive")
    expect(escaped.contains(#"<\/script>"#), "locator: el cierre queda escapado")
}

@MainActor func testReportCut() {
    // El mapa es respuesta, no proceso: visible, no tras el pliegue.
    let report = """
    Encontré 3 tiendas con filamento PLA en CDMX; la más cercana es Vorti \
    en la Roma Norte.

    ```companion:locations
    {"title":"Encontramos 3 tiendas cerca de ti","locations":[
      {"id":"vorti","name":"Vorti 3D — Roma Norte","eyebrow":"Roma Norte",
       "address":"Córdoba 87, Roma Norte","lat":19.4195,"lng":-99.1608,
       "url":"https://vorti.mx"},
      {"id":"grupo3d","name":"Grupo 3D — Doctores","eyebrow":"Doctores",
       "address":"Dr. Vértiz 668","lat":19.4009,"lng":-99.1498},
      {"id":"makercdmx","name":"Maker CDMX — Del Valle","eyebrow":"Del Valle",
       "address":"Eje 7 Sur 419","lat":19.3762,"lng":-99.1671}]}
    ```

    ## Cómo comparé

    Busqué en directorios y filtré por stock confirmado esta semana.

    | Tienda | PLA 1kg |
    |---|---|
    | Vorti | $349 |
    | Grupo 3D | $310 |
    """
    let cut = MarkdownSplitter.reportCut(report)

    expectEq(cut.summary.count, 1, "reportCut: el resumen es el primer bloque")
    expect({ if case .prose(let p) = cut.summary[0].kind {
        p.hasPrefix("Encontré 3 tiendas") } else { false } }(),
        "reportCut: el resumen es la línea que narra la voz")

    expectEq(cut.cards.count, 1, "reportCut: la tarjeta sale del pliegue")
    guard case .code(let lang, let body) = cut.cards[0].kind else {
        expect(false, "reportCut: la tarjeta es un fence companion:*")
        return
    }
    expectEq(lang, "companion:locations", "reportCut: el fence trae su lenguaje")

    let block = CompanionBlocks.locations(body)
    expectEq(block?.title ?? "", "Encontramos 3 tiendas cerca de ti",
             "caso de uso: el header del sidebar viaja en title")
    expectEq(block?.locations.count ?? 0, 3, "caso de uso: las 3 ubicaciones")
    expectEq(block?.locations[0].eyebrow ?? "", "Roma Norte",
             "caso de uso: eyebrow para la tarjeta")
    expectEq(block?.locations[0].address ?? "", "Córdoba 87, Roma Norte",
             "caso de uso: dirección con su icono")
    expect(block?.locations[0].url == "https://vorti.mx",
           "caso de uso: link Ver sitio")
    expect(block?.locations[1].url == nil,
           "caso de uso: sin url la tarjeta omite el link, no revienta")
    expect(block.map { $0.locatorJSON.contains(#""id":"vorti""#) } ?? false,
           "caso de uso: el payload del mapa lleva los pins")

    expect(cut.detail.count >= 3, "reportCut: el proceso vive en el pliegue")
    expect(cut.detail.contains { if case .table = $0.kind { true } else { false } },
           "reportCut: la tabla comparativa es proceso, no respuesta")
}

@MainActor func testPlainText() {
    // Copy de una respuesta: prosa, títulos y listas — nunca fences ni tablas.
    let parts = MarkdownSplitter.split("""
    Encontré 3 cafés.

    ## Detalle
    - Buna
    - Almanegra

    ```companion:locations
    {"locations":[]}
    ```

    | a | b |
    |---|---|
    | 1 | 2 |
    """)
    let plain = MarkdownSplitter.plainText(parts)
    expect(plain.contains("Encontré 3 cafés."), "plain: la prosa viaja")
    expect(plain.contains("Detalle"), "plain: los títulos viajan")
    expect(plain.contains("- Buna"), "plain: las listas viajan con viñeta")
    expect(!plain.contains("locations"), "plain: los fences no se copian")
    expect(!plain.contains("| a |") && !plain.contains("1"),
           "plain: las tablas no se copian")
}

@MainActor func testSources() {
    // Sources del informe → tarjeta: links markdown y URLs a pelo, sin duplicados.
    let parts = MarkdownSplitter.split("""
    ## Cómo comparé

    Filtré por stock confirmado.

    Sources:

    - [Buna — Café de especialidad](https://buna.mx/nosotros) — pan y café en Roma Norte
    - [Almanegra Café](https://almanegra.cafe)
    - https://mugen.cafe/corner
    - [Buna otra vez](https://buna.mx/nosotros)
    """)
    let (rest, web) = MarkdownSplitter.extractSources(parts)
    expectEq(web.count, 3, "fuentes: links únicos, sin duplicados")
    expectEq(web[0].title, "Buna — Café de especialidad",
             "fuentes: el título del link markdown viaja")
    expectEq(web[0].detail ?? "", "pan y café en Roma Norte",
             "fuentes: la línea de qué aporta viaja como descripción")
    expect(web[1].detail == nil, "fuentes: sin descripción no se inventa")
    expectEq(web[2].title, "mugen.cafe",
             "fuentes: la URL a pelo se titula con su host")
    expect(!rest.contains { if case .list = $0.kind { true } else { false } },
           "fuentes: la lista sale del detalle")
    expect(rest.contains { if case .heading(2, "Cómo comparé") = $0.kind {
        true } else { false } }, "fuentes: el resto del detalle queda intacto")

    let plain = MarkdownSplitter.split("Fuentes:\n\nno hay links aquí")
    let (untouched, none) = MarkdownSplitter.extractSources(plain)
    expect(none.isEmpty, "fuentes: sin links no hay tarjeta")
    expectEq(untouched.count, plain.count, "fuentes: y el markdown no se toca")
}
