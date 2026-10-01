import CompanionCore
import Foundation

/// Words for the island, ours, from the catalog.
enum IslandCopy {
    static func receipt(_ receipt: UndoReceipt) -> String {
        let key = switch receipt.kind {
        case .created: "island.receipt.created"
        case .wrote: "island.receipt.wrote"
        case .undone: "island.receipt.undone"
        case .couldNotUndo: "island.receipt.undoFailed"
        }
        return String(format: Localized.string(key), receipt.subject)
    }

    static func line(_ line: IslandState.Line) -> String {
        switch line {
        case .none: ""
        case .holdHint: Localized.string("island.hint")
        case .keyBlocked: Localized.string("island.keyBlocked")
        case .pending: Localized.string("island.pending")
        case .thinking: Localized.string("island.thinking")
        case .acting(let targets): ParentToolCopy.acting(targets, Localized.language())
        case .speaking: Localized.string("island.speaking")
        case .job(let goal, _, let steps):
            // "0 steps" is noise: the count appears once there is one.
            (goal ?? Localized.string("island.job")) + (steps == 0 ? "" : " · "
                + String(format: Localized.string(steps == 1 ? "island.job.step" : "island.job.steps"), steps))
        case .completed: Localized.string("island.completed")
        case .couldntHear: Localized.string("island.couldntHear")
        case .permission(let failure), .failure(let failure): VoiceCopy.failure(failure)
        case .dictating(let app): String(format: Localized.string("island.dictating"), app)
        case .pasting: Localized.string("island.pasting")
        case .dictated(let app): String(format: Localized.string("island.dictated"), app)
        case .dictationResult(let app, _): String(format: Localized.string("island.dictated"), app)
        case .updateAvailable(let tag): String(format: Localized.string("island.notice.update.title"), tag)
        case .transcriptsDebug: Localized.string("debug.transcriptsOn")
        case .cancelled: Localized.string("island.cancelled")
        case .followUp(let title): title
        case .dropZones: Localized.string("island.drop.title")
        case .connectApp(_, let name):
            String(format: Localized.string("island.connectApp"), name)
        case .signInApp(_, let name):
            String(format: Localized.string("island.signIn"), name)
        case .replyCut: Localized.string("island.replyCut.title")
        case .chatError(let text): text
        case .receipt(let receipt): receipt.lines.last ?? ""
        }
    }

    static func action(_ action: IslandState.Action) -> String {
        switch action {
        case .openKeys: Localized.string("island.action.keys")
        case .openPermission: Localized.string("permission.open")
        case .stopHands: Localized.string("island.hands.stop")
        case .openApps: Localized.string("island.connectApp.action")
        case .openUpdate: Localized.string("island.notice.update.action")
        }
    }

    /// The kind of line, not its words: what decides a swap (code review 16f-2).
    static func swapKey(_ line: IslandState.Line) -> String {
        switch line {
        case .permission(let failure), .failure(let failure): "failure-\(failure)"
        case .job: "job"
        case .acting: "acting"
        case .dictating: "dictating"
        case .dictated: "dictated"
        case .dictationResult: "dictationResult"
        case .updateAvailable: "updateAvailable"
        default: "\(line)"
        }
    }

    static func shimmers(_ line: IslandState.Line) -> Bool {
        switch line {
        case .pending, .thinking, .acting, .pasting: true
        default: false
        }
    }
}
