import Foundation

public enum EchoGuard: Sendable {
    public static func words(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    public static func isEcho(heard: String, agentSaying: String) -> Bool {
        let heardWords = words(heard)
        // No tokens means nothing to barge in with — treat as echo, not speech.
        guard !heardWords.isEmpty else { return true }
        let spoken = Set(words(agentSaying))
        guard !spoken.isEmpty else { return false }
        let hits = heardWords.filter { spoken.contains($0) }.count
        return Double(hits) / Double(heardWords.count) >= 0.6
    }

    public static func isRealInterruption(heard: String, agentSaying: String) -> Bool {
        words(heard).count >= 2 && !isEcho(heard: heard, agentSaying: agentSaying)
    }
}

public enum SpeechCues: Sendable {
    public static let continuations: Set<String> = [
        "y", "e", "o", "u", "ni", "pero", "sino", "porque", "pues", "que",
        "de", "del", "en", "con", "sin", "por", "para", "a", "al", "desde",
        "hasta", "sobre", "entre", "hacia", "según",
        "el", "la", "los", "las", "un", "una", "unos", "unas", "mi", "tu",
        "su", "mis", "tus", "sus", "este", "esta", "estos", "estas",
        "entonces", "cuando", "si", "como", "aunque", "mientras", "donde",
        "osea", "eh", "em", "mmm", "este…", "tipo", "digamos", "bueno",
        "más", "muy", "también", "tampoco", "no", "sí",
    ]

    public static func isIncomplete(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return true }
        if ",;:—-".contains(last) { return true }
        if ".!?…".contains(last) { return false }
        let lastWord = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" }).last ?? ""
        let token = lastWord.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return continuations.contains(token)
    }
}

public struct TranscriptEndpointer: Sendable {
    public struct Config: Sendable, Equatable {
        public var minDelay: TimeInterval = 0.6
        public var maxDelay: TimeInterval = 2.6
        public var quietClose: TimeInterval = 12
        public var maxUtterance: TimeInterval = 45
        public var voiceFloor: Double = 0.06
        public init() {}
    }

    public enum Verdict: Sendable, Equatable {
        case listening, finished, timedOut
    }

    private let config: Config
    private let start: TimeInterval
    private var chars = 0
    private var text = ""
    private var lastGrowth: TimeInterval?
    private var terminal: Verdict?
    public private(set) var hasSpeech = false

    public init(config: Config = Config(), start: TimeInterval) {
        self.config = config
        self.start = start
    }

    public mutating func feed(text incoming: String, level: Double,
                              at t: TimeInterval) -> Verdict {
        if let terminal { return terminal }
        if t - start > config.maxUtterance {
            terminal = .timedOut
            return .timedOut
        }
        // Recognizer revisions can shrink the hypothesis; only growth is new speech.
        if incoming.count > chars {
            chars = incoming.count
            text = incoming
            hasSpeech = true
            lastGrowth = t
            return .listening
        }
        guard hasSpeech else {
            if t - start > config.quietClose {
                terminal = .timedOut
                return .timedOut
            }
            return .listening
        }
        guard let growth = lastGrowth else { return .listening }
        let silence = t - growth
        let needed = SpeechCues.isIncomplete(text) ? config.maxDelay : config.minDelay
        // Voice can delay the close (filler, pause) but never stretch past maxDelay.
        if level >= config.voiceFloor, silence < config.maxDelay {
            return .listening
        }
        if silence >= needed {
            terminal = .finished
            return .finished
        }
        return .listening
    }
}

public struct Endpointer: Sendable {
    public struct Config: Sendable, Equatable {
        public var calibration: TimeInterval = 0.4
        public var margin: Double = 0.045
        public var minSpeech: TimeInterval = 0.25
        public var silenceHold: TimeInterval = 1.2
        public var maxUtterance: TimeInterval = 30
        public var quietClose: TimeInterval = 12
        public init() {}
    }

    public enum Verdict: Sendable, Equatable {
        case listening, speechStarted, finished, timedOut
    }

    private let config: Config
    private let start: TimeInterval
    private var floor: Double = 0
    private var speechAccum: TimeInterval = 0
    private var lastT: TimeInterval?
    private var silenceSince: TimeInterval?
    private var terminal: Verdict?
    public private(set) var hasSpeech = false

    public init(config: Config = Config(), start: TimeInterval) {
        self.config = config
        self.start = start
    }

    public mutating func feed(rms: Double, at t: TimeInterval) -> Verdict {
        if let terminal { return terminal }
        let elapsed = t - start
        if elapsed > config.maxUtterance
            || (!hasSpeech && elapsed > config.quietClose) {
            terminal = .timedOut
            return .timedOut
        }
        let dt = lastT.map { max(0, t - $0) } ?? 0
        lastT = t

        if elapsed <= config.calibration {
            floor = max(floor, rms)
            return .listening
        }
        let threshold = floor + config.margin

        if rms >= threshold {
            silenceSince = nil
            speechAccum += dt
            if !hasSpeech && speechAccum >= config.minSpeech {
                hasSpeech = true
                return .speechStarted
            }
            return .listening
        }

        if hasSpeech {
            if silenceSince == nil { silenceSince = t }
            if let s = silenceSince, t - s >= config.silenceHold {
                terminal = .finished
                return .finished
            }
        } else {
            // Non-contiguous noise must not add up: a door slam is not speech.
            speechAccum = 0
        }
        return .listening
    }
}
