import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// QA en vivo 2026-10-16: «recuerda que prefiero respuestas cortas» no guardo
// nada y la conversacion siguiente contesto «no tengo nada guardado».

private func store() -> (FileMemoryStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("remember-\(UUID().uuidString)")
    return (FileMemoryStore(root: dir), dir)
}

@Test func rememberSavesAndTheNextConversationReadsIt() async {
    let (memory, dir) = store()
    defer { try? FileManager.default.removeItem(at: dir) }
    let runner = MemoryToolRunner(notes: memory)
    expect(runner.handles("remember"), "remember: lo atiende")
    let outcome = await runner.execute(name: "remember", argumentsJSON: #"{"fact":"prefiere respuestas cortas"}"#)
    expect(outcome.ok, "remember: guarda — \(outcome.output)")

    // Una conversacion nueva abre otro store sobre la misma carpeta.
    let next = FileMemoryStore(root: dir)
    let prompt = MemoryPrompt.inject(next.load(), language: .es)
    expect(prompt.contains("prefiere respuestas cortas"), "remember: el dato entra al prompt de la conversacion nueva")
    expectEq(next.entries().count, 1, "remember: Ajustes > Memoria lo lista para olvidarlo")
}

@Test func rememberKeepsMoreThanFiveFacts() async {
    let (memory, dir) = store()
    defer { try? FileManager.default.removeItem(at: dir) }
    let runner = MemoryToolRunner(notes: memory)
    for index in 1...8 {
        _ = await runner.execute(name: "remember", argumentsJSON: #"{"fact":"dato \#(index)"}"#)
    }
    let kept = memory.load().notes.joined(separator: "\n")
    expect(kept.contains("dato 1") && kept.contains("dato 8"), "remember: el primero no se cae al sexto")
}

@Test func rememberRefusesASecretInsteadOfSavingIt() async {
    let (memory, dir) = store()
    defer { try? FileManager.default.removeItem(at: dir) }
    let runner = MemoryToolRunner(notes: memory)
    let outcome = await runner.execute(
        name: "remember", argumentsJSON: #"{"fact":"mi clave es sk-abcdefghijklmnopqrstuvwxyz123456"}"#)
    expect(!outcome.ok, "secreto: se rechaza")
    expect(memory.load().isEmpty && memory.entries().isEmpty, "secreto: no queda nada en disco")
    let blank = await runner.execute(name: "remember", argumentsJSON: #"{"fact":"  "}"#)
    expect(!blank.ok, "remember: un dato vacio no se guarda")
}

// QA 606 review: a fact that names a strong label is refused even when the
// redaction would not change it, so the secret never reaches the notes.
@Test func memoryRefusesAFactWithAStrongLabel() {
    if case .success = MemoryTool.accepted("mi contraseña: secreto") {
        expect(false, "memoria: una contraseña no se guarda")
    }
    if case .success = MemoryTool.accepted("prefiero respuestas cortas") {
    } else {
        expect(false, "memoria: un dato normal sí se guarda")
    }
}
