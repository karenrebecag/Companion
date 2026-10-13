import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// El contrato de voz para una respuesta con estructura: el cerebro llama a
// show_document con la frase y el documento por separado (verificado en vivo
// con gpt-oss-120b en Cerebras el 2026-10-12: 15/15 con estructura, 0/3 en
// una pregunta corta).

/// The arguments as Cerebras streamed them live (run doc2-0, "pasos").
private let liveArguments = #"{"say":"Aquí tienes los pasos para preparar pizza","title":"Preparar pizza","markdown":"1. Preparar la masa y dejarla reposar.\n2. Extender la masa y agregar salsa.\n3. Colocar los toppings al gusto.\n4. Hornear a 220 °C por 12‑15 min.\n5. Sacar, cortar y servir."}"#

@Test func aLiveShowDocumentCallParsesIntoSentenceAndDocument() {
    guard let doc = SpokenDocument.parse(arguments: liveArguments) else {
        expect(false, "contrato: la llamada real parsea")
        return
    }
    expectEq(doc.say, "Aquí tienes los pasos para preparar pizza", "contrato: la frase")
    expectEq(doc.title, "Preparar pizza", "contrato: el titulo")
    expect(doc.markdown.hasPrefix("1. Preparar la masa"), "contrato: el documento entero")
    expect(doc.markdown.contains("\n5. Sacar, cortar y servir."), "contrato: con sus saltos de linea")
    expectEq(doc.threaded(after: doc.say),
             doc.say + "\n\n" + doc.markdown, "contrato: el hilo guarda frase y documento")
}

@Test func aCallWithoutADocumentIsNotOneAndABlankSentenceStillShowsIt() {
    expect(SpokenDocument.parse(arguments: #"{"say":"Hola","markdown":"  "}"#) == nil,
           "contrato: sin markdown no hay documento")
    expect(SpokenDocument.parse(arguments: "{not json") == nil, "contrato: JSON roto no es documento")
    let blank = SpokenDocument.parse(arguments: #"{"say":"","title":"","markdown":"| a | b |"}"#)
    expectEq(blank?.say, "", "contrato: la frase vacia se conserva vacia")
    expectEq(blank?.title, nil, "contrato: un titulo vacio no es titulo")
    expectEq(blank?.threaded(after: ""), "| a | b |", "contrato: el hilo guarda solo el documento")
    expectEq(SpokenDocument.fallbackSay(.es), "Aquí lo tienes.", "contrato: la voz dice algo propio")
}

@Test func theToolIsDeclaredWithoutStrictAndThePromptNamesIt() {
    let spec = SpokenDocument.spec(.es)
    expectEq(spec.name, "show_document", "contrato: el nombre es wire")
    expectEq(spec.required, ["say", "title", "markdown"], "contrato: los tres campos")
    // Cerebras refuses a tool list with mixed strict values (live 2026-10-12).
    expect(!spec.encodeChat(strict: false).contains("\"strict\""), "contrato: sin strict")
    for language in [AppLanguage.es, .en] {
        let voice = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true, language: language, voice: true)
        expect(voice.contains("show_document"), "prompt \(language): la voz conoce la tool")
        let typed = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true, language: language)
        expect(!typed.contains("show_document"), "prompt \(language): el chat escrito no")
        expect(ContextBlock.replyHint(.voice, language: language)?.contains("show_document") == true,
               "hint \(language): la pista de respuesta ya no contradice la tool")
    }
}
