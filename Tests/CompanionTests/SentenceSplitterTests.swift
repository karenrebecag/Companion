import Foundation
import CompanionCore

@MainActor func sentenceSplitterTests() {
    testTakeSentenceStreaming()
    testTakeSentenceNewline()
    testTakeSentenceBoundaries()
    testSentencesSplit()
    testSplitFirstSentence()
}

@MainActor func testTakeSentenceStreaming() {
    expect(SentenceSplitter.takeSentence("Claro, te ayudo con eso en un") == nil,
           "stream: sin cierre de oración no se habla")
    expect(SentenceSplitter.takeSentence("Claro, te ayudo con eso ahora.") == nil,
           "stream: terminador al final espera confirmación")

    guard let cut = SentenceSplitter.takeSentence("Claro, te ayudo con eso ahora. Y luego") else {
        return expect(false, "stream: debía cortar la primera oración")
    }
    expectEq(cut.sentence, "Claro, te ayudo con eso ahora.", "stream: corta la oración")
    expectEq(cut.rest, "Y luego", "stream: conserva el resto sin espacios de más")

    let dec = SentenceSplitter.takeSentence("El total asciende a 3.14 pesos por unidad")
    expect(dec == nil, "stream: un decimal no dispara la frase")
}

@MainActor func testTakeSentenceNewline() {
    guard let cut = SentenceSplitter.takeSentence(
        "Claro, te ayudo con eso ahora\nY luego"
    ) else {
        return expect(false, "stream: un salto de línea también cierra")
    }
    expectEq(cut.sentence, "Claro, te ayudo con eso ahora",
             "stream: corta antes del salto")
    expectEq(cut.rest, "Y luego", "stream: el resto arranca en la línea siguiente")
}

@MainActor func testTakeSentenceBoundaries() {
    expect(SentenceSplitter.takeSentence("") == nil,
           "stream: vacío no entrega frase")
    expect(SentenceSplitter.takeSentence("Hola. Mundo") == nil,
           "stream: por debajo de minChars no corta")
    expect(SentenceSplitter.takeSentence(
        "Claro, te ayudo con eso ahora. Y luego", minChars: 80) == nil,
           "stream: minChars alto espera más texto")
    expect(SentenceSplitter.takeSentence("¡Listo, ya quedó todo hecho!\n") != nil,
           "stream: admiración + salto cierra")
}

@MainActor func testSentencesSplit() {
    let s = SentenceSplitter.sentences(
        "Primera oración con largo suficiente aquí. Segunda parte también larga. Tercera.")
    expectEq(s.count, 3, "sentences: parte en tres")
    expect(s[0].hasPrefix("Primera"), "sentences: conserva el orden")
    expectEq(SentenceSplitter.sentences("").count, 0, "sentences: vacío no produce frases")
    expectEq(SentenceSplitter.sentences("   ").count, 0,
             "sentences: solo espacios no produce frases")
}

@MainActor func testSplitFirstSentence() {
    let (f, r) = SentenceSplitter.splitFirstSentence(
        "Primera oración con largo suficiente aquí. Y esta es la segunda parte.")
    expectEq(f, "Primera oración con largo suficiente aquí.",
             "split: corta en el fin de la primera oración")
    expect(r?.hasPrefix("Y esta") == true, "split: el resto arranca limpio")

    let (whole, none) = SentenceSplitter.splitFirstSentence("Corto.")
    expectEq(whole, "Corto.", "split: texto corto queda entero")
    expect(none == nil, "split: sin resto cuando no hay corte")

    let (num, rest2) = SentenceSplitter.splitFirstSentence(
        "Esta oración menciona el número 3.14159 y sigue sin cortarse mal. Fin de la prueba.")
    expect(num.hasSuffix("mal."), "split: un decimal no es fin de oración")
    expect(rest2?.hasPrefix("Fin") == true, "split: corta en el punto real")

    let (empty, emptyRest) = SentenceSplitter.splitFirstSentence("   ")
    expectEq(empty, "", "split: espacios quedan cadena vacía")
    expect(emptyRest == nil, "split: espacios no inventan resto")
}
