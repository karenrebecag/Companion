import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 16j-1: the window keeps what the island leaves behind, not the
// machinery. Incredible's saved conversation holds only the user's turns
// and its replies; status lines ("Entendí…", "Encargo…") live in the island.

@Test @MainActor func mainWindowCleanupTests() {
    let rows = [
        ChatMessage(role: .user, text: "busca México"),
        ChatMessage(isStatus: true, text: "Entendí: «buscar». Dime para si no es eso."),
        ChatMessage(isStatus: true, text: "Encargo: buscar · 1 búsqueda"),
        ChatMessage(role: .assistant, text: "## México\n\npuntos clave"),
    ]
    let shown = ThreadView.visible(rows)
    expectEq(shown.map(\.text), ["busca México", "## México\n\npuntos clave"],
             "hilo: solo tus turnos y las respuestas")
}
