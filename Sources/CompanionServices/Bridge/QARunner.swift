import CompanionCore
import Foundation

/// Serves `companion_ask` and `companion_wait_turn` (puente QA, PR-2). They
/// exist only while the QA scope is on, read per call: with it off the tools
/// are not listed and a call answers `unknown_tool`. No sheet of its own:
/// the gates of the turn it starts are QA mode's.
package struct QARunner: ParentToolExecuting, Sendable {
    private let driving: any QADriving
    private let waiter: TurnWaiter
    private let scope: @Sendable () -> Bool
    private let language: @Sendable () -> AppLanguage
    private let recognizer: any LanguageRecognizing

    package init(
        driving: any QADriving,
        waiter: TurnWaiter,
        scope: @escaping @Sendable () -> Bool,
        language: @escaping @Sendable () -> AppLanguage,
        recognizer: any LanguageRecognizing = NaturalLanguageRecognizer()
    ) {
        self.driving = driving
        self.waiter = waiter
        self.scope = scope
        self.language = language
        self.recognizer = recognizer
    }

    package func specs(_ language: AppLanguage) -> [ToolSpec] {
        scope() ? QATool.allCases.map { $0.spec(language) } : []
    }

    package func handles(_ name: String) -> Bool {
        scope() && QATool(rawValue: name) != nil
    }

    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        guard let tool = QATool(rawValue: name) else {
            return .failed(.notFound("unknown tool: \(InspectionName.capped(name))"))
        }
        guard scope() else {
            return .failed(
                ContractError(code: BridgeCode.qaScopeOff, message: "QA mode is off"), tool: name)
        }
        // The text is never echoed back: it is what the user would have typed.
        guard let arguments = ToolArguments.parse(argumentsJSON) else {
            return .failed(.invalidArgs("could not parse arguments; send one JSON object"), tool: name)
        }
        switch tool {
        case .ask: return await ask(arguments)
        case .waitTurn: return await waitTurn(arguments)
        }
    }

    private func ask(_ arguments: [String: Any]) async -> ParentToolOutcome {
        let name = QATool.ask.rawValue
        guard let text = arguments["text"] as? String, !text.isEmpty,
              text.utf8.count <= QATool.maxTextBytes, !text.utf8.contains(0)
        else {
            return .failed(.invalidArgs(
                "text must be 1 to \(QATool.maxTextBytes) UTF-8 bytes and contain no NUL"), tool: name)
        }
        let conversation = arguments["conversation"] as? String ?? "current"
        guard conversation == "current" || conversation == "new" else {
            return .failed(.invalidArgs("conversation must be current or new"), tool: name)
        }
        let asUserWords: Bool
        if let raw = arguments["as_user_words"] {
            guard let flag = Self.flag(raw) else {
                return .failed(.invalidArgs("as_user_words must be true or false"), tool: name)
            }
            asUserWords = flag
        } else {
            asUserWords = true
        }
        guard let seconds = Self.seconds(arguments["wait_seconds"]) else {
            return .failed(.invalidArgs(
                "wait_seconds must be a whole number from 0 to \(QATool.maxWaitSeconds)"), tool: name)
        }
        switch await driving.ask(text: text, newConversation: conversation == "new", asUserWords: asUserWords) {
        case .unavailable:
            return .failed(ContractError(
                code: BridgeCode.notAvailable, message: "the conversation cannot take a turn yet"), tool: name)
        case .busy(let turnId):
            return .failed(ContractError(
                code: BridgeCode.busyTurn,
                message: "a turn is already running (turn_id \(turnId)): call companion_wait_turn"), tool: name)
        case .started(let turnId, _):
            return await settled(turnId, seconds: seconds, tool: name)
        }
    }

    private func waitTurn(_ arguments: [String: Any]) async -> ParentToolOutcome {
        let name = QATool.waitTurn.rawValue
        guard let turnId = arguments["turn_id"] as? String, !turnId.isEmpty, turnId.utf8.count <= 64 else {
            return .failed(.invalidArgs("turn_id must be the id companion_ask returned"), tool: name)
        }
        guard let seconds = Self.seconds(arguments["wait_seconds"]) else {
            return .failed(.invalidArgs(
                "wait_seconds must be a whole number from 0 to \(QATool.maxWaitSeconds)"), tool: name)
        }
        return await settled(turnId, seconds: seconds, tool: name)
    }

    /// Waits only if the turn is still going; a finished one answers at once.
    private func settled(_ turnId: String, seconds: Int, tool: String) async -> ParentToolOutcome {
        guard let first = await driving.turn(turnId) else {
            return .failed(ContractError(code: BridgeCode.notFound, message: "no turn with that id"), tool: tool)
        }
        if !first.status.isFinished {
            _ = await waiter.wait(turnId: turnId, seconds: seconds)
        }
        guard let record = await driving.turn(turnId) else {
            return .failed(ContractError(code: BridgeCode.notFound, message: "no turn with that id"), tool: tool)
        }
        return result(record, tool: tool)
    }

    private func result(_ record: TurnRecord, tool: String) -> ParentToolOutcome {
        let detected = record.reply.flatMap { recognizer.dominant($0.text) }
        let json = TurnResult.json(record, includeText: scope(), detected: detected)
        // An interrupted turn is a result the agent reads, not a failed call.
        return ParentToolOutcome(
            ok: true, output: json + "\n" + BridgeCopy.toolDataSuffix(language()), target: "", tool: tool)
    }

    /// `true as? Int` is 1 on Darwin, and a flag must not pass for a count.
    private static func isBoolean(_ raw: Any) -> Bool {
        CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID()
    }

    private static func flag(_ raw: Any) -> Bool? {
        isBoolean(raw) ? raw as? Bool : nil
    }

    /// Nil when present but not a whole number in range.
    private static func seconds(_ raw: Any?) -> Int? {
        guard let raw else { return QATool.defaultWaitSeconds }
        guard !isBoolean(raw), let value = raw as? Int, (0...QATool.maxWaitSeconds).contains(value) else {
            return nil
        }
        return value
    }
}
