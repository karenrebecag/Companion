import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Audit H-2/H-3: the copy the model reads for a browser failure names what
// to do next, never "the browser failed" for a reason the extension gave.

private let reasons: [(code: String, en: String, es: String)] = [
    (BridgeCode.debuggerRevoked, "ask the user", "pregunta"),
    (BridgeCode.debuggerUnavailable, "then retry", "vuelve a intentar"),
    (BridgeCode.unreadablePage, "tell the user", "dile"),
    (BridgeCode.notTypable, "browser_select", "browser_select"),
    (BridgeCode.notSelectable, "choose another", "elige otro"),
    (BridgeCode.optionNotFound, "read the tab again", "vuelve a leer"),
    (BridgeCode.notFocused, "browser_click", "browser_click"),
    (BridgeCode.pressUnconfirmed, "read the tab again", "vuelve a leer"),
]

@Test func everyBrowserReasonNamesTheNextStep() {
    for reason in reasons {
        let en = BrowserCopy.failure(code: reason.code, .en)
        let es = BrowserCopy.failure(code: reason.code, .es)
        expect(!en.hasPrefix("The browser failed"), "\(reason.code) en: its own copy: \(en)")
        expect(!es.hasPrefix("El navegador falló"), "\(reason.code) es: its own copy: \(es)")
        expect(en.localizedCaseInsensitiveContains(reason.en), "\(reason.code) en names the step: \(en)")
        expect(es.localizedCaseInsensitiveContains(reason.es), "\(reason.code) es names the step: \(es)")
    }
}

@Test func aUserStopIsNeverToldToRetry() {
    let en = BrowserCopy.failure(code: BridgeCode.debuggerRevoked, .en)
    expect(en.contains("stopped") && en.contains("Do not retry"), "the stop reads as the user's choice: \(en)")
    let es = BrowserCopy.failure(code: BridgeCode.debuggerRevoked, .es)
    expect(es.contains("No reintentes"), "es: no retry either: \(es)")
}

@Test func theCodesAreTheExtensionsSpelling() {
    expectEq([BridgeCode.debuggerRevoked, BridgeCode.debuggerUnavailable, BridgeCode.unreadablePage,
              BridgeCode.notTypable, BridgeCode.notSelectable, BridgeCode.optionNotFound, BridgeCode.notFocused,
              BridgeCode.pressUnconfirmed],
             ["debugger_revoked", "debugger_unavailable", "unreadable_page", "not_typable", "not_selectable",
              "option_not_found", "not_focused", "press_unconfirmed"],
             "wire spelling matches background.js and page.js")
}

@Test func anUnconfirmedPressTellsTheModelToReadFirstNotBlindlyRetry() {
    // The press was a click on a field; typing the wrong keys is the dangerous outcome.
    // The message must lead with "read the tab again" before the word "retry".
    let en = BrowserCopy.failure(code: BridgeCode.pressUnconfirmed, .en)
    let es = BrowserCopy.failure(code: BridgeCode.pressUnconfirmed, .es)
    let enReadAt = en.range(of: "read", options: .caseInsensitive)?.lowerBound
    let enRetryAt = en.range(of: "retry", options: .caseInsensitive)?.lowerBound
    let esReadAt = es.range(of: "leer")?.lowerBound
    let esRetryAt = es.range(of: "reintenta")?.lowerBound
    expect(enReadAt != nil && enRetryAt != nil && enReadAt! < enRetryAt!,
           "en: read before retry: \(en)")
    expect(esReadAt != nil && esRetryAt != nil && esReadAt! < esRetryAt!,
           "es: leer before reintenta: \(es)")
    expect(en.contains("no key was sent"), "en: the model must know nothing was typed: \(en)")
    expect(es.contains("no se envió ninguna tecla"), "es: same in Spanish: \(es)")
}

@Test func theUnconfirmedPressLineTellsTheModelToReadBeforeActing() {
    let en = BrowserCopy.pressUnconfirmed(.en)
    let es = BrowserCopy.pressUnconfirmed(.es)
    expect(en.contains("could not be confirmed") && en.contains("read the tab"), "en: \(en)")
    expect(en.contains("do not repeat"), "en: no blind repeat: \(en)")
    expect(es.contains("No se pudo confirmar") && es.contains("lee la pestaña"), "es: \(es)")
    expect(es.contains("no repitas"), "es: no blind repeat: \(es)")
}
