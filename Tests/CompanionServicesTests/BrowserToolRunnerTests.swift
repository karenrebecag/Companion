import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 18-3 (§8 criteria 3, 4, 6; §9). The browser's tools and their gates,
// against a fake channel that records every command it is asked to send: a
// denied call must leave that record without a write in it.


// MARK: - criterion 6

@Test func noExtensionMeansNoBrowserSpecs() {
    let rig = makeToolRig(connected: false)
    expect(rig.runner.specs(.en).isEmpty, "criterio 6: sin extension no hay ninguna browser_*")
    expect(!rig.runner.handles("browser_read"), "criterio 6: y no se atiende")
    expectEq(rig.runner.unavailability(for: "browser_read"), BridgeCode.notConnected, "criterio 6: dice por que")
}

@Test func aConnectedExtensionOffersTheEightTools() {
    let rig = makeToolRig()
    expectEq(rig.runner.specs(.en).map(\.name),
             ["browser_tabs", "browser_read", "browser_click", "browser_type", "browser_navigate",
              "browser_open", "browser_take", "browser_release"], "ocho tools (18b anade open, take, release)")
    expectEq(rig.runner.specs(.es).count, 8, "tambien en espanol")
    expect(rig.runner.handles("browser_click"), "atiende sus tools")
    expect(!rig.runner.handles("look"), "y solo las suyas")
    expect(!rig.runner.handles("click"), "click de Accesibilidad no es suyo")
    expectEq(rig.runner.unavailability(for: "browser_read"), nil, "lista: sin motivo")
    expectEq(rig.runner.unavailability(for: "look"), nil, "ajeno: nil")
    rig.presence.set(nil)
    expect(rig.runner.specs(.en).isEmpty, "si se va, se retiran")
}

// MARK: - reads

@Test func tabsAreListedThroughTheChannel() async {
    let rig = makeToolRig(tabs: [
        BrowserTab(id: 12, title: "CRM\nforged line", url: crm, active: false),
        BrowserTab(id: 3, title: "Mail", url: "https://mail.example", active: true),
    ])
    let out = await rig.runner.execute(name: "browser_tabs", argumentsJSON: "{}")
    expect(out.ok, "tabs ok")
    expect(out.output.contains("[12]") && out.output.contains("[3]"), "ids de pestana")
    expect(!out.output.contains("CRM\nforged"), "un titulo no forja una linea")
    expect(out.output.hasSuffix(BrowserCopy.toolDataSuffix(.en)), "declara que son datos")
}

@Test func readRendersScrubsCachesAndCarriesTheDataSuffix() async {
    let rig = makeToolRig(page: crmPage(text: "Bienvenida"))
    let out = await rig.runner.execute(name: "browser_read", argumentsJSON: #"{"tab":12,"selector":"form >>> input"}"#)
    expect(out.ok, "read ok")
    expect(out.output.contains("[1] button \"Guardar\""), "elementos numerados")
    expect(out.output.contains("Bienvenida"), "texto de la pagina")
    expect(!out.output.contains("hunter2"), "el valor de un password nunca sale")
    expect(out.output.hasSuffix(BrowserCopy.toolDataSuffix(.en)), "datos, nunca instrucciones")
    guard case .read(let tab, let selector)? = rig.channel.sent.first?.command else { Issue.record("no read sent"); return }
    expectEq(tab, 12, "pestana")
    expectEq(selector, "form >>> input", "selector")
    expectEq(rig.channel.sent.first?.timeout, .seconds(15), "lectura: 15 s")
}

@Test func aReadOfTheModelsOwnBadArgumentsSendsNothing() async {
    let rig = makeToolRig()
    for args in ["{}", #"{"tab":"x"}"#, "not json", #"{"tab":-1}"#] {
        let out = await rig.runner.execute(name: "browser_read", argumentsJSON: args)
        expect(!out.ok && out.output.contains(BridgeCode.invalidArgs), "invalid_args: \(args)")
    }
    expect(rig.channel.sent.isEmpty, "nada llega a la extension")
}

@Test func aChannelFailureSurfacesItsCode() async {
    let presence = BrowserPresence()
    presence.set(.chrome)
    let channel = FakeBrowserChannel(failure: ContractError(code: BridgeCode.timeout, message: "slow"))
    let leases = BrowserLeases(epoch: presence.epoch)
    leases.acquire(tab: 1, caller: "chat")
    let runner = BrowserToolRunner(channel: channel, presence: presence, leases: leases, caller: "chat")
    let out = await runner.execute(name: "browser_read", argumentsJSON: #"{"tab":1}"#)
    expect(!out.ok && out.output.contains(BridgeCode.timeout), "el codigo llega al modelo")
}

// MARK: - stale ids

@Test func clickWithoutAReadIsStaleGuidanceAndSendsNothing() async {
    let rig = makeToolRig()
    let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "sin lectura: stale_id")
    expect(out.output.contains("read the tab again"), "con guia")
    expect(rig.channel.writes.isEmpty, "cero escrituras")
}

@Test func anUnknownElementIsStaleGuidance() async {
    let rig = makeToolRig()
    await rig.read()
    let out = await rig.run("browser_click", #"{"tab":12,"element":99}"#)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "elemento inexistente: stale_id")
    expect(rig.channel.writes.isEmpty, "cero escrituras")
}

@Test func theExtensionsStaleIdComesBackAsGuidance() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.failWrites(with: ContractError(code: BridgeCode.staleId, message: "gone"))
    let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "stale_id de la extension llega al modelo")
    expect(out.output.contains("read the tab again"), "con la guia de volver a leer")
}

/// H-2/H-3: each reason the extension gives reaches the model as its own copy, not "the browser failed".
@Test func eachExtensionReasonComesBackWithItsNextStep() async {
    for code in [BridgeCode.debuggerRevoked, BridgeCode.debuggerUnavailable, BridgeCode.unreadablePage,
                 BridgeCode.notTypable] {
        let rig = makeToolRig()
        await rig.read()
        rig.channel.failWrites(with: ContractError(code: code, message: "page wording, never shown"))
        let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#)
        expect(!out.ok && out.output.contains(code), "\(code): the code: \(out.output)")
        expect(out.output.contains(BrowserCopy.failure(code: code, .en)), "\(code): its copy: \(out.output)")
        expect(!out.output.contains("page wording"), "\(code): the extension's wording stays out")
    }
}

/// A read of a tab that is gone lets the lease go, so a later write needs a new take.
@Test func aReadOfAGoneTabReleasesTheLease() async {
    let rig = makeToolRig()
    rig.channel.goneOnRead(12)
    let read = await rig.run("browser_read", #"{"tab":12}"#)
    expect(!read.ok && read.output.contains(BridgeCode.staleId), "gone tab: stale_id: \(read.output)")
    let click = await rig.run("browser_click", #"{"tab":12,"element":1}"#)
    expect(click.output.contains(BridgeCode.notControlled), "the lease is gone: \(click.output)")
    expect(rig.channel.writes.isEmpty, "nothing sent")
}

// MARK: - criterion 3: click

@Test func clickOnEliminarNotSaidAsksAndADenialSendsNoFrame() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    let request = rig.runner.approval(for: rig.call("browser_click", arguments), said: "guarda el registro")
    expect(request != nil, "criterio 3: Eliminar no dicho pide hoja")
    expectEq(request?.toolName, "browser_click", "la hoja nombra la tool")
    // Denied: the gate never calls `granted`.
    let out = await rig.runner.execute(name: "browser_click", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "sin ticket no hay clic")
    expect(rig.channel.writes.isEmpty, "criterio 3: la extension no recibe ningun call de escritura")
}

@Test func clickOnEliminarClearedBySheetRunsWithTheBoundGeneration() async {
    let rig = makeToolRig()
    await rig.read()
    let out = await rig.run("browser_click", #"{"tab":12,"element":2}"#, said: "guarda", approve: true)
    expect(out.ok, "aprobada: corre")
    guard case .click(let tab, let generation, let element)? = rig.channel.writes.first else {
        Issue.record("no click sent"); return
    }
    expectEq([tab, generation, element], [12, 3, 2], "tab, generation y elemento de la lectura")
    expectEq(rig.channel.sent.last?.timeout, .seconds(15), "clic: 15 s")
}

@Test func aTicketIsSpentOnce() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    _ = await rig.run("browser_click", arguments, approve: true)
    let again = await rig.runner.execute(name: "browser_click", argumentsJSON: arguments)
    expect(!again.ok, "el mismo sí no vale dos veces")
    expectEq(rig.channel.writes.count, 1, "una sola escritura")
}

@Test func aTicketDoesNotSurviveARead() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    if let request = rig.runner.approval(for: rig.call("browser_click", arguments), said: "") { rig.runner.granted(request) }
    rig.channel.setPage(crmPage(generation: 4))
    await rig.read()
    let out = await rig.runner.execute(name: "browser_click", argumentsJSON: arguments)
    expect(!out.ok, "una lectura nueva renumera: el sí de antes no aplica")
    expect(rig.channel.writes.isEmpty, "cero escrituras")
}

@Test func aTicketDoesNotFollowALabelChangeUnderTheSameId() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    if let request = rig.runner.approval(for: rig.call("browser_click", arguments), said: "") { rig.runner.granted(request) }
    var swapped = crmPage(generation: 3)
    swapped.elements[1].label = "Enviar pago"
    rig.channel.setPage(swapped)
    await rig.read()
    let out = await rig.runner.execute(name: "browser_click", argumentsJSON: arguments)
    expect(!out.ok, "mismo id y generacion, otra etiqueta: no vale el ticket")
    expect(rig.channel.writes.isEmpty, "cero escrituras")
}

@Test func aHarmlessClickActsWithoutASheet() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":1}"#
    expect(rig.runner.approval(for: rig.call("browser_click", arguments), said: "") == nil, "Guardar: sin hoja")
    let out = await rig.runner.execute(name: "browser_click", argumentsJSON: arguments)
    expect(out.ok, "corre")
    expectEq(rig.channel.writes.count, 1, "una escritura")
}

@Test func aWriteThatSkippedTheGateIsRefused() async {
    let rig = makeToolRig()
    await rig.read()
    let out = await rig.runner.execute(name: "browser_click", argumentsJSON: #"{"tab":12,"element":1}"#)
    expect(!out.ok && out.output.contains("approval_required"), "sin pasar por la puerta no corre, ni lo inocuo")
    expect(rig.channel.writes.isEmpty, "cero escrituras")
}

@Test func aLinkToAnotherOriginAsksEvenWithAHarmlessLabel() async {
    let rig = makeToolRig()
    await rig.read()
    expect(rig.runner.approval(for: rig.call("browser_click", #"{"tab":12,"element":3}"#), said: "") != nil,
           "enlace a otro origen: hoja")
    expect(rig.runner.approval(for: rig.call("browser_click", #"{"tab":12,"element":7}"#), said: "") == nil,
           "enlace del mismo origen: sin hoja")
}

@Test func aFrameOfAnotherOriginAsks() async {
    let rig = makeToolRig()
    await rig.read()
    let request = rig.runner.approval(for: rig.call("browser_click", #"{"tab":12,"element":6}"#), said: "")
    expect(request != nil, "iframe de otro origen: hoja")
    let out = await rig.runner.execute(name: "browser_click", argumentsJSON: #"{"tab":12,"element":6}"#)
    expect(!out.ok, "y sin sí no corre")
    expect(rig.channel.writes.isEmpty, "cero escrituras")
}

@Test func aTabThatLeftItsOriginSinceTheReadIsNotClicked() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.setTabs([BrowserTab(id: 12, title: "Phish", url: "https://evil.example/", active: true)])
    let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#, approve: true)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "otra pagina ahora: stale_id")
    expect(rig.channel.writes.isEmpty, "cero escrituras")
}

// MARK: - type

@Test func typingIntoASensitiveFieldIsRefusedWithoutSending() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":4,"text":"hunter2"}"#
    #expect(rig.runner.approval(for: rig.call("browser_type", arguments), said: "hunter2") == nil)
    let out = await rig.run("browser_type", arguments, said: "hunter2", approve: true)
    expect(!out.ok && out.output.contains(BridgeCode.secureField), "password: secure_field")
    expect(rig.channel.writes.isEmpty, "cero escrituras")
}

@Test func typingPlainTextActsAndAnAddressNotSaidAsks() async {
    let rig = makeToolRig()
    await rig.read()
    let plain = #"{"tab":12,"element":5,"text":"Ana"}"#
    let out = await rig.run("browser_type", plain)
    expect(out.ok, "texto normal en campo normal: corre")
    guard case .type(_, let generation, let element, let text)? = rig.channel.writes.first else {
        Issue.record("no type sent"); return
    }
    expectEq([generation, element, text.count], [3, 5, 3], "generacion, elemento, texto")

    let email = #"{"tab":12,"element":5,"text":"https://evil.example/x"}"#
    expect(rig.runner.approval(for: rig.call("browser_type", email), said: "escribe mi nombre") != nil,
           "una direccion que el usuario no dijo pide hoja")
}

@Test func typingInAForeignFrameAsks() async {
    var page = crmPage()
    page.elements.append(webElement(8, "input", "Nombre", inputType: "text", frameOrigin: "https://ads.example"))
    let rig = makeToolRig(page: page)
    await rig.read()
    expect(rig.runner.approval(for: rig.call("browser_type", #"{"tab":12,"element":8,"text":"Ana"}"#), said: "") != nil,
           "escribir en un iframe ajeno pide hoja")
}

// MARK: - criterion 4: navigate

@Test func navigatingToAnotherOriginNotSaidAsksAndADenialSendsNoFrame() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"url":"https://evil.example/login"}"#
    let request = rig.runner.approval(for: rig.call("browser_navigate", arguments), said: "abre el reporte")
    expect(request != nil, "criterio 4: otro origen no dicho, hoja")
    let out = await rig.runner.execute(name: "browser_navigate", argumentsJSON: arguments)
    expect(!out.ok, "denegada: no navega")
    expect(rig.channel.writes.isEmpty, "criterio 4: cero escrituras")
}

@Test func navigatingWithinTheSameOriginActsWithoutASheet() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"url":"https://crm.example/reports"}"#
    expect(rig.runner.approval(for: rig.call("browser_navigate", arguments), said: "") == nil, "mismo origen: sin hoja")
    let out = await rig.runner.execute(name: "browser_navigate", argumentsJSON: arguments)
    expect(out.ok, "corre")
    guard case .navigate(let tab, let url)? = rig.channel.writes.first else { Issue.record("no navigate sent"); return }
    expectEq(tab, 12, "pestana")
    expectEq(url.absoluteString, "https://crm.example/reports", "url")
    expectEq(rig.channel.sent.last?.timeout, .seconds(30), "navegar: 30 s")
}

@Test func navigatingToAnotherOriginTheUserNamedActs() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"url":"https://github.com/karenrebecag"}"#
    expect(rig.runner.approval(for: rig.call("browser_navigate", arguments), said: "abre github.com/karenrebecag") == nil,
           "dicho por el usuario: sin hoja")
    let out = await rig.runner.execute(name: "browser_navigate", argumentsJSON: arguments)
    expect(out.ok, "corre")
}

@Test func navigateReChecksTheTabsCurrentOriginAtCallTime() async {
    let rig = makeToolRig()
    await rig.read()
    // The cached page says crm.example, so the gate lets the same-origin
    // navigation through; the tab has since moved somewhere else.
    rig.channel.setTabs([BrowserTab(id: 12, title: "x", url: "https://evil.example/", active: true)])
    let out = await rig.run("browser_navigate", #"{"tab":12,"url":"https://crm.example/reports"}"#)
    expect(!out.ok, "M4: el origen vigente no es el de la lectura")
    expect(rig.channel.writes.isEmpty, "cero escrituras")
    expect(rig.channel.sent.contains { if case .tabs = $0.command { return true } else { return false } },
           "se pregunto por las pestanas antes de decidir")
}

@Test func navigateRefusesNonHttpSchemesWithoutSending() async {
    let rig = makeToolRig()
    await rig.read()
    for url in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,x", "chrome://settings"] {
        let arguments = #"{"tab":12,"url":"\#(url)"}"#
        expect(rig.runner.approval(for: rig.call("browser_navigate", arguments), said: url) == nil, "\(url): sin hoja")
        let out = await rig.run("browser_navigate", arguments, said: url, approve: true)
        expect(!out.ok, "\(url): rechazada")
    }
    expect(rig.channel.writes.isEmpty, "cero escrituras")
}

@Test func navigateDropsTheCachedPageOfThatTab() async {
    let rig = makeToolRig()
    await rig.read()
    _ = await rig.run("browser_navigate", #"{"tab":12,"url":"https://crm.example/reports"}"#)
    let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "los ids de la pagina anterior ya no valen")
}

// MARK: - logs

@Test func logsCarryNoPageTextNorTypedValues() async throws {
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("btr-log-\(UUID().uuidString.prefix(8)).log")
    defer { do { try FileManager.default.removeItem(at: logURL) } catch {} }
    let secret = "SECRET-PAGE-TEXT-4242"
    let typed = "TYPED-VALUE-9911"
    try await Log.capturing(to: logURL) {
        let rig = makeToolRig(page: crmPage(text: secret))
        await rig.read()
        _ = await rig.run("browser_type", #"{"tab":12,"element":4,"text":"\#(typed)"}"#, said: typed)
        _ = await rig.run("browser_click", #"{"tab":12,"element":2}"#)
        _ = await rig.run("browser_click", #"{"tab":12,"element":99}"#)
    }
    let log = try String(contentsOf: logURL, encoding: .utf8)
    expect(!log.contains(secret), "logs: nunca texto de pagina")
    expect(!log.contains(typed), "logs: nunca lo escrito")
    expect(!log.contains("Eliminar"), "logs: nunca etiquetas")
    expect(log.contains("tool=browser_click"), "logs: la tool se nombra")
}
