import CompanionUI
import Testing

@Test @MainActor func chatThreadTests() {
    testIdlePhrasesHaveNoDashes()
    testIdleCaptionFollowsMode()
    testUserBubbleRadiusIsLarge()
    testComposerPlaceholder()
}

@MainActor func testIdlePhrasesHaveNoDashes() {
    expect(!ChatIdle.phrases.isEmpty, "idle: hay frases")
    for phrase in ChatIdle.phrases {
        expect(!phrase.contains("-"), "idle: sin guiones: \(phrase)")
    }
}

@MainActor func testIdleCaptionFollowsMode() {
    expect(
        ChatIdle.caption(.voice).contains("orb"),
        "idle voz: invita a tocar el orb")
    expect(
        ChatIdle.caption(.text).contains("Escribe"),
        "idle texto: invita a escribir")
}

@MainActor func testUserBubbleRadiusIsLarge() {
    expectEq(ChatIdle.bubbleRadius, Radius.xl,
             "burbuja: cornerRadiusLarge = Radius.xl")
}

@MainActor func testComposerPlaceholder() {
    expectEq(
        ChatInputCopy.placeholder, "Escríbele a Companion",
        "composer: mismo placeholder que el prototipo")
}
