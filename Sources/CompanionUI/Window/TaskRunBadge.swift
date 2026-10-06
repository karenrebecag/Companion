import CompanionCore
import SwiftUI

/// What a task's work state and length say in words, shared by Home's row and
/// the detail sheet so both read the same.
enum TaskRunCopy {
    static func stateKey(_ state: TaskRun.State) -> String {
        switch state {
        case .running: "island.runcard.state.running"
        case .done: "island.runcard.state.done"
        case .failed: "island.runcard.state.failed"
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        if whole < 60 { return String(format: Localized.string("task.duration.seconds"), whole) }
        if whole < 3_600 { return String(format: Localized.string("task.duration.minutes"), whole / 60) }
        return String(format: Localized.string("task.duration.hours"), whole / 3_600)
    }

    /// The state, then how long it ran or has run; nil when the task has no
    /// record (saved before it was kept).
    static func summary(_ run: TaskRun?, live: Bool, now: Date = Date()) -> String? {
        guard let shown = run?.shown(live: live) else { return nil }
        let state = Localized.string(stateKey(shown.state))
        guard let seconds = shown.duration(now: now) else { return state }
        return "\(state) · \(duration(seconds))"
    }
}

/// A small status pill in the island's status colors.
struct TaskRunBadge: View {
    let state: TaskRun.State

    var body: some View {
        Text(Localized.string(TaskRunCopy.stateKey(state)))
            .font(Fonts.sans(TypeSize.caption).weight(.medium))
            .foregroundStyle(ink)
            .padding(.horizontal, Space.x2)
            .padding(.vertical, Space.x0_5)
            .background(Capsule().fill(wash))
    }

    private var ink: Color {
        switch state {
        case .running: Semantic.warning
        case .done: Semantic.success
        case .failed: Semantic.danger
        }
    }

    private var wash: Color {
        switch state {
        case .running: Semantic.warningMuted
        case .done: Semantic.successMuted
        case .failed: Semantic.dangerMuted
        }
    }
}
