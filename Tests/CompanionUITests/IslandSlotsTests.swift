import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Testing

// The grid replaced the three dotted slots (K7): a running task shows in its
// run, whose loader leads the status row. The lead column holds one mark per
// state: the run's loader during a job, the orb while it listens, thinks or
// speaks, the status dot otherwise.

@Test @MainActor func aJobLeadsWithTheRunNotTheSlots() {
    expect(IslandView.isJob(.job(goal: "ordenar", step: nil, steps: 2)), "un encargo: el loader del run")
    expect(!IslandView.isJob(.thinking), "pensar no es un encargo")
}

@Test @MainActor func theLeadHoldsTheOrbOnlyWhileItWorksOrSpeaks() {
    var thinking = IslandState(size: .bar)
    thinking.line = .thinking
    expect(IslandView.leadHoldsMeter(thinking), "pensando: el orbe")
    var done = IslandState(size: .bar)
    done.line = .completed
    expect(!IslandView.leadHoldsMeter(done), "listo: el punto de estado")
    var listening = IslandState(size: .bar)
    listening.meter = .mic
    expect(IslandView.leadHoldsMeter(listening), "escuchando: el orbe")
}
