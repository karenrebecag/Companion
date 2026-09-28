import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 16a-3 (spec §5 fila 6). Cada turno pagaba 3,3–3,7 s de visión para
// describir una captura que el cerebro (solo texto) no usa para actuar. La
// vista del turno es el texto de Accesibilidad; los píxeles, bajo demanda.

@Test @MainActor func sightOnDemandTests() async {
    await testATurnNoLongerCallsVision()
    await testSeeDescribesTheScreenOnDemand()
    await testTheSeeToolIsOfferedOnlyWithVisionBehindIt()
}

private func visionStub() -> ScriptedTransport {
    let transport = ScriptedTransport()
    transport.stub(
        url: ProviderDescriptor.openAI.endpoint!.absoluteString,
        ScriptedReply(
            status: 200,
            body: Data("""
            {"choices":[{"message":{"content":"SUMMARY: a bar chart of sales\\nSNIPPETS:\\n[Numbers] \\"Q3\\""}}]}
            """.utf8)))
    return transport
}

private func sight(_ transport: ScriptedTransport) -> ScreenSight {
    ScreenSight(
        capture: ScreenCapture(bundleID: "test", trusted: { true }, grab: { Data([0xFF, 0xD8]) }),
        vision: ScreenVision(secrets: TestSecretStore([.openAI: "sk-test"]), transport: transport),
        axHarvest: { _ in ["texto de la ventana"] },
        pid: { 4242 }, appName: { "Numbers" },
        visionPerTurn: false)
}

@MainActor func testATurnNoLongerCallsVision() async {
    let transport = visionStub()
    let screen = sight(transport)
    screen.begin(app: "Numbers")
    let brief = await screen.finish(wait: .seconds(2))
    expect(transport.requests.isEmpty, "turno: sin llamada de visión")
    expectEq(brief.snippets.first?.text, "texto de la ventana", "turno: el texto de Accesibilidad")
    expect(!brief.pending, "turno: nada pendiente")
    expect(brief.summary == nil, "turno: sin resumen de píxeles")
}

@MainActor func testSeeDescribesTheScreenOnDemand() async {
    let transport = visionStub()
    let brief = await sight(transport).see(SeeRequest(app: "Numbers"))
    expect(brief?.summary?.contains("a bar chart of sales") == true, "see: la transcripcion tal cual")
    expectEq(transport.requests.count, 1, "see: una llamada")
}

@MainActor func testTheSeeToolIsOfferedOnlyWithVisionBehindIt() async {
    let hands = FakeHands(field: FocusedField(app: "Numbers", pid: 7))
    let with = ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.iWork.Numbers" },
            see: { _ in ScreenBrief(summary: "a bar chart of sales") }))
    expect(with.specs(.es).contains { $0.name == "see" }, "see: ofrecida con visión")
    let out = await with.execute(name: "see", argumentsJSON: "{}")
    expect(out.ok && out.output.contains("a bar chart of sales"), "see: devuelve la descripción")
    let without = handsRunner(hands)
    expect(!without.specs(.es).contains { $0.name == "see" }, "see: sin visión, no se ofrece")
}
