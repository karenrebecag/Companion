import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// S2a of the Settings brief (ajustes-hoja-incredible, signed by Karen, KD1 and
// KD2 as recommended): the pages regroup into Incredible's map. Pages with no
// backend (Contacts, Members, Billing) stay in the brief's GAPS and are not
// drawn; the raw values the island and the menus send never change.

@Test @MainActor func theRailGroupsAreIncrediblesMap() {
    expectEq(SettingsTab.firstGroup, [.general, .voice, .vocabulary, .memory, .system],
             "arriba: General, Companion, Vocabulario, Memoria, Sistema")
    expectEq(SettingsTab.secondGroup, [.you, .privacy], "Cuenta: Cuenta y Datos y privacidad")
    expectEq(SettingsTab.allCases, SettingsTab.firstGroup + SettingsTab.secondGroup,
             "el orden de las paginas es el del rail")
}

@Test @MainActor func theRawValuesTheIslandSendsNeverChange() {
    expectEq(Set(SettingsTab.allCases.map(\.rawValue)),
             ["general", "voice", "vocabulary", "memory", "system", "you", "privacy"],
             "los ids son los de siempre, solo cambian los nombres")
}

@Test @MainActor func thePagesAreNamedAsIncredibleNamesThem() async {
    await Localized.scoped(to: .es) {
        expectEq(SettingsTab.allCases.map(\.title),
                 ["General", "Companion", "Vocabulario", "Memoria", "Sistema", "Cuenta", "Datos y privacidad"], "es")
    }
    await Localized.scoped(to: .en) {
        expectEq(SettingsTab.allCases.map(\.title),
                 ["General", "Companion", "Vocabulary", "Memory", "System", "Account", "Data and privacy"], "en")
    }
}

@Test @MainActor func oldPageIdsStillOpenTheirPage() {
    for tab in SettingsTab.allCases {
        expectEq(SettingsTab.resolve(tab.rawValue), tab, "\(tab): su propio id")
    }
    let aliases: [String: SettingsTab] = [
        "preferences": .general, "tools": .general, "microphone": .general, "updates": .general,
        "shortcuts": .general, "incredible": .voice, "companion": .voice, "personalization": .you,
        "account": .you, "dictionary": .vocabulary, "permissions": .privacy, "data": .privacy,
    ]
    for (old, tab) in aliases {
        expectEq(SettingsTab.resolve(old), tab, "\(old) abre \(tab)")
    }
    for gap in ["members", "organization", "usage", "billing", "contacts", "nada"] {
        expect(SettingsTab.resolve(gap) == nil, "\(gap): sin pagina en Companion, no abre ninguna")
    }
}

@Test @MainActor func soundAndGlowMovedToSystem() {
    func tab(_ key: String) -> SettingsTab? {
        SettingsInventory.options.first { $0.titleKey == key }?.tab
    }
    expectEq(tab("settings.muteWhileTalking"), .system, "Silenciar al hablar en Sistema > Sonido")
    expectEq(tab("settings.muteEffects"), .system, "Silenciar efectos en Sistema > Sonido")
    expectEq(tab("settings.screenGlow"), .system, "el brillo en Sistema > App (KD1)")
    expectEq(tab("settings.app.appearance"), .you, "apariencia en Cuenta (KD2)")
    expectEq(tab("settings.app.textSize"), .you, "tamano de texto en Cuenta (KD2)")
    expect(tab("settings.sounds") == nil, "Sonidos se muestra invertido como Silenciar efectos")
    expectEq(SettingsInventory.panels.first { $0.titleKey == "settings.welcome.again" }?.tab, .you,
             "repetir la bienvenida en Cuenta, como Replay the tour")
}

@Test @MainActor func systemSectionsFollowIncrediblesOrder() async {
    expectEq(SettingsSystemSection.allCases, [.app, .sound, .about, .data],
             "App, Sonido, Acerca de, Datos: una sola seccion de datos")
    await Localized.scoped(to: .es) {
        expectEq(SettingsSystemSection.allCases.map(\.label),
                 ["App", "Sonido", "Acerca de", "Datos"], "es")
    }
    await Localized.scoped(to: .en) {
        expectEq(SettingsSystemSection.allCases.map(\.label),
                 ["App", "Sound", "About", "Data"], "en")
    }
    expectEq(SettingsSystemSection.sound.rows, ["settings.muteWhileTalking", "settings.muteEffects"],
             "Sonido: silenciar al hablar y silenciar efectos, en ese orden")
    expectEq(SettingsSystemSection.app.rows, ["settings.screenGlow"], "App: el brillo")
    expectEq(SettingsSystemSection.data.rows, [SettingsInventory.clearHistoryRowID, "settings.app.attachments"],
             "Datos: borrar historial (con su rowId para la busqueda) y luego los adjuntos")
}

// The reset row lives in another branch (PR #228, ResetPermissionsRow). A row that
// erases nothing would be a lie, so the zone stays out until that port lands.
// Whoever mounts #228 flips this test on purpose: add `.danger`, its row and its search entry.
@Test @MainActor func dangerZoneStaysOutUntilTheResetPortLands() async {
    expectEq(SettingsSystemSection.allCases.count, 4, "cuatro secciones, ninguna de peligro")
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            let entries = SettingsInventory.searchEntries
            expect(!entries.contains { $0.id.contains("resetPermissions") }, "\(language): no hay fila de reinicio")
            for word in ["peligro", "danger", "reset", "reiniciar"] {
                let hits = SettingsSearch.match(word, in: entries).map(\.id)
                expect(!hits.contains { $0.contains("resetPermissions") }, "\(language): «\(word)» no halla reinicio")
            }
            expect(SettingsSearch.match("peligro", in: entries).isEmpty, "\(language): «peligro» no halla nada")
        }
    }
}

// Code and QA review S2a: the page drew its own rows, so the tested order could drift from it.
@Test @MainActor func systemSectionsHoldExactlyTheSystemInventory() {
    let inventory = SettingsInventory.options.filter { $0.tab == .system }.map(\.titleKey)
        + SettingsInventory.panels.filter { $0.tab == .system }.map { $0.rowId ?? $0.titleKey }
    expectEq(Set(SettingsSystemSection.allCases.flatMap(\.rows)), Set(inventory),
             "las secciones de Sistema tienen todo su inventario y nada mas")
    for section in SettingsSystemSection.allCases {
        for key in section.rows {
            expect(SettingsSystemPage.draws(key), "\(section): la pagina sabe pintar \(key)")
        }
    }
    expect(!SettingsSystemPage.draws("settings.resetPermissions"), "una clave sin fila no se pinta")
}

// QA review S2a: only the helpers were tested, not the switch the page binds.
@Test @MainActor func theMuteEffectsSwitchWritesTheInverse() {
    var sounds = true
    let effects = SettingsSystemSection.effectsMuted(Binding(get: { sounds }, set: { sounds = $0 }))
    expect(!effects.wrappedValue, "sonidos encendidos: el interruptor de silenciar efectos esta apagado")
    effects.wrappedValue = true
    expect(!sounds, "encender silenciar efectos apaga los sonidos")
    expect(effects.wrappedValue, "y el interruptor lo refleja")
    effects.wrappedValue = false
    expect(sounds, "apagarlo los vuelve a encender")
}

// The passive wait already has a preference. A settings row with no control
// would be hollow, so the Companion page does not grow an empty line for it.
// local reference; brief ajustes-hoja-incredible S2
@Test @MainActor func passiveKeepsItsPreferenceAndPaintsNoHollowRow() {
    let store = UserDefaults(suiteName: "passive-\(UUID().uuidString)")!
    expectEq(PassivePreference.seconds(in: store), SessionMachine.defaultPassiveAfter,
             "el modo pasivo sigue en su preferencia")
    store.set(7, forKey: PassivePreference.key)
    expectEq(PassivePreference.seconds(in: store), 7, "y la lee por su clave")
    let keys = SettingsInventory.options.map(\.titleKey) + SettingsInventory.panels.map(\.titleKey)
    expect(!keys.contains { $0.contains("passive") }, "no hay una fila hueca de modo pasivo")
}

// Account and privacy rows that exist only for an internal team stay out.
@Test @MainActor func internalTeamRowsAreNotInTheInventory() {
    let keys = SettingsInventory.options.map(\.titleKey) + SettingsInventory.panels.map(\.titleKey)
    expect(!keys.contains { $0.split(separator: ".").contains("internal") }, "ninguna fila de equipo interno")
    for banned in ["settings.onboarding.reset", "settings.onboarding.hardReset", "settings.team"] {
        expect(!keys.contains(banned), "\(banned) no se replica")
    }
}

@Test @MainActor func muteEffectsIsTheInverseOfSounds() {
    expect(SettingsSystemSection.effectsMuted(soundsOn: false), "sonidos apagados: efectos silenciados")
    expect(!SettingsSystemSection.effectsMuted(soundsOn: true), "sonidos encendidos: efectos sin silenciar")
    expect(SettingsSystemSection.soundsOn(effectsMuted: false), "quitar el silencio enciende los sonidos")
    expect(!SettingsSystemSection.soundsOn(effectsMuted: true), "silenciar apaga los sonidos")
}
