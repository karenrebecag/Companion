import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

/// A task as Karen actually leaves one: ten turns about something on screen,
/// two replies that used tools, and one long enough to scroll.
@MainActor enum TaskDetailFixture {
    static let task = ConversationMeta(
        id: "orca", title: "Botón de Orca", updatedAt: Date().addingTimeInterval(-7200))

    static func call(_ name: String) -> ToolCallRef {
        ToolCallRef(id: UUID().uuidString, name: name, arguments: "{}")
    }

    static func reply(_ text: String, tools: [String] = []) -> ChatMessage {
        ChatMessage(
            role: .assistant, text: text,
            recall: tools.isEmpty ? nil : Recall(role: .assistant, content: text, toolCalls: tools.map(call)))
    }

    static let messages: [ChatMessage] = [
        ChatMessage(role: .user, text: "Hola, me escuchas?"),
        reply("Sí, te escucho perfecto. ¿En qué te ayudo?"),
        ChatMessage(role: .user, text: "¿Qué es esto que estoy señalando?"),
        reply(
            "Estás señalando el botón **Nueva pestaña** de Orca, arriba a la derecha de la barra de pestañas. Abre una terminal nueva dentro del worktree activo.",
            tools: ["see"]),
        ChatMessage(role: .user, text: "¿Y el ícono de al lado?"),
        reply("Es el selector de agente: eliges con qué se abre la pestaña nueva, Claude, Codex o una terminal vacía."),
        ChatMessage(
            role: .user, text: "Ábreme una con Claude en el worktree de companion.",
            attachments: [AttachmentRef(name: "plan-orca.md", path: "/tmp/plan-orca.md", kind: .file)]),
        ChatMessage(isStatus: true, text: "Hice clic en Nueva pestaña."),
        reply("Listo. Abrí una pestaña con Claude en **companion-next**; ya está escribiendo en ella.", tools: ["look", "click"]),
        ChatMessage(role: .user, text: "¿Cómo la cierro sin perder lo que hizo?"),
        reply("""
        Tienes dos caminos y ninguno borra el trabajo:

        - Escribe `/exit` en la pestaña. Claude termina el turno y la sesión queda en el historial de Orca.
        - O ciérrala con ⌘W. Orca guarda la conversación y el worktree sigue con sus cambios.

        Lo único que se pierde es lo que no esté guardado en disco, así que si tiene un archivo abierto a medias, pídele que lo guarde antes.
        """),
    ]
}

/// Before/after captures of the task sheet at its real size. Off by default:
/// `COMPANION_SNAPSHOTS=<dir>` turns it on and `COMPANION_SHOT_TAG` names the run.
@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func taskDetailGallery() async throws {
    let env = ProcessInfo.processInfo.environment
    let dir = try #require(env["COMPANION_SNAPSHOTS"], "gallery: directory")
    let tag = env["COMPANION_SHOT_TAG"] ?? "after"
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let size = CGSize(width: MainWindowMetrics.detailMaxWidth, height: MainWindowMetrics.detailMaxHeight)
    for scheme in [ColorScheme.light, .dark] {
        try await saveLive(
            AnyView(TaskDetailSheet(
                task: TaskDetailFixture.task, messages: TaskDetailFixture.messages,
                canFollowUp: true, onFollowUp: { _ in true }, onClose: {})),
            scheme: scheme, size: size, to: out,
            "task-detail-\(tag)-\(scheme == .dark ? "dark" : "light")")
    }
    guard tag == "after" else { return }
    // The composer's other faces: words written, another turn busy, no messages.
    let states: [(String, [ChatMessage], Bool, String, ColorScheme)] = [
        ("typing", TaskDetailFixture.messages, true, "Ciérrala tú y dime qué quedó guardado", .light),
        ("busy", TaskDetailFixture.messages, false, "", .dark),
        ("empty", [], true, "", .light),
    ]
    for (name, messages, canFollowUp, draft, scheme) in states {
        try await saveLive(
            AnyView(TaskDetailSheet(
                task: TaskDetailFixture.task, messages: messages, canFollowUp: canFollowUp,
                draft: draft, onFollowUp: { _ in true }, onClose: {})),
            scheme: scheme, size: size, to: out, "task-detail-state-\(name)")
    }
}
