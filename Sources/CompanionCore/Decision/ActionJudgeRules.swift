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
    /// Another call of the same step writes or opens the same target: two
    /// covered answers for one destination must not both come down.
    package let repeatedTarget: Bool

    package init(band: ActionBand, opinion: JudgeOpinion?, alwaysAllowed: Bool, repeatedTarget: Bool = false) {
        self.band = band
        self.opinion = opinion
        self.alwaysAllowed = alwaysAllowed
        self.repeatedTarget = repeatedTarget
    }
}

/// What the step's sheets come to. `free` runs without a question; `ask` goes
/// to the person, and when there are two or more they share one sheet.
package enum SheetLane: Sendable, Equatable {
    case free, ask

    package static func of(_ entries: [SheetEntry]) -> [SheetLane] {
        entries.map { entry in
            if entry.repeatedTarget { return .ask }
            return (entry.alwaysAllowed && entry.band == .confirm) || JudgeBand.lowered(entry.band, by: entry.opinion) == .act
                ? .free : .ask
        }
    }
}

// MARK: - Grounding

/// A recipient the judge calls covered must be one her words repeat. The
/// arguments came from a model that may have read a page, so an address the
/// words do not contain is an address she did not name.
package enum JudgeGrounding {
    // `host` is the site an upload goes to: for grounding it is a recipient like any other.
    private static let addressKeys: Set<String> = [
        "to", "recipient", "recipients", "channel", "email", "phone", "number", "contact",
        "participants", "chat", "cc", "bcc", "host",
    ]
    /// Tools whose effect is known without asking: the judge's label for them is not read.
    private static let leavesTheMac: Set<String> = [BrowserTool.setFiles.rawValue]

    package static func grounded(
        _ opinions: [JudgeOpinion?], candidates: [JudgeCandidate], words: UserWords
    ) -> [JudgeOpinion?] {
        let heard = words.text.lowercased()
        return zip(opinions, candidates).map { opinion, candidate in
            guard let opinion else { return nil }
            let found = addresses(in: candidate)
            // A call that carries a destination reaches someone whatever the judge
            // calls it, so a mislabel cannot skip the check below. The pin only ever
            // tightens: an irreversible verdict is never softened into one that lowers.
            let pinned = leavesTheMac.contains(candidate.tool) || !found.isEmpty
            let effect: JudgeEffect = opinion.effect == .irreversible
                ? .irreversible : (pinned ? .reachesSomeone : opinion.effect)
            guard effect == .reachesSomeone, opinion.covered else {
                return JudgeOpinion(effect: effect, covered: opinion.covered)
            }
            // No address in the arguments means the destination is implicit (a default
            // channel, the last chat), so the words cannot have named it.
            let named = !found.isEmpty && found.allSatisfy { said($0.lowercased(), in: heard) }
            return JudgeOpinion(effect: effect, covered: named)
        }
    }

    /// The address as a whole token of the words: a piece of the address she
    /// named ("aren@gmail.com" inside "karen@gmail.com") is not that address.
    static func said(_ address: String, in heard: String) -> Bool {
        guard !address.isEmpty else { return false }
        var start = heard.startIndex
        while let range = heard.range(of: address, range: start..<heard.endIndex) {
            let before = range.lowerBound == heard.startIndex ? nil : heard[heard.index(before: range.lowerBound)]
            let after = range.upperBound == heard.endIndex ? nil : heard[range.upperBound]
            if !isAddressCharacter(before), !isAddressCharacter(after) { return true }
            start = heard.index(after: range.lowerBound)
        }
        return false
    }

    private static func isAddressCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || "@._-+/:".contains(character)
    }

    /// Values shaped like a destination: under an address key, or with an @ or a scheme.
    private static func addresses(in candidate: JudgeCandidate) -> [String] {
        candidate.arguments.values.flatMap { key, value -> [String] in
            let texts: [String]
            switch value {
            case .text(let text): texts = [text]
            case .list(let items): texts = items
            case .number, .bool: texts = []
            }
            let keyed = addressKeys.contains(key.lowercased())
            return texts.filter { keyed || $0.contains("@") || $0.contains("://") }
        }
    }
}

// MARK: - Step

/// Whether a step may have any sheet lowered before it runs. The taint is only
/// marked once a read has run, and the step is planned before any call, so a
/// read in the same step counts as the mark it is about to leave.
package enum JudgeStep {
    private static let reads: Set<String> = [
        NativeTool.readFile.rawValue, NativeTool.listDirectory.rawValue, NativeTool.sheetRead.rawValue,
        NativeTool.runShell.rawValue,
    ]

    package static func mayLower(tainted: Bool, toolNames: [String]) -> Bool {
        !tainted && !toolNames.contains(where: reads.contains)
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

/// Rule: no new recipient for the turn's words. The judge uses the hold
/// brain's own chain, in its own order. Ollama takes the model `LocalCatalog`
/// confirmed at runtime: the static default tag may not be installed, and it 404s.
package enum ActionJudgeRoute {
    package static func provider(keys: Set<SecretKey>, ollamaModel: String?) -> ProviderDescriptor? {
        if keys.contains(.cerebras) { return .cerebras }
        // The cheap judge model on OpenRouter: the role the OpenAI mini held
        // before OpenAI left the product.
        if keys.contains(.openRouter) { return ProviderDescriptor.openRouter.withModel("openai/gpt-4o-mini") }
        guard let model = ollamaModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else {
            return nil
        }
        return ProviderDescriptor.ollama.withModel(model)
    }
}
