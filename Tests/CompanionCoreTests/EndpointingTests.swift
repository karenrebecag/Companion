import CompanionTestKit
import Foundation
import CompanionCore
import Testing

@Test @MainActor func endpointingTests() {
    testEchoGuard()
    testEchoScrub()
    testEchoGuardWords()
}

@MainActor func testEchoScrub() {
    let agent = "Hola, sí, te escucho claramente. ¿En qué te echo una mano hoy?"
    let mixed = "Hola, sí, te escucho claramente. ¿En qué te echo una mano "
        + "hoy? Hola, ¿puedes crear un archivo de prueba?"
    let scrubbed = EchoGuard.scrub(heard: mixed, agentSaying: agent)
    expect(!scrubbed.contains("escucho claramente"),
           "scrub: el eco del agente se recorta")
    expect(scrubbed.contains("puedes crear un archivo"),
           "scrub: las palabras de la usuaria sobreviven")

    expectEq(EchoGuard.scrub(heard: "crea un archivo nuevo", agentSaying: agent),
             "crea un archivo nuevo",
             "scrub: un turno sin eco pasa intacto, con su puntuación")
    expect(EchoGuard.words(EchoGuard.scrub(
        heard: "te escucho claramente hoy", agentSaying: agent)).isEmpty,
        "scrub: eco puro queda vacío — se tira")
    expectEq(EchoGuard.scrub(heard: "hola puedes ayudarme", agentSaying: agent),
             "hola puedes ayudarme",
             "scrub: abrir con una palabra compartida no te roba el turno")
}

@MainActor func testEchoGuard() {
    let saying = "Claro, te cuento la historia de un viaje muy largo"
    expect(EchoGuard.isEcho(heard: "te cuento la historia", agentSaying: saying),
           "eco: repetir lo que el widget dice es eco, no interrupción")
    expect(!EchoGuard.isEcho(heard: "espera para ya entendí", agentSaying: saying),
           "eco: palabras propias no son eco")
    expect(EchoGuard.isEcho(heard: "", agentSaying: saying),
           "eco: sin palabras no hay interrupción")

    expect(EchoGuard.isRealInterruption(heard: "oye espera", agentSaying: saying),
           "barge-in: dos palabras propias interrumpen")
    expect(!EchoGuard.isRealInterruption(heard: "mmm", agentSaying: saying),
           "barge-in: una muletilla no interrumpe")
    expect(!EchoGuard.isRealInterruption(heard: "la historia", agentSaying: saying),
           "barge-in: el eco no interrumpe aunque traiga dos palabras")
}

@MainActor func testEchoGuardWords() {
    expectEq(EchoGuard.words(""), [], "words: vacío no produce tokens")
    expectEq(EchoGuard.words("a b c"), [], "words: una letra no cuenta")
    expectEq(EchoGuard.words("hola, mundo!"), ["hola", "mundo"],
             "words: puntuación no es palabra")
    expectEq(EchoGuard.words("TE Cuento"), ["te", "cuento"],
             "words: minúsculas y tokens de 2+")
    expect(!EchoGuard.isEcho(heard: "oye espera", agentSaying: ""),
           "eco: si el agente no dice nada, lo oído no es eco")
    expect(!EchoGuard.isRealInterruption(heard: "", agentSaying: "hola mundo"),
           "barge-in: silencio no interrumpe")
    expect(!EchoGuard.isRealInterruption(heard: "sí", agentSaying: "otra cosa"),
           "barge-in: una sola palabra no alcanza")
}
