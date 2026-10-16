import Foundation

package enum TurnStatus: String, Sendable, Equatable {
    case running
    case awaitingOwner = "awaiting_owner"
    case completed, failed, cancelled

    package var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .running, .awaitingOwner: false
        }
    }
}

package enum TurnPhase: String, Sendable, Equatable {
    case started, streaming, acting
    case ownerCheck = "owner_check"
    case completed, failed, cancelled
}

package struct TurnPhaseMark: Sendable, Equatable {
    package var phase: TurnPhase
    package var atMs: Int

    package init(phase: TurnPhase, atMs: Int) {
        self.phase = phase
        self.atMs = atMs
    }
}

/// One tool the model called inside a turn, with what the gate decided.
/// `band` and `ownerCheck` are the gate's own words, never the model's.
package struct TurnToolCall: Sendable, Equatable {
    package var index: Int
    package var name: String
    package var arguments: String
    package var ok: Bool
    package var target: String
    package var output: String
    package var verified: Bool
    package var band: String
    package var ownerCheck: String

    package init(
        index: Int, name: String, arguments: String, ok: Bool, target: String, output: String,
        verified: Bool, band: String, ownerCheck: String
    ) {
        self.index = index
        self.name = name
        self.arguments = arguments
        self.ok = ok
        self.target = target
        self.output = output
        self.verified = verified
        self.band = band
        self.ownerCheck = ownerCheck
    }
}

/// A card the turn showed. The kind is the case name of the payload; the
/// card's own words are not part of the record.
package struct TurnCardMark: Sendable, Equatable {
    package var kind: String

    package init(kind: String) {
        self.kind = kind
    }
}

package struct TurnPendingOwner: Sendable, Equatable {
    package var tool: String
    package var band: String
    package var reason: String

    package init(tool: String, band: String, reason: String) {
        self.tool = tool
        self.band = band
        self.reason = reason
    }
}

package struct TurnReply: Sendable, Equatable {
    package var text: String
    package var isFailure: Bool

    package init(text: String, isFailure: Bool) {
        self.text = text
        self.isFailure = isFailure
    }
}

package struct TurnFault: Sendable, Equatable {
    package var code: String
    package var message: String

    package init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// What one turn did, kept in memory. Holds the words; `TurnResult` decides
/// whether they leave.
package struct TurnRecord: Sendable, Equatable {
    package var turnId: String
    package var conversationId: String
    /// `typed | choice | agent | voice`.
    package var origin: String
    package var status: TurnStatus = .running
    package var phases: [TurnPhaseMark] = []
    package var toolCalls: [TurnToolCall] = []
    package var cards: [TurnCardMark] = []
    package var receipts: [String] = []
    package var statusLines: [String] = []
    package var handoffGoalLength: Int?
    package var pendingOwner: TurnPendingOwner?
    package var reply: TurnReply?
    package var error: TurnFault?
    package var elapsedMs = 0

    package init(turnId: String, conversationId: String, origin: String) {
        self.turnId = turnId
        self.conversationId = conversationId
        self.origin = origin
    }
}

/// What a running turn tells whoever waits on it. Not a status: the waiter
/// only needs to know when to look again.
package enum TurnSignal: Sendable, Equatable {
    case ownerCheckOpened, ownerCheckClosed, finished
}

extension TurnRecord {
    /// Consecutive repeats of a phase are one phase.
    package mutating func mark(_ phase: TurnPhase, atMs: Int) {
        guard phases.last?.phase != phase else { return }
        phases.append(TurnPhaseMark(phase: phase, atMs: atMs))
    }
}

/// The last turns, newest last. A value: `appending` returns a copy, so a
/// reader holding the old ring never sees it change.
package struct TurnRing: Sendable, Equatable {
    package static let capacity = 50

    package let records: [TurnRecord]

    package init(records: [TurnRecord] = []) {
        self.records = records
    }

    package func appending(_ record: TurnRecord) -> TurnRing {
        TurnRing(records: Array((records + [record]).suffix(Self.capacity)))
    }

    package func record(_ id: String) -> TurnRecord? {
        records.last { $0.turnId == id }
    }
}

/// The wire shape of §4.1. The text fields exist only with `includeText`
/// (QA scope on): without it the same JSON carries lengths.
package struct TurnResult: Encodable, Sendable, Equatable {
    package static let maxOutputBytes = 4_000
    /// Under `BridgeCallResult.maxOutputBytes`, leaving room for the fence suffix.
    package static let maxBytes = 22_000

    struct Phase: Encodable, Equatable {
        let phase: String
        let atMs: Int
        enum CodingKeys: String, CodingKey { case phase, atMs = "at_ms" }
    }

    struct Call: Encodable, Equatable {
        let index: Int
        let name: String
        let ok: Bool
        let target: String
        let verified: Bool
        let band: String
        let ownerCheck: String
        let outputLength: Int
        let arguments: String?
        let output: String?
        enum CodingKeys: String, CodingKey {
            case index, name, ok, target, verified, band, arguments, output
            case ownerCheck = "owner_check", outputLength = "output_length"
        }
    }

    struct Card: Encodable, Equatable {
        let kind: String
    }

    struct Pending: Encodable, Equatable {
        let tool: String
        let band: String
        let reason: String
    }

    struct Handoff: Encodable, Equatable {
        let executor: String
        let goalLength: Int
        enum CodingKeys: String, CodingKey { case executor, goalLength = "goal_length" }
    }

    struct Reply: Encodable, Equatable {
        let length: Int
        let isFailure: Bool
        let language: String?
        let confidence: Double?
        let text: String?
        enum CodingKeys: String, CodingKey { case length, language, confidence, text, isFailure = "is_failure" }
    }

    struct Failure: Encodable, Equatable {
        let code: String
        let message: String
    }

    let turnId: String
    let conversationId: String
    let status: String
    let elapsedMs: Int
    let phases: [Phase]
    let toolCalls: [Call]
    let cards: [Card]
    let receipts: [String]?
    let handoff: Handoff?
    let pendingOwnerCheck: Pending?
    let reply: Reply?
    let statusLines: [String]?
    let error: Failure?
    let truncated: Bool?

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id", conversationId = "conversation_id", status
        case elapsedMs = "elapsed_ms", phases, toolCalls = "tool_calls", cards, receipts, handoff
        case pendingOwnerCheck = "pending_owner_check", reply, statusLines = "status_lines", error, truncated
    }

    /// `detected` is the reply's language worked out in-process by the caller.
    package init(
        _ record: TurnRecord, includeText: Bool, detected: DetectedLanguage? = nil, outputCap: Int = maxOutputBytes,
        keepingCalls: Int = .max
    ) {
        turnId = record.turnId
        conversationId = record.conversationId
        status = record.status.rawValue
        elapsedMs = record.elapsedMs
        phases = record.phases.map { Phase(phase: $0.phase.rawValue, atMs: $0.atMs) }
        let kept = record.toolCalls.prefix(keepingCalls)
        toolCalls = kept.map { call in
            Call(
                index: call.index, name: call.name, ok: call.ok, target: call.target, verified: call.verified,
                band: call.band, ownerCheck: call.ownerCheck, outputLength: call.output.utf8.count,
                arguments: includeText ? Self.capped(call.arguments, outputCap) : nil,
                output: includeText ? Self.capped(call.output, outputCap) : nil)
        }
        cards = record.cards.map { Card(kind: $0.kind) }
        receipts = includeText ? record.receipts : nil
        handoff = record.handoffGoalLength.map { Handoff(executor: "claude-code", goalLength: $0) }
        pendingOwnerCheck = record.pendingOwner.map { Pending(tool: $0.tool, band: $0.band, reason: $0.reason) }
        reply = record.reply.map {
            Reply(
                length: $0.text.count, isFailure: $0.isFailure, language: detected?.code,
                confidence: detected?.confidence, text: includeText ? $0.text : nil)
        }
        statusLines = includeText ? record.statusLines : nil
        error = record.error.map { Failure(code: $0.code, message: $0.message) }
        truncated = kept.count < record.toolCalls.count ? true : nil
    }

    /// Whole characters only: a cut through a multibyte one would not decode.
    static func capped(_ text: String, _ limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var kept = ""
        var used = 0
        for character in text {
            let size = character.utf8.count
            guard used + size <= limit else { break }
            kept.append(character)
            used += size
        }
        return kept + "…"
    }

    /// Sorted-key JSON that fits `maxBytes` and stays valid JSON: the outputs
    /// shrink first, then the tail of the calls goes, flagged as truncated.
    package static func json(
        _ record: TurnRecord, includeText: Bool, detected: DetectedLanguage? = nil
    ) -> String {
        for (cap, keep) in [(maxOutputBytes, Int.max), (800, Int.max), (200, Int.max), (0, 20), (0, 5), (0, 0)] {
            let text = encode(TurnResult(
                record, includeText: includeText, detected: detected, outputCap: cap, keepingCalls: keep))
            if text.utf8.count <= maxBytes { return text }
        }
        return encode(TurnResult(record, includeText: false, outputCap: 0, keepingCalls: 0))
    }

    private static func encode(_ result: TurnResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return String(decoding: try encoder.encode(result), as: UTF8.self)
        } catch {
            return "{}"
        }
    }
}
