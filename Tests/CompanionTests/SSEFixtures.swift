import Foundation

/// Recorded OpenAI-compatible SSE lines. No live network.
enum SSEFixtures {
    static let done = "data: [DONE]"

    static let hello =
        #"data: {"choices":[{"delta":{"content":"Hola"}}]}"#

    static let groq =
        #"data: {"choices":[{"delta":{"content":"Desde Groq"}}]}"#

    /// 25+ chars and ". " so SentenceSplitter.takeSentence cuts.
    static let sentence =
        #"data: {"choices":[{"delta":{"content":"Claro, te ayudo con eso ahora. "}}]}"#

    static let preface =
        #"data: {"choices":[{"delta":{"content":"Puedo intentarlo"}}]}"#

    static func content(_ text: String) -> String {
        dataLine(["choices": [["delta": ["content": text]]]])
    }

    static func chunks(_ texts: String...) -> [String] {
        texts.map { content($0) } + [done]
    }

    /// Name arrives first; arguments arrive in JSON fragments.
    static let delegateName =
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"delegate","arguments":""}}]}}]}"#

    static let delegateGoalHead =
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"goal\": \"lis"}}]}}]}"#

    static let delegateGoalTail =
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"tar el escritorio\", \"context\": \"workdir ~\"}"}}]}}]}"#

    static let delegateFragments: [String] = [
        delegateName, delegateGoalHead, delegateGoalTail, done,
    ]

    static let malformedDelegate: [String] = [
        preface,
        #"data: {"choices":[{"delta":{"tool_calls":[{"function":{"name":"delegate","arguments":"{\"goal\": \"x"}}]}}]}"#,
        done,
    ]

    private static func dataLine(_ obj: [String: Any]) -> String {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: obj)
        } catch {
            return "data: {}"
        }
        return "data: " + (String(data: data, encoding: .utf8) ?? "{}")
    }
}
