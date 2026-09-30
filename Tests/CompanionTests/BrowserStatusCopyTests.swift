import CompanionCore
import Foundation
import Testing

// Wave 18-3c. A browser failure in the thread must not read as "Could not
// open ...": that line belongs to open_app/open_url.

@Test func browserFailureDoesNotReadAsAnOpenFailure() {
    let failure = ParentToolOutcome.failed(
        ContractError(code: BridgeCode.notConnected, message: "x"), tool: "browser_click")
    for language in [AppLanguage.en, .es] {
        let line = ParentToolCopy.status("browser_click", failure, language)
        #expect(!line.contains("open") && !line.contains("abrir"), "\(language): \(line)")
        #expect(line.lowercased().contains("browser") || line.contains("avegador"), Comment(rawValue: line))
    }
}

@Test func browserDenialSaysYouSaidNo() {
    let denied = ParentToolOutcome(ok: false, output: "denied_by_user", tool: "browser_navigate")
    expectEq(ParentToolCopy.status("browser_navigate", denied, .en), "Did not do it in the browser: you said no.", "en")
    expectEq(ParentToolCopy.status("browser_navigate", denied, .es), "No lo hice en el navegador: dijiste que no.", "es")
}

@Test func browserSuccessNamesTheAction() {
    let ok = ParentToolOutcome(ok: true, output: "done", target: "https://a.com", tool: "browser_read")
    for tool in BrowserTool.allCases {
        for language in [AppLanguage.en, .es] {
            let line = ParentToolCopy.status(tool.rawValue, ok, language)
            #expect(!line.hasPrefix("Done:") && !line.hasPrefix("Hecho:"), "\(tool.rawValue) \(language): \(line)")
        }
    }
}
