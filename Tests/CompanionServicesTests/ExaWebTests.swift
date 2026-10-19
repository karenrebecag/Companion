import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func exaSearchSendsTheDocumentedRequest() throws {
    let transport = ScriptedTransport()
    transport.stub(url: ExaWebSearch.endpoint, ScriptedReply(status: 200, body: Data(#"{"results":[]}"#.utf8)))
    let search = ExaWebSearch(transport: transport, secrets: TestSecretStore([.exa: "exa-test"]))
    _ = try runAsync { try await search.search("vuelos a Lima") }

    guard let request = transport.requests.first else {
        expect(false, "salio una peticion")
        return
    }
    expectEq(request.httpMethod, "POST", "la busqueda de Exa es un POST")
    expectEq(request.value(forHTTPHeaderField: "x-api-key"), "exa-test",
             "la clave viaja en x-api-key, no en la URL")
    expect(request.url?.absoluteString.contains("exa-test") == false,
           "y nunca aparece en la URL")
    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
    expectEq(body?["query"] as? String, "vuelos a Lima", "la consulta va en query")
    expectEq(body?["numResults"] as? Int, 6, "pide seis resultados")
    let contents = body?["contents"] as? [String: Any]
    let highlights = contents?["highlights"] as? [String: Any]
    expectEq(highlights?["maxCharacters"] as? Int, ExaWebSearch.highlightCharacters,
             "pide highlights: los pasajes que responden, con numeros como texto")
}

@Test @MainActor func exaSearchReturnsHighlightsAsTheSnippet() throws {
    let body = Data("""
    {"requestId":"r1","results":[
      {"title":"Vuelo LIM-MEX","url":"https://ejemplo.pe/a",
       "highlights":["Desde 189 USD ida y vuelta.","Escala en Bogota."]},
      {"title":"Sin url","highlights":["no se cita"]}
    ]}
    """.utf8)
    let results = try ExaWebSearch.decode(body, limit: 6)
    expectEq(results.count, 1, "un resultado sin url no se puede citar, asi que no es respuesta")
    expectEq(results.first?.title, "Vuelo LIM-MEX", "el titulo llega")
    expectEq(results.first?.url, "https://ejemplo.pe/a", "y su url")
    expect(results.first?.snippet.contains("189 USD") == true,
           "los highlights son el fragmento que responde, con la cifra")
}

@Test @MainActor func exaSearchFailsClosedOnMalformedJSON() {
    do {
        _ = try ExaWebSearch.decode(Data("{\"results\":[".utf8), limit: 6)
        expect(false, "un cuerpo que no es JSON valido debe fallar, no devolver vacio")
    } catch {
        expectEq(error as? ExaError, .malformedResponse,
                 "un cuerpo malformado falla cerrado con el error de Exa")
    }
}

@Test func webProviderPrefersExaThenBraveThenNothing() {
    expectEq(WebProvider.select(secrets: TestSecretStore([.exa: "e", .brave: "b"])), .exa,
             "con las dos claves gana Exa")
    expectEq(WebProvider.select(secrets: TestSecretStore([.brave: "b"])), .brave,
             "sin clave de Exa, Brave")
    expectEq(WebProvider.select(secrets: TestSecretStore([.exa: "   ", .brave: "b"])), .brave,
             "una clave de Exa en blanco no cuenta como configurada")
    expectEq(WebProvider.select(secrets: TestSecretStore()), .none,
             "sin ninguna clave, no hay proveedor")
}

@Test @MainActor func exaReaderSendsFreshOnlyWhenAsked() throws {
    let url = URL(string: "https://ejemplo.pe/vuelos")!
    let reply = ScriptedReply(status: 200, body: Data(#"{"results":[]}"#.utf8))

    let cached = ScriptedTransport()
    cached.stub(url: ExaWebReader.endpoint, reply)
    _ = try runAsync { try await ExaWebReader(transport: cached, secrets: TestSecretStore([.exa: "exa-test"])).read([url], fresh: false) }
    let cachedBody = try JSONSerialization.jsonObject(with: cached.requests.first?.httpBody ?? Data()) as? [String: Any]
    expect(cachedBody?["maxAgeHours"] == nil, "sin fresh se acepta la copia en cache de Exa")
    expectEq(cached.requests.first?.value(forHTTPHeaderField: "x-api-key"), "exa-test",
             "la lectura usa la misma cabecera de clave")

    let live = ScriptedTransport()
    live.stub(url: ExaWebReader.endpoint, reply)
    _ = try runAsync { try await ExaWebReader(transport: live, secrets: TestSecretStore([.exa: "exa-test"])).read([url], fresh: true) }
    let liveBody = try JSONSerialization.jsonObject(with: live.requests.first?.httpBody ?? Data()) as? [String: Any]
    expectEq(liveBody?["maxAgeHours"] as? Int, 0, "fresh=true pide contenido nuevo (maxAgeHours 0)")
    expectEq(liveBody?["urls"] as? [String], [url.absoluteString], "la URL viaja en urls")
}

@Test func readURLTextIsCappedAndSaidSo() throws {
    let long = String(repeating: "a", count: ExaWebReader.maxPageCharacters + 5_000)
    let body = try JSONSerialization.data(withJSONObject: [
        "results": [["title": "Largo", "url": "https://ejemplo.pe/l", "text": long]],
    ])
    let pages = try ExaWebReader.decode(body)
    expectEq(pages.count, 1, "la pagina llega")
    let text = pages.first?.text ?? ""
    expect(text.hasPrefix(String(repeating: "a", count: ExaWebReader.maxPageCharacters)),
           "conserva el inicio de la pagina hasta el tope")
    expect(text.hasSuffix("[cut at \(ExaWebReader.maxPageCharacters) characters]"),
           "y dice que la cortó, para que el modelo sepa que hay mas")
}

@Test @MainActor func readURLIsOfferedOnlyWithAnExaKey() {
    let transport = ScriptedTransport()
    let withExa = NativeToolRunner(
        workdir: NSTemporaryDirectory(),
        webReader: ExaWebReader(transport: transport, secrets: TestSecretStore([.exa: "exa-test"])))
    expect(withExa.availableTools.contains(.readURL), "con clave de Exa, read_url se ofrece")

    let withBraveOnly = NativeToolRunner(
        workdir: NSTemporaryDirectory(),
        webReader: WebProvider.brave.reader(transport: transport, secrets: TestSecretStore([.brave: "b"])))
    expect(!withBraveOnly.availableTools.contains(.readURL),
           "con solo Brave no hay quien lea paginas, y read_url no se ofrece")
}
