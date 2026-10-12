import CompanionCore
import Foundation
import Testing

// "Parar es parar": a hold that is only an order to stop ends the turn in
// silence. "para" is also a preposition, so only the whole utterance counts.

@Suite struct SpokenStopOrders {
    @Test(arguments: [
        "Para.", "para", "para ya", "ya para", "para por favor", "basta", "Stop", "stop it",
        "be quiet", "párale", "Detente", "¡Cállate!", "silencio", "alto", "cancela",
    ])
    func aBareStopStops(_ said: String) {
        #expect(SpokenStop.stops(said), "«\(said)» is a stop")
    }

    @Test(arguments: [
        "para mañana", "para qué sirve esto", "¿para?", "no", "", "   ",
        "cuéntame una historia para dormir", "stop the music and open Safari", "ya llegué",
        "dale", "para 2",
    ])
    func anythingElseIsNotAStop(_ said: String) {
        #expect(!SpokenStop.stops(said), "«\(said)» is not a stop")
    }
}
