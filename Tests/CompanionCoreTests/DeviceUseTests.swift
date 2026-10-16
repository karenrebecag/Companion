import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Una reunión ajena deja la isla compacta; el micrófono que usa Companion para
// escuchar no cuenta como reunión.

@Test func aMeetingIsACameraOrAMicrophoneThatIsNotOurs() {
    expect(MeetingPresence.compact(DeviceUse(microphone: false, camera: true), ownMicrophone: false),
           "reunión: una cámara en uso")
    expect(MeetingPresence.compact(DeviceUse(microphone: true, camera: false), ownMicrophone: false),
           "reunión: un micrófono ajeno")
    expect(!MeetingPresence.compact(DeviceUse(microphone: true, camera: false), ownMicrophone: true),
           "reunión: el micrófono de Companion no cuenta")
    expect(!MeetingPresence.compact(.idle, ownMicrophone: false), "reunión: nada en uso, isla normal")
}

@Test func aMeetingKeepsAFinishedReplyFromOpeningTheIsland() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.replyMeasured(.content))
    _ = machine.handle(.typedReplyFinished)
    expectEq(IslandState.from(machine.projection, pebbleHidden: false).size, .docCard,
             "reunión: sin reunión la respuesta abre la tarjeta")
    _ = machine.handle(.deviceUseChanged(DeviceUse(microphone: false, camera: true)))
    expectEq(IslandState.from(machine.projection, pebbleHidden: false).size, .bar,
             "reunión: la respuesta no abre la isla sola")
}
