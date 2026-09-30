import Foundation

/// N2 sees the top actions N1 already weighed, each with the candidates N0
/// offered for it. It never sees the installed-app list and it never emits
/// a free tool call: the only legal result is one of these ids.
public struct ShortlistEntry: Sendable, Equatable {
    public var id: String
    public var action: DecisionAction
    public var args: [String: PlanValue]
    public var mass: Double

    public init(id: String, action: DecisionAction, args: [String: PlanValue], mass: Double) {
        self.id = id
        self.action = action
        self.args = args
        self.mass = mass
    }
}

extension ShortlistEntry {
    /// N2 already chose one id off the shortlist; this turns that choice into
    /// the same `Plan` shape N1 would have produced, so "irreversible always
    /// confirms" lives once in `PlanThreshold` and not again on N2's path.
    public func plan(utterance: String, confidence: Double, trust: Double?) -> Plan {
        let risk = Plan.risk(action: action, args: args)
        let disposition = PlanThreshold.evaluate(
            action: action, risk: risk, confidence: confidence,
            argumentsComplete: true, directed: false, trust: trust)
        return Plan(
            utterance: utterance, action: action, args: args,
            confidence: confidence, risk: risk, disposition: disposition)
    }
}

/// `choiceSchema` never swallows a failure: an empty shortlist and a
/// non-UTF8 encoding are both a thrown error, not a silent `""`.
public enum ArbitrationSchemaError: Error, Sendable, Equatable {
    case emptyShortlist
    case notUTF8
}

public struct ArbitrationShortlist: Sendable, Equatable {
    public var entries: [ShortlistEntry]

    public init(entries: [ShortlistEntry]) {
        var seen: Set<String> = []
        self.entries = entries.filter { seen.insert($0.id).inserted }
    }

    public var allowedIds: [String] { entries.map(\.id) }

    public func accepts(_ choice: String) -> Bool {
        entries.contains { $0.id == choice }
    }

    public func entry(for id: String) -> ShortlistEntry? {
        entries.first { $0.id == id }
    }

    /// `ToolSpec.strict` closes the object and does not enum the string.
    /// This schema is the enum. An id that is not in it is not a choice.
    /// An empty shortlist would serialize to `enum: []`, which OpenAI strict
    /// mode rejects — that state throws instead of handing back a broken
    /// schema silently, same as a real `JSONSerialization` failure.
    public func choiceSchema() throws -> String {
        guard !entries.isEmpty else { throw ArbitrationSchemaError.emptyShortlist }
        let parameters: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["choice"],
            "properties": [
                "choice": [
                    "type": "string",
                    "enum": allowedIds,
                    "description": "one id from this list",
                ],
            ],
        ]
        let body: [String: Any] = [
            "name": "arbitrate",
            "description": "Pick one shortlist id. Do not invent an id or a tool call.",
            "parameters": parameters,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ArbitrationSchemaError.notUTF8
        }
        return json
    }

    public static func build(
        utterance: String, world: DecisionWorld, actionMass: [String: Double]
    ) -> ArbitrationShortlist {
        let top = actionMass.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(3)
        var entries: [ShortlistEntry] = []
        for (raw, mass) in top {
            guard let action = DecisionAction(rawValue: raw) else { continue }
            entries.append(contentsOf: expand(action, mass: mass, utterance: utterance, world: world))
        }
        return ArbitrationShortlist(entries: entries)
    }
}

/// Below this the fast tier does not get the last word. The strong tier is
/// asked the same constrained question. Jev's fast-tier floor.
public enum ArbitrationTier {
    public static let fastDoubt = 0.5

    public static func needsStrong(fastConfidence: Double) -> Bool {
        fastConfidence < fastDoubt
    }
}

/// `0.75 − 0.4 · trust`, clamped to 0.35...0.75. Trust 1 arbitrates rarely;
/// trust 0 arbitrates often. It never removes the irreversible confirmation.
public enum AppTrust {
    public static func threshold(for trust: Double) -> Double {
        let clamped = min(1, max(0, trust.isFinite ? trust : 0))
        let raw = 0.75 - 0.4 * clamped
        let bounded = min(0.75, max(0.35, raw))
        return (bounded * 100).rounded() / 100
    }
}

public struct LearnedAppRule: Sendable, Equatable {
    public var app: String
    public var trust: Double
    public var rule: String

    public init(app: String, trust: Double, rule: String) {
        self.app = app
        self.trust = min(1, max(0, trust.isFinite ? trust : 0))
        self.rule = rule.count > 200 ? String(rule.prefix(200)) : rule
    }
}

private func expand(
    _ action: DecisionAction, mass: Double, utterance: String, world: DecisionWorld
) -> [ShortlistEntry] {
    func one(_ id: String, _ args: [String: PlanValue]) -> ShortlistEntry {
        ShortlistEntry(id: id, action: action, args: args, mass: mass)
    }
    switch action {
    case .openApp:
        return CandidateSets.appCandidates(utterance, apps: world.apps).map {
            one("open_app:\($0.id)", ["app": .text($0.id)])
        }
    case .openURL:
        return CandidateSets.siteCandidates(utterance, sites: world.sites).map {
            one("open_url:\($0.id)", ["url": .text($0.detail)])
        }
    case .openFile:
        return CandidateSets.fileCandidates(utterance, files: world.files).map {
            one("open_file:\($0.id)", ["path": .text($0.id)])
        }
    case .readSkill:
        return CandidateSets.skillCandidates(utterance, skills: world.skills).map {
            one("read_skill:\($0.id)", ["name": .text($0.id)])
        }
    case .findPlaces:
        return CandidateSets.textSpans(utterance).map {
            one("find_places:\($0.id)", ["query": .text($0.detail)])
        }
    case .typeText:
        return CandidateSets.textSpans(utterance).flatMap { span in
            [
                one("type_text:\(span.id):no", ["text": .text(span.detail), "submit": .flag(false)]),
                one("type_text:\(span.id):yes", ["text": .text(span.detail), "submit": .flag(true)]),
            ]
        }
    case .task:
        return CandidateSets.textSpans(utterance).map {
            one("task:\($0.id)", ["goal": .text($0.detail)])
        }
    case .volume:
        return CandidateSets.volumeOps.map { one("volume:\($0.id)", ["op": .text($0.id)]) }
    case .shortcut:
        return CandidateSets.shortcuts.map { one("shortcut:\($0.id)", ["shortcut": .text($0.id)]) }
    case .media:
        return CandidateSets.mediaOps.map { one("media:\($0.id)", ["op": .text($0.id)]) }
    case .system:
        return CandidateSets.systemOps.map { one("system:\($0.id)", ["op": .text($0.id)]) }
    case .scroll:
        return CandidateSets.scrollDirections.flatMap { direction in
            CandidateSets.scrollAmounts.map { amount in
                one("scroll:\(direction.id):\(amount.id)", [
                    "direction": .text(direction.id),
                    "amount": .text(amount.id),
                ])
            }
        }
    case .listApps:
        return [one("list_apps", [:])]
    case .none:
        return [one("none", [:])]
    }
}
