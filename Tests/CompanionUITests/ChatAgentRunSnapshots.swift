import AppKit
import CompanionCore
import CompanionUIPro
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

/// The specialist's job as Arc's agent-run: live in the chat, folded once it
/// ends, a failed step open on its own, and the notch card's compact run.
@MainActor enum ChatAgentRunFixture {
    static let start = Date().addingTimeInterval(-47)

    static let steps: [JobStepInfo] = [
        JobStepInfo(tool: JobSteps.Thinking.tool, label: "Comparo hoteles en Miraflores por precio y distancia.",
                    done: true, id: "t1", startedAt: start, finishedAt: start.addingTimeInterval(3)),
        JobStepInfo(tool: "WebSearch", label: "WebSearch: hoteles Miraflores noviembre", done: true,
                    id: "s1", startedAt: start.addingTimeInterval(3), finishedAt: start.addingTimeInterval(9)),
        JobStepInfo(tool: "WebFetch", label: "WebFetch: booking.com/miraflores", done: true,
                    id: "s2", startedAt: start.addingTimeInterval(9), finishedAt: start.addingTimeInterval(21)),
        JobStepInfo(tool: "Read", label: "Read: viaje-lima.md", done: true,
                    id: "s3", startedAt: start.addingTimeInterval(21), finishedAt: start.addingTimeInterval(23)),
        JobStepInfo(tool: "Bash", label: "Bash: python3 compara.py --zona miraflores", done: true,
                    id: "s4", startedAt: start.addingTimeInterval(23), finishedAt: start.addingTimeInterval(31)),
        JobStepInfo(tool: "Write", label: "Write: hoteles-miraflores.md", id: "s5",
                    startedAt: start.addingTimeInterval(31)),
    ]

    static let question = ChatMessage(role: .user, text: "Busca hoteles cerca del malecón de Miraflores.")

    static var live: ChatLive {
        ChatLive(streaming: "", busy: true,
                 job: JobTimeline(goal: "hoteles", startedAt: start, steps: steps), now: Date())
    }

    static func finished(_ outcome: JobRecord.Outcome) -> [ChatMessage] {
        var settled = steps
        if outcome == .done {
            settled[5].done = true
            settled[5].finishedAt = start.addingTimeInterval(36)
        }
        let record = JobRecord(timeline: JobTimeline(goal: "hoteles", startedAt: start, steps: settled),
                               finishedAt: start.addingTimeInterval(36), outcome: outcome)
        return [
            question,
            ChatMessage(isStatus: true, text: "Encargo: hoteles", job: record),
            ChatMessage(role: .assistant, text: outcome == .done
                ? "Dejé tres opciones en **hoteles-miraflores.md**; la más cercana al malecón está a cuatro minutos a pie."
                : "Me detuve antes de escribir el archivo. Lo que encontré hasta ahí sigue arriba."),
        ]
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func chatAgentRunGallery() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let size = CGSize(width: MainWindowMetrics.detailMaxWidth, height: MainWindowMetrics.detailMaxHeight)
    let cases: [(String, [ChatMessage], ChatLive?, ColorScheme)] = [
        ("live-light", [ChatAgentRunFixture.question], ChatAgentRunFixture.live, .light),
        ("live-dark", [ChatAgentRunFixture.question], ChatAgentRunFixture.live, .dark),
        ("done-light", ChatAgentRunFixture.finished(.done), nil, .light),
        ("done-dark", ChatAgentRunFixture.finished(.done), nil, .dark),
        ("stopped-light", ChatAgentRunFixture.finished(.stopped), nil, .light),
    ]
    for (name, messages, live, scheme) in cases {
        try await saveLive(
            AnyView(TaskDetailSheet(
                task: ChatArcFixture.task, messages: messages, live: live != nil, progress: live,
                canFollowUp: live == nil, onFollowUp: { _ in true }, onClose: {})),
            scheme: scheme, size: size, to: out, "agent-run-chat-\(name)")
    }
    // The run as the chat would show it unfolded, with a failed step open.
    // A tool the island has no words for keeps its own line as the detail.
    var failed = Array(ChatAgentRunFixture.steps.prefix(5))
    failed.append(JobStepInfo(
        tool: "mcp__notion__create_page", label: "mcp__notion__create_page: Hoteles Miraflores",
        done: true, failed: true, id: "s5", startedAt: ChatAgentRunFixture.start.addingTimeInterval(31),
        finishedAt: ChatAgentRunFixture.start.addingTimeInterval(33)))
    let unfolded = AIAgentRun(
        steps: ChatAgentRun.steps(failed, now: Date(), language: .es), phase: .running, worked: "33s")
    for scheme in [ColorScheme.light, .dark] {
        try await saveLive(
            AnyView(AIAgentRunView(run: unfolded, strings: ChatAgentRun.strings, style: .companion)
                .padding(24).frame(width: 560).background(Semantic.background)),
            scheme: scheme, size: CGSize(width: 560, height: 420), to: out,
            "agent-run-failed-step-\(scheme == .dark ? "dark" : "light")")
    }
    // The notch card: the island is always dark.
    let messages = ChatAgentRunFixture.finished(.done)
    let record = try #require(ChatAgentRun.latestRecord(messages))
    let document = IslandResultCardModel.document(of: messages.last?.text ?? "")
    try await saveLive(
        AnyView(IslandResultCard(
            title: "Hoteles cerca del malecón de Miraflores", blocks: document.blocks, links: .none,
            maxHeight: 520, onOpenURL: { _ in }, onDismiss: nil, onContinue: {}
        ) {
            AIAgentRunView(run: ChatAgentRun.finished(record), strings: ChatAgentRun.strings, style: .notchRun,
                           density: .compact(rows: IslandResultCardMetrics.runRows))
        }
        .padding(24)),
        scheme: .dark, size: CGSize(width: DocCardMetrics.width + 48, height: 560), to: out, "agent-run-notch-card")
}
