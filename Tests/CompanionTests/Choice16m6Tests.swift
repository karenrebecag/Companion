import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 16m-6: the question with options. What the model may put in the fence,
// how a pick is derived from the transcript, what the keys do and what the
// card measures are decided in pure code and pinned here before any view.

private func fence(_ json: String) -> String { "```companion:choice\n\(json)\n```" }

private let sample = #"{"question":"¿Cómo lo quieres?","options":[{"label":"Rápido","detail":"5 minutos"},{"label":"Completo"}]}"#

// MARK: - Core: the fence

@Test func choiceBlockParsingTests() {
    testAValidFenceBecomesAChoice()
    testBareStringsAreOptions()
    testItRidesTheAnswerBlocks()
    testBrokenFencesStayVisibleAsCode()
    testTheCapsAreNamedAndExact()
    testModelTextIsSanitized()
    testOrdinaryCharactersSurvive()
}

func testAValidFenceBecomesAChoice() {
    let block = CompanionBlocks.choice(sample)
    expectEq(block?.question, "¿Cómo lo quieres?", "16m-6: la pregunta")
    expectEq(block?.options, [
        ChoiceBlock.Option(label: "Rápido", detail: "5 minutos"),
        ChoiceBlock.Option(label: "Completo"),
    ], "16m-6: opciones con etiqueta y detalle opcional")
    expectEq(CompanionBlocks.choiceLanguage, "companion:choice", "16m-6: la fence sigue la convención companion:*")
}

func testBareStringsAreOptions() {
    let block = CompanionBlocks.choice(#"{"question":"¿Cuál?","options":["A","B","C"]}"#)
    expectEq(block?.options.map(\.label), ["A", "B", "C"], "16m-6: un modelo chico puede mandar solo cadenas")
    expectEq(block?.options.map(\.detail), [nil, nil, nil], "16m-6: sin detalle")
}

func testItRidesTheAnswerBlocks() {
    let blocks = AnswerBlocks.blocks(from: "Te dejo elegir.\n\n" + fence(sample))
    expectEq(blocks.count, 2, "16m-6: prosa y pregunta")
    if blocks.count == 2 {
        expectEq(blocks[1], .choice(ChoiceBlock(question: "¿Cómo lo quieres?", options: [
            .init(label: "Rápido", detail: "5 minutos"), .init(label: "Completo"),
        ])), "16m-6: el bloque llega tipado")
    }
    expect(!AnswerBlocks.isRich(blocks), "16m-6: la pregunta vive en la isla, no abre el popup")
}

func testBrokenFencesStayVisibleAsCode() {
    let bad: [(String, String)] = [
        ("no es json", "not json"),
        ("sin pregunta", #"{"options":["A","B"]}"#),
        ("pregunta en blanco", #"{"question":"  ","options":["A","B"]}"#),
        ("una sola opción", #"{"question":"¿?","options":["A"]}"#),
        ("opciones no es lista", #"{"question":"¿?","options":"A,B"}"#),
        ("etiqueta vacía", #"{"question":"¿?","options":["A",""]}"#),
        ("etiqueta que queda vacía al sanear", #"{"question":"¿?","options":["A","​‮"]}"#),
        ("etiqueta repetida", #"{"question":"¿?","options":["Sí","sí "]}"#),
        ("opción que no es texto ni objeto", #"{"question":"¿?","options":["A",7]}"#),
        ("objeto sin etiqueta", #"{"question":"¿?","options":["A",{"detail":"x"}]}"#),
    ]
    for (name, json) in bad {
        expect(CompanionBlocks.choice(json) == nil, "16m-6: \(name) no es pregunta")
        let blocks = AnswerBlocks.blocks(from: fence(json))
        expect(blocks.count == 1 && !blocks[0].isChoice, "16m-6: \(name) queda como código visible")
        if case .code(let language, _)? = blocks.first {
            expectEq(language, CompanionBlocks.choiceLanguage, "16m-6: \(name) conserva su fence")
        } else {
            expect(false, "16m-6: \(name) debía caer a código")
        }
    }
    let huge = #"{"question":"¿?","options":["A","B"],"pad":""# + String(repeating: "x", count: CompanionBlocks.maxFenceBytes) + #""}"#
    expect(CompanionBlocks.choice(huge) == nil, "16m-6: una fence pasada del tope de bytes se rechaza antes de parsear")
}

func testTheCapsAreNamedAndExact() {
    expectEq([ChoiceBlock.minOptions, ChoiceBlock.maxOptions], [2, 6], "16m-6: de 2 a 6 opciones")
    expectEq([ChoiceBlock.maxQuestion, ChoiceBlock.maxLabel, ChoiceBlock.maxDetail], [200, 80, 160],
             "16m-6: topes de pregunta, etiqueta y detalle")
    func options(_ n: Int) -> String {
        (1 ... n).map { "\"Opción \($0)\"" }.joined(separator: ",")
    }
    let max = CompanionBlocks.choice(#"{"question":"¿?","options":[\#(options(ChoiceBlock.maxOptions))]}"#)
    expectEq(max?.options.count, ChoiceBlock.maxOptions, "16m-6: el tope exacto entra")
    expect(CompanionBlocks.choice(#"{"question":"¿?","options":[\#(options(ChoiceBlock.maxOptions + 1))]}"#) == nil,
           "16m-6: una más se rechaza en vez de tirar opciones en silencio")
    let min = CompanionBlocks.choice(#"{"question":"¿?","options":[\#(options(ChoiceBlock.minOptions))]}"#)
    expectEq(min?.options.count, ChoiceBlock.minOptions, "16m-6: el mínimo entra")

    let long = String(repeating: "ñ", count: 500)
    let clipped = CompanionBlocks.choice(#"{"question":"\#(long)","options":[{"label":"\#(long)","detail":"\#(long)"},"B"]}"#)
    expectEq(clipped?.question.count, ChoiceBlock.maxQuestion, "16m-6: la pregunta se recorta")
    expectEq(clipped?.options.first?.label.count, ChoiceBlock.maxLabel, "16m-6: la etiqueta se recorta")
    expectEq(clipped?.options.first?.detail?.count, ChoiceBlock.maxDetail, "16m-6: el detalle se recorta")
}

func testModelTextIsSanitized() {
    let block = CompanionBlocks.choice(
        #"{"question":"¿Borrar‮ todo?\n\ndos líneas","options":[{"label":"Sí​,\n borrar","detail":"\u0007irreversible"},"No"]}"#)
    expectEq(block?.question, "¿Borrar todo? dos líneas", "16m-6: sin controles bidi y en una línea")
    expectEq(block?.options.first?.label, "Sí, borrar", "16m-6: la etiqueta que se enviará no lleva invisibles ni saltos")
    expectEq(block?.options.first?.detail, "irreversible", "16m-6: el detalle sin controles")
    let blankDetail = CompanionBlocks.choice(#"{"question":"¿?","options":[{"label":"A","detail":"  "},"B"]}"#)
    expectEq(blankDetail?.options.first?.detail, nil, "16m-6: un detalle en blanco no se pinta")
}

func testOrdinaryCharactersSurvive() {
    let block = CompanionBlocks.choice(
        #"{"question":"¿'; DROP TABLE x;--?","options":["👨‍👩‍👧 Familia","<b>\"comillas\"</b>","日本語 — ñ"]}"#)
    expectEq(block?.options.map(\.label), ["👨‍👩‍👧 Familia", "<b>\"comillas\"</b>", "日本語 — ñ"],
             "16m-6: emoji con ZWJ, marcado y Unicode pasan como texto")
    expectEq(block?.question, "¿'; DROP TABLE x;--?", "16m-6: metacaracteres SQL son solo texto")
}

// MARK: - Core: the pick

@Test func choiceResolutionTests() {
    let block = ChoiceBlock(question: "¿?", options: [.init(label: "Rápido"), .init(label: "Completo")])
    expectEq(block.resolution(reply: nil), .open, "16m-6: sin respuesta sigue abierta")
    expectEq(block.resolution(reply: "  \n"), .open, "16m-6: una respuesta en blanco no responde")
    expectEq(block.resolution(reply: "Completo"), .chosen(1), "16m-6: la etiqueta enviada marca la elegida")
    expectEq(block.resolution(reply: " Completo \n"), .chosen(1), "16m-6: el espacio no la pierde")
    expectEq(block.resolution(reply: "lo quiero completo"), .passed,
             "16m-6: otra respuesta la deja respondida sin marca")
}

// MARK: - Core: voice and prompt

@Test @MainActor func choiceSpeechAndPromptTests() {
    expect(SpeechBudget.hasCard(in: "¿Cuál?\n" + fence(sample)),
           "16m-6: la pregunta cuenta como tarjeta para el presupuesto de voz")
    expect(!SpeechBudget.hasCard(in: "¿Cuál?\n" + fence(#"{"question":"¿?","options":["A"]}"#)),
           "16m-6: una pregunta rota se ve como código y la voz no se acorta por ella")
    let spoken = SpeechBudget.brief(
        "Tengo dos caminos y los dos sirven. Uno es rápido. El otro es completo. Dime cuál prefieres ahora mismo por favor.",
        hasCard: SpeechBudget.hasCard(in: "x\n" + fence(sample)))
    expect(spoken.split(separator: " ").count <= SpeechBudget.maxWords, "16m-6: con pregunta, la voz dice una línea")
    expectEq(IslandReplyText.spoken(from: "¿Cuál prefieres?\n" + fence(sample)), "¿Cuál prefieres?",
             "16m-6: la isla nunca pinta el JSON de la fence")

    for language in [AppLanguage.en, .es] {
        let vocabulary = CardVocabulary.text(language)
        expect(vocabulary.contains(CompanionBlocks.choiceLanguage), "\(language): el vocabulario enseña la fence")
        expect(vocabulary.contains("\(ChoiceBlock.maxOptions)"), "\(language): y el tope de opciones")
        let rule = language == .en ? "decides the next step" : "decide el siguiente paso"
        expect(vocabulary.contains(rule), "\(language): y cuándo usarla")
    }
}

// MARK: - UI: transcript, keys, copy, metrics

@MainActor private func message(_ role: TurnRole, _ text: String, status: Bool = false) -> ChatMessage {
    ChatMessage(role: role, isStatus: status, text: text)
}

@Test @MainActor func islandChoiceTranscriptTests() {
    let ask = message(.assistant, "¿Cuál?\n" + fence(sample))
    expectEq(IslandChoice.block(in: ask)?.options.count, 2, "16m-6: la isla saca la pregunta del mensaje")
    expect(IslandChoice.block(in: message(.assistant, "hola")) == nil, "16m-6: sin fence no hay pregunta")
    let twice = message(.assistant, fence(sample) + "\n\n" + fence(#"{"question":"otra","options":["X","Y"]}"#))
    expectEq(IslandChoice.block(in: twice)?.question, "¿Cómo lo quieres?", "16m-6: una pregunta por turno, la primera")

    let block = IslandChoice.block(in: ask) ?? ChoiceBlock(question: "", options: [])
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id, in: [ask]), .open, "16m-6: recién hecha, abierta")
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id, in: [ask, message(.assistant, "nota", status: true)]),
             .open, "16m-6: una línea de estado no responde")
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id, in: [ask, message(.user, "Rápido")]),
             .chosen(0), "16m-6: el siguiente mensaje de la usuaria marca la elegida")
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id, in: [ask, message(.user, "mejor otra cosa")]),
             .passed, "16m-6: tecleó otra cosa: respondida, sin marca")
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id,
                                     in: [message(.user, "Completo"), ask]),
             .open, "16m-6: un mensaje anterior no cuenta")
    expectEq(IslandChoice.resolution(of: block, messageID: UUID(), in: [ask, message(.user, "Rápido")]),
             .open, "16m-6: un id ajeno no responde nada")
}

@Test @MainActor func islandChoiceKeyTests() {
    typealias K = IslandChoiceKeys
    expectEq(K.outcome(for: .down, focused: nil, count: 3), .focus(0), "16m-6: flecha abajo entra por la primera")
    expectEq(K.outcome(for: .up, focused: nil, count: 3), .focus(2), "16m-6: flecha arriba entra por la última")
    expectEq(K.outcome(for: .down, focused: 0, count: 3), .focus(1), "16m-6: baja")
    expectEq(K.outcome(for: .down, focused: 2, count: 3), .focus(0), "16m-6: da la vuelta abajo")
    expectEq(K.outcome(for: .up, focused: 0, count: 3), .focus(2), "16m-6: da la vuelta arriba")
    expectEq(K.outcome(for: .enter, focused: 1, count: 3), .choose(1), "16m-6: Return elige la enfocada")
    expectEq(K.outcome(for: .enter, focused: nil, count: 3), .none, "16m-6: Return sin foco no elige nada")
    expectEq(K.outcome(for: .digit(2), focused: nil, count: 3), .choose(1), "16m-6: el 2 elige la segunda")
    expectEq(K.outcome(for: .digit(3), focused: 0, count: 3), .choose(2), "16m-6: el número manda sobre el foco")
    expectEq(K.outcome(for: .digit(4), focused: nil, count: 3), .none, "16m-6: un número sin opción no hace nada")
    expectEq(K.outcome(for: .digit(0), focused: nil, count: 3), .none, "16m-6: el 0 no es atajo")
    expectEq(K.outcome(for: .digit(9), focused: nil, count: 9), .choose(8), "16m-6: hasta el 9")
    expect(ChoiceBlock.maxOptions <= 9, "16m-6: cada opción cabe en un atajo de un dígito")
    for key in [K.Key.up, .down, .enter, .digit(1)] {
        expectEq(K.outcome(for: key, focused: nil, count: 0), .none, "16m-6: sin opciones no hay teclas (\(key))")
    }
}

@Test @MainActor func islandChoiceCopyTests() async {
    await pinLanguage(.en) {
        let open = IslandChoiceCopy.optionAccessibility(index: 1, count: 3, label: "Rápido", resolution: .open)
        expectEq(open, "Rápido, 2 of 3", "16m-6 en: posición para VoiceOver")
        expect(IslandChoiceCopy.optionAccessibility(index: 1, count: 3, label: "Rápido", resolution: .chosen(1))
            .hasSuffix("selected"), "16m-6 en: la elegida se anuncia")
        let other = IslandChoiceCopy.optionAccessibility(index: 0, count: 3, label: "Rápido", resolution: .chosen(1))
        expect(other.hasSuffix("not available"), "16m-6 en: las demás, deshabilitadas")
        expect(IslandChoiceCopy.optionAccessibility(index: 0, count: 3, label: "Rápido", resolution: .passed)
            .hasSuffix("not available"), "16m-6 en: respondida por otra vía, deshabilitada")
    }
    await pinLanguage(.es) {
        expectEq(IslandChoiceCopy.optionAccessibility(index: 0, count: 2, label: "Sí", resolution: .open),
                 "Sí, 1 de 2", "16m-6 es: posición")
        expect(IslandChoiceCopy.optionAccessibility(index: 0, count: 2, label: "Sí", resolution: .chosen(0))
            .hasSuffix("elegida"), "16m-6 es: elegida")
        expect(IslandChoiceCopy.optionAccessibility(index: 1, count: 2, label: "No", resolution: .chosen(0))
            .hasSuffix("no disponible"), "16m-6 es: no disponible")
    }
}

@Test @MainActor func islandChoiceMetricsTests() {
    expectEq([IslandChoiceMetrics.minWidth, IslandChoiceMetrics.maxWidth], [340, 440],
             "16m-6: answer-card 340-440 (investigación §5)")
    expectEq([IslandChoiceMetrics.paddingY, IslandChoiceMetrics.paddingX], [18, 20],
             "16m-6: padding 18 × 20")
    expectEq(IslandChoiceMetrics.gap, 14, "16m-6: gap 14")
    expectEq(IslandChoiceMetrics.listMaxHeight, 260, "16m-6: valor propio, la lista de opciones hace scroll pasado esto")
    expectEq(IslandChoiceMetrics.width(available: 460, ideal: 300), 340, "16m-6: el mínimo")
    expectEq(IslandChoiceMetrics.width(available: 460, ideal: 500), 440, "16m-6: el máximo")
    expectEq(IslandChoiceMetrics.width(available: 460, ideal: 400), 400, "16m-6: lo que piden las palabras")
    expectEq(IslandChoiceMetrics.width(available: 300, ideal: 400), 300, "16m-6: nunca más que el hueco")
}

// MARK: - Chat: a pick is a typed message

@Test @MainActor func choosingSendsTheLabelLikeTypingTests() async {
    let provider = FakeChatProvider(replies: [.success([.text("Listo")]), .success([.text("Ok")])])
    let vm = primed(chat: provider)
    vm.draft = "borrador de la ventana"
    vm.choose("  Rápido  ")
    expectEq(vm.messages.map(\.text), ["Rápido"], "16m-6: la etiqueta entra como mensaje de la usuaria")
    expectEq(vm.messages.first?.role, .user, "16m-6: con su rol")
    expectEq(vm.draft, "borrador de la ventana", "16m-6: no pisa lo que ella tenía escrito")
    await pumpUntil("16m-6: el turno termina") { !vm.busy }
    expectEq(provider.histories.last?.last?.content, ChoiceOrigin.mark("Rápido", language: vm.config.language),
             "16m-6: el modelo recibe la etiqueta con la marca de tarjeta")

    vm.choose("   ")
    expectEq(vm.messages.count, 2, "16m-6: una etiqueta en blanco no manda nada")

    let second = FakeChatProvider(replies: [.success([.text("A")]), .success([.text("B")])])
    let busy = primed(chat: second)
    busy.draft = "uno"
    busy.send()
    busy.choose("Completo")
    expectEq(busy.queued, ["Completo"], "16m-6: con un turno en curso hace cola, como teclear")
    await pumpUntil("16m-6: la cola corre") { !busy.busy && busy.queued.isEmpty }
    expect(busy.messages.map(\.text).contains("Completo"), "16m-6: y termina entrando")
}
