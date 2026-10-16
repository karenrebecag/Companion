import CompanionCore
import Foundation

/// A `QADriving` whose answers the test sets and whose asks it can read back.
package final class FakeQADriving: QADriving, @unchecked Sendable {
    package struct Ask: Equatable {
        package var text: String
        package var newConversation: Bool
        package var asUserWords: Bool

        package init(text: String, newConversation: Bool, asUserWords: Bool) {
            self.text = text
            self.newConversation = newConversation
            self.asUserWords = asUserWords
        }
    }

    private let lock = NSLock()
    private var _start: QAAskStart
    private var _asks: [Ask] = []
    private var records: [String: TurnRecord] = [:]

    package init(start: QAAskStart = .started(turnId: "t1", conversationId: "c1")) {
        _start = start
    }

    package var asks: [Ask] { lock.withLock { _asks } }

    package func set(_ record: TurnRecord) {
        lock.withLock { records[record.turnId] = record }
    }

    package func ask(text: String, newConversation: Bool, asUserWords: Bool) async -> QAAskStart {
        lock.withLock {
            _asks.append(Ask(text: text, newConversation: newConversation, asUserWords: asUserWords))
            return _start
        }
    }

    package func turn(_ id: String) async -> TurnRecord? {
        lock.withLock { records[id] }
    }
}

/// A `QAGating` that answers what the test says, and can hold the call open
/// until its task is cancelled (an owner dialog nobody has touched yet).
package final class FakeQAGate: QAGating, @unchecked Sendable {
    private let lock = NSLock()
    private var _verdict: QAVerdict
    private let hold: Bool
    private var _decided: [String] = []

    package init(_ verdict: QAVerdict, hold: Bool = false) {
        _verdict = verdict
        self.hold = hold
    }

    /// The tool names of every request it was asked about.
    package var decided: [String] { lock.withLock { _decided } }

    package func decide(_ request: ApprovalRequest, call: ToolCallRef, said: String) async -> QAVerdict {
        lock.withLock { _decided.append(call.name) }
        if hold {
            while !Task.isCancelled { await Task.yield() }
            return .refused(code: BridgeCode.ownerRefused)
        }
        return lock.withLock { _verdict }
    }

    package func canVerify() async -> Bool { true }
}
