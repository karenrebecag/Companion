import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// The written chat (`.chat`): the panel she types in, once there is a
// conversation, is the result document's width, and a turn sent from it
// plays there instead of folding into the bar.

private func processing(_ phase: SessionPhase) -> SessionProjection {
    var p = SessionProjection()
    p.kind = .processing(phase)
    p.presence = .active
    return p
}

@Test func theTypedPanelWithAConversationIsTheChat() {
    let idle = SessionProjection()
    expectEq(IslandState.from(idle, pebbleHidden: false, composing: true, conversation: true).size, .chat,
             "con conversación, el panel escrito es el chat")
    expectEq(IslandState.from(idle, pebbleHidden: false, composing: true).size, .nudge,
             "sin conversación sigue siendo la barra de Incredible")
    var hover = SessionProjection()
    hover.kind = .hover
    expectEq(IslandState.from(hover, pebbleHidden: false, conversation: true).size, .chat,
             "al pasar el puntero se ve el mismo chat")
    for phase: SessionPhase in [.pending, .thinking, .toolExecuting, .speaking, .subAgentRunning, .completed] {
        let typed = IslandState.from(processing(phase), pebbleHidden: false, composing: true, conversation: true)
        expectEq(typed.size, .chat, "\(phase): el turno enviado desde el chat se ve en el chat")
        let away = IslandState.from(processing(phase), pebbleHidden: false, conversation: true)
        expect(away.size != .chat, "\(phase): sin el campo abierto, el turno usa su forma de siempre")
    }
    var dictating = processing(.pending)
    dictating.dictation = "Notas"
    expect(IslandState.from(dictating, pebbleHidden: false, composing: true, conversation: true).size != .chat,
           "un dictado es de otra app: no entra al chat")
    var asking = processing(.toolExecuting)
    asking.approvalQueue = [ApprovalRequest(requestId: "r", toolName: "enviar", summary: "Enviar", inputJSON: "{}")]
    expectEq(IslandState.from(asking, pebbleHidden: false, composing: true, conversation: true).size, .card,
             "la hoja de aprobación sigue mandando sobre el chat")
}
