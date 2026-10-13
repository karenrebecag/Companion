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
