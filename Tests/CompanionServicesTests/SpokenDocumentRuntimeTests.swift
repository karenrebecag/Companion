import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// El contrato de documento, de punta a punta por el camino real: las lineas
// SSE con la forma que Cerebras mando en vivo (2026-10-12) entran por
// ChatProviderClient, el runtime clasico dice solo la frase, el hilo guarda
// frase y documento, y la marca del documento sale antes de replyCompleted.

@Test @MainActor func spokenDocumentRuntimeTests() async {
    await testAShowDocumentCallSpeaksTheSentenceAndThreadsTheDocument()
    await testAPlainAnswerIsSpokenWholeWithNoDocument()
    await testAFileRequestGoesToCreateDocumentNotTheIsland()
}

/// The streamed tool call as Cerebras delivered it live (run doc2-1,
/// "tabla"): the id and name first, the arguments in fragments.
private let liveShowDocumentLines: [String] = [
    #"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#,
    #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"show_document","arguments":""}}]}}]}"#,
    #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"say\":\"Aquí tienes la comparación solicitada.\",\"title\":\"Comparación de smartphones\",\"markdown\":\"| Modelo | Pantalla | Cámara |\\n|---|---|---|\\n"}}]}}]}"#,
    #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"| iPhone 17 | 6.7\\\" OLED, 120Hz | Triple 48 MP |\\n"}}]}}]}"#,
    #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"| Pixel 10 | 6.4\\\" OLED, 90Hz | Dual 50 MP |\\n"}}]}}]}"#,
    #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"| Galaxy S26 | 6.8\\\" AMOLED, 120Hz | Quad 108 MP |\\n\"}"}}]}}]}"#,
    #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
    SSEFixtures.done,
]

/// "¿Qué hora es en Tokio?" as it came live (run doc2-1): content only.
private let liveTokyoLines: [String] = [
    SSEFixtures.content("Son las 08:02 del 13 de octubre "),
    SSEFixtures.content("de 2026 en Tokio."),
    #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
    SSEFixtures.done,
]

/// "Hazme un PDF con esa tabla" as it came live (run doc2-2): the file tool.
private let liveCreateDocumentLines: [String] = [
    #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c2","type":"function","function":{"name":"create_document","arguments":""}}]}}]}"#,
    #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"document\":\"{\\\"title\\\":\\\"Comparativa\\\",\\\"blocks\\\":[]}\","}}]}}]}"#,
    #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"path\":\"~/Desktop/comparativa.pdf\"}"}}]}}]}"#,
    #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
    SSEFixtures.done,
]

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TurnEvent] = []
    var all: [TurnEvent] { lock.withLock { items } }
    func append(_ e: TurnEvent) { lock.withLock { items.append(e) } }
}

/// The real chat client over the Cerebras descriptor, fed canned SSE lines.
@MainActor private func documentRuntime(
    lines: [String], synth: ScriptedSynth, thread: ScriptedThread
) -> (ClassicRuntime, ScriptedTransport) {
    let transport = ScriptedTransport()
    transport.stub(.cerebras, ScriptedReply(lines: lines))
    let chat = ChatProviderClient(
        secrets: TestSecretStore([.cerebras: "csk-test"]),
        probe: TestProbe(available: ["cerebras"]),
        transport: transport, ownerFirstName: "Karen",
        catalog: [ProviderDescriptor.cerebras], voice: true)
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "compara los teléfonos"
    let runtime = ClassicRuntime(transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    return (runtime, transport)
}

@MainActor func testAShowDocumentCallSpeaksTheSentenceAndThreadsTheDocument() async {
    let synth = ScriptedSynth()
    let thread = ScriptedThread()
    let events = EventBox()
    let (runtime, transport) = documentRuntime(lines: liveShowDocumentLines, synth: synth, thread: thread)
    await runtime.submit(config: Config(language: .es)) { events.append($0) }
    expectEq(synth.queue, ["Aquí tienes la comparación solicitada."], "documento: la voz dice solo la frase")
    let threaded = thread.turns.last { $0.role == .assistant }?.content ?? ""
    expect(threaded.hasPrefix("Aquí tienes la comparación solicitada.\n\n| Modelo | Pantalla | Cámara |\n|---|---|---|\n"),
           "documento: el hilo guarda la frase y la tabla entera")
    expect(threaded.contains("| Galaxy S26 | 6.8\" AMOLED, 120Hz | Quad 108 MP |"), "documento: hasta la ultima fila")
    expect(!thread.stream.contains("|"), "documento: el subtitulo nunca vio la tabla")
    let order = events.all
    let mark = order.firstIndex(of: .replyHasDocument)
    let done = order.firstIndex(of: .replyCompleted)
    expect(mark != nil && done != nil && mark! < done!, "documento: la marca llega antes de replyCompleted")
    // The request carried the tool, so the model could take it.
    let body = transport.requests.first.map { chatBody($0) } ?? [:]
    let names = (body["tools"] as? [[String: Any]] ?? []).compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
    expect(names.contains("show_document"), "documento: la request anuncia show_document")
    expect(!(body["tools"] as? [[String: Any]] ?? []).contains { ($0["function"] as? [String: Any])?["strict"] != nil },
           "documento: sin strict para Cerebras")
}

@MainActor func testAPlainAnswerIsSpokenWholeWithNoDocument() async {
    let synth = ScriptedSynth()
    let thread = ScriptedThread()
    let events = EventBox()
    let (runtime, _) = documentRuntime(lines: liveTokyoLines, synth: synth, thread: thread)
    await runtime.submit(config: Config(language: .es)) { events.append($0) }
    expectEq(synth.queue.joined(separator: " "), "Son las 08:02 del 13 de octubre de 2026 en Tokio.",
             "plana: se dice entera")
    expectEq(thread.turns.last { $0.role == .assistant }?.content,
             "Son las 08:02 del 13 de octubre de 2026 en Tokio.", "plana: el hilo guarda la frase")
    expect(!events.all.contains(.replyHasDocument), "plana: sin documento")
    expect(events.all.contains(.replyCompleted), "plana: el turno termina")
}

@MainActor func testAFileRequestGoesToCreateDocumentNotTheIsland() async {
    // The same SSE layer the runtime reads: the file tool arrives as a tool
    // call for the parent's hands, never as a document for the island.
    let transport = ScriptedTransport()
    transport.stub(.cerebras, ScriptedReply(lines: liveCreateDocumentLines))
    let deltas = collectChat(
        makeChatClient(
            keys: [.cerebras: "csk-test"], available: ["cerebras"],
            transport: transport, catalog: [ProviderDescriptor.cerebras]),
        tools: [NativeTool.createDocument.spec, SpokenDocument.spec(.es)])
    expectEq(deltas, [.toolCalls([ToolCallRef(
        id: "c2", name: "create_document",
        arguments: #"{"document":"{\"title\":\"Comparativa\",\"blocks\":[]}","path":"~/Desktop/comparativa.pdf"}"#)])],
             "archivo: la tool del archivo llega entera como llamada, sin documento ni texto")
}
