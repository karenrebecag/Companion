import Foundation

public enum SecretKey: String, Sendable, Equatable {
    case openAI = "OPENAI_API_KEY"
    case groq = "GROQ_API_KEY"
    case openRouter = "OPENROUTER_API_KEY"
    /// Web search. A secondary key like the rest: without it the tool is not
    /// offered at all, which is the whole point — see Wave 9f.
    case brave = "BRAVE_API_KEY"
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

    public init(
        id: String,
        name: String,
        baseURL: URL,
        model: String,
        secretKey: SecretKey?,
        temperature: Double? = 0.7
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.secretKey = secretKey
        self.temperature = temperature
    }

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

    public static let groq = ProviderDescriptor(
        id: "groq",
        name: "Groq",
        baseURL: URL(string: "https://api.groq.com/openai/v1")!,
        model: "llama-3.3-70b-versatile",
        secretKey: .groq
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
        openAI, groq, openRouter, ollama,
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

    public init(
        voice: VoiceID = .marin,
        speed: Double = 1.0,
        volume: Double = 1.0,
        turnDetection: TurnDetection = .serverVAD(silenceMs: 700),
        tone: String = "",
        echoCancellation: Bool = true
    ) {
        self.voice = voice
        self.speed = Self.clamp(speed, Self.speedRange)
        self.volume = Self.clamp(volume, 0 ... 1)
        self.turnDetection = Self.clamped(turnDetection)
        self.tone = tone
        self.echoCancellation = echoCancellation
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
    /// Decides the UI copy AND the language the model answers in; a prompt
    /// left in one language makes the other half of the app a lie.
    public var language: AppLanguage
    /// The assembled memory block (core + recent sessions + notes), injected
    /// into every prompt. Empty when there is nothing remembered (9j-2).
    public var memory: String
    /// Remote MCP servers for the realtime session (9j-3), from the user's
    /// mcp.json. OpenAI executes their tools server-side.
    public var mcpServers: [MCPServerConfig]

    public init(
        chat: ChatSettings = .default,
        voice: VoiceSettings = .default,
        executors: [ExecutorDescriptor] = [ExecutorCatalog.native],
        workdir: String? = nil,
        ownerFirstName: String = "",
        ownerAbout: String = "",
        ownerInstructions: String = "",
        language: AppLanguage = .en,
        memory: String = "",
        mcpServers: [MCPServerConfig] = []
    ) {
        self.chat = chat
        self.voice = voice
        self.executors = executors
        self.workdir = workdir
        self.ownerFirstName = ownerFirstName
        self.ownerAbout = ownerAbout
        self.ownerInstructions = ownerInstructions
        self.language = language
        self.memory = memory
        self.mcpServers = mcpServers
    }

    public static let `default` = Config()
}
