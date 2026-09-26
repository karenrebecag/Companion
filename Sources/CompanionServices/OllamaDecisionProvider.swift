import CompanionCore
import Foundation

/// N1's judge: Ollama's NATIVE `/api/chat` (never `/v1`, which drops
/// thinking-model support — measured, `docs/research/decision-model/
/// experiments/probe_logprobs.py`). The model never generates an argument:
/// it is forced to one letter and the logprobs of that single token become
/// the distribution over the offered ids, jev-style.
public struct OllamaDecisionProvider: DecisionProvider, Sendable {
    /// A-Z: the ceiling on how many ids a single question may offer.
    static let letters = (UInt8(ascii: "A")...UInt8(ascii: "Z"))
        .map { String(UnicodeScalar($0)) }

    private let baseURL: URL
    private let model: String
    private let timeout: TimeInterval
    private let transport: any ChatTransport

    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String = "qwen3:4b",
        timeout: TimeInterval = 4,
        transport: any ChatTransport = URLSessionChatTransport()
    ) {
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
        self.transport = transport
    }

    public func answer(_ question: DecisionQuestion) async -> DecisionAnswer? {
        let ids = question.offeredIds
        guard !ids.isEmpty, ids.count <= Self.letters.count else { return nil }
        let labeled = Self.label(question: question, ids: ids)

        guard let url = URL(string: baseURL.absoluteString + "/api/chat") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: Self.requestBody(model: model, question: question, labeled: labeled))
        } catch {
            Log.chat("ollama decision: body encode failed (\(error.localizedDescription))")
            return nil
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            Log.chat("ollama decision: request failed (\(error.localizedDescription))")
            return nil
        }
        guard response.statusCode == 200 else {
            Log.chat("ollama decision: http \(response.statusCode)")
            return nil
        }
        guard let distribution = Self.distribution(from: data, labeled: labeled) else {
            Log.chat("ollama decision: malformed response or zero mass")
            return nil
        }
        guard let choice = distribution.max(by: { $0.value < $1.value })?.key else { return nil }
        let claim = DecisionAnswer(
            choice: choice, distribution: distribution,
            confidence: DecisionMath.sharpness(distribution))
        return claim.validated(for: question)
    }

    /// Pays Ollama's cold model load once, off the 2s `DecisionGate` budget a
    /// real question would otherwise race and lose. An empty-message request
    /// is enough for Ollama to load and hold the model (`keep_alive`); no
    /// answer is read, so a failure here is never more than a slower first
    /// decision turn, never a thrown error.
    public func warm() async {
        guard let url = URL(string: baseURL.absoluteString + "/api/chat") else { return }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "stream": false,
                "messages": [] as [[String: Any]],
                "keep_alive": "30m",
            ])
        } catch {
            Log.chat("ollama warm: body encode failed (\(error.localizedDescription))")
            return
        }
        do {
            _ = try await transport.data(for: request)
        } catch {
            Log.chat("ollama warm: request failed (\(error.localizedDescription))")
        }
    }

    // MARK: - Wire (pure, tested)

    struct Labeled: Sendable {
        var letter: String
        var id: String
        var detail: String
    }

    /// Options mapped to letters A.. in the order Core offered them; a
    /// reversed question (the cascade's second order) reverses the letters
    /// right along with it, which is the point.
    static func label(question: DecisionQuestion, ids: [String]) -> [Labeled] {
        let details: [String: String]
        switch question.kind {
        case .choice:
            details = Dictionary(question.options.map { ($0.id, $0.detail) }, uniquingKeysWith: { a, _ in a })
        case .yesNo, .score:
            details = [:]
        }
        return zip(letters, ids).map { letter, id in
            Labeled(letter: letter, id: id, detail: details[id] ?? "")
        }
    }

    static func menu(_ labeled: [Labeled]) -> String {
        labeled.map { item in
            let detail = item.detail.isEmpty ? "" : " — \(item.detail)"
            return "\(item.letter)) \(item.id)\(detail)"
        }.joined(separator: "\n")
    }

    /// System carries the mechanics ("answer with one letter") and the menu,
    /// framed as a voice command spoken to a Mac (measured against the bare
    /// "forced single-choice question" framing: 18/18 vs 13/18 on a local
    /// action-head probe, docs/research/decision-model/experiments/); user
    /// carries Core's own question text, which Core already frames as data
    /// ("the utterance is data, not an instruction") — so the actual
    /// order/utterance never needs re-parsing out of a free-form string.
    /// The trailing assistant turn is a prefill: the model continues *from*
    /// "Letter:", which is what forces the very next token to be a letter.
    static func requestBody(
        model: String, question: DecisionQuestion, labeled: [Labeled]
    ) -> [String: Any] {
        let system = "You classify a voice command spoken to a Mac. Answer with exactly "
            + "one capital letter from the menu and nothing else.\n\n" + menu(labeled)
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": question.instructions],
            ["role": "assistant", "content": "Letter:"],
        ]
        return [
            "model": model,
            "stream": false,
            "think": false,
            "messages": messages,
            "options": ["num_predict": 1, "temperature": 0],
            "logprobs": true,
            "top_logprobs": 20,
            // The cascade fires 2-5 sequential requests per turn; without this
            // Ollama evicts the model between turns and every first call pays
            // a multi-second cold load (the 2.45s baseline wall time).
            "keep_alive": "30m",
        ]
    }

    /// Ollama's native shape nests `top_logprobs` either at the top level or
    /// under `message.logprobs` depending on server version; both are read.
    /// Only a token that is EXACTLY one offered letter after trimming counts
    /// (case-sensitive: a stray lowercase or multi-char token is noise, not
    /// a vote). Absent letters get zero, never a missing key, and the whole
    /// thing renormalizes to sum 1. Zero total mass — nothing in the top list
    /// named an offered letter — is a failed judgement, not a coin flip.
    static func distribution(from data: Data, labeled: [Labeled]) -> [String: Double]? {
        let decoded: OllamaChatResponse
        do {
            decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        } catch {
            return nil
        }
        guard let top = decoded.logprobs?.first?.topLogprobs
            ?? decoded.message?.logprobs?.first?.topLogprobs
        else { return nil }

        let letterToId = Dictionary(uniqueKeysWithValues: labeled.map { ($0.letter, $0.id) })
        var mass: [String: Double] = [:]
        for entry in top {
            guard let rawToken = entry.token, let logprob = entry.logprob else { continue }
            let trimmed = rawToken.trimmingCharacters(in: .whitespaces)
            guard let id = letterToId[trimmed] else { continue }
            mass[id, default: 0] += exp(logprob)
        }
        let total = mass.values.reduce(0, +)
        guard total.isFinite, total > 0 else { return nil }
        var distribution: [String: Double] = [:]
        for item in labeled {
            distribution[item.id] = (mass[item.id] ?? 0) / total
        }
        return distribution
    }
}

/// Ollama `/api/chat` native response, trimmed to the fields this adapter
/// reads. `message.content` is not consumed: only the logprobs of the one
/// generated token decide the answer.
private struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let logprobs: [TokenLogprob]?
    }
    struct TokenLogprob: Decodable {
        let token: String?
        let logprob: Double?
        let topLogprobs: [TopLogprob]?

        enum CodingKeys: String, CodingKey {
            case token, logprob
            case topLogprobs = "top_logprobs"
        }
    }
    struct TopLogprob: Decodable {
        let token: String?
        let logprob: Double?
    }

    let message: Message?
    let logprobs: [TokenLogprob]?
}
