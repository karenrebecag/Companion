import CompanionCore
import Foundation

/// Serves the read-only `companion_*` family over the bridge (spec
/// self-qa-inspeccion, PR-2). It reads the port and the main log and answers
/// in metadata: no write, no sheet of its own (`approval` stays the default,
/// nil) and an empty `target`, so the bridge log line never carries content.
/// It does not depend on the hands, which is why it answers while Companion
/// is in front.
package struct SelfInspectionRunner: ParentToolExecuting, Sendable {
    package static let defaultLogLines = 50
    package static let maxLogLines = 200
    package static let maxLogBytes = 32_000

    /// One per process (PR-1 contract): a limit per runner or per connection
    /// would reset on every reconnect and stop limiting anything.
    package static let sharedEqualityLimit = EqualityLimitBox()

    private let source: any SelfInspecting
    private let recognizer: any LanguageRecognizing
    private let language: @Sendable () -> AppLanguage
    private let logTail: @Sendable (Int) -> [String]
    private let now: @Sendable () -> Date
    let equalityLimit: EqualityLimitBox

    package init(
        source: any SelfInspecting,
        recognizer: any LanguageRecognizing = NaturalLanguageRecognizer(),
        language: @escaping @Sendable () -> AppLanguage,
        logTail: @escaping @Sendable (Int) -> [String] = { Log.tail(lines: $0) },
        now: @escaping @Sendable () -> Date = { Date() },
        equalityLimit: EqualityLimitBox = SelfInspectionRunner.sharedEqualityLimit
    ) {
        self.source = source
        self.recognizer = recognizer
        self.language = language
        self.logTail = logTail
        self.now = now
        self.equalityLimit = equalityLimit
    }

    package func specs(_ language: AppLanguage) -> [ToolSpec] {
        CompanionTool.allCases.map { $0.spec(language) }
    }

    package func handles(_ name: String) -> Bool {
        CompanionTool(rawValue: name) != nil
    }

    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        guard let tool = CompanionTool(rawValue: name) else {
            return .failed(.notFound("unknown tool: \(InspectionName.capped(name))"))
        }
        // The arguments are never echoed back: `expected` is a guess at what
        // the user typed.
        guard let arguments = ToolArguments.parse(argumentsJSON) else {
            return .failed(.invalidArgs("could not parse arguments; send one JSON object"), tool: name)
        }
        switch tool {
        case .state:
            return encoded(SessionInspection(await source.session()), tool: name)
        case .island:
            guard let painted = await source.island() else {
                return Self.notPainted(name)
            }
            return encoded(IslandInspection(painted), tool: name)
        case .settings:
            return encoded(await source.settings(), tool: name)
        case .thread:
            let thread = await source.activeThread()
            // D4: the language is worked out here, in-process; only the code
            // and the confidence leave.
            let inspected = thread.map { MessageInspection($0, detected: recognizer.dominant($0.text)) }
            return encoded(inspected, tool: name)
        case .lastMessageMatches:
            return await lastMessageMatches(arguments, tool: name)
        case .log:
            return log(arguments, tool: name)
        }
    }

    private func lastMessageMatches(_ arguments: [String: Any], tool: String) async -> ParentToolOutcome {
        let thread = await source.activeThread()
        // Admission before validation (PR-1 contract): an empty or oversize
        // probe that cost nothing would be a free side channel.
        switch equalityLimit.admit(now: now(), messageKey: LastMessageMatch.messageKey(in: thread)) {
        case .admitted:
            break
        case .rateLimited:
            return .failed(ContractError(
                code: BridgeCode.rateLimited,
                message: "at most \(EqualityCheckLimit.perMinute) checks per minute"), tool: tool)
        case .exhausted:
            return .failed(ContractError(
                code: BridgeCode.rateLimited,
                message: "no more checks against this message; wait for the next one"), tool: tool)
        }
        guard let expected = arguments["expected"] as? String,
              expected.unicodeScalars.count <= LastMessageMatch.maxExpectedScalars
        else {
            return .failed(.invalidArgs(
                "expected must be text of at most \(LastMessageMatch.maxExpectedScalars) characters"), tool: tool)
        }
        return encoded(MatchAnswer(matches: LastMessageMatch.matches(expected, in: thread)), tool: tool)
    }

    private func log(_ arguments: [String: Any], tool: String) -> ParentToolOutcome {
        let requested: Int
        if let raw = arguments["lines"] {
            // JSONSerialization yields NSNumber, and on Darwin `true as? Int`
            // is 1: a flag must not pass for a line count.
            let isFlag = CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID()
            guard !isFlag, let count = raw as? Int, (1...Self.maxLogLines).contains(count) else {
                return .failed(.invalidArgs("lines must be a whole number from 1 to \(Self.maxLogLines)"), tool: tool)
            }
            requested = count
        } else {
            requested = Self.defaultLogLines
        }
        let lines = Self.newestWithin(Self.maxLogBytes, logTail(requested))
        // D6: log lines hold wire and error text, so they leave framed as data.
        let body = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        return ParentToolOutcome(
            ok: true, output: body + BridgeCopy.toolDataSuffix(language()), target: "", tool: tool)
    }

    /// The newest lines whose joined size fits `budget`; a single line that
    /// alone is over the budget is dropped rather than cut mid-line.
    static func newestWithin(_ budget: Int, _ lines: [String]) -> [String] {
        var kept: [String] = []
        var used = 0
        for line in lines.reversed() {
            let cost = line.utf8.count + 1
            guard used + cost <= budget else { break }
            kept.append(line)
            used += cost
        }
        return kept.reversed()
    }

    private static func notPainted(_ tool: String) -> ParentToolOutcome {
        .failed(ContractError(
            code: BridgeCode.notAvailable, message: "the island has not been painted yet"), tool: tool)
    }

    /// Sorted keys so two reads of the same state compare as text.
    private func encoded<T: Encodable>(_ value: T, tool: String) -> ParentToolOutcome {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(value)
            return ParentToolOutcome(
                ok: true, output: String(decoding: data, as: UTF8.self), target: "", tool: tool)
        } catch {
            return .failed(ContractError(
                code: BridgeCode.notAvailable, message: "could not encode the answer"), tool: tool)
        }
    }
}

private struct MatchAnswer: Encodable {
    let matches: Bool
}

/// The process-wide `EqualityCheckLimit`, behind a lock: bridge calls run on
/// whatever task the session uses, and the limit is a mutating value.
package final class EqualityLimitBox: @unchecked Sendable {
    private let lock = NSLock()
    private var limit = EqualityCheckLimit()

    package init() {}

    package func admit(now: Date, messageKey: Int?) -> EqualityCheckAdmission {
        lock.withLock { limit.admit(now: now, messageKey: messageKey) }
    }
}
