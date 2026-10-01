import CompanionTestKit
import CompanionUI
import Testing

@Test @MainActor func headerTests() {
    testSettingsTabsSkipHermes()
    testHistoryOverlayUsesSettingsBounds()
}

@MainActor func testSettingsTabsSkipHermes() {
    expectEq(SettingsOverlayMetrics.maxSide, 560, "ajustes: max 560")
    expect(
        !SettingsTab.allCases.map(\.rawValue).contains { $0.lowercased().contains("hermes") },
        "ajustes: sin tab Hermes")
    expectEq(SettingsTab.you.symbol, "person.crop.circle", "ajustes: Tú es perfil")
    expectEq(SettingsTab.voice.symbol, "waveform", "ajustes: Voz")
}

@MainActor func testHistoryOverlayUsesSettingsBounds() {
    expectEq(
        HistoryOverlayMetrics.maxSide, SettingsOverlayMetrics.maxSide,
        "recientes: mismo tope 560 que ajustes")
    expectEq(HistoryOverlayMetrics.minWidth, 300,
             "recientes: no se estrecha más que ajustes")
}
