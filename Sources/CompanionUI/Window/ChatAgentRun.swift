import CompanionCore
import CompanionUIPro
import SwiftUI

/// A specialist's job as Arc's agent-run: the one place that turns Companion's
/// job timeline into the port's run, for the chat thread and the notch card.
/// Titles, icons and durations are the island run's own (AgentRunModel), so a
/// step reads the same wherever it shows.
enum ChatAgentRun {
    /// The run while the job works.
    static func live(_ job: JobTimeline, now: Date, language: AppLanguage = Localized.language()) -> AIAgentRun {
        AIAgentRun(steps: steps(job.steps, now: now, language: language), phase: .running,
                   worked: RunCardDuration.step(now.timeIntervalSince(job.startedAt)))
    }

    /// The run as the job ended. A step still open when it ended did not
    /// finish: shown as running it would claim work that is not happening.
    static func finished(_ record: JobRecord, language: AppLanguage = Localized.language()) -> AIAgentRun {
        let settled = record.timeline.steps.map { step in
            var closed = step
            if !closed.done {
                closed.done = true
                closed.failed = record.outcome != .done
                closed.finishedAt = closed.finishedAt ?? record.finishedAt
            }
            return closed
        }
        let phase: AIAgentRun.Phase = switch record.outcome {
        case .done: .done
        case .failed: .failed
        case .stopped: .stopped
        }
        return AIAgentRun(steps: steps(settled, now: record.finishedAt, language: language), phase: phase,
                          worked: RunCardDuration.step(record.finishedAt.timeIntervalSince(record.timeline.startedAt)))
    }

    /// Thoughts stay in the answer's reasoning fold and bookkeeping tools stay
    /// out, so the rail holds only what the specialist did. The detail is the
    /// step's own line, offered only when it says more than the title.
    static func steps(_ steps: [JobStepInfo], now: Date, language: AppLanguage) -> [AIAgentRunStep] {
        let shown = steps.filter { !JobSteps.isHidden($0.tool) }
        let byID = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return AgentRunModel.steps(steps: shown, now: now, language: language).map { step in
            let info = byID[step.id]
            let line = info.map { RunCardModel.goal($0.label) }
            // The title already carries what follows the tool's name.
            let said = line.map { text in
                info.map { text.hasPrefix($0.tool + ": ") ? String(text.dropFirst($0.tool.count + 2)) : text } ?? text
            }
            let status: AIAgentRunStep.Status = switch step.status {
            case .active: .active
            case .done: .done
            case .failed: .failed
            }
            return AIAgentRunStep(
                id: step.id, symbol: step.icon, title: step.title, status: status, duration: step.duration,
                detail: said.flatMap { $0.isEmpty || step.title.contains($0) ? nil : line })
        }
    }

    /// The finished job of the newest turn: what the notch card summarises.
    static func latestRecord(_ messages: [ChatMessage]) -> JobRecord? {
        let turnStart = messages.lastIndex { $0.role == .user && !$0.isStatus }.map { $0 + 1 } ?? 0
        return messages[turnStart...].last { $0.job != nil }?.job
    }

    static var strings: AIAgentRunStrings {
        AIAgentRunStrings(
            running: Localized.string("chat.run.running"),
            done: Localized.string("chat.run.done"),
            failed: Localized.string("chat.run.failed"),
            stopped: Localized.string("chat.run.stopped"),
            worked: Localized.string("chat.run.worked"),
            stepsOne: Localized.string("chat.run.steps.one"),
            stepsOther: Localized.string("chat.run.steps.other"),
            foldedOne: Localized.string("agentrun.folded.one"),
            foldedOther: Localized.string("agentrun.folded"),
            stepRunning: Localized.string("island.runcard.state.running"),
            stepDone: Localized.string("island.runcard.state.done"),
            stepFailed: Localized.string("island.runcard.state.failed"),
            timeline: Localized.string("chat.run.timeline"))
    }
}

extension AIThreadStyle {
    /// The run on the notch card's dark document: the card's own white inks,
    /// so the timeline reads as part of the document, not a pasted window.
    static var notchRun: AIThreadStyle {
        let white = Color.white
        return AIThreadStyle(
            foreground: white.opacity(DocCardInk.value),
            secondary: white.opacity(DocCardInk.secondary),
            muted: white.opacity(DocCardInk.label),
            surface: DocCardInk.surface.color,
            surfaceMuted: DocCardInk.toolFill.color,
            border: white.opacity(DocCardInk.lineStrong),
            borderStrong: white.opacity(DocCardInk.lineStrong),
            userBubble: DocCardInk.toolFill.color,
            // The island's accent, the same blue its live run turns in.
            primary: ArcTone.accent.color,
            primaryForeground: DocCardInk.surface.color,
            success: DocCardInk.checkMark.color,
            body: Fonts.geist(DocCardMetrics.tableSize),
            caption: Fonts.geist(DocCardMetrics.sourceSize),
            mono: .uiMono,
            danger: ArcTone.danger.color)
    }
}
