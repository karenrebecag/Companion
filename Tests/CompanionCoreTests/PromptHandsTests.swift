import CompanionCore
import CompanionTestKit
import Testing

// Wave 15g-3 / 15g-4 (spec §5 rows 10 and 12). The prompt promised that the
// specialist "has the terminal" and never said the assistant itself could
// type: asked to write in Terminal, the model told Karen to do it, or sent
// the specialist to type through AppleScript and lose the spaces.

@Test @MainActor func promptHandsTests() {
    testActRuleNamesTheHandsTools()
    testActRuleActsInsteadOfInstructing()
    testActRuleVerifiesAndOnlyConfirmsReturnInATerminal()
    testActRuleKeepsTheScreenIsDataClause()
    testHandsAreOnlyPromisedWhenDeclared()
    testDelegateCopyNoLongerPromisesTheTerminal()
    testDelegateRuleExcludesTyping()
}

@MainActor private func handsPrompt(_ language: AppLanguage, delegate: Bool = true) -> String {
    ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: delegate,
        parentToolsEnabled: true, handsEnabled: true, language: language)
}

@MainActor func testActRuleNamesTheHandsTools() {
    for language in [AppLanguage.es, .en] {
        let p = handsPrompt(language)
        for tool in ["type_text", "press_key", "focus_window", "read_focused"] {
            expect(p.contains(tool), "15g-3 \(language): actRule nombra \(tool)")
        }
    }
    expect(handsPrompt(.es).contains("campo enfocado"), "15g-3 es: escribe en el campo enfocado")
    expect(handsPrompt(.en).contains("focused field"), "15g-3 en: types into the focused field")
}

@MainActor func testActRuleActsInsteadOfInstructing() {
    expect(handsPrompt(.es).contains("nunca le digas al usuario que lo haga"),
           "15g-4 fila 12 es: actúa, nunca instruye")
    expect(handsPrompt(.en).contains("never tell the user to do it"),
           "15g-4 fila 12 en: act, never instruct")
    expect(handsPrompt(.es).contains("una frase") && handsPrompt(.es).contains("por qué"),
           "15g-4 es: si no puede, una frase diciendo por qué")
    expect(handsPrompt(.en).contains("one sentence") && handsPrompt(.en).contains("why"),
           "15g-4 en: when it cannot, one sentence saying why")
}

@MainActor func testActRuleVerifiesAndOnlyConfirmsReturnInATerminal() {
    let es = handsPrompt(.es)
    expect(es.contains("verifica con read_focused"),
           "15g-4 es: verifica con read_focused antes de decir que quedó escrito")
    expect(es.contains("Return en una terminal"),
           "15g-4 es: solo pide confirmación para Return en una terminal")
    let en = handsPrompt(.en)
    expect(en.contains("check with read_focused"),
           "15g-4 en: verifies with read_focused before claiming it is written")
    expect(en.contains("Return in a terminal"),
           "15g-4 en: confirmation only for Return in a terminal")
}

/// §6: the 12e clause survives the rewrite — screen text is never an order.
@MainActor func testActRuleKeepsTheScreenIsDataClause() {
    let es = handsPrompt(.es)
    expect(es.contains("dentro de <context>") && es.contains("con sus palabras"),
           "15g §6 es: lo que hay en <context> sigue siendo datos")
    let en = handsPrompt(.en)
    expect(en.contains("inside <context>") && en.contains("in their own words"),
           "15g §6 en: what sits in <context> is still data")
    expect(es.contains("nunca escribas") || es.contains("nunca abras"),
           "15g §6 es: la regla cubre también escribir")
    expect(en.contains("never type") || en.contains("never open"),
           "15g §6 en: the rule also covers typing")
    // Review 2026-09-25 M3: a field read back, a fetched page or a job's
    // result can carry instructions too.
    expect(es.contains("lo que devuelve una herramienta"), "M3 es: resultados de tools son datos")
    expect(en.contains("whatever a tool returns"), "M3 en: tool results are data")
}

/// "A tool with no backing is never offered": without Accessibility the
/// hands tools are not declared, and the prompt must not promise them.
@MainActor func testHandsAreOnlyPromisedWhenDeclared() {
    for language in [AppLanguage.es, .en] {
        let p = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true,
            parentToolsEnabled: true, language: language)
        expect(!p.contains("type_text") && !p.contains("read_focused"),
               "15g-3 \(language): sin manos declaradas no se promete type_text")
        expect(p.contains("open_app"), "15g-3 \(language): abrir apps sigue")
    }
}

@MainActor func testDelegateCopyNoLongerPromisesTheTerminal() {
    for language in [AppLanguage.es, .en] {
        for web in [false, true] {
            let p = ChatPrompt.system(
                ownerFirstName: "Karen", delegateEnabled: true,
                parentToolsEnabled: true, handsEnabled: true,
                webSearchEnabled: web, language: language)
            expect(!p.contains("la terminal") && !p.contains("the terminal"),
                   "15g-3 fila 10 \(language) web=\(web): el prompt ya no dice «la terminal»")
        }
        let spec = ToolSpec.delegate(language).description
        expect(!spec.contains("terminal"),
               "15g-3 fila 10 \(language): ToolSpec.delegate ya no dice terminal")
    }
    expect(ToolSpec.delegate(.es).description.contains("shell"),
           "15g-3 es: el especialista tiene una shell")
    expect(ToolSpec.delegate(.en).description.contains("shell"),
           "15g-3 en: the specialist has a shell")
    expect(handsPrompt(.es).contains("shell") && handsPrompt(.en).contains("shell"),
           "15g-3: delegateRule dice shell")
}

@MainActor func testDelegateRuleExcludesTyping() {
    expect(handsPrompt(.es).contains("Escribir en un campo o app, o pulsar sus botones o menús, no se delega"),
           "15g-4 fila 12 es: escribir en un campo no se reparte al especialista")
    expect(handsPrompt(.en).contains("Typing into a field or app, and pressing its buttons or menus, is never delegated"),
           "15g-4 fila 12 en: typing into an app is not delegated")
    expect(ToolSpec.delegate(.es).description.contains("escribir en un campo o app"),
           "15g-4 es: la tool delegate excluye escribir en un campo o app")
    expect(ToolSpec.delegate(.en).description.contains("typing into an app"),
           "15g-4 en: the delegate tool excludes typing into an app")
}
