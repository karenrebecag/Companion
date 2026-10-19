import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func aSearchKeyPastedAfterLaunchIsUsedOnTheNextCall() throws {
    let secrets = TestSecretStore()
    let transport = ScriptedTransport()
    transport.stub(url: ExaWebSearch.endpoint, ScriptedReply(status: 200, body: Data(#"{"results":[]}"#.utf8)))
    let search = SelectedWebSearch(transport: transport, secrets: secrets)
    expect(!search.isConfigured, "sin clave no hay busqueda que ofrecer")

    try secrets.write(.exa, value: "exa-test")
    expect(search.isConfigured, "una clave pegada despues del arranque cuenta en la siguiente llamada")
    _ = try runAsync { try await search.search("vuelos a Lima") }
    expectEq(transport.requests.first?.value(forHTTPHeaderField: "x-api-key"), "exa-test",
             "la busqueda va a Exa con la clave guardada en ese momento")
}

@Test @MainActor func aReadKeyPastedAfterLaunchIsUsedOnTheNextCall() throws {
    let secrets = TestSecretStore()
    let transport = ScriptedTransport()
    transport.stub(url: ExaWebReader.endpoint, ScriptedReply(status: 200, body: Data(#"{"results":[]}"#.utf8)))
    let reader = SelectedWebReader(transport: transport, secrets: secrets)
    expect(!reader.isConfigured, "sin clave de Exa no se ofrece leer paginas")

    try secrets.write(.exa, value: "exa-test")
    expect(reader.isConfigured, "la clave de Exa pegada despues del arranque habilita read_url")
    _ = try runAsync { try await reader.read([URL(string: "https://ejemplo.pe/vuelos")!], fresh: false) }
    expectEq(transport.requests.first?.value(forHTTPHeaderField: "x-api-key"), "exa-test",
             "la lectura va a Exa con la clave guardada en ese momento")
}

@Test @MainActor func theOfferedToolsFollowTheKeychainEveryTurn() throws {
    let secrets = TestSecretStore()
    let transport = ScriptedTransport()
    let runner = NativeToolRunner(
        workdir: nil,
        webSearch: SelectedWebSearch(transport: transport, secrets: secrets),
        webReader: SelectedWebReader(transport: transport, secrets: secrets))
    expect(!runner.availableTools.contains(.webSearch) && !runner.availableTools.contains(.readURL),
           "antes de la clave, el turno no ofrece web_search ni read_url")

    try secrets.write(.exa, value: "exa-test")
    expect(runner.availableTools.contains(.webSearch) && runner.availableTools.contains(.readURL),
           "despues de pegar la clave, el siguiente turno ya las ofrece")
}
