import CompanionCore
import Foundation
import Testing

@Test @MainActor func conversationMemoryTests() {
    testShortResultsSurviveWhole()
    testLongResultsAreCutToBudget()
    testACutSaysThatItCut()
    testTheCutStartsAtTheSummaryNotTheRawTop()
    testTheBudgetMatchesTheDocumentedRange()
}

private let longReport = """
# Resultado de la búsqueda

La carpeta se llama `SoftwareDevProjects`, en el escritorio.

\(String(repeating: "Una línea de detalle que ocupa espacio de contexto. ", count: 200))
"""

@MainActor func testShortResultsSurviveWhole() {
    // Recortar lo que cabe costaria poder contestar "¿y que habia dentro?"
    // sin volver a delegar. El presupuesto acota lo patologico, no lo normal.
    let short = "Listo, abrí `at_dashboard` en Cursor."
    expectEq(ConversationMemory.recall(short), short,
             "un resultado corto entra entero en la memoria")
}

@MainActor func testLongResultsAreCutToBudget() {
    let recalled = ConversationMemory.recall(longReport)
    expect(recalled.count < longReport.count, "un informe largo no entra entero")
    expect(recalled.count <= ConversationMemory.defaultBudget + 200,
           "y respeta el presupuesto: \(recalled.count)")
}

@MainActor func testACutSaysThatItCut() {
    // Un recorte mudo se lee como "esto es todo lo que hubo", que es mentira
    // del tamaño del informe.
    let recalled = ConversationMemory.recall(longReport)
    expect(recalled.lowercased().contains("pantalla"),
           "el recorte avisa que el informe completo sigue en pantalla")
}

@MainActor func testTheCutStartsAtTheSummaryNotTheRawTop() {
    // reportCut existe justo para esto y llevaba probado y sin invocar desde
    // que se porto.
    let recalled = ConversationMemory.recall(longReport)
    expect(recalled.contains("SoftwareDevProjects"),
           "lo que sobrevive es el resumen, que es lo que el modelo necesita")
}

@MainActor func testTheBudgetMatchesTheDocumentedRange() {
    // Anthropic documenta 1.000-2.000 tokens para el resumen de un subagente.
    // 4.000 caracteres son ~1.000: el extremo bajo, a proposito.
    expectEq(ConversationMemory.defaultBudget, 4000,
             "el presupuesto es una decision citada, no un numero al azar")
}

@Test @MainActor func cardsNeverEnterMemoryTests() {
    testAShortReplyWithACardDropsThePayload()
    testTheModelStillKnowsACardWasShown()
    testALongReportDropsItToo()
    testOrdinaryFencesAreUntouched()
}

private let withCard = """
Aquí está el museo.

```companion:locations
{"title":"Museos","locations":[{"name":"Soumaya","lat":19.44,"lng":-99.20}]}
```

Abre de 10:30 a 18:30.
"""

@MainActor func testAShortReplyWithACardDropsThePayload() {
    // El mismo dato tenia dos destinos segun el tamaño del texto: un informe
    // largo dejaba fuera las tarjetas y uno corto mandaba el JSON entero a la
    // memoria. Eso no lo decidio nadie.
    let recalled = ConversationMemory.recall(withCard)
    expect(!recalled.contains("19.44"),
           "las coordenadas no entran en el contexto del modelo")
    expect(!recalled.contains("companion:locations"),
           "ni el cerco crudo")
}

@MainActor func testTheModelStillKnowsACardWasShown() {
    // Borrar la tarjeta sin decir nada le haria creer que no mostro nada, y
    // ofreceria de nuevo lo que ya esta en pantalla.
    let recalled = ConversationMemory.recall(withCard)
    expect(recalled.lowercased().contains("tarjeta"),
           "queda constancia de que se pinto una: \(recalled)")
    expect(recalled.contains("Soumaya") || recalled.contains("museo"),
           "y la prosa alrededor sobrevive")
}

@MainActor func testALongReportDropsItToo() {
    let long = withCard + String(repeating: "Detalle largo. ", count: 500)
    let recalled = ConversationMemory.recall(long)
    expect(!recalled.contains("19.44"), "tampoco en el camino de recorte")
}

@MainActor func testOrdinaryFencesAreUntouched() {
    // Un bloque de codigo normal es contenido, no UI: el modelo lo necesita.
    let code = "Corre esto:\n\n```bash\nls -la ~/Desktop\n```\n"
    expectEq(ConversationMemory.recall(code), code,
             "un fence de codigo normal viaja entero")
}
