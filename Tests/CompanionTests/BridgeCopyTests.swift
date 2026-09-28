import CompanionCore
import Foundation
import Testing

@Test @MainActor func bridgeCopyTests() {
    pinLanguage(.en)
    testCopyConsistency()
    testCopyLanguageVariance()
    testChipContainsCorrectLabel()
}

private func testCopyConsistency() {
    // Every string must be non-empty in both languages
    let en_title = BridgeCopy.sheetTitle(.en)
    let es_title = BridgeCopy.sheetTitle(.es)
    expect(!en_title.isEmpty, "sheet title en: non-empty")
    expect(!es_title.isEmpty, "sheet title es: non-empty")

    let en_detail = BridgeCopy.sheetDetail(.en)
    let es_detail = BridgeCopy.sheetDetail(.es)
    expect(!en_detail.isEmpty, "sheet detail en: non-empty")
    expect(!es_detail.isEmpty, "sheet detail es: non-empty")

    let en_allow1h = BridgeCopy.allowOneHour(.en)
    let es_allow1h = BridgeCopy.allowOneHour(.es)
    expect(!en_allow1h.isEmpty, "allow 1h en: non-empty")
    expect(!es_allow1h.isEmpty, "allow 1h es: non-empty")

    let en_allowConn = BridgeCopy.allowThisConnection(.en)
    let es_allowConn = BridgeCopy.allowThisConnection(.es)
    expect(!en_allowConn.isEmpty, "allow connection en: non-empty")
    expect(!es_allowConn.isEmpty, "allow connection es: non-empty")

    let en_deny = BridgeCopy.deny(.en)
    let es_deny = BridgeCopy.deny(.es)
    expect(!en_deny.isEmpty, "deny en: non-empty")
    expect(!es_deny.isEmpty, "deny es: non-empty")

    let en_chip = BridgeCopy.chipLabel(.en)
    let es_chip = BridgeCopy.chipLabel(.es)
    expect(!en_chip.isEmpty, "chip en: non-empty")
    expect(!es_chip.isEmpty, "chip es: non-empty")

    let en_stop = BridgeCopy.stopHands(.en)
    let es_stop = BridgeCopy.stopHands(.es)
    expect(!en_stop.isEmpty, "stop en: non-empty")
    expect(!es_stop.isEmpty, "stop es: non-empty")

    let en_settingTitle = BridgeCopy.settingTitle(.en)
    let es_settingTitle = BridgeCopy.settingTitle(.es)
    expect(!en_settingTitle.isEmpty, "setting title en: non-empty")
    expect(!es_settingTitle.isEmpty, "setting title es: non-empty")

    let en_settingDesc = BridgeCopy.settingDescription(.en)
    let es_settingDesc = BridgeCopy.settingDescription(.es)
    expect(!en_settingDesc.isEmpty, "setting desc en: non-empty")
    expect(!es_settingDesc.isEmpty, "setting desc es: non-empty")

    let en_suffix = BridgeCopy.toolDataSuffix(.en)
    let es_suffix = BridgeCopy.toolDataSuffix(.es)
    expect(!en_suffix.isEmpty, "tool suffix en: non-empty")
    expect(!es_suffix.isEmpty, "tool suffix es: non-empty")
}

private func testCopyLanguageVariance() {
    // Ensure English and Spanish are actually different (not translated copies)
    let en_title = BridgeCopy.sheetTitle(.en)
    let es_title = BridgeCopy.sheetTitle(.es)
    expect(en_title != es_title, "sheet title: en != es")

    let en_detail = BridgeCopy.sheetDetail(.en)
    let es_detail = BridgeCopy.sheetDetail(.es)
    expect(en_detail != es_detail, "sheet detail: en != es")

    let en_allow1h = BridgeCopy.allowOneHour(.en)
    let es_allow1h = BridgeCopy.allowOneHour(.es)
    expect(en_allow1h != es_allow1h, "allow 1h: en != es")

    let en_allowConn = BridgeCopy.allowThisConnection(.en)
    let es_allowConn = BridgeCopy.allowThisConnection(.es)
    expect(en_allowConn != es_allowConn, "allow connection: en != es")

    let en_chip = BridgeCopy.chipLabel(.en)
    let es_chip = BridgeCopy.chipLabel(.es)
    expect(en_chip != es_chip, "chip: en != es")

    let en_stop = BridgeCopy.stopHands(.en)
    let es_stop = BridgeCopy.stopHands(.es)
    expect(en_stop != es_stop, "stop: en != es")

    let en_settingTitle = BridgeCopy.settingTitle(.en)
    let es_settingTitle = BridgeCopy.settingTitle(.es)
    expect(en_settingTitle != es_settingTitle, "setting title: en != es")

    let en_settingDesc = BridgeCopy.settingDescription(.en)
    let es_settingDesc = BridgeCopy.settingDescription(.es)
    expect(en_settingDesc != es_settingDesc, "setting desc: en != es")

    let en_suffix = BridgeCopy.toolDataSuffix(.en)
    let es_suffix = BridgeCopy.toolDataSuffix(.es)
    expect(en_suffix != es_suffix, "tool suffix: en != es")
}

private func testChipContainsCorrectLabel() {
    let client = "TestAgent"
    let en_chip = BridgeCopy.chipLabel(.en)
    let es_chip = BridgeCopy.chipLabel(.es)

    expect(en_chip == "Hands", "chip en: correct label")
    expect(es_chip == "Manos", "chip es: correct label")

    // Format with client name as the UI layer would do
    let en_full = "\(client): \(en_chip)"
    expect(en_full.contains(client), "chip en: format with client")
}
