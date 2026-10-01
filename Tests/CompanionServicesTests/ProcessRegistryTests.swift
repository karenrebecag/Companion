import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func processRegistryTests() async {
    await testLiveCountRisesAndFalls()
    await testTheCapRefusesInsteadOfPilingUp()
    await testFreedSlotsAreReusable()
    await testTerminateAllKillsWhatIsLeft()
    await testLauncherKillsTheWholeGroup()
    await testLauncherRespectsTheCap()
}

@MainActor func testLiveCountRisesAndFalls() async {
    let registry = ProcessRegistry(cap: 4)
    expectEq(registry.liveCount, 0, "arranca en cero")
    let outcome = await ProcessGroupRunner.run(
        executable: "/bin/sh", arguments: ["-c", "echo hola"],
        cwd: NSTemporaryDirectory(), timeout: 5, registry: registry)
    expectEq(outcome.exitCode, 0, "el comando corrio")
    expectEq(registry.liveCount, 0, "y el registro no se queda con el muerto")
}

@MainActor func testTheCapRefusesInsteadOfPilingUp() async {
    // Un techo que no se aplica es documentacion. Sin el, cada encargo suma
    // shells hasta que la Mac se arrastra.
    let registry = ProcessRegistry(cap: 2)
    async let a = ProcessGroupRunner.run(
        executable: "/bin/sh", arguments: ["-c", "sleep 0.3"],
        cwd: NSTemporaryDirectory(), timeout: 5, registry: registry)
    async let b = ProcessGroupRunner.run(
        executable: "/bin/sh", arguments: ["-c", "sleep 0.3"],
        cwd: NSTemporaryDirectory(), timeout: 5, registry: registry)
    await settle(0.08)
    let third = await ProcessGroupRunner.run(
        executable: "/bin/sh", arguments: ["-c", "echo tarde"],
        cwd: NSTemporaryDirectory(), timeout: 5, registry: registry)
    expect(third.refusedByCap, "el tercero se rechaza con el techo lleno")
    expect(!third.stderr.isEmpty, "y dice por que, en vez de fallar mudo")
    _ = await (a, b)
}

@MainActor func testFreedSlotsAreReusable() async {
    let registry = ProcessRegistry(cap: 1)
    let first = await ProcessGroupRunner.run(
        executable: "/bin/sh", arguments: ["-c", "echo uno"],
        cwd: NSTemporaryDirectory(), timeout: 5, registry: registry)
    expect(!first.refusedByCap, "el primero pasa")
    let second = await ProcessGroupRunner.run(
        executable: "/bin/sh", arguments: ["-c", "echo dos"],
        cwd: NSTemporaryDirectory(), timeout: 5, registry: registry)
    expect(!second.refusedByCap, "y al liberarse, el siguiente tambien")
}

@MainActor func testTerminateAllKillsWhatIsLeft() async {
    // La red de applicationWillTerminate: cerrar la app con un encargo en
    // marcha no puede dejar la shell — ni sus hijos — corriendo.
    let registry = ProcessRegistry(cap: 4)
    let launcher = RealProcessLauncher(registry: registry)
    guard let handle = await launcher.launch(
        executable: "/bin/sh", arguments: ["-c", "sleep 30 & echo $!; wait"],
        cwd: nil)
    else {
        expect(false, "el proceso debia arrancar")
        return
    }
    let grandchild = pid_t(await handle.readLine() ?? "") ?? 0
    expect(grandchild > 0, "el nieto reporto su pid")
    expectEq(registry.liveCount, 1, "el registro lo tiene")

    // terminateGroup spins through the SIGTERM grace per group; on the main
    // actor that starves every MainActor test running alongside.
    await Task.detached { registry.terminateAll() }.value
    let gone = await waitUntilGone(grandchild)
    expect(gone, "el nieto murio con la limpieza")
    expectEq(registry.liveCount, 0, "y el registro queda vacio")
}

@MainActor func testLauncherKillsTheWholeGroup() async {
    let registry = ProcessRegistry(cap: 4)
    let launcher = RealProcessLauncher(registry: registry)
    guard let handle = await launcher.launch(
        executable: "/bin/sh", arguments: ["-c", "sleep 30 & echo $!; wait"],
        cwd: nil)
    else {
        expect(false, "el proceso debia arrancar")
        return
    }
    let grandchild = pid_t(await handle.readLine() ?? "") ?? 0
    await handle.terminate()
    let gone = await waitUntilGone(grandchild)
    expect(gone, "terminate() de un ejecutor tambien alcanza a la descendencia")
}

@MainActor func testLauncherRespectsTheCap() async {
    let registry = ProcessRegistry(cap: 1)
    let launcher = RealProcessLauncher(registry: registry)
    let first = await launcher.launch(
        executable: "/bin/cat", arguments: [], cwd: nil)
    expect(first != nil, "el primero entra")
    let second = await launcher.launch(
        executable: "/bin/cat", arguments: [], cwd: nil)
    expect(second == nil, "el segundo no, con el techo lleno")
    await first?.terminate()
}
