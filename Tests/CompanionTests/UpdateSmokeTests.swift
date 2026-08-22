import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Opt-in (RUN_SMOKE=1): sale a la red de verdad. Hasta 2026-08-22 el repo no
// tenía un solo release, así que el único camino que el updater había
// recorrido era el 404. Los fixtures pueden derivar del JSON real de GitHub;
// esto lo comprueba contra la API, una vez, cuando alguien lo pide.

@Test @MainActor func updateSmokeTests() async throws {
    guard ProcessInfo.processInfo.environment["RUN_SMOKE"] == "1" else { return }

    let (data, response) = try await URLSession.shared.data(
        from: UpdateChecker.releaseAPI)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    expectEq(status, 200, "smoke: la API de releases contesta")

    let old = UpdateChecker.parse(data, current: "0.0.1")
    expect(old != nil, "smoke: una versión vieja SÍ ve el release publicado")
    expect(old?.tag.contains("0.10") ?? false,
           "smoke: y es el tag que se publicó — got \(old?.tag ?? "nil")")
    expect(old?.pageURL.scheme == "https",
           "smoke: la página del release viaja por https")

    expect(UpdateChecker.parse(data, current: "99.0.0") == nil,
           "smoke: una versión más nueva que el release no ofrece nada")
    expect(UpdateChecker.parse(data, current: Build.version) == nil,
           "smoke: la versión que corre hoy está al día")
}
