import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 16m-7: what a mention does to a turn. Only what she picked travels,
// only while its @name is still in the words, and never to disk.

private let ana = MentionCandidate(id: "c1", kind: .contact, name: "Ana García")!
private let email = MentionChannel(kind: .email, label: "work", value: "ana@example.com")!

@Test @MainActor func mentionTurnContextTests() async {
    let provider = FakeChatProvider(replies: [.success([.text("a")]), .success([.text("b")]), .success([.text("c")])])
    let store = MemoryConversationStore()
    let vm = primed(chat: provider, store: store)
    vm.addMention(Mention(candidate: ana))
    vm.draft = "escríbele a @Ana García"
    vm.send()
    await pumpUntil("16m-7: t1") { !vm.busy }
    let first = provider.histories[0].last { $0.role == .user }?.content ?? ""
    expect(first.contains("Ana García") && first.contains(MentionContext.render([Mention(candidate: ana)], language: vm.config.language)),
           "16m-7: el turno lleva el bloque de la mención")
    expect(!first.contains("example.com"), "16m-7: sin medio de contacto que ella no eligió")
    expectEq(vm.pendingMentions.count, 0, "16m-7: enviar consume las menciones pendientes")
    expectEq(vm.messages.first { $0.role == .user }?.text, "escríbele a @Ana García", "16m-7: el hilo muestra sus palabras, sin bloque")

    vm.draft = "y luego"
    vm.send()
    await pumpUntil("16m-7: t2") { !vm.busy }
    let again = provider.histories[1].filter { $0.role == .user }.map(\.content)
    expect(again[0].contains("Ana García") && !again[1].contains("Mentions") && !again[1].contains("Menciones"),
           "16m-7: la mención sigue en el hilo en memoria y no se repite en el turno siguiente")

    let memory = await vm.memoryTurns()
    expect(!memory.contains { $0.content.contains("Menciones") || $0.content.contains("Mentions") },
           "16m-7: la memoria de sesión guarda solo las palabras")
    let saved = try? store.load(vm.conversationId)
    let disk = saved?.messages.map(\.text).joined(separator: "\n") ?? ""
    expect(!disk.contains("Menciones") && !disk.contains("Mentions"), "16m-7: nada del bloque llega al disco")
}

@Test @MainActor func mentionChannelAndDeletionTests() async {
    let provider = FakeChatProvider(replies: [.success([.text("a")]), .success([.text("b")])])
    let vm = primed(chat: provider)
    vm.addMention(Mention(candidate: ana, channel: email))
    vm.draft = "borré la mención de Ana"
    vm.send()
    await pumpUntil("16m-7: sin @") { !vm.busy }
    let sent = provider.histories[0].last { $0.role == .user }?.content ?? ""
    expect(!sent.contains("example.com") && !sent.contains("Ana García"),
           "16m-7: si ella borró el @nombre, ni el correo ni el nombre viajan")

    vm.addMention(Mention(candidate: ana, channel: email))
    vm.draft = "manda a @Ana García"
    vm.send()
    await pumpUntil("16m-7: con @") { !vm.busy }
    let with = provider.histories[1].last { $0.role == .user }?.content ?? ""
    expectEq(with.components(separatedBy: "ana@example.com").count - 1, 1, "16m-7: el medio elegido viaja una vez")
}

@Test @MainActor func mentionQueueChoiceAndResetTests() async {
    let provider = FakeChatProvider(replies: [.success([.text("a")]), .success([.text("b")])])
    let vm = primed(chat: provider)
    vm.draft = "uno"
    vm.send()
    vm.addMention(Mention(candidate: ana))
    vm.draft = "dos @Ana García"
    vm.send()
    await pumpUntil("16m-7: cola") { !vm.busy && vm.queued.isEmpty }
    let second = provider.histories[1].last { $0.role == .user }?.content ?? ""
    expect(second.contains("Ana García") && second.count > "dos @Ana García".count, "16m-7: la cola conserva la mención")

    let pick = primed(chat: FakeChatProvider(replies: [.success([.text("a")])]))
    pick.addMention(Mention(candidate: ana))
    pick.choose("Rápido")
    expectEq(pick.pendingMentions.count, 1, "16m-7: una elección de tarjeta no se lleva las menciones")
    expectEq(pick.messages.first?.mentions.count, 0, "16m-7: ni las lleva")

    pick.newConversation()
    expectEq(pick.pendingMentions.count, 0, "16m-7: conversación nueva, sin menciones colgadas")
    pick.addMention(Mention(candidate: ana))
    pick.changeKey()
    expectEq(pick.pendingMentions.count, 0, "16m-7: cambiar la clave también las suelta")
}

@Test @MainActor func mentionWithSensedContextTests() async {
    let provider = FakeChatProvider(replies: [.success([.text("a")])])
    let vm = primed(chat: provider, sensor: FakeContextSensor(TurnContext(source: .typed, focusedApp: "Safari")))
    vm.addMention(Mention(candidate: ana))
    vm.draft = "hola @Ana García"
    vm.send()
    await pumpUntil("16m-7: sensado") { !vm.busy }
    let sent = provider.histories[0].last { $0.role == .user }?.content ?? ""
    expect(sent.contains("Safari") && sent.contains(MentionContext.render([Mention(candidate: ana)], language: vm.config.language))
           && sent.hasSuffix("hola @Ana García"),
           "16m-7: con contexto sensado la mención también llega")
}

@Test @MainActor func mentionPendingFollowsTheDraftTests() async {
    let provider = FakeChatProvider(replies: [.success([.text("a")])])
    let vm = primed(chat: provider)
    vm.addMention(Mention(candidate: ana, channel: email))
    vm.syncMentions(with: "hola @Ana García")
    expectEq(vm.pendingMentions.count, 1, "16m-7 review: mientras el @nombre siga en el campo, la mención sigue")
    vm.syncMentions(with: "hola ")
    expectEq(vm.pendingMentions.count, 0, "16m-7 review: al borrar el @nombre se va con su medio de contacto")
    vm.syncMentions(with: "hola @Ana García")
    expectEq(vm.pendingMentions.count, 0, "16m-7 review: escribirlo a mano después no la resucita")
    vm.draft = "hola @Ana García"
    vm.send()
    await pumpUntil("16m-7 review: turno") { !vm.busy }
    let sent = provider.histories[0].last { $0.role == .user }?.content ?? ""
    expect(!sent.contains("example.com"), "16m-7 review: lo tecleado a mano no hereda el medio de una elección borrada")
    vm.addMention(Mention(candidate: ana))
    vm.syncMentions(with: "")
    expectEq(vm.pendingMentions.count, 0, "16m-7 review: un campo vacío las suelta todas")
}
