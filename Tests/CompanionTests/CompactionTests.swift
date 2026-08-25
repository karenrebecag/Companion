import CompanionCore
import Foundation
import Testing

@Test @MainActor func compactionTests() {
    testNothingIsDroppedInSilence()
    testTheFirstRequestSurvives()
    testTheNoteSaysItIsANote()
    testAShortConversationIsUntouched()
}

private func turns(_ count: Int) -> [Turn] {
    var out = [Turn(role: .user, content: "quiero un sitio para cenar")]
    for i in 1 ..< count {
        out.append(Turn(
            role: i % 2 == 0 ? .user : .assistant, content: "turno \(i)"))
    }
    return out
}

@MainActor func testNothingIsDroppedInSilence() {
    // Truncar borra el principio de la conversacion sin dejar rastro, y en una
    // sesion larga eso se siente como que se le olvidan cosas que tu recuerdas
    // haber dicho.
    let note = ConversationMemory.compaction(of: turns(30))
    expect(note != nil, "lo que sale de la ventana deja una nota")
}

@MainActor func testTheFirstRequestSurvives() {
    // Lo primero que pediste es lo que da sentido a todo lo demas.
    let note = ConversationMemory.compaction(of: turns(30))
    expect(note?.content.contains("cenar") == true,
           "la primera peticion sobrevive al recorte: \(note?.content ?? "")")
}

@MainActor func testTheNoteSaysItIsANote() {
    // Un resumen que se hace pasar por memoria completa es la misma mentira
    // que un corte silencioso.
    let note = ConversationMemory.compaction(of: turns(30))
    expectEq(note?.role, .system, "entra como nota de contexto, no como turno")
    expect(note?.content.lowercased().contains("resumen") == true
        || note?.content.lowercased().contains("summary") == true,
           "y se identifica como tal")
}

@MainActor func testAShortConversationIsUntouched() {
    expect(ConversationMemory.compaction(of: []) == nil,
           "sin nada que comprimir, no se inventa una nota")
}
