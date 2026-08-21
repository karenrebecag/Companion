import CompanionUI
import Testing

@Test @MainActor func headerTests() {
    testTopClearanceClearsTrafficLights()
    testModeHasVoiceAndText()
    testAvatarMatchesHeroIcon()
    testSettingsTabsSkipHermes()
    testHistoryOverlayUsesSettingsBounds()
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
    expectEq(SettingsTab.allCases, [.you, .voice, .app],
             "ajustes: Tú, Voz, App — no MCP ni atajos sueltos")
    expectEq(SettingsTab.you.symbol, "person.crop.circle", "ajustes: Tú es perfil")
    expectEq(SettingsTab.voice.symbol, "waveform", "ajustes: Voz")
    expectEq(SettingsTab.app.symbol, "square.grid.2x2", "ajustes: App")
}

@MainActor func testHistoryOverlayUsesSettingsBounds() {
    expectEq(
        HistoryOverlayMetrics.maxSide, SettingsOverlayMetrics.maxSide,
        "recientes: mismo tope 560 que ajustes")
    expectEq(HistoryOverlayMetrics.minWidth, 300,
             "recientes: no se estrecha más que ajustes")
}
