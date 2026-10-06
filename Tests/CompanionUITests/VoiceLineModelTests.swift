import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// P3: when Incredible's voice line chip shows and leaves (referencia local): it
// appears with its turn, stays 6 s once the turn is over, and leaves in 260 ms.

/// Each sleep the model asks for waits here until the test lets it go.
private actor Sleeps {
    private(set) var requested: [TimeInterval] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func sleep(_ delay: TimeInterval) async {
        requested.append(delay)
        await withCheckedContinuation { waiting.append($0) }
    }

    func release(_ index: Int) { waiting[index].resume() }
    func count() -> Int { requested.count }

    /// Lets every sleep go, so no test leaves a continuation behind.
    func releaseAll() {
        for (index, _) in waiting.enumerated() where index < waiting.count { waiting[index].resume() }
        waiting.removeAll()
    }
}

@MainActor private func eventually(_ done: () async -> Bool) async {
    for _ in 0..<400 where !(await done()) {
        do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
    }
}

private func line(_ turn: UUID, settled: Bool, spoken: Int = 0) -> VoiceLine? {
    VoiceLine.make(turn: turn, text: "Hola. Ya esta.", spoken: spoken, settled: settled, cards: [], quiet: true)
}

@Test @MainActor func aTurnInProgressShowsTheChipWithoutAClock() async {
    let sleeps = Sleeps()
    let model = VoiceLineModel(sleep: { await sleeps.sleep($0) })
    let turn = UUID()
    model.show(line(turn, settled: false))
    expectEq(model.line?.turn, turn, "montado")
    expect(model.visible, "y visible")
    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
    expectEq(await sleeps.count(), 0, "mientras habla no hay reloj")
}

@Test @MainActor func aFinishedTurnStaysSixSecondsThenLeaves() async {
    let sleeps = Sleeps()
    let model = VoiceLineModel(sleep: { await sleeps.sleep($0) })
    let turn = UUID()
    model.show(line(turn, settled: false))
    model.show(line(turn, settled: true, spoken: 3))
    await eventually { await sleeps.count() == 1 }
    expectEq(await sleeps.requested, [VoiceLine.lingerAfterSettle], "espera 6 s")
    await sleeps.release(0)
    await eventually { !model.visible }
    expect(!model.visible, "se apaga")
    expect(model.line != nil, "pero sigue montado mientras sale")
    await eventually { await sleeps.count() == 2 }
    expectEq(await sleeps.requested.last, VoiceLine.leave, "sale en 260 ms")
    await sleeps.release(1)
    await eventually { model.line == nil }
    expect(model.line == nil, "y se desmonta")
}

@Test @MainActor func goingAwayWhileVisibleFadesFirst() async {
    let sleeps = Sleeps()
    let model = VoiceLineModel(sleep: { await sleeps.sleep($0) })
    model.show(line(UUID(), settled: false))
    model.show(nil)
    expect(!model.visible, "se apaga al instante")
    await eventually { await sleeps.count() == 1 }
    expectEq(await sleeps.requested, [VoiceLine.leave], "y sale en 260 ms")
    await sleeps.release(0)
    await eventually { model.line == nil }
    expect(model.line == nil, "desmontado")
}

// A finished turn the chip never showed (the island carried it) does not pop up after.
@Test @MainActor func aFinishedTurnNeverShownDoesNotAppear() async {
    let model = VoiceLineModel(sleep: { _ in })
    model.show(line(UUID(), settled: true))
    expect(model.line == nil, "no aparece")
    expect(!model.visible, "ni se enciende")
}

@Test @MainActor func theSameLineAgainDoesNotRestartTheClock() async {
    let sleeps = Sleeps()
    let model = VoiceLineModel(sleep: { await sleeps.sleep($0) })
    let turn = UUID()
    model.show(line(turn, settled: false))
    model.show(line(turn, settled: true))
    await eventually { await sleeps.count() == 1 }
    model.show(line(turn, settled: true))
    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
    expectEq(await sleeps.count(), 1, "la misma linea no reinicia los 6 s")
    await sleeps.releaseAll()
}

// A new turn arriving while the old chip leaves is never taken away by the old clock.
@Test @MainActor func aNewTurnIsNotTakenAwayByTheOldClock() async {
    let sleeps = Sleeps()
    let model = VoiceLineModel(sleep: { await sleeps.sleep($0) })
    model.show(line(UUID(), settled: false))
    model.show(nil)
    await eventually { await sleeps.count() == 1 }
    let next = UUID()
    model.show(line(next, settled: false))
    await sleeps.release(0)
    do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
    expectEq(model.line?.turn, next, "el turno nuevo sigue")
    expect(model.visible, "y visible")
}

private func line(_ turn: UUID, settled: Bool, text: String) -> VoiceLine? {
    VoiceLine.make(turn: turn, text: text, spoken: 0, settled: settled, cards: [], quiet: true)
}

// QA review (P3): new words for a finished turn while it lingers show without restarting the clock.
@Test @MainActor func newWordsWhileLingeringShowWithoutANewClock() async {
    let sleeps = Sleeps()
    let model = VoiceLineModel(sleep: { await sleeps.sleep($0) })
    let turn = UUID()
    model.show(line(turn, settled: false, text: "Uno."))
    model.show(line(turn, settled: true, text: "Uno."))
    await eventually { await sleeps.count() == 1 }
    model.show(line(turn, settled: true, text: "Uno. Dos."))
    expectEq(model.line?.words, ["Uno.", "Dos."], "las palabras nuevas")
    expect(model.visible, "sigue visible")
    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
    expectEq(await sleeps.count(), 1, "sin reloj nuevo")
    await sleeps.releaseAll()
}

// QA review (P3): a finished turn that already started leaving is not lit again.
@Test @MainActor func aLeavingFinishedTurnIsNotLitAgain() async {
    let sleeps = Sleeps()
    let model = VoiceLineModel(sleep: { await sleeps.sleep($0) })
    let turn = UUID()
    model.show(line(turn, settled: false, text: "Uno."))
    model.show(line(turn, settled: true, text: "Uno."))
    await eventually { await sleeps.count() == 1 }
    await sleeps.release(0)
    await eventually { !model.visible }
    model.show(line(turn, settled: true, text: "Uno. Dos."))
    expect(!model.visible, "no se vuelve a encender")
    await eventually { await sleeps.count() == 2 }
    await sleeps.release(1)
    await eventually { model.line == nil }
    expect(model.line == nil && !model.visible, "y sale una sola vez")
}

// QA review (P3): the same turn still talking while the chip fades brings it back.
@Test @MainActor func theTurnTalkingAgainDuringTheFadeBringsItBack() async {
    let sleeps = Sleeps()
    let model = VoiceLineModel(sleep: { await sleeps.sleep($0) })
    let turn = UUID()
    model.show(line(turn, settled: false, text: "Uno."))
    model.show(nil)
    await eventually { await sleeps.count() == 1 }
    model.show(line(turn, settled: false, text: "Uno. Dos."))
    await sleeps.release(0)
    do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
    expect(model.line != nil && model.visible, "vuelve y se queda")
}
