import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func taskRunTransitions() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(120)
    let running = TaskRun.begin(at: start)
    expectEq(running.state, .running, "run: begin arranca en curso")

    let done = running.finishing(at: end)
    expectEq(done.state, .done, "run: finishing cierra como hecho")
    expectEq(done.duration(now: end.addingTimeInterval(999)), 120, "run: la duración cerrada ignora el reloj")
    expectEq(done.failing(at: end.addingTimeInterval(5)), done, "run: un estado terminal no cambia")

    let failed = running.failing(at: end)
    expectEq(failed.finishing(at: end.addingTimeInterval(5)).state, .failed, "run: un fallo no se tapa con hecho")

    expectEq(running.shown(live: false).state, .failed, "run: en curso sin turno vivo se muestra como fallido")
    expectEq(running.shown(live: true).state, .running, "run: en curso con turno vivo sigue en curso")
    expectEq(running.shown(live: false).duration(now: end), nil, "run: interrumpido no inventa duración")
}
