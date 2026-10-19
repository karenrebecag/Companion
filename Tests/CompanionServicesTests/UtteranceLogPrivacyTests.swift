import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Code review 2026-09-24 (medio, previo a 15d): the main log is shared in
// bug reports, so what the user said and what the model decided to do on
// their behalf reach it only as counts — the rule the on-device ear
// already follows ("first words N chars", AnalyzerTranscriberTests).

@Test @MainActor func utteranceLogPrivacyTests() async {
    await testTheEarGoalAndTheAuditLineLogCountsNotTheWords()
}

private func privacyLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-privacy-\(UUID().uuidString).log")
}

private func logText(_ url: URL) -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        return ""
    }
}

@MainActor func testTheEarGoalAndTheAuditLineLogCountsNotTheWords() async {
    let url = privacyLogURL()
    await Log.capturing(to: url) {
        let ear = ScriptedTranscriber()
        let audit = VoiceAudit(native: ear)
        await audit.begin(locale: "es-MX")
        audit.noteGoal("transfiere a carmesí-\(UUID().uuidString.prefix(6))")
        ear.yieldPartial("dile a índigo-\(UUID().uuidString.prefix(6)) que llego tarde")
        audit.logTurn()
        let text = logText(url)
        expect(text.contains("ear goal"), "log: el goal deja rastro")
        expect(!text.contains("carmesí"), "log: el goal nunca se escribe")
        expect(!text.contains("índigo"), "log: la línea de auditoría nunca lleva lo oído")
        expect(text.contains("chars"), "log: cuenta caracteres en su lugar")
    }
}
