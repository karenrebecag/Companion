import Foundation

/// Native is always present; CLI adapters are detected later (ADR 001).
package struct ExecutorID: RawRepresentable, Hashable, Sendable {
    package var rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }

    package static let native = ExecutorID(rawValue: "native")
    /// Prefix, not equality: each claude tier is its own row
    /// (claude-code:opus), and routing only cares about the family.
    package static let claudeCode = ExecutorID(rawValue: "claude-code")
    package static let hermes = ExecutorID(rawValue: "hermes")
}

/// What a lane can actually do. Declared so a job can be sent where the
/// capability lives instead of failing in the lane that happened to be
/// selected — which is how a request for cinemas died in the native lane while
/// an installed Claude Code sat next to it with web search included.
package enum ExecutorCapability: String, Sendable, CaseIterable {
    case files, shell, web, places
}

package struct ExecutorDescriptor: Sendable, Equatable, Identifiable {
    package var id: ExecutorID
    package var shortName: String
    package var title: String
    package var kind: Kind
    package var modelArgs: [String]
    package var capabilities: Set<ExecutorCapability>

    package enum Kind: Sendable, Equatable {
        case native
        case detectedCLI
    }

    package init(
        id: ExecutorID,
        shortName: String,
        title: String,
        kind: Kind,
        modelArgs: [String] = [],
        capabilities: Set<ExecutorCapability> = ExecutorCapability.cli
    ) {
        self.id = id
        self.shortName = shortName
        self.title = title
        self.kind = kind
        self.capabilities = capabilities
        self.modelArgs = modelArgs
    }
}

extension ExecutorCapability {
    /// What a detected CLI specialist brings. Claude Code ships WebSearch and
    /// WebFetch as built-in tools — both this repo and the prototype already
    /// pass them in `--allowedTools` — and hermes carries its own toolset.
    package static let cli: Set<ExecutorCapability> = [.files, .shell, .web]
}

/// Which lane does the WORK, which is not the same question as which lane you
/// picked to talk to.
///
/// Ported from the prototype, where the rule was hardcoded to claude
/// (`workExecutor(claudeInstalled:)`). Generalised here: a job goes to a lane
/// that has what it needs, and the selected one wins whenever it qualifies.
package enum WorkRouting: Sendable {
    /// The work goes to the most capable installed lane, with the selected one
    /// winning every tie.
    ///
    /// No guessing about what a job "needs": inferring that from the wording
    /// of a goal is a keyword heuristic, and this codebase has one of those
    /// already, marked as a HACK. The prototype did not guess either — it sent
    /// the work to claude whenever claude was installed. This is that rule
    /// with the specific vendor taken out of it.
    package static func executor(
        selected: ExecutorID,
        installed: [ExecutorDescriptor]
    ) -> ExecutorID {
        // Ranked by kind, not by counting capabilities. Counting looked
        // principled and was wrong: the native lane has `.places` and a CLI
        // lane has `.web`, so they tie at three each and neither dominates —
        // and a tie left the work in the weakest lane, which is the exact bug
        // this routing exists to fix. A detected specialist is the one with
        // the tools; native is the floor that always exists (ADR 001).
        if let chosen = installed.first(where: { $0.id == selected }),
           chosen.kind == .detectedCLI {
            return selected
        }
        let specialist = installed.first { $0.kind == .detectedCLI }
        return specialist?.id ?? selected
    }

    /// True when the work left the lane the user picked. The prototype said so
    /// in the status line; a routing nobody can see is the app deciding behind
    /// your back.
    package static func overrides(
        selected: ExecutorID, chosen: ExecutorID
    ) -> Bool {
        selected != chosen
    }
}

package enum ExecutorCatalog: Sendable {
    package static let native = ExecutorDescriptor(
        id: .native,
        shortName: "native",
        title: "Nativo",
        kind: .native,
        // No `.web`: our own web_search needs a key that the base tier does
        // not have, and a lane that claims a capability it lacks is what sends
        // a model down a road that dead-ends.
        capabilities: [.files, .shell, .places]
    )

    /// Native first; later detections append. Duplicate ids are skipped so
    /// a probe cannot hide or double the built-in executor.
    package static func list(detected: [ExecutorDescriptor]) -> [ExecutorDescriptor] {
        var seen: Set<ExecutorID> = [native.id]
        var result = [native]
        for descriptor in detected where seen.insert(descriptor.id).inserted {
            result.append(descriptor)
        }
        return result
    }
}
