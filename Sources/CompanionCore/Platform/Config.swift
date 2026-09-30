import Foundation

public enum SecretKey: String, Sendable, Equatable {
    case openAI = "OPENAI_API_KEY"
    /// 15e-2: Groq is no longer a provider. The case survives only so
    /// `KeychainSecretStore` can find and delete a key saved before 15e —
    /// nothing reads it for any other purpose.
    case groq = "GROQ_API_KEY"
    case openRouter = "OPENROUTER_API_KEY"
    /// Wave 15c-7: the hold's fast brain, 500k tokens/min where the previous
    /// fast brain's 8k/min free cap ran out in two hold turns.
    case cerebras = "CEREBRAS_API_KEY"
    /// Web search. A secondary key like the rest: without it the tool is not
    /// offered at all, which is the whole point — see Wave 9f.
    case brave = "BRAVE_API_KEY"
    /// Wave 15f-7a: the hold's mouth when a voice is chosen too; without it
    /// the mouth stays OpenAI's.
    case elevenLabs = "ELEVENLABS_API_KEY"
    /// Wave 16k: the key the app shows the companion-apps function. Not a
    /// provider key: it opens only Karen's own function.
    case companionApps = "COMPANION_APPS_KEY"
}

public struct ProviderDescriptor: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var baseURL: URL
    public var model: String
    /// nil = local, no auth (Ollama).
    public var secretKey: SecretKey?
    /// nil = do not send the field at all. A temperature is a choice about a
    /// SPECIFIC model, so it does not survive a model change.
    public var temperature: Double?
    /// nil = do not send the field. Wave 15c-3: `gpt-oss`'s own knob, sent
    /// only for the descriptor that asks for it (the hold's fast brain) —
    /// never guessed for a model that never mentioned it.
    public var reasoningEffort: String?

    public init(
        id: String,
        name: String,
        baseURL: URL,
        model: String,
        secretKey: SecretKey?,
        temperature: Double? = 0.7,
        reasoningEffort: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.secretKey = secretKey
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
    }

    /// Whether the provider takes `strict: true` on a function tool. Known
    /// for OpenAI; the compatibles answer 400 to fields they do not know.
    /// HACK: decided by id. Upgrade trigger: read the provider's 400 body
    /// once and flip per provider instead of guessing.
    public var supportsStrictTools: Bool { id == "openai" }

    /// Original concatenates `base + "/chat/completions"`; base has no
    /// trailing slash, so `absoluteString` matches that contract.
    public var endpoint: URL? {
        URL(string: baseURL.absoluteString + "/chat/completions")
    }

    public static let openAI = ProviderDescriptor(
        id: "openai",
        name: "OpenAI",
        baseURL: URL(string: "https://api.openai.com/v1")!,
        model: "gpt-4o",
        secretKey: .openAI
    )

    /// Wave 15c-7: gpt-oss-120b, measured live at 0.27 s to a tool call with
    /// a 500k tokens/min limit (spec §11). Not in `catalog`: it is the hold's
    /// brain, not a typed-chat row. Low reasoning effort is the hold's speed
    /// budget, not a default for every model.
    public static let cerebras = ProviderDescriptor(
        id: "cerebras",
        name: "Cerebras",
        baseURL: URL(string: "https://api.cerebras.ai/v1")!,
        model: "gpt-oss-120b",
        secretKey: .cerebras,
        temperature: nil,
        reasoningEffort: "low"
    )

    public static let openRouter = ProviderDescriptor(
        id: "openrouter",
        name: "OpenRouter",
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        model: "openai/gpt-4o",
        secretKey: .openRouter
    )

    /// The model here is a PLACEHOLDER, never a promise: which tag exists is
    /// a fact about the user's machine, so the composition root replaces it
    /// with one the daemon actually has (see `LocalCatalog`). Shipping a fixed
    /// tag made the health probe say yes and the first message die on a 404.
    public static let ollama = ProviderDescriptor(
        id: "ollama",
        name: "Ollama",
        baseURL: URL(string: "http://localhost:11434/v1")!,
        model: "qwen3.6:27b",
        secretKey: nil
    )

    /// Immutable update: the catalog entry is a template and each resolution
    /// produces a new descriptor rather than editing the shared one.
    public func withModel(_ model: String) -> ProviderDescriptor {
        var copy = self
        copy.model = model
        // Kept unless the new model cannot take it. Dropping it always would
        // strip the local row of its temperature on every launch — Ollama's
        // model is resolved at runtime, so it goes through here every time —
        // while keeping it always would turn a switch to a reasoning model
        // into a 400 on every message.
        if !ChatParameters.acceptsTemperature(model) { copy.temperature = nil }
        return copy
    }

    public static let catalog: [ProviderDescriptor] = [
        openAI, openRouter, ollama,
    ]

    /// The ladder, in the user's order. Named ids go first in the order given;
    /// everything unnamed keeps catalog order behind them.
    ///
    /// Absent does NOT mean off. A provider the user has never seen — one that
    /// appeared because they installed Ollama or pasted a key — must not start
    /// switched off just because an older preference did not mention it. An
    /// off switch needs a UI to toggle it, and until that exists inventing one
    /// here would only produce a setting nobody can undo.
    public static func route(
        order: [String],
        catalog: [ProviderDescriptor] = catalog
    ) -> [ProviderDescriptor] {
        let named = order.compactMap { id in
            catalog.first { $0.id == id }
        }
        let rest = catalog.filter { !order.contains($0.id) }
        return named + rest
    }
}

/// 15b-1: the key that dictates into the focused field. FN is always the
/// agent now (§3A); dictation is a second, separate hold, off a closed set
/// so it never collides with a system shortcut. `keyCode`/`deviceFlag` are
/// plain values (not `CGEventFlags`) because Core cannot import
/// CoreGraphics — Services wraps them for the actual event tap.
public enum DictationKey: String, Sendable, Equatable, CaseIterable {
    case off, rightOption, rightCommand

    /// `nil` for `.off`: there is no key to arm.
    public var keyCode: Int64? {
        switch self {
        case .off: return nil
        case .rightOption: return 61
        case .rightCommand: return 54
        }
    }

    /// The device-specific bit for the RIGHT-hand key: the plain modifier
    /// mask matches either side, and Opción Izquierda types `@`/`#` on a
    /// Spanish keyboard — measured risk, §11.
    public var deviceFlag: UInt64? {
        switch self {
        case .off: return nil
        case .rightOption: return 0x40
        case .rightCommand: return 0x10
        }
    }
}

/// Code review 2026-09-23 (medio): the dictation `HoldKeyTap` was built once
/// at launch from whatever `dictationKey` read then — changing "Tecla de
/// dictado" in Settings (including turning it off) did nothing until
/// restart. This is the rebuild decision the App layer must act on when the
/// setting changes, pure so it is testable without a real `CGEventTap`.
public enum DictationTapChange: Sendable, Equatable {
    case stop
    case rebuild(keyCode: Int64, flag: UInt64)

    public static func decide(for key: DictationKey) -> DictationTapChange {
        guard let keyCode = key.keyCode, let flag = key.deviceFlag else { return .stop }
        return .rebuild(keyCode: keyCode, flag: flag)
    }
}

public enum VoiceID: String, Sendable, CaseIterable {
    case marin, cedar, alloy, ash, ballad, coral, echo, sage, shimmer, verse
}

public enum Eagerness: String, Sendable, CaseIterable {
    case low, auto, high
}

public enum TurnDetection: Sendable, Equatable {
    case serverVAD(silenceMs: Int)
    case semanticVAD(eagerness: Eagerness)
}

public struct VoiceSettings: Sendable, Equatable {
    public static let speedRange: ClosedRange<Double> = 0.25 ... 1.5
    public static let silenceRange: ClosedRange<Double> = 200 ... 1500

    public var voice: VoiceID
    public var speed: Double {
        didSet { speed = Self.clamp(speed, Self.speedRange) }
    }
    public var volume: Double {
        didSet { volume = Self.clamp(volume, 0 ... 1) }
    }
    public var turnDetection: TurnDetection {
        didSet { turnDetection = Self.clamped(turnDetection) }
    }
    public var tone: String
    public var echoCancellation: Bool
    /// Wave 12e: what a hold does with the words.
    public var mode: VoiceMode
    /// 15b-1: the separate key that dictates. FN itself no longer reads
    /// `mode` at press — this is the only thing left deciding dictation.
    public var dictationKey: DictationKey

    public init(
        voice: VoiceID = .marin,
        speed: Double = 1.0,
        volume: Double = 1.0,
        turnDetection: TurnDetection = .serverVAD(silenceMs: 700),
        tone: String = "",
        echoCancellation: Bool = true,
        mode: VoiceMode = .automatic,
        dictationKey: DictationKey = .rightOption
    ) {
        self.voice = voice
        self.speed = Self.clamp(speed, Self.speedRange)
        self.volume = Self.clamp(volume, 0 ... 1)
        self.turnDetection = Self.clamped(turnDetection)
        self.tone = tone
        self.echoCancellation = echoCancellation
        self.mode = mode
        self.dictationKey = dictationKey
    }

    public static let `default` = VoiceSettings()

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private static func clamped(_ detection: TurnDetection) -> TurnDetection {
        switch detection {
        case .serverVAD(let ms):
            let lo = Int(silenceRange.lowerBound)
            let hi = Int(silenceRange.upperBound)
            return .serverVAD(silenceMs: min(hi, max(lo, ms)))
        case .semanticVAD:
            return detection
        }
    }
}

public struct ChatSettings: Sendable, Equatable {
    /// Provider ids, best first. Empty means "catalog order", which is what a
    /// user who never expressed an opinion gets.
    public var providerOrder: [String]
    public var historyWindow: Int
    public var inactivityTimeout: TimeInterval
    public var turnTimeout: TimeInterval

    public init(
        providerOrder: [String] = [],
        historyWindow: Int = 20,
        inactivityTimeout: TimeInterval = 15,
        turnTimeout: TimeInterval = 60
    ) {
        self.providerOrder = providerOrder
        self.historyWindow = historyWindow
        self.inactivityTimeout = inactivityTimeout
        self.turnTimeout = turnTimeout
    }

    public static let `default` = ChatSettings()
}

/// DM1c-2 (wave-dm1-router.md §8): the local router in front of the classic
/// hold. Off by default until DM1b's accuracy bar and DM1c-3's Settings
/// toggle both land. `COMPANION_DECISION=1` is the only way to flip it
/// before that toggle exists — an optional override read fresh per
/// construction, the same shape `OllamaModelScan` uses for its RAM tier,
/// never a required secret.
public struct DecisionSettings: Sendable, Equatable {
    public var enabled: Bool
    /// `DecisionGate.plan`'s race budget (wave-dm1-router.md §8 done: "commit→decision < 1.5s").
    public var budget: Duration
    public var judgeModel: String
    public var ollamaURL: String

    public init(
        enabled: Bool = ProcessInfo.processInfo.environment["COMPANION_DECISION"] == "1",
        budget: Duration = .seconds(2),
        judgeModel: String = "qwen3:4b",
        ollamaURL: String = "http://localhost:11434"
    ) {
        self.enabled = enabled
        self.budget = budget
        self.judgeModel = judgeModel
        self.ollamaURL = ollamaURL
    }

    public static let `default` = DecisionSettings()
}

/// 16q-3: the action coverage judge. It only ever shadows: it judges and
/// records, and no approval reads its verdict. `enforce` is read as `shadow`
/// (invariant 8) and flagged so the composition root can log that it was asked.
public struct ActionJudgeSettings: Sendable, Equatable {
    public enum Mode: String, Sendable, Equatable { case off, shadow }

    public static let defaultMaxActions = 8

    public var mode: Mode
    /// Wall-clock budget for one judgment; one attempt, no retries.
    public var timeout: TimeInterval
    public var maxActions: Int
    public var enforceRequested: Bool

    public init(mode: Mode = .shadow, timeout: TimeInterval = 2.5,
                maxActions: Int = ActionJudgeSettings.defaultMaxActions, enforceRequested: Bool = false) {
        self.mode = mode
        self.timeout = timeout
        self.maxActions = maxActions
        self.enforceRequested = enforceRequested
    }

    /// Shadow is on unless `COMPANION_ACTION_JUDGE` says off (`off`, `0`,
    /// `false`, any case, trimmed): an app launched from /Applications reads no
    /// shell variables, and without it there is no metric.
    public init(environment: [String: String]) {
        let value = (environment["COMPANION_ACTION_JUDGE"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.init(mode: ["off", "0", "false"].contains(value) ? .off : .shadow,
                  enforceRequested: value == "enforce")
    }

    public static let `default` = ActionJudgeSettings()
}

/// Port for reading the current configuration at runtime.
/// Implementations read from persistent storage (UserPreferences) and
/// construct the effective Config, allowing voice session preferences to
/// apply without session reconstruction.
public protocol ConfigProviding: Sendable {
    var current: Config { get }
}

public struct Config: Sendable, Equatable {
    public var chat: ChatSettings
    public var voice: VoiceSettings
    public var executors: [ExecutorDescriptor]
    public var workdir: String?
    public var ownerFirstName: String
    public var ownerAbout: String
    public var ownerInstructions: String
    /// Settings › Tú: the city "nearby" means. Empty defers to the system's.
    public var ownerCity: String
    /// Decides the UI copy AND the language the model answers in; a prompt
    /// left in one language makes the other half of the app a lie.
    public var language: AppLanguage
    /// The assembled memory block (core + recent sessions + notes), injected
    /// into every prompt. Empty when there is nothing remembered (9j-2).
    public var memory: String
    /// The rendered skills + knowledge catalog (Wave 11a), injected after
    /// memory. Empty when there is no catalog, and then nothing is promised.
    public var skills: String
    /// Remote MCP servers for the realtime session (9j-3), from the user's
    /// mcp.json. OpenAI executes their tools server-side.
    public var mcpServers: [MCPServerConfig]
    /// Which perception channels travel with each turn (Wave 10a). Read per
    /// access like everything else: turning one off applies to the next turn.
    public var contextChannels: ContextChannels
    /// The turn cannot wait for the Accessibility tree of a busy app: what
    /// has not arrived by then does not travel.
    public var contextBudget: Duration
    /// DM1c-2: the local router in front of the classic hold. Off by default.
    public var decision: DecisionSettings
    /// 16q-3: the action coverage judge, shadow only.
    public var judge: ActionJudgeSettings
    public var debugTranscripts: Bool
    /// Wave 15f-7a: the ElevenLabs voice the hold speaks with. Empty means
    /// none chosen, and the mouth stays OpenAI's even with the key saved.
    public var elevenLabsVoiceID: String

    public init(
        chat: ChatSettings = .default,
        voice: VoiceSettings = .default,
        executors: [ExecutorDescriptor] = [ExecutorCatalog.native],
        workdir: String? = nil,
        ownerFirstName: String = "",
        ownerAbout: String = "",
        ownerInstructions: String = "",
        ownerCity: String = "",
        language: AppLanguage = .en,
        memory: String = "",
        skills: String = "",
        mcpServers: [MCPServerConfig] = [],
        contextChannels: ContextChannels = .default,
        contextBudget: Duration = .milliseconds(150),
        decision: DecisionSettings = DecisionSettings(),
        judge: ActionJudgeSettings = ActionJudgeSettings(environment: ProcessInfo.processInfo.environment),
        debugTranscripts: Bool = Config.debugTranscriptsEnabled(),
        elevenLabsVoiceID: String = Config.defaultElevenLabsVoiceID
    ) {
        self.chat = chat
        self.voice = voice
        self.executors = executors
        self.workdir = workdir
        self.ownerFirstName = ownerFirstName
        self.ownerAbout = ownerAbout
        self.ownerInstructions = ownerInstructions
        self.ownerCity = ownerCity
        self.language = language
        self.memory = memory
        self.skills = skills
        self.mcpServers = mcpServers
        self.contextChannels = contextChannels
        self.contextBudget = contextBudget
        self.decision = decision
        self.judge = judge
        self.debugTranscripts = debugTranscripts
        self.elevenLabsVoiceID = elevenLabsVoiceID
    }

    /// Karen's blind pick on 2026-09-25 (15f-6): "Ana María", Mexican
    /// Spanish, over the earlier default Brian (`Gubgw9l4dtIoQA9YZHgx`),
    /// an American voice whose Spanish accent sounded off. It is a
    /// shared-library voice and plays by id without adding it to the
    /// account, so saving the key is still the only step.
    public static let defaultElevenLabsVoiceID = "m7yTemJqdIqrcNleANfX"

    /// Wave 15d-6: the hold's words are private; only the exact value opts in.
    public static func debugTranscriptsEnabled(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["COMPANION_DEBUG_TRANSCRIPTS"] == "1"
    }

    public static let `default` = Config()
}
