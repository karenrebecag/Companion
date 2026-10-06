import CompanionCore
import Foundation

// Arc's agent-run on the island (uiarc.dev, Pro): every step sits on a rail
// that fills as the specialist works, names what it is doing while it runs
// and what it did once done, and older steps fold away so the island keeps
// its height. Pure, so titles and folding are checked without a view.

/// What a step does, picked from the specialist's tool name.
enum AgentRunKind: Equatable {
    case search, web, open, read, write, edit, run, delegate, plan, other

    init(tool: String) {
        switch tool {
        case "Grep", "Glob": self = .search
        case "WebSearch": self = .web
        case "WebFetch": self = .open
        case "Read", "NotebookRead": self = .read
        case "Write": self = .write
        case "Edit", "MultiEdit", "NotebookEdit": self = .edit
        case "Bash": self = .run
        case "Task", "Agent": self = .delegate
        case "TodoWrite": self = .plan
        default: self = .other
        }
    }

    fileprivate var key: String? {
        switch self {
        case .search: "search"
        case .web: "web"
        case .open: "open"
        case .read: "read"
        case .write: "write"
        case .edit: "edit"
        case .run: "run"
        case .delegate: "delegate"
        case .plan: "plan"
        case .other: nil
        }
    }
}

struct AgentRunStep: Equatable, Identifiable {
    enum Status: Equatable { case active, done, failed }
    let id: String
    let kind: AgentRunKind
    let title: String
    let icon: String
    let status: Status
    let duration: String?

    /// The rail below a node fills once its step is behind the specialist.
    var railFill: Double { status == .active ? 0 : 1 }
}

enum AgentRunModel {
    /// At rest the island shows the newest steps only; the rest fold into one line.
    static let restingRows = 3

    static func steps(steps: [JobStepInfo], now: Date, language: AppLanguage) -> [AgentRunStep] {
        let rows = RunCardModel.rows(steps: steps, now: now)
        let byId = Dictionary(steps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.compactMap { row in
            guard let info = byId[row.id] else { return nil }
            let status: AgentRunStep.Status = switch row.state {
            case .live: .active
            case .done: .done
            case .failed: .failed
            }
            let kind = AgentRunKind(tool: info.tool)
            return AgentRunStep(id: row.id, kind: kind,
                                title: title(kind: kind, info: info, status: status, language: language),
                                icon: JobSteps.icon(for: info.tool), status: status, duration: row.duration)
        }
    }

    /// The steps worth a row now, and how many older ones fold above them.
    static func visible(_ steps: [AgentRunStep], expanded: Bool) -> (folded: Int, shown: [AgentRunStep]) {
        guard !expanded, steps.count > restingRows else { return (0, steps) }
        // Parallel tools can finish after one that still runs: a live step
        // stays in view wherever it sits.
        let recent = steps.count - restingRows
        let shown = steps.enumerated().filter { $0.offset >= recent || $0.element.status == .active }.map(\.element)
        return (steps.count - shown.count, shown)
    }

    /// The run's loader: turning while anything runs, then the fate of the last step.
    static func status(_ steps: [JobStepInfo]) -> MorphLoaderStatus {
        let real = steps.filter { $0.tool != JobSteps.Thinking.tool }
        guard let last = real.last, real.allSatisfy(\.done) else { return .loading }
        return last.failed ? .error : .success
    }

    /// What VoiceOver says of a step's state.
    static func stateKey(_ status: AgentRunStep.Status) -> String {
        switch status {
        case .active: "island.runcard.state.running"
        case .done: "island.runcard.state.done"
        case .failed: "island.runcard.state.failed"
        }
    }

    private static func title(kind: AgentRunKind, info: JobStepInfo, status: AgentRunStep.Status,
                              language: AppLanguage) -> String {
        let cleaned = RunCardModel.goal(info.label)
        guard let kind = kind.key else { return cleaned }
        let tense = switch status {
        case .active: "active"
        case .done: "done"
        case .failed: "failed"
        }
        let object = summary(of: info)
        let key = "agentrun.\(kind).\(tense)" + (object == nil ? ".bare" : "")
        let format = Localized.string(key, language: language)
        return object.map { String(format: format, $0) } ?? format
    }

    /// "Read: inventario.md" -> "inventario.md"; nil when the step is the bare tool.
    private static func summary(of info: JobStepInfo) -> String? {
        let cleaned = RunCardModel.goal(info.label)
        let prefix = info.tool + ": "
        guard cleaned.hasPrefix(prefix) else { return nil }
        let rest = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}
