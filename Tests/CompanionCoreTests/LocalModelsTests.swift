import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func localModelsTests() {
    testTierBoundaries()
    testTierNeverLandsOnAShippingConfiguration()
    testEmbeddingOnlyModelsAreNotUsable()
    testEmptyListChoosesNothing()
    testOnlyNonChatModelsChoosesNothing()
    testPreferredWinsWhenStillInstalled()
    testPreferredIgnoredWhenUninstalled()
    testLargestThatFitsTheTierWins()
    testOversizedModelIsBetterThanNothing()
    testTieBreaksLexicographically()
    testSuggestedPullIsDistinctPerTier()
    testJobsNeedMoreThanTheSmallestTier()
}

private func model(_ name: String, _ gib: Double) -> InstalledModel {
    InstalledModel(name: name, sizeBytes: UInt64(gib * 1024 * 1024 * 1024))
}

private let gib = UInt64(1024 * 1024 * 1024)

@MainActor func testTierBoundaries() {
    expectEq(RAMTier.forBytes(8 * gib), .small, "8 GB cae en small")
    expectEq(RAMTier.forBytes(16 * gib), .medium, "16 GB cae en medium")
    expectEq(RAMTier.forBytes(18 * gib), .medium, "18 GB sigue en medium")
    expectEq(RAMTier.forBytes(24 * gib), .large, "24 GB cae en large")
    expectEq(RAMTier.forBytes(32 * gib), .large, "32 GB cae en large")
    expectEq(RAMTier.forBytes(64 * gib), .xlarge, "64 GB cae en xlarge")
    expectEq(RAMTier.forBytes(128 * gib), .xlarge, "128 GB cae en xlarge")
}

@MainActor func testTierNeverLandsOnAShippingConfiguration() {
    // Los umbrales viven ENTRE configuraciones reales: si un Mac que se vende
    // cae justo en el borde, el escalon depende del redondeo del fabricante.
    for gigs in [8, 16, 18, 24, 32, 36, 48, 64, 96, 128] {
        let below = RAMTier.forBytes(UInt64(gigs) * gib - 1)
        let exact = RAMTier.forBytes(UInt64(gigs) * gib)
        expectEq(below, exact, "\(gigs) GB no debe caer sobre un umbral")
    }
}

@MainActor func testEmbeddingOnlyModelsAreNotUsable() {
    let all = [
        model("nomic-embed-text", 0.3),
        model("bge-m3", 1.2),
        model("mxbai-rerank-large", 1.5),
        model("qwen3:8b", 5),
    ]
    let usable = LocalModelChoice.usable(all)
    expectEq(usable.count, 1, "solo el modelo de chat sobrevive el filtro")
    expectEq(usable.first?.name, "qwen3:8b", "y es el de chat")
}

@MainActor func testEmptyListChoosesNothing() {
    expect(LocalModelChoice.choose(from: [], tier: .medium, preferred: nil) == nil,
           "sin modelos no hay eleccion")
}

@MainActor func testOnlyNonChatModelsChoosesNothing() {
    // El bug que esta wave existe para arreglar, con otra cara: ofrecer un
    // modelo de embeddings falla el primer mensaje igual que un tag fantasma.
    let all = [model("nomic-embed-text", 0.3), model("bge-m3", 1.2)]
    expect(LocalModelChoice.choose(from: all, tier: .large, preferred: nil) == nil,
           "una lista solo de embeddings equivale a no tener modelo")
}

@MainActor func testPreferredWinsWhenStillInstalled() {
    let all = [model("qwen3:14b", 9), model("llama3.2:3b", 2)]
    let picked = LocalModelChoice.choose(
        from: all, tier: .large, preferred: "llama3.2:3b")
    expectEq(picked?.name, "llama3.2:3b",
             "lo guardado gana: la estabilidad entre arranques vale mas")
}

@MainActor func testPreferredIgnoredWhenUninstalled() {
    let all = [model("qwen3:14b", 9)]
    let picked = LocalModelChoice.choose(
        from: all, tier: .large, preferred: "un-modelo-que-ya-no-esta")
    expectEq(picked?.name, "qwen3:14b",
             "un preferido borrado no bloquea la eleccion")
}

@MainActor func testLargestThatFitsTheTierWins() {
    let all = [model("chico:3b", 2), model("mediano:8b", 5), model("enorme:70b", 40)]
    let picked = LocalModelChoice.choose(from: all, tier: .medium, preferred: nil)
    expectEq(picked?.name, "mediano:8b",
             "el mayor que cabe en el escalon, no el mayor de la lista")
}

@MainActor func testOversizedModelIsBetterThanNothing() {
    // El usuario ya pago la descarga: decirle que no tiene modelo seria
    // mentira. Lento es un problema distinto de ausente.
    let all = [model("enorme:70b", 40)]
    let picked = LocalModelChoice.choose(from: all, tier: .small, preferred: nil)
    expectEq(picked?.name, "enorme:70b",
             "si nada cabe, el mas chico instalado en vez de nada")
}

@MainActor func testTieBreaksLexicographically() {
    let all = [model("zeta:8b", 5), model("alfa:8b", 5)]
    let picked = LocalModelChoice.choose(from: all, tier: .large, preferred: nil)
    expectEq(picked?.name, "alfa:8b", "empate de tamano se rompe determinista")
}

@MainActor func testSuggestedPullIsDistinctPerTier() {
    let pulls = RAMTier.allCases.map(\.suggestedPull)
    expectEq(Set(pulls).count, RAMTier.allCases.count,
             "cada escalon sugiere un modelo distinto")
    for pull in pulls {
        expect(!pull.isEmpty, "ninguna sugerencia esta vacia")
        expect(pull.contains(":"), "la sugerencia lleva tag explicito: \(pull)")
    }
}

@MainActor func testJobsNeedMoreThanTheSmallestTier() {
    expect(!RAMTier.small.suitableForJobs,
           "la clase 3B falla tool calling: no se promete especialista")
    expect(RAMTier.medium.suitableForJobs, "desde 16 GB si")
    expect(RAMTier.large.suitableForJobs, "y en adelante")
    expect(RAMTier.xlarge.suitableForJobs, "y en adelante")
}
