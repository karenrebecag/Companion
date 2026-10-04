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
             "App, Sonido, Acerca de, Datos; Zona de peligro llega con su fila")
    await Localized.scoped(to: .es) {
        expectEq(SettingsSystemSection.allCases.map(\.label), ["App", "Sonido", "Acerca de", "Datos"], "es")
    }
    await Localized.scoped(to: .en) {
        expectEq(SettingsSystemSection.allCases.map(\.label), ["App", "Sound", "About", "Data"], "en")
    }
    expectEq(SettingsSystemSection.sound.rows, ["settings.muteWhileTalking", "settings.muteEffects"],
             "Sonido: silenciar al hablar y silenciar efectos, en ese orden")
    expectEq(SettingsSystemSection.app.rows, ["settings.screenGlow"], "App: el brillo")
}

// Code and QA review S2a: the page drew its own rows, so the tested order could drift from it.
@Test @MainActor func systemSectionsHoldExactlyTheSystemInventory() {
    let inventory = SettingsInventory.options.filter { $0.tab == .system }.map(\.titleKey)
        + SettingsInventory.panels.filter { $0.tab == .system }.map(\.titleKey)
    expectEq(Set(SettingsSystemSection.allCases.flatMap(\.rows)), Set(inventory),
             "las secciones de Sistema tienen todo su inventario y nada mas")
    for section in SettingsSystemSection.allCases {
        for key in section.rows {
            expect(SettingsSystemPage.draws(key), "\(section): la pagina sabe pintar \(key)")
        }
    }
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

@Test @MainActor func muteEffectsIsTheInverseOfSounds() {
    expect(SettingsSystemSection.effectsMuted(soundsOn: false), "sonidos apagados: efectos silenciados")
    expect(!SettingsSystemSection.effectsMuted(soundsOn: true), "sonidos encendidos: efectos sin silenciar")
    expect(SettingsSystemSection.soundsOn(effectsMuted: false), "quitar el silencio enciende los sonidos")
    expect(!SettingsSystemSection.soundsOn(effectsMuted: true), "silenciar apaga los sonidos")
}
