import Foundation

public enum SecretKey: String, Sendable, Equatable {
    case openAI = "OPENAI_API_KEY"
    case groq = "GROQ_API_KEY"
    case openRouter = "OPENROUTER_API_KEY"
}

public struct ProviderDescriptor: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var baseURL: URL
    public var model: String
    /// nil = local, no auth (Ollama).
    public var secretKey: SecretKey?

    public init(
        id: String,
        name: String,
        baseURL: URL,
        model: String,
        secretKey: SecretKey?
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.secretKey = secretKey
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

    public static let ollama = ProviderDescriptor(
        id: "ollama",
        name: "Ollama",
        baseURL: URL(string: "http://localhost:11434/v1")!,
        model: "qwen3.6:27b",
        secretKey: nil
    )

    public static let catalog: [ProviderDescriptor] = [openAI, groq, ollama]

    /// Known preferred name moves to the front; unknown keeps catalog order.
    public static func route(
        preferred: String?,
        catalog: [ProviderDescriptor] = catalog
    ) -> [ProviderDescriptor] {
        guard let p = catalog.first(where: { $0.name == preferred }) else {
            return catalog
        }
        return [p] + catalog.filter { $0 != p }
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
    public var preferredProviderName: String?
    public var historyWindow: Int
    public var inactivityTimeout: TimeInterval
    public var turnTimeout: TimeInterval

    public init(
        preferredProviderName: String? = nil,
        historyWindow: Int = 20,
        inactivityTimeout: TimeInterval = 15,
        turnTimeout: TimeInterval = 60
    ) {
        self.preferredProviderName = preferredProviderName
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

    public init(
        chat: ChatSettings = .default,
        voice: VoiceSettings = .default,
        executors: [ExecutorDescriptor] = [ExecutorCatalog.native],
        workdir: String? = nil,
        ownerFirstName: String = "",
        ownerAbout: String = "",
        ownerInstructions: String = ""
    ) {
        self.chat = chat
        self.voice = voice
        self.executors = executors
        self.workdir = workdir
        self.ownerFirstName = ownerFirstName
        self.ownerAbout = ownerAbout
        self.ownerInstructions = ownerInstructions
    }

    public static let `default` = Config()
}
