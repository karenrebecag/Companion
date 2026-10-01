import Foundation

/// Recorded OpenAI-compatible SSE lines. No live network.
package enum SSEFixtures {
    package static let done = "data: [DONE]"

    package static let hello =
        #"data: {"choices":[{"delta":{"content":"Hola"}}]}"#

    /// What the second rung of a ladder answers in a failover test.
    package static let fallback =
        #"data: {"choices":[{"delta":{"content":"Desde el respaldo"}}]}"#

    /// 25+ chars and ". " so SentenceSplitter.takeSentence cuts.
    package static let sentence =
        #"data: {"choices":[{"delta":{"content":"Claro, te ayudo con eso ahora. "}}]}"#

    package static let preface =
        #"data: {"choices":[{"delta":{"content":"Puedo intentarlo"}}]}"#

    package static func content(_ text: String) -> String {
        dataLine(["choices": [["delta": ["content": text]]]])
    }

    package static func chunks(_ texts: String...) -> [String] {
        texts.map { content($0) } + [done]
    }

    /// Name arrives first; arguments arrive in JSON fragments.
    package static let delegateName =
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"delegate","arguments":""}}]}}]}"#

    package static let delegateGoalHead =
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"goal\": \"lis"}}]}}]}"#

    package static let delegateGoalTail =
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"tar el escritorio\", \"context\": \"workdir ~\"}"}}]}}]}"#

    package static let delegateFragments: [String] = [
        delegateName, delegateGoalHead, delegateGoalTail, done,
    ]

    package static let malformedDelegate: [String] = [
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

    /// Wave 10c: dos calls intercaladas por índice, como las manda OpenAI.
    package static let twoToolCalls = [
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"read_file","arguments":""}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call_b","type":"function","function":{"name":"read_file","arguments":""}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"path\":"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{\"path\":\"b.md\"}"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"a.md\"}"}}]}}]}"#,
        #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        done,
    ]

    package static let delegatePlusOpenApp = [
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_0","function":{"name":"delegate","arguments":"{\"goal\":\"listar el escritorio\"}"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call_1","function":{"name":"open_app","arguments":"{\"name\":\"Safari\"}"}}]}}]}"#,
        done,
    ]
}
