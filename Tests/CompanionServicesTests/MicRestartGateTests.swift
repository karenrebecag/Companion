import CompanionServices
import CompanionTestKit
import Testing

// An unplug raises two triggers (the device list and the engine's own
// configuration change) on two threads, while the user may stop the mic.

@Suite struct MicRestartGateTests {
    @Test func aStopRacingAQueuedRestartKeepsTheMicClosed() {
        var gate = MicRestartGate()
        let ticket = gate.ticket
        gate.invalidate()
        expect(!gate.admit(ticket: ticket, running: false), "parar antes: no reabre")
        expect(!gate.admit(ticket: ticket, running: true), "parar antes: ni aunque algo lo reabriera")
    }

    @Test func twoTriggersOfTheSameUnplugRestartOnce() {
        var gate = MicRestartGate()
        let first = gate.ticket
        let second = gate.ticket
        expect(gate.admit(ticket: first, running: true), "el primero reinicia")
        expect(!gate.admit(ticket: second, running: true), "el segundo, mismo origen, se descarta")
    }

    @Test func aLaterChangeAfterTheRestartIsHonoured() {
        var gate = MicRestartGate()
        expect(gate.admit(ticket: gate.ticket, running: true), "primer cambio")
        expect(gate.admit(ticket: gate.ticket, running: true), "otro cambio después: reinicia otra vez")
    }

    @Test func aStaleTicketIsIgnored() {
        var gate = MicRestartGate()
        let old = gate.ticket
        gate.invalidate()
        expect(!gate.admit(ticket: old, running: true), "ticket viejo: se ignora")
        expect(gate.admit(ticket: gate.ticket, running: true), "ticket nuevo: pasa")
    }

    @Test func aMicThatIsNotRunningNeverRestarts() {
        var gate = MicRestartGate()
        expect(!gate.admit(ticket: gate.ticket, running: false), "parado: no reinicia")
        expect(gate.admit(ticket: gate.ticket, running: true), "y el rechazo no gasta el ticket")
    }

    // The without-VP retry reads its ticket where it decided, after its own
    // halt; a user stop that lands afterwards must retire that ticket.
    @Test func aStopAfterTheRetryDecisionRetiresTheRetry() {
        var gate = MicRestartGate()
        expect(gate.admit(ticket: gate.ticket, running: true), "el cambio de entrada se admite")
        gate.invalidate()
        let retry = gate.ticket
        expect(gate.stillCurrent(retry), "sin parar: el reintento sigue vigente")
        gate.invalidate()
        expect(!gate.stillCurrent(retry), "parar tras decidir: el reintento no reabre el micro")
    }

    @Test func aTicketFromBeforeAnyHaltIsNotCurrent() {
        var gate = MicRestartGate()
        let early = gate.ticket
        gate.invalidate()
        expect(!gate.stillCurrent(early), "ticket anterior al halt: no vigente")
        expect(gate.stillCurrent(gate.ticket), "ticket tomado ahora: vigente")
    }

    // An outside start() invalidates the gate: a retry decided before it must
    // not discard the engine that start now owns.
    @Test func anOutsideStartRetiresARetryDecidedBefore() {
        var gate = MicRestartGate()
        let retry = gate.ticket
        expect(gate.stillCurrent(retry), "antes del start externo: vigente")
        gate.invalidate()
        expect(!gate.stillCurrent(retry), "start externo: el reintento previo queda retirado")
        expect(gate.stillCurrent(gate.ticket), "el reintento propio del start nace vigente")
    }
}
