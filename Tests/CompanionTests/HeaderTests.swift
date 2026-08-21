import CompanionUI
import Testing

@Test @MainActor func headerTests() {
    testTopClearanceClearsTrafficLights()
    testModeHasVoiceAndText()
    testAvatarMatchesHeroIcon()
    testSettingsTabsSkipHermes()
}

@MainActor func testTopClearanceClearsTrafficLights() {
    expectEq(HeaderMetrics.topClearance, Space.x1 * 10,
             "header: 10 grid bajo titlebar invisible")
}

@MainActor func testModeHasVoiceAndText() {
    expectEq(InteractionMode.allCases, [.voice, .text],
             "header: voz y texto")
}

@MainActor func testAvatarMatchesHeroIcon() {
    expectEq(HeaderMetrics.avatar, IconSize.hero,
             "header: avatar 7 grid")
}

@MainActor func testSettingsTabsSkipHermes() {
    expectEq(SettingsOverlayMetrics.maxSide, 560, "ajustes: max 560")
    expect(
        !SettingsTab.allCases.map(\.rawValue).contains { $0.lowercased().contains("hermes") },
        "ajustes: sin tab Hermes")
    expectEq(SettingsTab.allCases.count, 5, "ajustes: panes existentes, no MCP")
}
