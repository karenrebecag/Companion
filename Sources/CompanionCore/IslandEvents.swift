import Foundation

/// The kinds of card the island shows that the model may hear about.
public enum IslandCardKind: String, Sendable, Equatable {
    case result, notice, receipt, answer
}

/// What happened on the island since the model last spoke (16h-3). Facts
/// about cards and the user, never their content.
public enum IslandEvent: Sendable, Equatable {
    case shown(IslandCardKind)
    /// The user closed it.
    case closed(IslandCardKind)
    /// It left on its own, unattended.
    case ignored(IslandCardKind)
    /// The user cut the reply or the work short.
    case interrupted
}

/// What a turn is about to hear, and up to which fact: the turn confirms
/// with `through` only once the prompt that carries them was built.
public struct IslandEventBatch: Sendable, Equatable {
    public let events: [IslandEvent]
    public let through: Int

    public init(events: [IslandEvent], through: Int) {
        self.events = events
        self.through = through
    }
}

/// Events waiting for the next turn: bounded, consecutive repeats folded.
/// Delivery has two phases (peek, then acknowledge): a turn that never built
/// its prompt (a cancelled hold, a router answer) consumes nothing.
public struct IslandEventLog: Sendable, Equatable {
    /// The same number the context block shows: what is kept is what is told.
    public static let capacity = 4

    private struct Entry: Sendable, Equatable {
        let sequence: Int
        let event: IslandEvent
    }

    private var entries: [Entry] = []
    public private(set) var lastSequence = 0
    /// The last fact a turn was shown: a repeat recorded after it is news.
    private var deliveredThrough = 0

    public init() {}

    public var pending: [IslandEvent] { entries.map(\.event) }

    public mutating func record(_ event: IslandEvent) {
        // Fold only into a fact nobody has been shown yet.
        if let last = entries.last, last.event == event, last.sequence > deliveredThrough { return }
        lastSequence += 1
        entries.append(Entry(sequence: lastSequence, event: event))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    public mutating func peek() -> IslandEventBatch {
        deliveredThrough = lastSequence
        return IslandEventBatch(events: pending, through: lastSequence)
    }

    /// Forgets what the prompt carried; facts recorded since stay for the next.
    public mutating func acknowledge(through: Int) {
        entries.removeAll { $0.sequence <= through }
    }
}

public protocol IslandEventSink: Sendable {
    func record(_ event: IslandEvent)
}

public protocol IslandEventSource: Sendable {
    /// The facts waiting, without consuming them.
    func pending() -> IslandEventBatch
    /// The prompt that carried them was built: forget up to `through`.
    func acknowledge(through: Int)
}

extension SessionCard {
    /// The hold hint teaches a key and the approval sheet has its own road:
    /// neither is news for the model.
    var islandKind: IslandCardKind? {
        switch self {
        case .couldntHear, .permission, .failure, .connectApp, .signInApp: .notice
        case .receipt: .receipt
        case .holdHint, .approval, .approvalAnswered, .answer: nil
        }
    }
}

/// The latest result card: shown, then either attended to or, when a newer
/// one arrives first, ignored.
public struct IslandResultAttention: Sendable, Equatable {
    private var current: UUID?
    private var wasAttended = false

    public init() {}

    public mutating func replyShown(_ id: UUID) -> [IslandEvent] {
        guard id != current else { return [] }
        var out: [IslandEvent] = []
        if current != nil, !wasAttended { out.append(.ignored(.result)) }
        current = id
        wasAttended = false
        out.append(.shown(.result))
        return out
    }

    /// The user opened or closed the current one: it was not ignored.
    public mutating func attended() {
        wasAttended = true
    }
}
