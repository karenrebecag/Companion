import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Los dos ajustes que la auditoría encontró decorativos: el volumen (el
// player lo leía UNA vez al lanzar la app) y el perfil de "Tú" (el chat lo
// congelaba en constantes al arranque; la voz sí lo releía por sesión).

@Test @MainActor func settingsWiringTests() async {
    await testVolumeReachesThePlayerLive()
    testChatReadsProfileAtRequestTime()
}

@MainActor func testVolumeReachesThePlayerLive() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("volumen: listening") { h.watch.latest.state == .listening }

    await h.session.setVolume(0.4)

    expectEq(h.player.volumes.last, 0.4,
             "volumen: el slider llega al player en vivo, no al relanzar")
}

@MainActor func testChatReadsProfileAtRequestTime() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: SSEFixtures.chunks("hola")))
    let profile = ProfileBox(name: "Karen")
    let client = ChatProviderClient(
        secrets: TestSecretStore([.openAI: "sk-test"]),
        probe: TestProbe(available: ["openai"]),
        transport: transport,
        settings: .default,
        profileSource: { profile.snapshot },
        catalog: [.openAI])

    // El perfil cambia DESPUÉS de construir el cliente: la petición debe
    // llevar el valor nuevo — antes se quedaba con el del arranque.
    profile.set(name: "Rebeca")
    _ = collectChat(client)

    let body = transport.requests.last?.httpBody
        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    expect(body.contains("Rebeca"),
           "perfil: el system prompt se arma con el perfil del momento")
    expect(!body.contains("Karen"),
           "perfil: el valor congelado del arranque no se cuela")
}

final class ProfileBox: @unchecked Sendable {
    private let lock = NSLock()
    private var name: String
    init(name: String) { self.name = name }
    func set(name: String) { lock.withLock { self.name = name } }
    var snapshot: (name: String, about: String, instructions: String) {
        lock.withLock { (name, "", "") }
    }
}
