import Testing
@testable import CompanionUI

/// The settings keys the Settings page showed before the Arc Pro rewrite.
/// The rewrite moved the layout, not the inventory: a key that disappears
/// here is a setting or a row someone can no longer reach.
@Suite("SettingsInventoryKeys")
@MainActor
struct SettingsInventoryKeysTests {
    static let shownBeforeRewrite = [
        "settings.app.talk.hold",
        "settings.app.talk.hold.subtitle",
        "settings.app.talk.dictationKey",
        "settings.app.talk.dictationKey.subtitle",
        "settings.microphone",
        "settings.microphone.subtitle",
        "settings.app.language",
        "settings.app.language.subtitle",
        "settings.sounds",
        "settings.sounds.subtitle",
        "settings.muteWhileTalking",
        "settings.muteWhileTalking.subtitle",
        "settings.screenGlow",
        "settings.screenGlow.subtitle",
        "settings.voice.blurb",
        "settings.vocabulary",
        "settings.vocabulary.subtitle",
        "settings.you.name",
        "settings.you.photo",
        "settings.you.photo.subtitle",
        "settings.you.city",
        "settings.you.city.subtitle",
        "settings.you.about",
        "settings.you.instructions",
        "settings.app.appearance",
        "settings.app.textSize",
        "settings.app.textSize.subtitle",
        "settings.context.screen",
        "settings.context.screen.subtitle",
        "settings.context.documents",
        "settings.context.documents.subtitle",
        "settings.context.location",
        "settings.context.location.subtitle",
        "settings.privacy.lendHands",
        "settings.privacy.lendHands.subtitle",
        "settings.memory.header",
        "settings.permissions",
        "settings.keys.header",
        "settings.browser.header",
        "settings.app.version",
        "settings.app.attachments",
        "settings.welcome.again",
        "settings.history.row",
        "settings.tab.general",
        "settings.tab.voice",
        "settings.tab.vocabulary",
        "settings.tab.memory",
        "settings.tab.you",
        "settings.tab.privacy",
        "settings.tab.system",
    ]

    @Test("the inventory keeps every key the settings pages showed before the rewrite")
    func keepsEveryKey() {
        let inventory = Set(SettingsInventory.visibleKeys + SettingsInventory.panels.compactMap(\.rowId))
        let missing = Self.shownBeforeRewrite.filter { !inventory.contains($0) }
        #expect(missing.isEmpty, "keys gone from the inventory: \(missing)")
    }

    @Test("every option and panel row is a palette item that names its page")
    func everyRowIsAPaletteItem() {
        let items = SettingsInventory.commandItems
        let rows = SettingsInventory.options.map { ($0.titleKey, $0.tab) }
            + SettingsInventory.panels.map { ($0.rowId ?? $0.titleKey, $0.tab) }
        for (id, tab) in rows {
            let item = items.first { $0.id == id }
            #expect(item?.sectionID == tab.rawValue, "\(id) is a palette item on \(tab)")
        }
    }
}
