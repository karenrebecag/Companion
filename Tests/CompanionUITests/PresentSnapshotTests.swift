import AppKit
import CompanionCore
import CompanionTestKit
import CompanionUI
import CompanionUIPro
import Foundation
import SwiftUI
import Testing

// The present blocks compare by eye: one capture per family, in the chat and
// in the island, in light and dark. Same harness rule as the other snapshot
// tests: nothing happens without COMPANION_SNAPSHOTS.

@Test @MainActor func presentSnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    for sample in PresentSamples.all() {
        guard let renders = PresentFence.renders(body: sample.body) else {
            expect(false, "present snapshot: \(sample.name) no resolvio a bloques")
            continue
        }
        for compact in [false, true] {
            for dark in [false, true] {
                let name = "\(compact ? "isla" : "chat")-\(sample.name)-\(dark ? "oscuro" : "claro")"
                try capture(
                    PresentView(renders, compact: compact),
                    width: compact ? 440 : 640, dark: dark, to: out, name)
            }
        }
    }
}

@MainActor private func capture(
    _ view: some View, width: CGFloat, dark: Bool, to dir: URL, _ name: String
) throws {
    let framed = view
        .chartMotionPaused()
        .frame(width: width, alignment: .leading)
        .padding(20)
        .background(dark ? Color(white: 0.06) : Color.white)
        .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else {
        expect(false, "present snapshot: \(name) no rindio imagen")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}

private struct PresentSample {
    let name: String
    let body: String

    init(_ name: String, blocks: String) {
        self.name = name
        body = "{\"blocks\":[\(blocks)]}"
    }
}

/// The same JSON a model would send, so the capture takes the product's path:
/// parser, resolver, then the view.
private enum PresentSamples {
    static func all() -> [PresentSample] {
        let iso = ISO8601DateFormatter()
        let soon = iso.string(from: Date().addingTimeInterval(3 * 86_400 + 4 * 3_600))
        let past = iso.string(from: Date().addingTimeInterval(-3_600))
        let earlier = iso.string(from: Date().addingTimeInterval(-26 * 3_600))
        return prose + data + series(iso) + time(soon: soon, past: past, earlier: earlier) + files
    }

    private static let prose = [
        PresentSample("prosa", blocks: """
        {"type":"heading","text":"Resumen del trimestre","level":2},
        {"type":"paragraph","text":"Las ventas subieron **12 %** frente al trimestre anterior, con `Norte` al frente."},
        {"type":"list","items":["Renovar el contrato","Abrir la sucursal Sur"]},
        {"type":"keyvalue","items":[{"key":"Región","value":"Norte"},{"key":"Equipo","value":"12 personas"}]},
        {"type":"quote","text":"Lo simple escala.","source":"Notas del equipo"},
        {"type":"divider"},
        {"type":"callout","tone":"info","title":"Dato","text":"El cierre es el día 30."}
        """),
        PresentSample("aviso", blocks: """
        {"type":"notice","tone":"warning","title":"Límite cercano","text":"Usaste el 92 % de la cuota mensual."},
        {"type":"notice","tone":"danger","text":"El envío falló tres veces seguidas."},
        {"type":"notice","tone":"success","text":"La copia terminó sin errores."}
        """),
    ]

    private static var data: [PresentSample] {
        let rows = (0..<14).map { index -> String in
            let state = ["Activa", "Pausada", "Cerrada"][index % 3]
            let region = ["Norte", "Sur"][index % 2]
            return "[\"Cuenta \(index + 1)\",\"\(state)\",\"\(region)\",\(120 + index * 37)]"
        }.joined(separator: ",")
        let folders = (1...8).map { "{\"label\":\"Carpeta \($0)\",\"value\":\(90 / $0)}" }.joined(separator: ",")
        return [
            PresentSample("tabla", blocks: """
            {"type":"table","title":"Cuentas","columns":["Cuenta","Estado","Saldo"],
             "rows":[["Alfa","Activa",1200],["Beta","Pausada",90],["Gama","Activa",15400.5]]}
            """),
            PresentSample("tabla-filtro", blocks: """
            {"type":"table","title":"Cuentas por región","columns":["Cuenta","Estado","Región","Saldo"],"rows":[\(rows)]}
            """),
            PresentSample("comparacion", blocks: """
            {"type":"comparison","title":"Antes y después","columns":["Antes","Después"],
             "rows":[{"label":"Norte","values":[40,55]},{"label":"Sur","values":[62,48]},{"label":"Centro","values":[30,34]}]}
            """),
            PresentSample("comparacion-qa", blocks: """
            {"type":"comparison","columns":["Criterio","Swift Charts","Charts de terceros","Chart.js"],
             "rows":[{"label":"Rendimiento","values":["alto","medio","alto"]},{"label":"Licencia","values":["MIT","MIT","MIT"]},
                     {"label":"Tipos","values":[4,2,3]}]},
            {"type":"paragraph","text":"Swift Charts es el marco nativo de Apple."}
            """),
            PresentSample("serie-ene-jun", blocks: """
            {"type":"timeSeries","title":"Usuarios","unit":"miles","labels":["Ene","Feb","Mar","Abr","May","Jun"],
             "series":[{"name":"Web","values":[120,135,150,162,170,200]},{"name":"App","values":[80,90,96,101,110,118]}]}
            """),
            PresentSample("dona", blocks: """
            {"type":"partsofwhole","title":"Ingresos por canal",
             "parts":[{"label":"Web","value":45},{"label":"Tienda","value":30},{"label":"Socios","value":15},{"label":"Otros","value":10}]}
            """),
            PresentSample("barra-dividida", blocks: """
            {"type":"partsofwhole","title":"Presupuesto usado","parts":[{"label":"Gastado","value":68},{"label":"Libre","value":32}]}
            """),
            PresentSample("mapa-arbol", blocks: """
            {"type":"partsofwhole","title":"Tamaño por carpeta","parts":[\(folders)]}
            """),
            PresentSample("barras", blocks: """
            {"type":"ranking","title":"Ventas por vendedor","unit":"mil",
             "items":[{"label":"Ana","value":92},{"label":"Luis","value":78},{"label":"Marta","value":64},{"label":"Iván","value":41}]}
            """),
            PresentSample("metricas", blocks: """
            {"type":"metrics","title":"Indicadores","items":[
             {"label":"Ingresos","value":128400,"unit":"USD","delta":"+8 %","trend":[90,96,101,99,112,120,128]},
             {"label":"Meta de usuarios","value":7200,"target":10000,"delta":"+3 %"},
             {"label":"Tickets abiertos","value":42,"delta":"-5"}]}
            """),
        ]
    }

    private static func series(_ iso: ISO8601DateFormatter) -> [PresentSample] {
        let days = (0..<100).map { index -> String in
            let date = Date(timeIntervalSince1970: 1_767_225_600 + Double(index) * 86_400)
            return "\"" + String(iso.string(from: date).prefix(10)) + "\""
        }.joined(separator: ",")
        let wave = (0..<100).map { index -> String in
            let x = Double(index)
            let value: Double = 50 + 30 * sin(x / 9) + Double(index % 7)
            return String(Int(value))
        }.joined(separator: ",")
        return [
            PresentSample("linea", blocks: """
            {"type":"timeseries","title":"Visitas semanales","unit":"visitas",
             "labels":["Sem 1","Sem 2","Sem 3","Sem 4","Sem 5","Sem 6"],
             "series":[{"name":"Web","values":[120,150,140,180,210,230]},{"name":"App","values":[60,70,95,90,120,140]}]}
            """),
            PresentSample("pincel", blocks: """
            {"type":"timeseries","title":"Carga diaria","unit":"%","labels":[\(days)],
             "series":[{"name":"CPU","values":[\(wave)]}]}
            """),
            PresentSample("flujo", blocks: """
            {"type":"timeseries","title":"Tráfico por fuente","stacked":true,"labels":["Ene","Feb","Mar","Abr","May"],
             "series":[{"name":"Orgánico","values":[30,36,40,52,60]},{"name":"Pago","values":[20,25,22,30,28]},
                       {"name":"Directo","values":[12,14,18,17,22]}]}
            """),
        ]
    }

    private static func time(soon: String, past: String, earlier: String) -> [PresentSample] {
        [
            PresentSample("cronologia", blocks: """
            {"type":"timeline","title":"Lanzamiento","events":[
             {"when":"\(earlier)","title":"Diseño aprobado","tone":"success"},
             {"when":"\(past)","title":"Pruebas internas","detail":"Dos errores abiertos."},
             {"when":"\(soon)","title":"Salida pública","tone":"danger"}]}
            """),
            PresentSample("pasos", blocks: """
            {"type":"steps","title":"Migración","steps":[
             {"title":"Respaldar datos","state":"done"},
             {"title":"Mover usuarios","detail":"Lote 2 de 4","state":"current"},
             {"title":"Apagar el servidor viejo","state":"todo"}]}
            """),
            PresentSample("cuenta-atras", blocks: """
            {"type":"events","title":"Entrega","events":[{"title":"Entrega del informe","start":"\(soon)","place":"Oficina central"}]}
            """),
        ]
    }

    private static let files = [
        PresentSample("lugares", blocks: """
        {"type":"places","title":"Cafés cerca","places":[
         {"name":"Café Central","address":"Av. Reforma 10","lat":19.4326,"lng":-99.1332},
         {"name":"Tostadores","address":"Calle Durango 5","lat":19.4194,"lng":-99.1627}]}
        """),
        PresentSample("arbol", blocks: """
        {"type":"files","title":"Proyecto","items":[
         {"name":"Sources","children":[{"name":"App.swift","size":"2 KB"},
           {"name":"Views","children":[{"name":"Home.swift","size":"4 KB"}]}]},
         {"name":"Package.swift","size":"1 KB"}]}
        """),
        PresentSample("archivos", blocks: """
        {"type":"files","title":"Adjuntos","items":[
         {"name":"informe-q3.pdf","size":"1.2 MB"},{"name":"datos.csv","size":"88 KB"},{"name":"portada.png","size":"340 KB"}]}
        """),
        PresentSample("codigo", blocks: """
        {"type":"codeordiff","title":"total.swift","language":"swift",
         "code":"func total(_ items: [Int]) -> Int {\\n    items.reduce(0, +)\\n}\\n"}
        """),
        PresentSample("diff", blocks: """
        {"type":"codeordiff","title":"total.swift","language":"swift",
         "before":"func total(_ items: [Int]) -> Int {\\n    var sum = 0\\n    for item in items { sum += item }\\n    return sum\\n}\\n",
         "after":"func total(_ items: [Int]) -> Int {\\n    items.reduce(0, +)\\n}\\n"}
        """),
        PresentSample("fuentes", blocks: """
        {"type":"websources","sources":[
         {"title":"Documentación de Swift Charts","url":"https://developer.apple.com/documentation/charts"},
         {"title":"Guía de SwiftUI","url":"https://developer.apple.com/xcode/swiftui/"}]}
        """),
    ]
}
