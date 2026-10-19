import AppKit
import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

/// The window's conversation as Arc's ai-chat: a table answer with sources
/// and a citation, an answer that used tools, and a turn still streaming.
@MainActor enum ChatArcFixture {
    static let task = ConversationMeta(id: "vuelos", title: "Vuelos a Lima", updatedAt: Date().addingTimeInterval(-600))

    static let table: [ChatMessage] = [
        ChatMessage(role: .user, text: "¿Cuánto cuesta volar de CDMX a Lima en noviembre?"),
        ChatMessage(role: .assistant, text: """
        Encontré tres opciones directas; **Aeroméxico** es la más barata esa semana [1].

        | Aerolínea | Salida | Precio |
        |---|---|--:|
        | Aeroméxico | 08:10 | $412 |
        | LATAM | 13:45 | $455 |
        | Volaris | 22:30 | $468 |

        Si puedes salir un martes, el precio baja cerca de un 8 % [2].

        Fuentes:
        - [Vuelos CDMX a Lima](https://www.kayak.com.mx/vuelos/MEX-LIM) precios del 12 de octubre
        - [Tarifas LATAM](https://www.latamairlines.com/mx/es/ofertas)
        """),
    ]

    static let tools: [ChatMessage] = {
        let call = ToolCallRef(id: "c1", name: "open_app", arguments: #"{"name":"Notas"}"#)
        let look = ToolCallRef(id: "c2", name: "see", arguments: "{}")
        return [
            ChatMessage(role: .user, text: "Abre Notas y dime qué tengo en la última nota."),
            ChatMessage(isStatus: true, text: "Abriendo Notas…",
                        recall: Recall(role: .assistant, content: "", toolCalls: [call, look])),
            ChatMessage(isStatus: true, text: "Abrí Notas", recall: Recall(role: .tool, content: "ok", toolCallID: "c1")),
            ChatMessage(isStatus: true, text: "Vi la pantalla", recall: Recall(role: .tool, content: "ok", toolCallID: "c2")),
            ChatMessage(role: .assistant, text: """
            Tu última nota se llama **Pendientes de la semana** y tiene cuatro cosas:

            1. Mandar la cotización de Pigmento.
            2. Revisar el PR de `companion-next`.
            3. Comprar boletos a Lima.
            4. Llamar al dentista.

            ```bash
            open -a Notes
            ```
            """),
        ]
    }()

    /// The same turn with a browser step that failed: its step is drawn failed,
    /// and the run's summary does not show a done check.
    static let toolsFailed: [ChatMessage] = {
        let open = ToolCallRef(id: "c1", name: "browser_open", arguments: #"{"url":"https://example.com"}"#)
        let click = ToolCallRef(id: "c2", name: "browser_click", arguments: #"{"element":3}"#)
        return [
            ChatMessage(role: .user, text: "Abre la página y haz clic en el menú."),
            ChatMessage(isStatus: true, text: "Abriendo la página…",
                        recall: Recall(role: .assistant, content: "", toolCalls: [open, click])),
            ChatMessage(isStatus: true, text: "Abrí una pestaña de fondo.",
                        recall: Recall(role: .tool, content: "ok", toolCallID: "c1")),
            ChatMessage(isStatus: true, text: "Navegador: Menú o lista no encontrada.",
                        recall: Recall(role: .tool, content: "not_found", toolCallID: "c2"), stepFailed: true),
            ChatMessage(role: .assistant, text: "No encontré el menú en la página."),
        ]
    }()

    /// A turn that ran out of steps: its copy says so and its run is failed.
    static let outOfSteps: [ChatMessage] = {
        let open = ToolCallRef(id: "c1", name: "browser_open", arguments: #"{"url":"https://example.com"}"#)
        return [
            ChatMessage(role: .user, text: "Busca el precio en esa página."),
            ChatMessage(isStatus: true, text: "Abriendo la página…",
                        recall: Recall(role: .assistant, content: "", toolCalls: [open])),
            ChatMessage(isStatus: true, text: "Abrí una pestaña de fondo.",
                        recall: Recall(role: .tool, content: "ok", toolCallID: "c1")),
            ChatMessage(role: .assistant, text: "Me quedé sin pasos antes de responder: abrí una pestaña de fondo.",
                        endedWithoutAnswer: true),
        ]
    }()

    static let streamingMessages: [ChatMessage] = table + [
        ChatMessage(role: .user, text: "Busca hoteles cerca de Miraflores para esas fechas."),
    ]

    static var streamingLive: ChatLive {
        let start = Date().addingTimeInterval(-6)
        let job = JobTimeline(goal: "hoteles", startedAt: start, steps: [
            JobStepInfo(tool: JobSteps.Thinking.tool,
                        label: "Busco hoteles en Miraflores para el 12 al 16 de noviembre; comparo precio y distancia al malecón.",
                        done: true, id: "t1", startedAt: start, finishedAt: start.addingTimeInterval(4)),
            JobStepInfo(tool: "WebSearch", label: "WebSearch: hoteles Miraflores noviembre", done: true,
                        id: "s1", startedAt: start, finishedAt: start.addingTimeInterval(5)),
            JobStepInfo(tool: "WebFetch", label: "WebFetch: booking.com/miraflores", id: "s2", startedAt: start),
        ])
        return ChatLive(
            streaming: "Encontré varias opciones a menos de diez minutos del malecón. La mejor relación precio",
            busy: true, job: job, now: Date())
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func chatArcGallery() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let size = CGSize(width: MainWindowMetrics.detailMaxWidth, height: MainWindowMetrics.detailMaxHeight)
    let cases: [(String, [ChatMessage], ChatLive?, ColorScheme)] = [
        ("table-sources-light", ChatArcFixture.table, nil, .light),
        ("table-sources-dark", ChatArcFixture.table, nil, .dark),
        ("tools-light", ChatArcFixture.tools, nil, .light),
        ("tools-failed-light", ChatArcFixture.toolsFailed, nil, .light),
        ("out-of-steps-light", ChatArcFixture.outOfSteps, nil, .light),
        ("streaming-light", ChatArcFixture.streamingMessages, ChatArcFixture.streamingLive, .light),
        ("streaming-dark", ChatArcFixture.streamingMessages, ChatArcFixture.streamingLive, .dark),
    ]
    for (name, messages, live, scheme) in cases {
        try await saveLive(
            AnyView(TaskDetailSheet(
                task: ChatArcFixture.task, messages: messages, live: live != nil, progress: live,
                canFollowUp: live == nil, onFollowUp: { _ in true }, onClose: {})),
            scheme: scheme, size: size, to: out, "chat-arc-\(name)")
    }
}
