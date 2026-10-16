import Foundation

// The pure rules around the coverage judge: how its reply is read, how a
// band may change because of it, and which provider answers. The adapter only
// carries these out, so every decision here is tested without a network.

// MARK: - Band

/// The only place the judge can change a band, and it can only take a sheet
/// off a confirm. Critical stays critical whatever the judge says: a
/// destructive target, an existing file outside the zone, or a turn that read
/// outside it is the owner's to decide, and the judge never sees it as covered.
package enum JudgeBand {
    package static func lowered(_ band: ActionBand, by opinion: JudgeOpinion?) -> ActionBand {
        guard band == .confirm, let opinion, opinion.covered else { return band }
        switch opinion.effect {
        case .undoable, .reachesSomeone: return .act
        case .irreversible: return band
        }
    }
}

// MARK: - Lanes

/// One sheet a model step would open, with what is known before anyone is asked.
package struct SheetEntry: Sendable, Equatable {
    package let band: ActionBand
    package let opinion: JudgeOpinion?
    /// The user kept a "siempre" for this request's host and kind of action.
    package let alwaysAllowed: Bool

    package init(band: ActionBand, opinion: JudgeOpinion?, alwaysAllowed: Bool) {
        self.band = band
        self.opinion = opinion
        self.alwaysAllowed = alwaysAllowed
    }
}

/// What the step's sheets come to. `free` runs without a question; `ask` goes
/// to the person, and when there are two or more they share one sheet.
package enum SheetLane: Sendable, Equatable {
    case free, ask

    package static func of(_ entries: [SheetEntry]) -> [SheetLane] {
        entries.map { entry in
            (entry.alwaysAllowed && entry.band == .confirm) || JudgeBand.lowered(entry.band, by: entry.opinion) == .act
                ? .free : .ask
        }
    }
}

// MARK: - Reply parser

/// Strict and fail-closed: a reply outside the contract fails the whole batch,
/// because a fault that cannot be pinned to one action says nothing reliable
/// about the others either.
package enum JudgeReplyParser {
    private static let entryKeys: Set<String> = ["id", "effect", "covered"]
    /// A batch is at most 8 verdicts of about 80 bytes each; 16 KB stops a
    /// runaway body before it is read.
    package static let maxBodyBytes = 16 * 1024

    package static func parse(_ data: Data, ids: [String]) -> [JudgeOpinion?] {
        let rejected = [JudgeOpinion?](repeating: nil, count: ids.count)
        guard data.count <= maxBodyBytes,
              case .object(let root)? = JSONValue.parse(data),
              Set(root.keys) == ["verdicts"],
              case .array(let entries)? = root["verdicts"],
              entries.count == ids.count
        else { return rejected }

        var byID: [String: JudgeOpinion] = [:]
        for entry in entries {
            guard let parsed = parseEntry(entry, ids: ids), byID[parsed.id] == nil else { return rejected }
            byID[parsed.id] = parsed.opinion
        }
        guard byID.count == ids.count else { return rejected }
        return ids.map { byID[$0] }
    }

    private static func parseEntry(_ entry: JSONValue, ids: [String]) -> (id: String, opinion: JudgeOpinion)? {
        guard case .object(let object) = entry,
              Set(object.keys) == entryKeys,
              case .string(let id)? = object["id"], ids.contains(id),
              case .string(let raw)? = object["effect"], let effect = JudgeEffect(rawValue: raw),
              case .bool(let covered)? = object["covered"]
        else { return nil }
        return (id: id, opinion: JudgeOpinion(effect: effect, covered: covered))
    }
}

// MARK: - Provider route

/// Rule: no new recipient for the turn's words. Realtime already sent them to
/// OpenAI; classic uses the hold brain's own chain, in its own order. Ollama
/// takes the model `LocalCatalog` confirmed at runtime: the static default tag
/// may not be installed, and it 404s.
package enum ActionJudgeRoute {
    package static func provider(pipeline: VoicePipeline, keys: Set<SecretKey>,
                                ollamaModel: String?) -> ProviderDescriptor? {
        let openAI = ProviderDescriptor.openAI.withModel(HoldBrainCatalog.openAIModel)
        switch pipeline {
        case .realtime:
            return openAI
        case .classic:
            if keys.contains(.cerebras) { return .cerebras }
            if keys.contains(.openAI) { return openAI }
            guard let model = ollamaModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else {
                return nil
            }
            return ProviderDescriptor.ollama.withModel(model)
        }
    }
}
