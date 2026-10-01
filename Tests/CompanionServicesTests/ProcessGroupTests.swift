import CompanionServices
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func processGroupTests() async {
    await testLargeOutputIsNotLostAndDoesNotHang()
    await testExitCodeTravels()
    await testStderrTravels()
    await testTimeoutKillsAndReports()
    await testAChildThatIgnoresSigtermStillDies()
    await testAGrandchildDiesWithTheGroup()
    await testTheWaitDoesNotBlockTheCaller()
}

@MainActor private func sh(_ command: String, timeout: TimeInterval = 5) async
    -> ShellOutcome
{
    await ProcessGroupRunner.run(
        executable: "/bin/sh", arguments: ["-c", command],
        cwd: NSTemporaryDirectory(), timeout: timeout)
}

@MainActor func testLargeOutputIsNotLostAndDoesNotHang() async {
    // El defecto que rompia encargos: un pipe tiene ~64 KB. Leyendo DESPUES de
    // esperar, cualquier comando que escupa mas se bloquea escribiendo y el
    // usuario recibe "timeout" por un comando que funcionaba.
    let outcome = await sh("yes 0123456789 | head -c 200000")
    expectEq(outcome.stdout.utf8.count, 200_000, "la salida grande llega entera")
    expect(!outcome.timedOut, "y no se disfraza de timeout")
    expectEq(outcome.exitCode, 0, "y el comando se considera exitoso")
}

@MainActor func testExitCodeTravels() async {
    let outcome = await sh("exit 3")
    expectEq(outcome.exitCode, 3, "el codigo de salida no se inventa")
    expect(!outcome.timedOut, "salir con error no es agotar el tiempo")
}

@MainActor func testStderrTravels() async {
    let outcome = await sh("echo fuera; echo dentro 1>&2")
    expect(outcome.stdout.contains("fuera"), "stdout llega")
    expect(outcome.stderr.contains("dentro"), "stderr llega por su canal")
}

@MainActor func testTimeoutKillsAndReports() async {
    let started = Date()
    let outcome = await sh("sleep 30", timeout: 0.4)
    expect(outcome.timedOut, "un comando colgado sigue siendo timeout")
    expect(Date().timeIntervalSince(started) < 5,
           "y el timeout se respeta en vez de esperar los 30 s")
}

@MainActor func testAChildThatIgnoresSigtermStillDies() async {
    // SIGTERM solo es una peticion. Sin escalada a SIGKILL, un proceso que lo
    // ignora vive para siempre y nadie se entera.
    let outcome = await sh("trap '' TERM; sleep 30", timeout: 0.4)
    expect(outcome.timedOut, "sigue reportandose como timeout")
    expect(outcome.pid > 0, "hubo proceso")
    let gone = await waitUntilGone(outcome.pid)
    expect(gone, "y el proceso ya no existe pese a haber ignorado SIGTERM")
}

@MainActor func testAGrandchildDiesWithTheGroup() async {
    // Matar al hijo directo deja vivos a sus hijos, que launchd adopta. Es el
    // mecanismo real de los procesos huerfanos.
    let outcome = await sh("sleep 30 & echo $!; wait", timeout: 0.4)
    let grandchild = pid_t(
        outcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    expect(grandchild > 0, "el nieto reporto su pid: \(outcome.stdout)")
    let gone = await waitUntilGone(grandchild)
    expect(gone, "el nieto murio con el grupo")
}

@MainActor func testTheWaitDoesNotBlockTheCaller() async {
    // El bucle de usleep ocupaba un hilo del pool durante todo el timeout.
    // Dos esperas concurrentes deben solaparse, no sumarse.
    let started = Date()
    async let a = sh("sleep 0.4")
    async let b = sh("sleep 0.4")
    _ = await (a, b)
    let elapsed = Date().timeIntervalSince(started)
    expect(elapsed < 0.75, "dos esperas se solapan (tardo \(elapsed) s)")
}

/// Espera a que el proceso desaparezca de verdad, en vez de dormir un tiempo
/// fijo: sale en cuanto muere. Un `settle` de reloj ocupaba CPU durante todo
/// su plazo y mataba de hambre a los tests que dependen de temporizadores.
@MainActor func waitUntilGone(_ pid: pid_t, timeout: TimeInterval = 2) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if kill(pid, 0) == -1 { return true }
        do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return false }
    }
    return kill(pid, 0) == -1
}
