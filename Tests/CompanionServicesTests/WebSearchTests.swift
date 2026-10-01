import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func webSearchTests() {
    testTheRequestMatchesTheDocumentedContract()
    testResultsComeBackAsSomethingTheModelCanRead()
    testNoKeyMeansTheToolIsNotOffered()
    testAKeyMakesTheToolAppear()
    testAFailedSearchSaysSoWithoutInventing()
    testTheOtherToolsNeverDependOnAKey()
}

private let braveBody = Data("""
{"web":{"results":[
  {"title":"Cinépolis Reforma","url":"https://ejemplo.mx/a","description":"Sala en Reforma 222."},
  {"title":"Cinemex Diana","url":"https://ejemplo.mx/b","description":"Frente al Ángel."}
]}}
""".utf8)

@MainActor private func search(
    key: String? = "brave-test", reply: ScriptedReply
) -> (ToolResult, ScriptedTransport) {
    let transport = ScriptedTransport()
    transport.stub(
        url: "https://api.search.brave.com/res/v1/web/search", reply)
    let secrets = TestSecretStore(key.map { [.brave: $0] } ?? [:])
    let runner = NativeToolRunner(
        workdir: NSTemporaryDirectory(),
        webSearch: BraveWebSearch(transport: transport, secrets: secrets))
    do {
        let result = try runAsync {
            try await runner.execute(
                tool: "web_search",
                arguments: ["query": "cines cerca de Reforma"], approved: false)
        }
        return (result, transport)
    } catch {
        expect(false, "web_search no debia tirar: \(error)")
        return (ToolResult(ok: false, output: ""), transport)
    }
}

@MainActor func testTheRequestMatchesTheDocumentedContract() {
    let (_, transport) = search(reply: ScriptedReply(status: 200, body: braveBody))
    guard let request = transport.requests.first else {
        expect(false, "salio una peticion")
        return
    }
    expectEq(request.httpMethod, "GET", "la busqueda es de lectura")
    expectEq(
        request.value(forHTTPHeaderField: "X-Subscription-Token"), "brave-test",
        "la clave viaja en la cabecera que documenta Brave, no en la URL")
    expect(
        request.url?.absoluteString.contains("q=cines") == true,
        "y la consulta va en q: \(request.url?.absoluteString ?? "")")
}

@MainActor func testResultsComeBackAsSomethingTheModelCanRead() {
    let (result, _) = search(reply: ScriptedReply(status: 200, body: braveBody))
    expect(result.ok, "con resultados, la busqueda salio bien")
    expect(result.output.contains("Cinépolis Reforma"), "el titulo llega")
    expect(result.output.contains("https://ejemplo.mx/a"), "y su url, para citarla")
    expect(result.output.contains("Reforma 222"), "y el fragmento que la resume")
}

@MainActor func testNoKeyMeansTheToolIsNotOffered() {
    // El defecto que abrio esto: anunciar una herramienta que siempre falla es
    // PEOR que no tenerla, porque captura la intencion y luego se muere. El
    // modelo dijo "no puedo buscar en la web" en vez de probar otra via.
    let runner = NativeToolRunner(
        workdir: NSTemporaryDirectory(),
        webSearch: BraveWebSearch(
            transport: ScriptedTransport(), secrets: TestSecretStore()))
    expect(!runner.availableTools.contains(.webSearch),
           "sin clave, web_search no se le ofrece al modelo")
}

@MainActor func testAKeyMakesTheToolAppear() {
    let runner = NativeToolRunner(
        workdir: NSTemporaryDirectory(),
        webSearch: BraveWebSearch(
            transport: ScriptedTransport(),
            secrets: TestSecretStore([.brave: "brave-test"])))
    expect(runner.availableTools.contains(.webSearch),
           "con clave si, y solo entonces")
}

@MainActor func testAFailedSearchSaysSoWithoutInventing() {
    let (result, _) = search(reply: ScriptedReply(status: 401, body: Data()))
    expect(!result.ok, "un 401 es un fallo")
    expect(!result.output.isEmpty, "y se dice, en vez de devolver vacio")
}

@MainActor func testTheOtherToolsNeverDependOnAKey() {
    // La base local no puede perder capacidades por no tener claves.
    let runner = NativeToolRunner(
        workdir: NSTemporaryDirectory(),
        webSearch: BraveWebSearch(
            transport: ScriptedTransport(), secrets: TestSecretStore()))
    for tool in [NativeTool.readFile, .listDirectory, .runShell, .findPlaces] {
        expect(runner.availableTools.contains(tool),
               "\(tool.rawValue) sigue disponible sin ninguna clave")
    }
}
