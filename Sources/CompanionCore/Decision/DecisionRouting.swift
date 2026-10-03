import Foundation

/// Why a turn fell through to today's path instead of the router acting.
/// Never the utterance text (privacy, DM1c-1 §8): only the shape of what
/// happened.
package enum DecisionPassReason: String, Sendable, Equatable {
    /// The "Decidir en local" toggle is off (DM1c-3); reserved here so the
    /// wire shape does not change when that toggle lands.
    case disabled
    case ignored
    case failed
    case timedOut
    case noExecutor
    case informational
    case noSpecialist
    case unresolved
    /// A pending voice confirmation replaced by a new utterance (DM1c-4);
    /// reserved here for the same reason as `disabled`.
    case superseded
    /// Wave 15c-4/15c-7: the hold's brain is already the fast one — it
    /// picks the tool by commit and N1's own cascade never won a hold once
    /// it did (wave-15c §1), so `DecisionGate` is not even called.
    case fastBrain
    /// 16h-1: "open X and tell me Y" — the router can only do the first
    /// half, so the whole request goes to the model that can also read.
    case compound
}

/// What N1's cascade routes a turn to, before anything runs. `execute` and
/// `system` carry the wire shape their executor needs; `passThrough` means
/// today's model-in-the-loop path handles the turn, unchanged.
package enum DecisionStep: Sendable, Equatable {
    /// `open_app` / `open_url` / `open_file`, already shaped as the parent
    /// tool's own call — `DecisionGate` runs it through `ParentToolRunner`,
    /// never around it.
    case execute(ToolCallRef, Plan)
    /// A closed-set action (volume, shortcut, scroll, media, system) with no
    /// executor yet (DM1d): carried so DM1c-4 can wire one without a second
    /// routing pass.
    case system(Plan)
    /// Irreversible, and the (future) executor supports it: ask by voice,
    /// never with a sheet.
    case confirm(Plan)
    case arbitrate(ArbitrationShortlist, Plan)
    case delegate(Handoff)
    case passThrough(DecisionPassReason)
}

/// N1's routing table (wave-dm1-router.md §2, §8): a pure function from a
/// composed `Plan` to what should happen next. Never touches the network or
/// the filesystem — `DecisionGate` is the only thing that acts.
package enum DecisionRoute {
    /// `systemSupports` answers for a single plan, not a whole action class:
    /// DM1d's trust-by-app can refuse a plan the class as a whole supports.
    package static func step(
        for plan: Plan,
        world: DecisionWorld,
        canDelegate: Bool,
        systemSupports: @Sendable (Plan) -> Bool
    ) -> DecisionStep {
        switch plan.disposition {
        case .ignore:
            return .passThrough(.ignored)
        case .act:
            if plan.steps.contains(.read) { return .passThrough(.compound) }
            return actStep(for: plan, systemSupports: systemSupports)
        case .confirm:
            // Never ask by voice about something nothing can execute.
            return systemSupports(plan) ? .confirm(plan) : .passThrough(.noExecutor)
        case .delegate:
            return delegateStep(for: plan, canDelegate: canDelegate)
        case .arbitrate:
            let shortlist = ArbitrationShortlist.build(
                utterance: plan.utterance, world: world, actionMass: plan.actionMass)
            return shortlist.entries.isEmpty
                ? .passThrough(.unresolved) : .arbitrate(shortlist, plan)
        }
    }

    private static func actStep(
        for plan: Plan, systemSupports: @Sendable (Plan) -> Bool
    ) -> DecisionStep {
        switch plan.action {
        case .openApp, .openURL, .openFile:
            guard let call = parentCall(for: plan) else { return .passThrough(.failed) }
            return .execute(call, plan)
        case .listApps, .readSkill, .findPlaces:
            // The model still has to say the result; N0 cannot speak for it.
            return .passThrough(.informational)
        case .volume, .shortcut, .scroll, .media, .system, .typeText, .task, .none:
            return systemSupports(plan) ? .system(plan) : .passThrough(.noExecutor)
        }
    }

    private static func delegateStep(for plan: Plan, canDelegate: Bool) -> DecisionStep {
        guard canDelegate else { return .passThrough(.noSpecialist) }
        guard case .text(let goal) = plan.args["goal"], !goal.isEmpty else {
            return .passThrough(.failed)
        }
        return .delegate(Handoff(goal: goal, context: ""))
    }

    /// The parent tool's own wire shape (Wave 10b): name and argument keys
    /// exactly as `ParentTool` and `ParentToolRunner` expect them, so
    /// `DecisionGate` executes through the runner unchanged and
    /// `ParentToolPolicy` still re-validates every field.
    package static func parentCall(for plan: Plan) -> ToolCallRef? {
        let tool: ParentTool
        let object: [String: String]
        switch plan.action {
        case .openApp:
            guard case .text(let name) = plan.args["app"] else { return nil }
            tool = .openApp
            object = ["name": name]
        case .openURL:
            guard case .text(let url) = plan.args["url"] else { return nil }
            tool = .openURL
            object = ["url": url]
        case .openFile:
            guard case .text(let path) = plan.args["path"] else { return nil }
            tool = .openFile
            object = ["path": path]
        default:
            return nil
        }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object)
        } catch {
            return nil
        }
        guard let json = String(data: data, encoding: .utf8) else { return nil }
        return ToolCallRef(id: UUID().uuidString, name: tool.rawValue, arguments: json)
    }

    /// N0's own re-check at the door, right before a closed-set action would
    /// run: an id `Candidates` never offered, or a `type_text` span that is
    /// not literally inside what the user said, is forged and must not
    /// execute — the same rule that built the option in the first place,
    /// checked again so a `Plan` built by hand (a test, N2's own output)
    /// cannot skip it.
    package static func validClosedSet(_ plan: Plan) -> Bool {
        switch plan.action {
        case .volume:
            return contains(CandidateSets.volumeOps, textArg(plan, "op"))
        case .shortcut:
            return contains(CandidateSets.shortcuts, textArg(plan, "shortcut"))
        case .media:
            return contains(CandidateSets.mediaOps, textArg(plan, "op"))
        case .system:
            return contains(CandidateSets.systemOps, textArg(plan, "op"))
        case .scroll:
            return contains(CandidateSets.scrollDirections, textArg(plan, "direction"))
                && contains(CandidateSets.scrollAmounts, textArg(plan, "amount"))
        case .typeText:
            guard let text = textArg(plan, "text") else { return false }
            return CandidateSets.fold(plan.utterance).contains(CandidateSets.fold(text))
        default:
            return true
        }
    }

    private static func contains(_ options: [DecisionOption], _ id: String?) -> Bool {
        guard let id else { return false }
        return options.contains { $0.id == id }
    }

    private static func textArg(_ plan: Plan, _ key: String) -> String? {
        guard case .text(let value) = plan.args[key] else { return nil }
        return value
    }
}

/// Jev's `yesNo` gate, but on the words the user actually spoke instead of a
/// forced token. A leading "sí"/"no" decides; silence, a fresh order, or
/// both words at once is not an answer to the question asked — `nil` says
/// "ask again", never "no".
package enum SpokenConfirmation: Sendable {
    private static let affirmative: Set<String> = ["si", "dale", "yes", "hazlo"]
    private static let negative: Set<String> = ["no", "cancela"]

    package static func reading(_ said: String) -> Bool? {
        let folded = CandidateSets.fold(said).trimmingCharacters(in: .whitespaces)
        guard !folded.isEmpty else { return nil }
        // Only the first clause answers; whatever follows the comma is the
        // detail ("sí, vaciala"), not a second vote.
        let head = folded.split(separator: ",", maxSplits: 1).first.map(String.init) ?? folded
        let words = Set(CandidateSets.tokens(head))
        let sawYes = !words.isDisjoint(with: affirmative)
        let sawNo = !words.isDisjoint(with: negative)
        if sawYes == sawNo { return nil }
        return sawYes
    }
}

/// Spoken copy for what the router itself said or did — never a sheet.
package enum DecisionCopy: Sendable {
    /// Reuses `ParentToolCopy`'s own wording (open_app/url/file): the router
    /// and the model-in-the-loop path must read identically to the user.
    package static func acted(
        _ outcome: ParentToolOutcome, tool: String, _ language: AppLanguage
    ) -> String {
        // The browser reports other permissions under the same code, with its own copy.
        if !outcome.ok, outcome.output.hasPrefix(BridgeCode.permissionRequired), BrowserTool(rawValue: tool) == nil {
            return automationRequired(app: outcome.target, language)
        }
        return ParentToolCopy.status(tool, outcome, language)
    }

    /// Spoken, so the pane is said as words; macOS lists each controlled app
    /// under Companion's row, so the switch is named, not only the pane.
    package static func automationRequired(app: String, _ language: AppLanguage) -> String {
        switch language {
        case .en:
            let name = app.isEmpty ? "that app" : app
            return "I'm not allowed to control \(name). Turn it on in System Settings, Privacy & Security, "
                + "Automation: the \(name) switch under Companion."
        case .es:
            let name = app.isEmpty ? "esa app" : app
            return "No tengo permiso para controlar \(name). Actívalo en Ajustes del Sistema, Privacidad y "
                + "seguridad, Automatización: el interruptor de \(name) debajo de Companion."
        }
    }

    package static func question(for plan: Plan, _ language: AppLanguage) -> String {
        let what = irreversibleVerb(plan, language)
        switch language {
        case .en: return "\(what)?"
        case .es: return "¿\(what)?"
        }
    }

    package static func declined(_ language: AppLanguage) -> String {
        switch language {
        case .en: return "Okay, not doing it."
        case .es: return "Bien, no lo hago."
        }
    }

    package static func delegated(_ language: AppLanguage) -> String {
        switch language {
        case .en: return "Passing this to the specialist…"
        case .es: return "Se lo paso al especialista…"
        }
    }

    /// The generic acknowledgement `AckPolicy` falls back to while the
    /// specific reply is not yet on disk (wave-15b §3C): short enough that
    /// it is always inside `PhraseCache`'s own 80-char limit.
    package static func quickAck(_ language: AppLanguage) -> String {
        switch language {
        case .en: return "Done."
        case .es: return "Listo."
        }
    }

    /// The closed set of fixed phrases worth having on disk before the
    /// words are even in: the quick ack itself, and the router's other
    /// fixed replies (declined, delegated, and the irreversible-action
    /// confirmations §3B and DM1c-4 already know the shape of). Never a
    /// phrase built from what the user said — that is the specific text
    /// `AckPolicy` warms per-hold, not this closed set.
    package static func prewarmSet(_ language: AppLanguage) -> [String] {
        let confirmations: [Plan] = [
            Plan(utterance: "", action: .system, args: ["op": .text("empty_trash")],
                 confidence: 1, risk: .irreversible, disposition: .confirm),
            Plan(utterance: "", action: .shortcut, args: ["shortcut": .text("quit_app")],
                 confidence: 1, risk: .irreversible, disposition: .confirm),
            Plan(utterance: "", action: .shortcut, args: ["shortcut": .text("send_message")],
                 confidence: 1, risk: .irreversible, disposition: .confirm),
            Plan(utterance: "", action: .typeText, args: ["submit": .flag(true)],
                 confidence: 1, risk: .irreversible, disposition: .confirm),
            Plan(utterance: "", action: .none, args: [:],
                 confidence: 1, risk: .irreversible, disposition: .confirm),
        ]
        return [quickAck(language), declined(language), delegated(language)]
            + confirmations.map { question(for: $0, language) }
    }

    private static func irreversibleVerb(_ plan: Plan, _ language: AppLanguage) -> String {
        switch plan.action {
        case .system where plan.args["op"] == .text("empty_trash"):
            return language == .en ? "Empty the trash" : "Vacío la papelera"
        case .shortcut where plan.args["shortcut"] == .text("quit_app"):
            return language == .en ? "Quit the app" : "Cierro la app"
        case .shortcut where plan.args["shortcut"] == .text("send_message")
            || plan.args["shortcut"] == .text("enter"):
            return language == .en ? "Send it" : "Lo envío"
        case .typeText where plan.args["submit"] == .flag(true):
            return language == .en ? "Send it" : "Lo envío"
        default:
            return language == .en ? "Do it" : "Lo hago"
        }
    }
}

/// The router's own turn is spoken now or never — there is no second pass
/// to catch up on a slow reply — so it speaks from the closed set of what is
/// already on disk (wave-15b §3C) and warms the specific phrase for next
/// time instead of paying a cold fetch on the turn the user is waiting on.
package enum AckPolicy: Sendable {
    /// Matches `PhraseCache`'s own 80-char limit (Services): warming a
    /// phrase that limit will never store is a wasted fetch, not a future hit.
    private static let maxCacheable = 80

    /// `speak` is what goes to the synthesizer now; `warm`, when present, is
    /// the phrase to fetch and cache in the background for the next time
    /// this exact reply comes up.
    package static func choose(
        specific: String, specificCached: Bool, language: AppLanguage
    ) -> (speak: String, warm: String?) {
        if specificCached { return (specific, nil) }
        guard specific.count <= maxCacheable else { return (DecisionCopy.quickAck(language), nil) }
        return (DecisionCopy.quickAck(language), specific)
    }
}
