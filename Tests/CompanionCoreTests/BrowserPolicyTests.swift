import CompanionCore
import CompanionTestKit
import Foundation
import Testing

/// Wave 18-0: what the browser is allowed to hand back and what may be done
/// with it. Core filters again on purpose: the extension is not trusted.

private func element(
    _ id: Int = 1, role: String = "textbox", label: String = "Campo", context: String = "",
    inputType: String? = nil, autocomplete: String? = nil, value: String? = nil
) -> BrowserElement {
    BrowserElement(id: id, frame: 0, role: role, label: label, context: context,
                   inputType: inputType, autocomplete: autocomplete, value: value)
}

private func page(_ elements: [BrowserElement], text: String = "", truncated: Bool = false) -> BrowserPage {
    BrowserPage(tab: 1, origin: "https://x.test", url: "https://x.test/a", title: "Titulo",
                text: text, generation: 2, elements: elements, truncated: truncated)
}

// MARK: - Launch

@Test func launchDetection() {
    let pinned = BrowserPolicy.pinnedOrigins
    expect(!pinned.isEmpty, "hay al menos un origen fijado")
    let origin = pinned.first ?? ""
    expect(origin.hasPrefix("chrome-extension://") && origin.hasSuffix("/"), "forma del origen")
    expectEq(BrowserPolicy.launch(arguments: ["Companion", origin]), .nativeHost(origin: origin), "id fijado")
    expectEq(BrowserPolicy.launch(arguments: ["Companion", "chrome-extension://zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz/"]),
             .rejected, "id desconocido")
    expectEq(BrowserPolicy.launch(arguments: ["Companion", "chrome-extension://"]), .rejected, "origen vacio")
    expectEq(BrowserPolicy.launch(arguments: ["Companion", String(origin.dropLast())]), .rejected,
             "sin barra final no es el origen que manda Chrome")
    expectEq(BrowserPolicy.launch(arguments: ["Companion", "--native-host"]), .rejected,
             "bare --native-host is no longer a way into host mode")
    expectEq(BrowserPolicy.launch(arguments: ["Companion"]), .app, "lanzamiento normal")
    expectEq(BrowserPolicy.launch(arguments: []), .app, "sin argv")
    expectEq(BrowserPolicy.launch(arguments: ["Companion", "-NSDocumentRevisionsDebugMode", "YES"]), .app,
             "argumentos de Xcode no son host")
}

// MARK: - Sensitive fields and scrub

@Test func sensitiveClassification() {
    let sensitive: [(BrowserElement, String)] = [
        (element(inputType: "password"), "password"),
        (element(inputType: "PASSWORD"), "password en mayusculas"),
        (element(autocomplete: "cc-number"), "cc-number"),
        (element(autocomplete: "cc-exp"), "cc-exp"),
        (element(autocomplete: "CC-CSC"), "cc-csc en mayusculas"),
        (element(autocomplete: "section-pay billing cc-name"), "cc-* entre otros tokens"),
        (element(autocomplete: "one-time-code"), "one-time-code"),
        (element(autocomplete: "current-password"), "current-password"),
        (element(autocomplete: "new-password"), "new-password"),
    ]
    for (item, label) in sensitive { expect(BrowserPolicy.isSensitive(item), label) }
    let plain: [(BrowserElement, String)] = [
        (element(inputType: "text"), "texto"), (element(inputType: "email", autocomplete: "email"), "email"),
        (element(autocomplete: "off"), "off"), (element(), "sin atributos"),
        (element(autocomplete: "accept-language"), "no confundir con cc-"),
    ]
    for (item, label) in plain { expect(!BrowserPolicy.isSensitive(item), label) }
}

@Test func scrubRemovesSensitiveValuesEvenWhenSent() {
    let dirty = page([
        element(1, inputType: "password", value: "hunter2"),
        element(2, autocomplete: "cc-number", value: "4111111111111111"),
        element(3, autocomplete: "cc-csc", value: "123"),
        element(4, autocomplete: "one-time-code", value: "884211"),
        element(5, autocomplete: "current-password", value: "old"),
        element(6, autocomplete: "new-password", value: "new"),
        element(7, inputType: "text", value: "visible"),
    ])
    let clean = BrowserPolicy.scrub(dirty)
    expectEq(clean.elements.count, 7, "los campos sensibles siguen listados")
    for item in clean.elements.dropLast() { expectEq(item.value, nil, "valor de \(item.id) fuera") }
    expectEq(clean.elements.last?.value, "visible", "un campo normal conserva el valor")
    expect(!"\(clean)".contains("hunter2"), "el secreto no queda en ningun sitio")
}

@Test func scrubDropsHiddenElements() {
    let clean = BrowserPolicy.scrub(page([
        element(1, inputType: "hidden", value: "csrf-token"), element(2, inputType: "text"),
    ]))
    expectEq(clean.elements.map(\.id), [2], "hidden no se lista")
}

// MARK: - Verdicts

@Test func typeVerdictRefusesSensitiveFields() {
    for item in [element(inputType: "password"), element(autocomplete: "cc-number"),
                 element(autocomplete: "one-time-code")] {
        expectEq(BrowserPolicy.typeVerdict(item, text: "hola", said: "escribe hola"),
                 .refuse(BridgeCode.secureField), "campo sensible: secure_field")
    }
    expectEq(BrowserPolicy.typeVerdict(element(), text: "hola", said: ""), .act, "texto llano actua")
    expectEq(BrowserPolicy.typeVerdict(element(), text: "https://evil.test/x", said: "escribe hola"), .ask,
             "una direccion que nadie dijo pregunta")
    expectEq(BrowserPolicy.typeVerdict(element(), text: "https://evil.test/x", said: "escribe https://evil.test/x"),
             .act, "una direccion dicha actua")
}

/// P3: an option is a value typed with the page's words and, through the list's change handler, a
/// button in disguise, so it answers to both rules.
@Test func selectVerdictJudgesTheOptionAsTypedTextAndAsAClick() {
    let list = element(role: "combobox", label: "Pais", inputType: "select")
    expectEq(BrowserPolicy.selectVerdict(list, option: "México", said: ""), .act, "una opcion llana actua")
    expectEq(BrowserPolicy.selectVerdict(list, option: "Eliminar todo", said: ""), .ask,
             "una opcion destructiva pregunta")
    expectEq(BrowserPolicy.selectVerdict(list, option: "https://evil.test/x", said: ""), .ask,
             "una direccion que nadie dijo pregunta")
    let bulk = element(role: "combobox", label: "Eliminar", inputType: "select")
    expectEq(BrowserPolicy.selectVerdict(bulk, option: "Cuenta 1", said: ""), .ask,
             "la lista que borra pregunta por cualquier opcion")
    expectEq(BrowserPolicy.selectVerdict(list, option: "   ", said: ""), .ask, "una opcion sin palabras pregunta")
    expectEq(BrowserPolicy.selectVerdict(list, option: "Eliminar todo", said: "elimina todo"), .act,
             "pedida con una palabra de la misma familia actua")
    let month = element(role: "combobox", label: "Mes", inputType: "select", autocomplete: "cc-exp-month")
    expectEq(BrowserPolicy.selectVerdict(month, option: "02", said: "elige 02"), .refuse(BridgeCode.secureField),
             "una lista sensible se rechaza")
}

// MARK: - P4: press

private func field(submit: String?, inputType: String = "text", frameOrigin: String? = nil) -> BrowserElement {
    BrowserElement(id: 5, frame: 0, role: "textbox", label: "Mensaje", context: "", inputType: inputType,
                   autocomplete: nil, value: "", frameOrigin: frameOrigin, submit: submit)
}

private func press(_ key: String, _ target: BrowserElement?, said: String = "") -> HandsVerdict {
    BrowserPolicy.pressVerdict(key: key, element: target, said: said, pageOrigin: "https://x.test")
}

/// The pin from the approved plan: an Enter that submits "Send" asks; Escape never does.
@Test func anEnterThatSubmitsSendAsksAndEscapeNeverDoes() {
    expectEq(press("Enter", field(submit: "Send")), .ask, "Enter en un campo cuyo formulario envia: pregunta")
    expectEq(press("Enter", field(submit: "Enviar")), .ask, "tambien en espanol")
    expectEq(press("Enter", field(submit: "Enviar"), said: "envialo"), .act, "pedido con su palabra: actua")
    for target in [nil, field(submit: "Send"), element(role: "button", label: "Eliminar")] {
        expectEq(press("Escape", target), .act, "Escape nunca pregunta")
    }
}

@Test func enterAndSpaceOnAControlAreJudgedAsAClick() {
    expectEq(press("Enter", element(role: "button", label: "Guardar")), .act, "un boton llano actua")
    expectEq(press("Enter", element(role: "button", label: "Eliminar")), .ask, "uno destructivo pregunta")
    expectEq(press("Space", element(role: "button", label: "Enviar")), .ask, "Space activa igual que Enter")
    expectEq(press("Space", element(role: "checkbox", label: "Recordarme")), .act, "una casilla llana actua")
    expectEq(press("Enter", element(role: "button", label: "")), .ask, "sin etiqueta pregunta, como un clic")
}

@Test func anEnterInAFieldWithoutAKnownSubmitAsks() {
    expectEq(press("Enter", field(submit: "Buscar")), .act, "un formulario que busca actua")
    expectEq(press("Enter", field(submit: nil)), .ask, "fuera de un formulario (un chat) pregunta")
    expectEq(press("Enter", field(submit: "")), .ask, "un formulario sin boton con nombre pregunta")
    expectEq(press("Enter", field(submit: "Buscar", inputType: "textarea")), .act, "un textarea igual")
    expectEq(press("Space", field(submit: "Enviar")), .act, "Space en un campo escribe un espacio")
}

@Test func enterOrSpaceWithoutAnElementAsks() {
    expectEq(press("Enter", nil), .ask, "Enter en el foco que nadie leyo pregunta")
    expectEq(press("Space", nil), .ask, "Space tambien")
}

@Test func backspaceAndDeleteOnlyActInsideATextField() {
    expectEq(press("Backspace", field(submit: nil)), .act, "borrar caracteres en un campo actua")
    expectEq(press("Delete", field(submit: nil)), .act, "Delete en un campo tambien")
    expectEq(press("Delete", nil), .ask, "Delete en el foco puede borrar un elemento: pregunta")
    expectEq(press("Backspace", element(role: "row", label: "Correo de Ana")), .ask, "fuera de un campo pregunta")
}

@Test func movingKeysNeverAsk() {
    for key in ["Tab", "Shift+Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End",
                "PageUp", "PageDown"] {
        expectEq(press(key, nil), .act, "\(key) en el foco actua")
        expectEq(press(key, field(submit: "Send")), .act, "\(key) en un campo actua")
    }
}

/// Typing refuses a secret field; a key that writes or erases there is typing by other means.
@Test func spaceBackspaceAndDeleteAreRefusedInASensitiveField() {
    let password = BrowserElement(id: 5, frame: 0, role: "textbox", label: "Clave", context: "", inputType: "password",
                                  autocomplete: nil, value: nil, submit: "Entrar")
    let card = BrowserElement(id: 6, frame: 0, role: "textbox", label: "Tarjeta", context: "", inputType: "text",
                              autocomplete: "cc-number", value: nil, submit: "Pagar")
    for target in [password, card] {
        for key in ["Space", "Backspace", "Delete"] {
            expectEq(press(key, target, said: "borra"), .refuse(BridgeCode.secureField), "\(key) en \(target.label)")
        }
        expectEq(press("Tab", target), .act, "salir del campo con Tab actua")
    }
    expectEq(press("Enter", password), .act, "Enter en la clave pulsa Entrar, que no es destructivo")
    expectEq(press("Enter", card), .ask, "Enter en la tarjeta pulsa Pagar: pregunta")
}

/// Chromium submits the form on Enter in a checkbox, radio, date or range too: the button decides.
@Test func anEnterOnAnyControlOfAFormIsJudgedByItsButton() {
    for type in ["checkbox", "radio", "date", "range"] {
        let control = BrowserElement(id: 5, frame: 0, role: type == "checkbox" ? "checkbox" : "textbox", label: "Recordarme",
                                     context: "", inputType: type, autocomplete: nil, value: nil, submit: "Enviar pago")
        expectEq(press("Enter", control), .ask, "Enter en \(type) pulsa Enviar pago: pregunta")
    }
    let box = BrowserElement(id: 5, frame: 0, role: "checkbox", label: "Recordarme", context: "", inputType: "checkbox",
                             autocomplete: nil, value: nil, submit: "Enviar pago")
    expectEq(press("Space", box), .act, "Space en una casilla la marca, no envia")
    let submit = BrowserElement(id: 6, frame: 0, role: "button", label: "Guardar", context: "", inputType: "submit",
                                autocomplete: nil, value: nil, submit: "Enviar pago")
    expectEq(press("Enter", submit), .act, "un boton de envio se juzga por su propia etiqueta")
}

/// An arrow changes a list's value or a radio group's choice, which a change handler may act on.
@Test func anArrowOnAListOrARadioIsJudgedByItsLabel() {
    let bulk = BrowserElement(id: 5, frame: 0, role: "combobox", label: "Eliminar", context: "", inputType: "select",
                              autocomplete: nil, value: nil)
    expectEq(press("ArrowDown", bulk), .ask, "una lista que borra pregunta")
    let country = BrowserElement(id: 6, frame: 0, role: "combobox", label: "Pais", context: "", inputType: "select",
                                 autocomplete: nil, value: nil)
    expectEq(press("ArrowDown", country), .act, "una lista llana actua")
    expectEq(press("Tab", bulk), .act, "Tab solo mueve el foco")
}

/// A contenteditable reports no input type, only its role.
@Test func aContentEditableIsATextField() {
    let editor = BrowserElement(id: 7, frame: 0, role: "textbox", label: "Mensaje", context: "", inputType: nil,
                                autocomplete: nil, value: nil, submit: nil)
    expectEq(press("Backspace", editor), .act, "borrar en el editor actua")
    expectEq(press("Space", editor), .act, "un espacio en el editor actua")
    expectEq(press("Enter", editor), .ask, "Enter en un editor fuera de un formulario (un chat) pregunta")
    let fake = BrowserElement(id: 8, frame: 0, role: "textbox", label: "Borrar", context: "", inputType: "button",
                              autocomplete: nil, value: nil)
    expectEq(press("Delete", fake), .ask, "un rol textbox con tipo button no es un campo")
}

@Test func anyKeyOnAnElementOfAForeignFrameAsks() {
    expectEq(press("ArrowDown", field(submit: nil, frameOrigin: "https://ads.test")), .ask, "frame ajeno pregunta")
}

@Test func handsGateTypeVerdictKeepsTheAddressRule() {
    expectEq(HandsGate.typeVerdict(text: "hola", said: ""), .act, "texto llano")
    expectEq(HandsGate.typeVerdict(text: "www.evil.test", said: "escribe hola"), .ask, "direccion no dicha")
    expectEq(HandsGate.typeVerdict(text: "www.evil.test", said: "escribe www.evil.test"), .act, "direccion dicha")
    expectEq(HandsGate.typeVerdict(text: "hola\u{1B}", said: ""), .act, "el control suelto es ruido")
    let call = ToolCallRef(id: "1", name: "type_text", arguments: #"{"text":"www.evil.test"}"#)
    expectEq(HandsGate.verdict(call, commandApp: false, said: "escribe hola"), .ask, "verdict sigue igual")
}

@Test func clickVerdictAsksOnDestructiveLabels() {
    expectEq(BrowserPolicy.clickVerdict(element(role: "button", label: "Eliminar"), said: "abre el correo"), .ask,
             "Eliminar no dicho")
    expectEq(BrowserPolicy.clickVerdict(element(role: "button", label: "Eliminar"), said: "elimina ese correo"), .act,
             "Eliminar dicho")
    expectEq(BrowserPolicy.clickVerdict(element(role: "button", label: "Guardar"), said: ""), .act, "Guardar")
    expectEq(BrowserPolicy.clickVerdict(element(role: "button", label: ""), said: ""), .ask, "icono sin etiqueta")
    expectEq(BrowserPolicy.clickVerdict(element(role: "button", label: "Delete"), said: "open it"), .ask, "Delete no dicho")
}

private func navigate(_ from: String?, _ raw: String, said: String = "") -> Result<HandsVerdict, ContractError> {
    BrowserPolicy.navigateVerdict(from: from, to: raw, said: said)
}

@Test func navigateVerdictRefusesNonHTTPSchemes() {
    for raw in ["javascript:alert(1)", "data:text/html,<b>x</b>", "file:///etc/passwd",
                "chrome://settings", "chrome-extension://abc/x.html", "about:blank", "ftp://x.test/"] {
        guard case .failure(let error) = navigate("https://x.test", raw) else {
            expect(false, "\(raw): debia ser error")
            continue
        }
        expect(["denied_url", "invalid_args"].contains(error.code), "\(raw): \(error.code)")
    }
    guard case .failure(let scheme) = navigate(nil, "javascript:alert(1)", said: "javascript:alert(1)") else {
        expect(false, "decirlo no lo hace valido")
        return
    }
    expectEq(scheme.code, "denied_url", "denied_url")
    guard case .failure = navigate("https://x.test", "") else {
        expect(false, "vacio")
        return
    }
}

@Test func navigateVerdictChecksOrigin() {
    expectEq(navigate("https://x.test", "https://x.test/other?q=1"), .success(.act), "mismo origen")
    expectEq(navigate("https://x.test", "https://X.TEST/a"), .success(.act), "el host no distingue mayusculas")
    expectEq(navigate("https://x.test:8443", "https://x.test:8443/a"), .success(.act), "mismo puerto")
    expectEq(navigate("https://x.test", "https://x.test:8443/a"), .success(.ask), "otro puerto es otro origen")
    expectEq(navigate("https://x.test", "http://x.test/a"), .success(.ask), "otro esquema es otro origen")
    expectEq(navigate("https://x.test", "https://evil.test/"), .success(.ask), "otro origen no dicho")
    expectEq(navigate("https://x.test", "https://sub.x.test/"), .success(.ask), "subdominio es otro origen")
    expectEq(navigate("https://x.test", "https://evil.test/", said: "abre evil.test"), .success(.act),
             "otro origen dicho")
    expectEq(navigate(nil, "https://evil.test/"), .success(.ask), "sin origen actual pregunta")
    expectEq(navigate("https://attacker.github.io", "https://attacker.github.io/x"), .success(.act), "mismo origen github.io")
    expectEq(navigate("https://x.test", "https://attacker.github.io/", said: "abre github"), .success(.ask),
             "la marca no cubre un subdominio ajeno")
}

// MARK: - Render

@Test func renderListsElementsAndScrubs() {
    let text = BrowserPolicy.render(page([
        element(1, role: "button", label: "Guardar"),
        element(2, inputType: "password", value: "hunter2"),
        element(3, label: "Mail", value: "a@b.c"),
    ], text: "Cuerpo de la pagina"), maxBytes: 4_000)
    expect(text.contains("Titulo"), "titulo")
    expect(text.contains("https://x.test/a"), "url")
    expect(text.contains("[1]") && text.contains("Guardar"), "elemento 1")
    expect(text.contains("[3]") && text.contains("a@b.c"), "valor normal")
    expect(!text.contains("hunter2"), "render tambien filtra")
    expect(text.contains("Cuerpo de la pagina"), "texto")
    expect(!text.contains("truncated") && !text.contains("recortad"), "sin aviso si cabe")
}

@Test func renderShowsElementStatesAfterTheLabel() {
    var trigger = element(1, role: "button", label: "Pais")
    trigger.states = ["collapsed", "haspopup"]
    var plain = element(2, role: "button", label: "Guardar")
    plain.states = []
    let text = BrowserPolicy.render(page([trigger, plain]), maxBytes: 4_000)
    expect(text.contains(#"[1] button "Pais" (collapsed, haspopup)"#), "states inline: \(text)")
    expect(text.contains(#"[2] button "Guardar""#) && !text.contains(#""Guardar" ("#), "no empty parentheses")
}

@Test func renderRespectsMaxBytesAndMarksTruncation() {
    let long = String(repeating: "\u{00E1}\u{1F600}", count: 5_000)
    for language in AppLanguage.allCases {
        let text = BrowserPolicy.render(page([element(1, label: "x")], text: long), maxBytes: 500, language: language)
        expect(text.utf8.count <= 500, "\(language): cabe en 500 bytes (\(text.utf8.count))")
        expect(text.hasSuffix(BrowserCopy.truncationNote(language)), "\(language): termina con el aviso")
    }
    let flagged = BrowserPolicy.render(page([], text: "corto", truncated: true), maxBytes: 4_000)
    expect(flagged.hasSuffix(BrowserCopy.truncationNote(.en)), "el recorte de la extension tambien se avisa")
    let tiny = BrowserPolicy.render(page([], text: long), maxBytes: 8)
    expect(tiny.utf8.count <= 8, "tope diminuto no revienta")
}

// H-4(a): a cut read must say how to reach what was cut, or the model reads "not listed" as
// "not there" and decides the menu never opened.
@Test func theCutNoteSaysHowToReachWhatWasCut() {
    for language in AppLanguage.allCases {
        let note = BrowserCopy.truncationNote(language)
        expect(note.contains("selector"), "\(language): names the selector route")
        expect(note.contains("[role=menu]") && note.contains("[role=dialog]"), "\(language): names the open menu or dialog")
    }
}

@Test func renderIsValidUTF8AtTheCut() {
    for cap in 200...230 {
        let text = BrowserPolicy.render(page([], text: String(repeating: "\u{1F600}", count: 300)), maxBytes: cap)
        expect(text.utf8.count <= cap, "cap \(cap)")
        expect(!text.contains("\u{FFFD}"), "cap \(cap): sin caracteres rotos")
    }
}

// MARK: - Tools and copy

@Test func browserToolShape() {
    expectEq(BrowserTool.allCases.map(\.rawValue),
             ["browser_tabs", "browser_read", "browser_click", "browser_double_click", "browser_right_click",
              "browser_type", "browser_select", "browser_scroll", "browser_hover", "browser_press", "browser_navigate", "browser_open",
              "browser_take", "browser_release"], "nombres")
    expectEq(BrowserTool.allCases.filter(\.isWrite),
             [.click, .doubleClick, .rightClick, .type, .select, .scroll, .hover, .press, .navigate, .open, .take, .release],
             "escrituras")
    expectEq(BrowserTool.allCases.filter(\.isClick), [.click, .doubleClick, .rightClick],
             "H-7 P5a: las tres pulsaciones comparten la puerta del clic")
    expectEq(BrowserTool.allCases.filter(\.skipsApproval), [.scroll, .hover],
             "H-7 P5b: desplazar y pasar el puntero no cambian la pagina, no piden hoja")
    for language in AppLanguage.allCases {
        for tool in BrowserTool.allCases {
            let spec = tool.spec(language)
            expectEq(spec.name, tool.rawValue, "\(tool) \(language): nombre")
            expect(!spec.description.isEmpty, "\(tool) \(language): descripcion")
            expect(spec.description.hasSuffix(BrowserCopy.toolDataSuffix(language)), "\(tool) \(language): datos, no instrucciones")
            expect(Set(spec.required).isSubset(of: Set(spec.properties.map(\.name))), "\(tool) \(language): required existe")
        }
    }
    expectEq(BrowserTool.click.spec(.en).required, ["tab", "element"], "click pide tab y element")
    expectEq(BrowserTool.type.spec(.en).required, ["tab", "element", "text"], "type")
    expectEq(BrowserTool.navigate.spec(.en).required, ["tab", "url"], "navigate")
    expectEq(BrowserTool.read.spec(.en).required, ["tab"], "read: selector opcional")
    expect(BrowserTool.tabs.spec(.en).description != BrowserTool.tabs.spec(.es).description, "es != en")
}

@Test func browserCopyIsBilingual() {
    expect(BrowserCopy.truncationNote(.en) != BrowserCopy.truncationNote(.es), "aviso es != en")
    for code in [BridgeCode.notConnected, BridgeCode.staleId, BridgeCode.secureField, BridgeCode.timeout,
                 BridgeCode.busy, BridgeCode.invalidArgs, BridgeCode.selectorNoMatch, BridgeCode.selectorHidden] {
        let en = BrowserCopy.failure(code: code, .en)
        let es = BrowserCopy.failure(code: code, .es)
        expect(!en.isEmpty && !es.isEmpty && en != es, "\(code): mensaje en ambos idiomas")
    }
    expect(BrowserCopy.failure(code: "unheard_of", .en).contains("unheard_of"), "codigo desconocido se nombra")
}

// An empty selector read names why and what to do next, in both languages.
@Test func aSelectorReadThatFindsNothingNamesTheNextStep() {
    for code in ["selector_no_match", "selector_hidden"] {
        let en = BrowserCopy.failure(code: code, .en)
        let es = BrowserCopy.failure(code: code, .es)
        expect(!en.contains(code) && !es.contains(code), "\(code): has its own copy, not the unknown-code fallback")
        expect(en != es, "\(code): en and es differ")
        expect(en.contains("read again") && en.contains("without a selector"), "\(code) en: \(en)")
        expect(es.contains("vuelve a leer") && es.contains("sin selector"), "\(code) es: \(es)")
    }
    expect(BrowserCopy.failure(code: "selector_no_match", .en) != BrowserCopy.failure(code: "selector_hidden", .en),
           "nothing found and found but hidden read differently")
}
