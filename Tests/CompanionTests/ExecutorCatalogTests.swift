import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// El catálogo de ejecutores se DETECTA, jamás se asume (ADR 001). Claude
// expone sus tiers por alias del CLI; hermes expone sus proveedores en su
// propio cache (~/.hermes/provider_models_cache.json) — leerlo es "buscar
// en la computadora", no cablear el setup de una sola persona.

@Test @MainActor func executorCatalogTests() throws {
    try testClaudeTiersAppearWithSonnetFirst()
    try testHermesProvidersComeFromItsCache()
    try testNoCLIsMeansEmptyCatalog()
    testProviderScanParsesTheCache()
    testProviderScanSurvivesGarbage()
}

@MainActor func testClaudeTiersAppearWithSonnetFirst() throws {
    let probe = CLIExecutorProbe(
        locator: CLIBinaryLocator(home: "/Users/k") {
            $0 == "/Users/k/.local/bin/claude"
        },
        hermesProviders: { [] })
    let detected = try runAsync { await probe.detectAvailable() }
    let claude = detected.filter { $0.id.rawValue.hasPrefix("claude-code") }

    expectEq(claude.count, 4, "catálogo: los cuatro tiers del CLI de claude")
    expectEq(claude.first?.id.rawValue, "claude-code",
             "catálogo: Sonnet encabeza — el especialista de trabajo por defecto")
    expectEq(claude.first?.modelArgs, ["--model", "sonnet"],
             "catálogo: el default es sonnet, no opus (costo de un encargo típico)")
    let args = claude.map { $0.modelArgs }
    expect(args.contains(["--model", "fable"]), "catálogo: tier fable")
    expect(args.contains(["--model", "opus"]), "catálogo: tier opus")
    expect(args.contains(["--model", "haiku"]), "catálogo: tier haiku")
    expect(claude.allSatisfy { $0.title.hasPrefix("Claude") },
           "catálogo: las filas se leen como Claude · tier")
}

@MainActor func testHermesProvidersComeFromItsCache() throws {
    let probe = CLIExecutorProbe(
        locator: CLIBinaryLocator(home: "/Users/k") {
            $0 == "/Users/k/.local/bin/hermes"
        },
        hermesProviders: { ["openrouter", "copilot", "xai-oauth"] })
    let detected = try runAsync { await probe.detectAvailable() }
    let hermes = detected.filter { $0.id.rawValue.hasPrefix("hermes") }

    expectEq(hermes.first?.id.rawValue, "hermes",
             "catálogo: la cadena por defecto encabeza")
    expectEq(hermes.first?.modelArgs, [],
             "catálogo: la cadena por defecto no fuerza proveedor")
    expect(hermes.contains { $0.modelArgs == ["--provider", "copilot"] },
           "catálogo: fila por proveedor del cache de hermes")
    expect(hermes.contains { $0.modelArgs == ["--provider", "xai-oauth"] },
           "catálogo: grok entra como proveedor detectado, no hardcodeado")
    expectEq(hermes.count, 4, "catálogo: cadena + 3 proveedores")
}

@MainActor func testNoCLIsMeansEmptyCatalog() throws {
    let probe = CLIExecutorProbe(
        locator: CLIBinaryLocator(home: "/Users/k") { _ in false },
        hermesProviders: { ["openrouter"] })
    let detected = try runAsync { await probe.detectAvailable() }
    expect(detected.isEmpty,
           "catálogo: sin binarios no hay filas — aunque el cache exista")
}

@MainActor func testProviderScanParsesTheCache() {
    let json = #"{"openrouter":{"fp":"x","at":1,"models":["a/b"]},"copilot":{"models":[]}}"#
    let providers = HermesProviderScan.providers(reading: { Data(json.utf8) })
    expectEq(providers, ["copilot", "openrouter"],
             "scan: los proveedores del cache, en orden estable")
}

@MainActor func testProviderScanSurvivesGarbage() {
    expectEq(HermesProviderScan.providers(reading: { nil }), [],
             "scan: sin archivo no hay filas")
    expectEq(HermesProviderScan.providers(reading: { Data("[1,2]".utf8) }), [],
             "scan: un cache con otra forma no revienta nada")
}
