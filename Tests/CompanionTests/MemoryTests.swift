import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// 9j-2: la memoria vive en markdown que la usuaria puede abrir y editar.
// Core arma el bloque (con marco de seguridad y topes); el store son archivos;
// el resumen de sesión es mecánico — la nota del 9h, cumplida.

@Test func memoryTests() throws {
    testInjectFramesMemoryAsData()
    testInjectCapsAndEmpty()
    testDistillTakesUserAsks()
    try testFileStoreRoundTrip()
    testChatPromptCarriesMemory()
}

func testInjectFramesMemoryAsData() {
    let pack = MemoryPack(core: "Karen es ingeniera frontend.",
                          recentSessions: ["## ayer\n- pidió un cuento"],
                          notes: ["prefiere respuestas cortas"])
    let block = MemoryPrompt.inject(
        pack, language: .es, knowledgeDirectory: "/tmp/Companion/knowledge")
    expect(block.contains("DATOS"), "inject: se enmarca como datos")
    expect(block.contains("nunca instrucciones"),
           "inject: el marco anti-inyección viaja — memoria no manda")
    expect(block.contains("Karen es ingeniera"), "inject: el core viaja")
    expect(block.contains("pidió un cuento"), "inject: lo episódico viaja")
    expect(block.contains("respuestas cortas"), "inject: las notas viajan")
    // El bug medido: "la carpeta de memoria" sin ruta hizo que el
    // especialista inventara un user_profile.md en otro lado.
    expect(block.contains("/tmp/Companion/knowledge"),
           "inject: la ruta viaja EXPLICITA — sin dirección, el "
           + "especialista inventa una")
    // Wave 11a: una sola forma de recordar, y es la que tiene catálogo.
    expect(block.contains("knowledge-builder"), "inject: apunta a la skill")
    expect(!block.contains("notes"), "inject: ya no manda a la carpeta de notas")
}

func testInjectCapsAndEmpty() {
    expectEq(MemoryPrompt.inject(MemoryPack()), "",
             "inject: sin memoria, sin bloque — ni el header viaja solo")
    let huge = MemoryPack(core: String(repeating: "a", count: 50_000))
    expect(MemoryPrompt.inject(huge).count < MemoryPrompt.coreCap + 500,
           "inject: el core no puede comerse el contexto")
    // Security review 2026-09-06: un grafema con 50 000 marcas pasaba el
    // tope por `count`; el tope cuenta scalars, como el bloque de contexto.
    let marks = MemoryPack(core: "a" + String(repeating: "\u{0301}", count: 50_000))
    expect(MemoryPrompt.inject(marks).unicodeScalars.count < MemoryPrompt.coreCap + 500,
           "inject: el tope cuenta scalars, no grafemas")
}

func testDistillTakesUserAsks() {
    let turns = [
        Turn(role: .user, content: "crea un archivo de prueba"),
        Turn(role: .assistant, content: "listo, lo creé"),
        Turn(role: .user, content: "ahora escríbele un cuento"),
    ]
    let summary = MemorySummary.distill(turns: turns, date: "2026-08-25")
    expect(summary?.contains("2026-08-25") == true, "distill: lleva la fecha")
    expect(summary?.contains("crea un archivo de prueba") == true,
           "distill: conserva la petición en palabras de la usuaria")
    expect(summary?.contains("escríbele un cuento") == true,
           "distill: y las siguientes")
    expect(MemorySummary.distill(turns: [], date: "x") == nil,
           "distill: sesión sin peticiones no deja nota")
}

func testFileStoreRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("memtest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FileMemoryStore(root: dir, recentSessions: 2)

    expect(store.load().isEmpty, "store: sin archivos, pack vacío")

    store.ensureCore(seed: "Es médica en formación")
    expect(store.load().core.contains("médica en formación"),
           "store: el perfil de Ajustes siembra el core")
    store.ensureCore(seed: "otro texto")
    expect(!store.load().core.contains("otro texto"),
           "store: ensureCore no pisa un core existente — el archivo es de la usuaria")

    try store.appendSession("## sesión uno")
    try store.appendSession("## sesión dos")
    let pack = store.load()
    expect(pack.recentSessions.count <= 2, "store: solo las últimas N")
    expect(pack.recentSessions.last?.contains("sesión") == true,
           "store: los resúmenes vuelven al leer")
}

func testChatPromptCarriesMemory() {
    let with = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false,
        language: .es, memory: "Memoria — DATOS: le gusta el café")
    expect(with.contains("le gusta el café"), "prompt: la memoria viaja al system")
    let without = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false, language: .es)
    expect(!without.contains("Memoria"), "prompt: sin memoria no hay bloque")
}
