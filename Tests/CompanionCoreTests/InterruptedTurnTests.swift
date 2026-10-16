import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Hablar o escribir encima de un turno lo corta. Lo que no llegó a hacer una
// herramienta viaja con las palabras nuevas; lo que ya actuó se queda en el hilo.

@Test func aCutTurnThatActedLeavesItsWordsOnTheThread() {
    expect(InterruptedTurn.carried("abre Notas", toolsRan: true) == nil,
           "interrumpir: si ya corrió una herramienta, sus palabras no se llevan")
}

@Test func aCutTurnThatHasNotActedCarriesItsWordsIntoTheNextOne() {
    let carried = InterruptedTurn.carried("  ¿Qué hora es?  ", toolsRan: false)
    expectEq(carried, "¿Qué hora es?", "interrumpir: sin herramienta, las palabras viajan recortadas")
    expectEq(InterruptedTurn.merged(carried: carried, next: "y en Madrid?"),
             "¿Qué hora es?\ny en Madrid?", "interrumpir: las palabras viejas van antes que las nuevas")
    expectEq(InterruptedTurn.merged(carried: nil, next: "hola"), "hola",
             "interrumpir: sin nada que llevar, solo lo nuevo")
    expect(InterruptedTurn.carried("   ", toolsRan: false) == nil, "interrumpir: un turno en blanco no lleva nada")
}
