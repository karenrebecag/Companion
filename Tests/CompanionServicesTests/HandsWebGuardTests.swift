import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Chromium browsers in front are the extension's job, not the
// accessibility hands. AX reports success on a web field and the page
// ignores it, so the agent would believe it typed. The hands refuse with
// a code the agent can act on: `browser_unsupported` for browsers Companion
// does not host, `browser_not_connected` for hosted browsers without the
// extension (or with another one connected), and `use_browser_tools` for
// hosted browsers with the extension. Native apps and Safari are unchanged.

private let secretText = "ZEBRA-SECRET-9F2C"
private let chrome = "com.google.Chrome"
private let comet = "ai.perplexity.comet"
private let safari = "com.apple.Safari"
private let notes = "com.apple.Notes"

private func webHandsRunner(
    _ hands: FakeHands, bundle: String,
    connectedBrowser: @escaping @Sendable () -> String? = { nil },
    appName: @escaping @Sendable (Int32) -> String? = { _ in nil },
    screen: (any ScreenActing)? = nil
) -> ParentToolRunner {
    ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in bundle },
            connectedBrowser: connectedBrowser, appName: appName, screen: screen))
}

private let unsupportedBrowsers: [String] = AXScreen.chromiumBrowsers
    .subtracting([chrome, comet]).sorted()

private func assertRefusedNoLeak(
    _ out: ParentToolOutcome, secret: String, code: String, message: String
) {
    expect(!out.ok, "refused: \(message)")
    expect(out.output.hasPrefix("\(code):"), "\(code) code: \(out.output)")
    expect(!out.output.contains(secret),
           "refused: el secreto nunca sale (\(secret)): \(out.output)")
}

// MARK: - Unsupported Chromium browsers

@MainActor func testTypeTextInAnUnsupportedChromiumBrowserIsRefused() async {
    for bundle in unsupportedBrowsers {
        let hands = FakeHands(field: FocusedField(app: bundle, pid: 7), text: secretText)
        let runner = webHandsRunner(hands, bundle: bundle, connectedBrowser: { nil })
        let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"x"}"#)
        assertRefusedNoLeak(out, secret: secretText, code: "browser_unsupported",
                            message: "unsupported type_text \(bundle)")
        expect(out.output.contains("Do not retry here"),
               "unsupported: el mensaje dice que no reintente: \(out.output)")
        expect(out.output.contains("Google Chrome") && out.output.contains("Comet"),
               "unsupported: nombra Chrome y Comet: \(out.output)")
        expect(hands.injected.isEmpty, "unsupported type_text \(bundle): inyector quieto")
        expect(hands.fieldLookups == 0, "unsupported type_text \(bundle): reader nunca consultado")
    }
}

@MainActor func testReadFocusedInAnUnsupportedChromiumBrowserIsRefused() async {
    for bundle in unsupportedBrowsers {
        let hands = FakeHands(field: FocusedField(app: bundle, pid: 7), text: secretText)
        let runner = webHandsRunner(hands, bundle: bundle, connectedBrowser: { nil })
        let out = await runner.execute(name: "read_focused", argumentsJSON: "{}")
        assertRefusedNoLeak(out, secret: secretText, code: "browser_unsupported",
                            message: "unsupported read_focused \(bundle)")
        expect(hands.reads == 0, "unsupported read_focused \(bundle): reader quieto")
        expect(hands.fieldLookups == 0, "unsupported read_focused \(bundle): focusedField quieto")
    }
}

// MARK: - Chrome and Comet, no extension connected

@MainActor func testTypeTextInChromeWithoutTheExtensionIsRefused() async {
    let hands = FakeHands(field: FocusedField(app: "Google Chrome", pid: 7), text: secretText)
    let runner = webHandsRunner(hands, bundle: chrome, connectedBrowser: { nil },
                                appName: { _ in "Google Chrome" })
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"x"}"#)
    assertRefusedNoLeak(out, secret: secretText, code: "browser_not_connected",
                        message: "chrome sin extension")
    expect(out.output.contains("Google Chrome"), "nombra al navegador: \(out.output)")
    expect(out.output.contains("Load the Companion extension in Google Chrome"),
           "dice como cargarla: \(out.output)")
    expect(out.output.contains("browser_tabs"),
           "apunta a browser_tabs: \(out.output)")
    expect(hands.injected.isEmpty, "inyector quieto")
    expect(hands.fieldLookups == 0, "focusedField quieto")
}

@MainActor func testReadFocusedInCometWithoutTheExtensionIsRefused() async {
    let hands = FakeHands(field: FocusedField(app: "Comet", pid: 7), text: secretText)
    let runner = webHandsRunner(hands, bundle: comet, connectedBrowser: { nil },
                                appName: { _ in "Comet" })
    let out = await runner.execute(name: "read_focused", argumentsJSON: "{}")
    assertRefusedNoLeak(out, secret: secretText, code: "browser_not_connected",
                        message: "comet sin extension")
    expect(out.output.contains("Comet"), "nombra al navegador: \(out.output)")
    expect(out.output.contains("browser_tabs"),
           "apunta a browser_tabs: \(out.output)")
    expect(hands.reads == 0, "reader.reads quieto")
    expect(hands.fieldLookups == 0, "focusedField quieto")
}

// MARK: - Chrome and Comet, another browser connected

@MainActor func testTypeTextInChromeWhileCometIsConnectedIsRefused() async {
    let hands = FakeHands(field: FocusedField(app: "Google Chrome", pid: 7), text: secretText)
    let runner = webHandsRunner(hands, bundle: chrome, connectedBrowser: { comet },
                                appName: { _ in "Google Chrome" })
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"x"}"#)
    assertRefusedNoLeak(out, secret: secretText, code: "browser_not_connected",
                        message: "chrome con comet conectado")
    expect(out.output.contains("connected to Comet"),
           "nombra al otro navegador: \(out.output)")
    expect(out.output.contains("not Google Chrome"),
           "nombra al navegador objetivo: \(out.output)")
    expect(out.output.contains("one browser at a time"),
           "explica la regla: \(out.output)")
    expect(hands.injected.isEmpty, "inyector quieto")
    expect(hands.fieldLookups == 0, "focusedField quieto")
}

@MainActor func testReadFocusedInCometWhileChromeIsConnectedIsRefused() async {
    let hands = FakeHands(field: FocusedField(app: "Comet", pid: 7), text: secretText)
    let runner = webHandsRunner(hands, bundle: comet, connectedBrowser: { chrome },
                                appName: { _ in "Comet" })
    let out = await runner.execute(name: "read_focused", argumentsJSON: "{}")
    assertRefusedNoLeak(out, secret: secretText, code: "browser_not_connected",
                        message: "comet con chrome conectado")
    expect(out.output.contains("connected to Google Chrome"),
           "nombra al otro navegador: \(out.output)")
    expect(out.output.contains("not Comet"),
           "nombra al navegador objetivo: \(out.output)")
    expect(hands.reads == 0, "reader.reads quieto")
    expect(hands.fieldLookups == 0, "focusedField quieto")
}

// MARK: - Chrome and Comet, this browser connected

@MainActor func testTypeTextInChromeWithTheExtensionConnectedRedirects() async {
    let hands = FakeHands(field: FocusedField(app: "Google Chrome", pid: 7), text: secretText)
    let runner = webHandsRunner(hands, bundle: chrome, connectedBrowser: { chrome },
                                appName: { _ in "Google Chrome" })
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"x"}"#)
    assertRefusedNoLeak(out, secret: secretText, code: "use_browser_tools",
                        message: "chrome con extension")
    expect(out.output.contains("typing into or reading Google Chrome"),
           "explica que el navegador es del extension: \(out.output)")
    expect(out.output.contains("browser_tabs"),
           "ordena empezar por browser_tabs: \(out.output)")
    expect(out.output.contains("browser_type") && out.output.contains("browser_read"),
           "nombra browser_type y browser_read: \(out.output)")
    expect(hands.injected.isEmpty, "inyector quieto")
    expect(hands.fieldLookups == 0, "focusedField quieto")
}

@MainActor func testReadFocusedInCometWithTheExtensionConnectedRedirects() async {
    let hands = FakeHands(field: FocusedField(app: "Comet", pid: 7), text: secretText)
    let runner = webHandsRunner(hands, bundle: comet, connectedBrowser: { comet },
                                appName: { _ in "Comet" })
    let out = await runner.execute(name: "read_focused", argumentsJSON: "{}")
    assertRefusedNoLeak(out, secret: secretText, code: "use_browser_tools",
                        message: "comet con extension")
    expect(out.output.contains("typing into or reading Comet"),
           "explica que el navegador es del extension: \(out.output)")
    expect(hands.reads == 0, "reader.reads quieto")
    expect(hands.fieldLookups == 0, "focusedField quieto")
}

// MARK: - Native apps and Safari unchanged

@MainActor func testTypeTextInANativeAppIsUnchanged() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let runner = webHandsRunner(hands, bundle: notes, connectedBrowser: { chrome })
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.ok, "nativa: type_text sigue funcionando")
    expectEq(hands.injected.map(\.text), ["hola"], "nativa: el texto entra")
    expectEq(hands.injected.map(\.pid), [7], "nativa: en el pid de delante")
    expect(!out.output.hasPrefix("browser_not_connected:"),
           "nativa: nunca el codigo de navegador")
    expect(!out.output.hasPrefix("use_browser_tools:"), "nativa: nunca el redirect")
    expect(!out.output.hasPrefix("browser_unsupported:"), "nativa: nunca unsupported")
}

@MainActor func testReadFocusedInANativeAppIsUnchanged() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: "hola")
    let runner = webHandsRunner(hands, bundle: notes, connectedBrowser: { chrome })
    let out = await runner.execute(name: "read_focused", argumentsJSON: "{}")
    expect(out.ok, "nativa: read_focused sigue funcionando")
    expectEq(out.output, "hola", "nativa: el texto se lee")
}

@MainActor func testSafariIsNotAChromiumTarget() async {
    let hands = FakeHands(field: FocusedField(app: "Safari", pid: 7))
    let runner = webHandsRunner(hands, bundle: safari, connectedBrowser: { chrome })
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.ok, "Safari no es Chromium: type_text sigue funcionando")
    expectEq(hands.injected.map(\.text), ["hola"], "Safari: el texto entra")
    let readHands = FakeHands(field: FocusedField(app: "Safari", pid: 7), text: "hi")
    let readRunner = webHandsRunner(readHands, bundle: safari, connectedBrowser: { chrome })
    let readOut = await readRunner.execute(name: "read_focused", argumentsJSON: "{}")
    expect(readOut.ok, "Safari: read_focused sigue funcionando")
    expectEq(readOut.output, "hi", "Safari: el texto se lee")
}

// MARK: - No approval sheet for a Chromium target

@MainActor func testNoApprovalIsRaisedForAChromiumTarget() async {
    let hands = FakeHands(field: FocusedField(app: "Google Chrome", pid: 7))
    let runner = webHandsRunner(hands, bundle: chrome, connectedBrowser: { nil },
                                appName: { _ in "Google Chrome" })
    // An address-like text the user did not say would normally raise a
    // sheet through `HandsGate.verdict`; the web guard must short-circuit
    // before that sheet appears.
    let call = ToolCallRef(id: "", name: "type_text", arguments: #"{"text":"github.com"}"#)
    let request = runner.approval(for: call, said: "escribe google.com")
    expect(request == nil, "Chromium: el runner no pide aprobacion: \(String(describing: request))")
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"github.com"}"#)
    expect(!out.ok && out.output.hasPrefix("browser_not_connected:"),
           "Chromium: la ejecucion se rehúsa con browser_not_connected: \(out.output)")
    expect(hands.injected.isEmpty, "Chromium: nada inyectado")
}

@MainActor func testNoApprovalIsRaisedForAChromiumTargetEvenWithAConnectedExtension() async {
    let hands = FakeHands(field: FocusedField(app: "Comet", pid: 7))
    let runner = webHandsRunner(hands, bundle: comet, connectedBrowser: { comet },
                                appName: { _ in "Comet" })
    let call = ToolCallRef(id: "", name: "type_text", arguments: #"{"text":"hola"}"#)
    let request = runner.approval(for: call, said: "saluda")
    expect(request == nil, "Chromium con extension: el runner no pide aprobacion: \(String(describing: request))")
}

// The guard only covers type_text and read_focused: every other hands tool
// in a browser keeps the approval it has in any other app.
@MainActor func testOtherHandsToolsKeepTheirApprovalInAChromiumBrowser() async {
    // Each call must raise a sheet in a native app first, or a browser
    // that also returns nil would pass without proving anything.
    let deleteButton = [ScanNode(role: "AXButton", subrole: "", label: "Eliminar", value: nil, secure: false)]
    let calls = [
        ToolCallRef(id: "", name: "press_key", arguments: #"{"key":"return"}"#),
        ToolCallRef(id: "", name: "click", arguments: #"{"id":1}"#),
    ]
    for call in calls {
        var results: [String: Bool] = [:]
        for (app, bundle) in [("Google Chrome", chrome), ("Notes", "com.apple.Notes")] {
            let runner = webHandsRunner(FakeHands(field: FocusedField(app: app, pid: 7)),
                                        bundle: bundle, connectedBrowser: { chrome },
                                        screen: FakeScreen(deleteButton))
            _ = await runner.execute(name: "look", argumentsJSON: "{}")
            results[app] = runner.approval(for: call, said: "nada que ver") != nil
        }
        expectEq(results["Notes"], true, "\(call.name): en una app nativa pide aprobacion")
        expectEq(results["Google Chrome"], true, "\(call.name): en Chrome tambien pide aprobacion")
    }
}

// MARK: - App name sanitization

@MainActor func testAppNameSanitizationStripsControlCharacters() async {
    let hands = FakeHands(field: FocusedField(app: "ignored", pid: 7))
    let dirty = "Google\u{0001}\nChrome\r"
    let runner = webHandsRunner(hands, bundle: chrome, connectedBrowser: { nil },
                                appName: { _ in dirty })
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"x"}"#)
    expect(out.output.contains("GoogleChrome"),
           "control chars fuera: \(out.output)")
    expect(!out.output.contains("\n") && !out.output.contains("\r") && !out.output.contains("\u{0001}"),
           "ningun caracter de control: \(out.output)")
}

@MainActor func testAppNameSanitizationCapsAtFortyCharacters() async {
    let hands = FakeHands(field: FocusedField(app: "ignored", pid: 7))
    let long = String(repeating: "A", count: 80)
    let runner = webHandsRunner(hands, bundle: chrome, connectedBrowser: { nil },
                                appName: { _ in long })
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"x"}"#)
    // Count the longest run of A's in the output; the name appears twice
    // and each instance must be capped to 40 characters.
    var longest = 0
    var current = 0
    for char in out.output {
        if char == "A" { current += 1; longest = max(longest, current) }
        else { current = 0 }
    }
    expect(longest <= 40, "cap a 40: longest run \(longest): \(out.output)")
    expect(longest >= 35, "se uso el nombre real, no el id: \(out.output)")
}

@MainActor func testAppNameSanitizationFallsBackToBundleIdWhenEmpty() async {
    let hands = FakeHands(field: FocusedField(app: "ignored", pid: 7))
    let runner = webHandsRunner(hands, bundle: chrome, connectedBrowser: { nil },
                                appName: { _ in "\n\u{0001}\t" })
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"x"}"#)
    expect(out.output.contains(chrome),
           "solo control chars: cae al bundle id: \(out.output)")
}

@MainActor func testAppNameSanitizationFallsBackToBundleIdWhenNil() async {
    let hands = FakeHands(field: FocusedField(app: "ignored", pid: 7))
    let runner = webHandsRunner(hands, bundle: chrome, connectedBrowser: { nil })
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"x"}"#)
    expect(out.output.contains(chrome),
           "nil: cae al bundle id: \(out.output)")
}

// MARK: - BrowserHost: supportsExtension and bundle mapping

@Test func browserHostSupportsChromeAndCometOnly() {
    expect(BrowserHost.supportsExtension(bundle: "com.google.Chrome"), "chrome")
    expect(BrowserHost.supportsExtension(bundle: "ai.perplexity.comet"), "comet")
    for bundle in AXScreen.chromiumBrowsers.subtracting([chrome, comet]) {
        expect(!BrowserHost.supportsExtension(bundle: bundle), "no soporta \(bundle)")
    }
    expect(!BrowserHost.supportsExtension(bundle: safari), "Safari no")
    expect(!BrowserHost.supportsExtension(bundle: notes), "Notes no")
    expectEq(BrowserHost.bundle(for: .chrome), chrome, "chrome -> com.google.Chrome")
    expectEq(BrowserHost.bundle(for: .comet), comet, "comet -> ai.perplexity.comet")
}

@Test func browserHostDisplayNameStripsAndCapsAndFallsBack() {
    expectEq(BrowserHost.displayName(name: "Google Chrome", bundle: chrome),
             "Google Chrome", "nombre limpio")
    expectEq(BrowserHost.displayName(name: "Google\u{0001}Chrome", bundle: chrome),
             "GoogleChrome", "control fuera")
    expectEq(BrowserHost.displayName(name: String(repeating: "A", count: 80), bundle: chrome),
             String(repeating: "A", count: 40), "cap 40")
    expectEq(BrowserHost.displayName(name: nil, bundle: chrome), chrome, "nil -> bundle")
    expectEq(BrowserHost.displayName(name: "\n\u{0001}", bundle: chrome), chrome, "vacio -> bundle")
    expectEq(BrowserHost.displayName(forBundle: chrome), "Google Chrome", "chrome friendly")
    expectEq(BrowserHost.displayName(forBundle: comet), "Comet", "comet friendly")
    expectEq(BrowserHost.displayName(forBundle: "com.brave.Browser"),
             "com.brave.Browser", "desconocido -> id")
}

@MainActor func testHandsWebGuardLoop() async {
    await testTypeTextInAnUnsupportedChromiumBrowserIsRefused()
    await testReadFocusedInAnUnsupportedChromiumBrowserIsRefused()
    await testTypeTextInChromeWithoutTheExtensionIsRefused()
    await testReadFocusedInCometWithoutTheExtensionIsRefused()
    await testTypeTextInChromeWhileCometIsConnectedIsRefused()
    await testReadFocusedInCometWhileChromeIsConnectedIsRefused()
    await testTypeTextInChromeWithTheExtensionConnectedRedirects()
    await testReadFocusedInCometWithTheExtensionConnectedRedirects()
    await testTypeTextInANativeAppIsUnchanged()
    await testReadFocusedInANativeAppIsUnchanged()
    await testSafariIsNotAChromiumTarget()
    await testNoApprovalIsRaisedForAChromiumTarget()
    await testOtherHandsToolsKeepTheirApprovalInAChromiumBrowser()
    await testNoApprovalIsRaisedForAChromiumTargetEvenWithAConnectedExtension()
    await testAppNameSanitizationStripsControlCharacters()
    await testAppNameSanitizationCapsAtFortyCharacters()
    await testAppNameSanitizationFallsBackToBundleIdWhenEmpty()
    await testAppNameSanitizationFallsBackToBundleIdWhenNil()
}

@Test @MainActor func handsWebGuardTests() async {
    await testHandsWebGuardLoop()
    browserHostSupportsChromeAndCometOnly()
    browserHostDisplayNameStripsAndCapsAndFallsBack()
}
