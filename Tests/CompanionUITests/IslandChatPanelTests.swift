import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import CompanionUIPro
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// The island's chat keeps the last conversations whole, hides the fences it
// draws itself, and stands on the result document's width.

@Test @MainActor func theChatKeepsTheLastConversationsWhole() {
    var messages: [ChatMessage] = []
    for index in 1...6 {
        messages.append(ChatMessage(role: .user, text: "pregunta \(index)"))
        messages.append(ChatMessage(isStatus: true, text: "Buscando"))
        messages.append(ChatMessage(role: .assistant, text: "respuesta \(index)"))
    }
    let kept = IslandChatModel.recent(messages, turns: 2)
    expectEq(kept.first?.text, "pregunta 5", "el corte cae en una pregunta: ninguna respuesta queda sin su pregunta")
    expectEq(kept.count, 6, "dos conversaciones enteras, con su línea de estado")
    expectEq(IslandChatModel.recent(Array(messages.prefix(3)), turns: 2).count, 3, "si cabe, no se corta nada")
}

@Test @MainActor func theChatDrawsItsOwnFencesUnderTheAnswer() {
    expect(IslandChatModel.fence(AIChatFence(language: "companion:choice", body: "{}", closed: true)) != nil,
           "la elección la pinta su tarjeta, no el texto")
    expect(IslandChatModel.fence(AIChatFence(language: "swift", body: "let a = 1", closed: true)) == nil,
           "otro código sigue siendo el bloque de código de Arc")
    let notch = NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 945,
        safeTop: 38, leftAuxWidth: 662, rightAuxWidth: 662))
    expectEq(IslandChrome.width(for: .chat, notch: notch), IslandChrome.docCardWidth,
             "el chat tiene el ancho de la tarjeta de documento")
    expect(IslandPopoverToggle.survives(size: .chat), "el menú de la banda sigue abierto en el chat")
}
