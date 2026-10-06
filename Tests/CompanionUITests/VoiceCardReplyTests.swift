import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

/// Karen 2026-10-06: show_card ran, but the spoken reply landed as a second
/// message and the island, which reads the latest reply, closed without it.
@Test @MainActor func aVoiceReplyJoinsTheCardItsTurnShowed() async {
    let model = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: Config())
    await model.appendUser("muéstrame las ventas")
    let chart = ChartBlock(kind: .bar, labels: ["Ene", "Feb"], series: [.init(values: [120, 150])])
    model.receiveJobEvent(JobEvent.card(Card(payload: .chart(chart), source: .model)), from: JobID?.none)
    await model.appendAssistant("Aquí tienes la gráfica.")
    let last = model.messages.last
    expectEq(model.messages.count, 2, "la respuesta se une a la tarjeta, no queda aparte")
    expectEq(last?.text, "Aquí tienes la gráfica.", "el texto hablado queda en el mensaje")
    expect(last?.card != nil, "la tarjeta sigue en el mensaje que la isla lee")
    await model.appendAssistant("Otra cosa.")
    expectEq(model.messages.count, 3, "una respuesta sin tarjeta previa es su propio mensaje")
}
