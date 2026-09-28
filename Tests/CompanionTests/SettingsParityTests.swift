import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 16d (spec 16c §2): Settings with at most fifteen options (16g moved
// the tabs to a sidebar: SettingsPagesTests), no technical labels, every menu through the catalog, a menu bar
// item with five entries, and the ear's vocabulary editable.

@Test @MainActor func settingsParityTests() async {
    testAtMostFifteenOptions()
    await testNoVisibleLabelIsJargon()
    await testMenusFollowTheLanguage()
    await testTheMenuBarItemHasFiveEntries()
    testVocabularyIsParsedFromWhatTheUserTyped()
}

private let forbidden = [
    "proveedor", "provider", "modelo", "model", "tts", "vad", "ejecutor", "executor",
    "endpoint", "token", "latencia", "latency", "websocket", "realtime", "api",
]

private func words(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter }.map(String.init)
}

@MainActor func testAtMostFifteenOptions() {
    let options = SettingsInventory.options
    // Wave 17: sixteen now — "Prestar las manos a otros agentes" (spec §3
    // "Ajuste") is the one addition since the fifteen-option line was drawn.
    expect(options.count <= 16, "ajustes: \(options.count) opciones, máximo 16")
    expectEq(Set(options.map(\.titleKey)).count, options.count, "ajustes: sin opciones repetidas")
    for gone in ["settings.voice.speed", "settings.voice.turnEnd", "settings.voice.tone",
                 "settings.voice.aec", "settings.voice.eagerness", "settings.voice.patience",
                 "settings.app.decision.local", "settings.context.clipboard", "settings.app.typeface",
                 "settings.app.accent"] {
        expect(!options.contains { $0.titleKey == gone }, "ajustes: \(gone) vive en Config, no en la UI")
    }
}

@MainActor func testNoVisibleLabelIsJargon() async {
    let welcome = ["welcome.cover.title", "welcome.cover.body", "welcome.hello.body", "welcome.keys.body",
                   "welcome.keys.local", "welcome.keys.cerebras", "welcome.keys.elevenLabs",
                   "welcome.permissions.body", "welcome.holdKey.body", "welcome.yourTurn.body"]
    let failures = ["micDenied", "micUnavailable", "micSilent", "notHeard", "speechEngine", "speechDenied",
                    "accessibilityDenied", "noProviders", "quotaExceeded", "sessionDropped",
                    "networkUnavailable"].map { "voice.fail." + $0 }
    let island = ["island.ask", "island.clear.ask", "island.action.keys", "island.couldntHear"] + failures
    let keys = SettingsInventory.visibleKeys + IslandMenuItem.allCases.map { "island.menu." + $0.rawValue }
        + welcome + island
        + ["microphone", "accessibility", "screenRecording", "speech"].flatMap {
            ["permission.\($0).title", "permission.\($0).body"]
        }
        + ["settings.keys.blurb", "settings.voice.blurb"]
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            var texts = keys.map { Localized.string($0) }
            texts += MenuPlan.build(shortcuts: .defaults).flatMap { [$0.title] + $0.items.map(\.title) }
            texts += StatusMenuPlan.items.map(\.title)
            for text in texts {
                let bad = words(text).filter(forbidden.contains)
                expect(bad.isEmpty, "\(language): «\(text)» dice \(bad)")
            }
            for key in keys {
                expect(Localized.string(key) != key, "\(language): \(key) está en el catálogo")
            }
        }
    }
}

@MainActor func testMenusFollowTheLanguage() async {
    await Localized.scoped(to: .en) {
        let en = MenuPlan.build(shortcuts: .defaults).flatMap { $0.items.map(\.title) }
        expect(en.contains("Settings…"), "menú en: Settings…")
        expect(en.contains("Quit Companion"), "menú en: Quit Companion")
        expect(!en.contains("Ajustes…"), "menú en: sin español")
    }
    await Localized.scoped(to: .es) {
        let es = MenuPlan.build(shortcuts: .defaults).flatMap { $0.items.map(\.title) }
        expect(es.contains("Ajustes…"), "menú es: Ajustes…")
        expect(es.contains("Salir de Companion"), "menú es: Salir de Companion")
    }
}

@MainActor func testTheMenuBarItemHasFiveEntries() async {
    await Localized.scoped(to: .es) {
        // Wave 17: `stopHands` ("Detener manos") joins the five, ahead of the
        // separator ahead of `quit` — spec §4.
        expectEq(StatusMenuPlan.items.map(\.command),
                 [.cancel, .show, .settings, .checkUpdates, .stopHands, .quit],
                 "barra: las cinco de la spec y Detener manos, en orden")
        expectEq(StatusMenuPlan.items.first?.keyEquivalent, "\u{1b}", "barra: cancelar con Esc")
        expectEq(StatusMenuPlan.items.map(\.title),
                 ["Cancelar acción", "Mostrar Companion", "Ajustes…", "Buscar actualización…",
                  "Detener manos", "Salir"],
                 "barra: sus nombres")
    }
}

@MainActor func testVocabularyIsParsedFromWhatTheUserTyped() {
    expectEq(Vocabulary.parse("Cerebras, ElevenLabs\nAtom,  cerebras , \n\n"),
             ["Cerebras", "ElevenLabs", "Atom"], "vocabulario: comas o líneas, sin repetidas")
    let many = (1...80).map { "palabra\($0)" }.joined(separator: ",")
    expectEq(Vocabulary.parse(many).count, Vocabulary.maxWords, "vocabulario: con tope")
    expect(Vocabulary.parse(String(repeating: "x", count: 200)).isEmpty, "vocabulario: una palabra absurda no entra")
}
