import CompanionCore
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing

@Test @MainActor func bridgeCopyTests() async {
    await pinLanguage {
        testCopyConsistency()
        testCopyLanguageVariance()
    }
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

    let en_suffix = BridgeCopy.toolDataSuffix(.en)
    let es_suffix = BridgeCopy.toolDataSuffix(.es)
    expect(en_suffix != es_suffix, "tool suffix: en != es")
}
