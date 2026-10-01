import CompanionCore
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func ollamaModelScanTests() {
    testScanReadsInstalledTags()
    testScanRequestShape()
    testDaemonSilentWithBinaryReportsNotRunning()
    testDaemonSilentWithoutBinaryReportsAbsent()
    testDaemonUpWithoutUsableModelReportsNoModel()
    testNon200IsNotReady()
    testMalformedBodyIsNotReady()
    testScanNeverThrows()
    testScanRefusesANonLocalBase()
}

private let tagsBody = Data("""
{"models":[
  {"name":"qwen3:14b","size":9663676416},
  {"name":"llama3.2:3b","size":2019393189},
  {"name":"nomic-embed-text","size":274301056}
]}
""".utf8)

@MainActor private func scan(
    _ transport: ScriptedTransport,
    binaryPresent: Bool = true,
    preferred: String? = nil,
    tier: RAMTier = .large
) -> OllamaScanResult {
    let sut = OllamaModelScan(
        transport: transport, binaryPresent: { binaryPresent })
    do {
        return try runAsync { await sut.scan(tier: tier, preferred: preferred) }
    } catch {
        expect(false, "scan no debia tirar: \(error)")
        return OllamaScanResult(state: .absent, installed: [])
    }
}

@MainActor func testScanReadsInstalledTags() {
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 200, body: tagsBody))
    let result = scan(transport)
    expectEq(result.installed.count, 3, "las tres filas del daemon se leen")
    guard case .ready(let chosen) = result.state else {
        expect(false, "con modelos usables el estado es ready")
        return
    }
    expectEq(chosen.name, "qwen3:14b", "elige el mayor que cabe en 24-32 GB")
}

@MainActor func testScanRequestShape() {
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 200, body: tagsBody))
    _ = scan(transport)
    expectEq(transport.requests.count, 1, "una sola peticion")
    let request = transport.requests[0]
    expectEq(request.httpMethod, "GET", "el scan es de lectura (ADR 004)")
    expect(request.httpBody == nil, "un GET de lectura no lleva cuerpo")
    expectEq(request.url?.absoluteString, "http://localhost:11434/api/tags",
             "pega al endpoint nativo del daemon")
}

@MainActor func testDaemonSilentWithBinaryReportsNotRunning() {
    // El caso de la Mac de Karen: ollama instalado, daemon apagado. Decirle
    // "instala Ollama" seria falso, y es copy distinto del de no tenerlo.
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 200, error: URLError(.cannotConnectToHost)))
    let result = scan(transport, binaryPresent: true)
    expectEq(result.state, .notRunning, "binario presente y daemon mudo")
}

@MainActor func testDaemonSilentWithoutBinaryReportsAbsent() {
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 200, error: URLError(.cannotConnectToHost)))
    let result = scan(transport, binaryPresent: false)
    expectEq(result.state, .absent, "sin binario y sin daemon")
}

@MainActor func testDaemonUpWithoutUsableModelReportsNoModel() {
    let body = Data(#"{"models":[{"name":"nomic-embed-text","size":274301056}]}"#.utf8)
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 200, body: body))
    let result = scan(transport)
    expectEq(result.state, .noModel, "daemon vivo pero nada con que hablar")
    expectEq(result.installed.count, 1, "lo instalado se reporta igual")
}

@MainActor func testNon200IsNotReady() {
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 500, body: tagsBody))
    let result = scan(transport, binaryPresent: true)
    expectEq(result.state, .notRunning, "un 500 no es un daemon utilizable")
    expect(result.installed.isEmpty, "y no se inventa inventario")
}

@MainActor func testMalformedBodyIsNotReady() {
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 200, body: Data("no soy json".utf8)))
    let result = scan(transport, binaryPresent: true)
    expectEq(result.state, .notRunning, "un cuerpo ilegible no es ready")
}

@MainActor func testScanNeverThrows() {
    // Un daemon caido es "no esta aqui", no un error que rompa el arranque:
    // la misma decision que ya tomo LiveCapabilityProbe.
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 200, error: URLError(.timedOut)))
    let result = scan(transport)
    expect(result.installed.isEmpty, "sin inventario, sin excepcion")
}

@MainActor func testScanRefusesANonLocalBase() {
    // EndpointPolicy ya prohibe http fuera de localhost; el scan no puede ser
    // la puerta por la que se cuela un host remoto en claro.
    let transport = ScriptedTransport()
    let sut = OllamaModelScan(
        transport: transport,
        baseURL: URL(string: "http://modelos.ejemplo.com:11434")!,
        binaryPresent: { true })
    do {
        let result = try runAsync { await sut.scan(tier: .large, preferred: nil) }
        expectEq(result.state, .absent, "un base no local no se sondea")
        expectEq(transport.requests.count, 0, "y no sale ni una peticion")
    } catch {
        expect(false, "scan no debia tirar: \(error)")
    }
}

@Test @MainActor func localCatalogTests() {
    testCatalogOmitsOllamaBeforeAnyScan()
    testCatalogCarriesTheInstalledTag()
    testCatalogOmitsOllamaWhenNothingUsable()
    testCatalogNeverTouchesKeyedProviders()
}

@MainActor private func catalog(
    _ transport: ScriptedTransport, tier: RAMTier = .large
) -> LocalCatalog {
    LocalCatalog(
        scan: OllamaModelScan(transport: transport, binaryPresent: { true }),
        tier: tier)
}

@MainActor func testCatalogOmitsOllamaBeforeAnyScan() {
    // Arrancar ofreciendo un modelo que nadie ha comprobado es exactamente el
    // defecto viejo: el probe dice que si y el primer mensaje muere.
    let sut = catalog(ScriptedTransport())
    let ids = sut.effective().map(\.id)
    expect(!ids.contains("ollama"), "sin scan, Ollama no se ofrece")
    expect(ids.contains("openai"), "los proveedores con clave siguen ahi")
}

@MainActor func testCatalogCarriesTheInstalledTag() {
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 200, body: tagsBody))
    let sut = catalog(transport)
    do {
        _ = try runAsync { await sut.refresh(preferred: nil) }
    } catch {
        expect(false, "refresh no debia tirar: \(error)")
        return
    }
    guard let ollama = sut.effective().first(where: { $0.id == "ollama" }) else {
        expect(false, "con modelo usable, Ollama entra al catalogo")
        return
    }
    expectEq(ollama.model, "qwen3:14b", "y lleva el tag que el daemon TIENE")
    expectEq(ProviderDescriptor.ollama.model, "qwen3.6:27b",
             "la plantilla compartida no se muta")
}

@MainActor func testCatalogOmitsOllamaWhenNothingUsable() {
    let body = Data(#"{"models":[{"name":"nomic-embed-text","size":274301056}]}"#.utf8)
    let transport = ScriptedTransport()
    transport.stub(url: "http://localhost:11434/api/tags",
                   ScriptedReply(status: 200, body: body))
    let sut = catalog(transport)
    do {
        _ = try runAsync { await sut.refresh(preferred: nil) }
    } catch {
        expect(false, "refresh no debia tirar: \(error)")
        return
    }
    expect(!sut.effective().contains { $0.id == "ollama" },
           "daemon vivo sin modelo de chat no es un peldano de la escalera")
}

@MainActor func testCatalogNeverTouchesKeyedProviders() {
    let sut = catalog(ScriptedTransport())
    let keyed = sut.effective().filter { $0.secretKey != nil }
    let expected = ProviderDescriptor.catalog.filter { $0.secretKey != nil }
    expectEq(keyed, expected,
             "el scan local no altera el orden ni el modelo de los de clave")
}
