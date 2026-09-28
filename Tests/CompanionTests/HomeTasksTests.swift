import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 16j-2 (spec 16j §8): Incredible's Home lists the tasks by day with
// "1 hour ago", and Follow up hands the task to the island as a TASK chip.

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Mexico_City")!
    return c
}()
private let now = ISO8601DateFormatter().date(from: "2026-09-25T19:00:00-06:00")!

@Test func homeTasksTests() {
    let metas = [
        ConversationMeta(id: "a", title: "Busca México", updatedAt: now.addingTimeInterval(-3_600)),
        ConversationMeta(id: "b", title: "Toca una canción", updatedAt: now.addingTimeInterval(-7_200)),
        ConversationMeta(id: "c", title: "Ayer", updatedAt: now.addingTimeInterval(-26 * 3_600)),
        ConversationMeta(id: "d", title: "Viejo", updatedAt: now.addingTimeInterval(-9 * 86_400)),
    ]
    let sections = HomeTasks.sections(metas, now: now, calendar: calendar)
    expectEq(sections.map(\.day), [.today, .yesterday, .earlier], "home: hoy, ayer, antes")
    expectEq(sections.first?.rows.map(\.id), ["a", "b"], "home: lo más reciente arriba")
    expectEq(HomeTasks.sections([], now: now, calendar: calendar).count, 0, "home: vacío sin secciones")

    expectEq(HomeTasks.ago(now.addingTimeInterval(-20), now: now), .justNow, "hace: ahora")
    expectEq(HomeTasks.ago(now.addingTimeInterval(-5 * 60), now: now), .minutes(5), "hace: minutos")
    expectEq(HomeTasks.ago(now.addingTimeInterval(-3_600), now: now), .hours(1), "hace: 1 hora")
    expectEq(HomeTasks.ago(now.addingTimeInterval(-3 * 86_400), now: now), .days(3), "hace: días")
    expectEq(HomeTasks.ago(now.addingTimeInterval(60), now: now), .justNow, "hace: reloj adelantado")
}

@Test @MainActor func followUpTests() async {
    let idle = SessionProjection()
    let state = IslandState.from(idle, pebbleHidden: false, followUp: "Busca México")
    expectEq(state.size, .bar, "seguir: la isla abre como barra")
    expectEq(state.line, .followUp("Busca México"), "seguir: con la tarea adjunta")
    expectEq(IslandState.from(idle, pebbleHidden: false, composing: true, followUp: "x").size, .nudge,
             "seguir: escribir gana")
    var listening = SessionProjection()
    listening.kind = .listening
    expectEq(IslandState.from(listening, pebbleHidden: false, followUp: "x").line, IslandState.Line.none,
             "seguir: al hablar, la barra escucha")
    await Localized.scoped(to: .es) {
        expect(Localized.string("island.task") != "island.task", "seguir: la etiqueta está en el catálogo")
    }
}

/// A task opened from Home shows its conversation without leaving the one in
/// progress; Follow up makes it the conversation and tags the island.
@Test @MainActor func followUpContinuesTheTask() async {
    let chat = ChatViewModel(chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
                             store: MemoryConversationStore(), config: Config())
    await chat.appendAssistant("## Uno\n\nprimera")
    chat.persist()
    let first = chat.recents.first
    chat.newConversation()
    await chat.appendAssistant("segunda")
    chat.persist()
    guard let first else { return expect(false, "tareas: la primera se guardó") }
    expectEq(chat.transcript(first.id).map(\.text), ["## Uno\n\nprimera"], "detalle: su conversación")
    expectEq(chat.messages.map(\.text), ["segunda"], "detalle: sin cambiar la que está abierta")
    chat.followUp(first)
    expectEq(chat.messages.map(\.text), ["## Uno\n\nprimera"], "seguir: la tarea es la conversación")
    expectEq(chat.followUp, first.title, "seguir: la isla lleva su título")
}

/// Code review 16j-2 (HIGH): Follow up switched conversations under a turn
/// still working, which dropped it without a word.
@Test @MainActor func followUpWaitsForTheWorkInProgress() async {
    let chat = ChatViewModel(chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
                             store: MemoryConversationStore(), config: Config())
    await chat.appendAssistant("vieja")
    chat.persist()
    guard let old = chat.recents.first else { return expect(false, "tareas: la vieja se guardó") }
    chat.newConversation()
    await chat.appendAssistant("en curso")
    chat.session.send(.job(.started(goal: "ordenar Descargas")))
    expect(!chat.canFollowUp, "seguir: con un trabajo en curso, no")
    expect(!chat.followUp(old), "seguir: no cambia")
    expectEq(chat.messages.map(\.text), ["en curso"], "seguir: la conversación que trabaja se queda")
    expectEq(chat.followUp, nil, "seguir: la isla no lleva nada")
}
