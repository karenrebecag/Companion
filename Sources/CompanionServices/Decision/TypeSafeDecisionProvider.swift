import CompanionCore
import Foundation

/// Jev (TypeSafe's System One model) behind the decision port. Unlike the
/// local judge it returns a calibrated distribution natively, so nothing is
/// read off logprobs: the adapter's whole job is the wire shape and refusing
/// any reply that does not name exactly what Core offered.
///
/// Only the question goes out: Core's utterance and the option names it is
/// weighed against. Nothing from the screen is ever part of a question.
package struct TypeSafeDecisionProvider: DecisionProvider, Sendable {
    /// Jev's own ceiling per choice; above it the API answers 422.
    static let maxChoiceOptions = 255
    /// Jev's wire tolerance. Core's own check is tighter (0.02), so a reply
    /// inside this one is renormalized before Core sees it.
    static let sumTolerance = 0.03

    private let descriptor: ProviderDescriptor
    private let secrets: any SecretStore
    private let timeout: TimeInterval
    private let transport: any ChatTransport

    package init(
        secrets: any SecretStore,
        descriptor: ProviderDescriptor = .typesafe,
        timeout: TimeInterval = 2,
        transport: any ChatTransport = URLSessionChatTransport()
    ) {
        self.secrets = secrets
        self.descriptor = descriptor
        self.timeout = timeout
        self.transport = transport
    }

    package var isConfigured: Bool { key != nil }

    private var key: String? {
        guard let secretKey = descriptor.secretKey else { return nil }
        let value: String?
        do {
            value = try secrets.read(secretKey)
        } catch {
            return nil
        }
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    package func answer(_ question: DecisionQuestion) async -> DecisionAnswer? {
        let ids = question.offeredIds
        guard !ids.isEmpty, ids.count <= Self.maxChoiceOptions else { return nil }
        guard let key else { return nil }
        guard let url = URL(string: descriptor.baseURL.absoluteString + "/systemone"),
              EndpointPolicy.isAcceptable(url)
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: Self.requestBody(model: descriptor.model, question: question),
                options: [.sortedKeys])
        } catch {
            Log.chat("typesafe decision: body encode failed (\(error.localizedDescription))")
            return nil
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            // Timeouts and drops pass the turn through to the brain; the
            // judgement is advisory, so a retry would only spend the budget.
            Log.chat("typesafe decision: request failed (\(error.localizedDescription))")
            return nil
        }
        guard response.statusCode == 200 else {
            // 429 and 529 are Jev saying "later"; any other status is a
            // request it refused. Either way there is no answer to act on.
            Log.chat("typesafe decision: http \(response.statusCode)")
            return nil
        }
        guard let claim = Self.answer(from: data, question: question) else {
            Log.chat("typesafe decision: malformed or invalid reply")
            return nil
        }
        return claim.validated(for: question)
    }

    // MARK: - Wire (pure, tested)

    static let questionKey = "q"

    /// Core already frames the utterance as data inside its question text,
    /// so that text is the state Jev evaluates and the instructions only say
    /// how to read it.
    static func requestBody(model: String, question: DecisionQuestion) -> [String: Any] {
        [
            "model": model,
            "state": question.instructions,
            "questions": [questionKey: wireQuestion(question)],
        ]
    }

    static let readingInstructions =
        "`state` quotes a voice command spoken to a Mac, then asks one question about it. "
        + "Answer that question."

    static func wireQuestion(_ question: DecisionQuestion) -> [String: Any] {
        switch question.kind {
        case .choice:
            var criteria: [String: Any] = [:]
            for option in question.options {
                criteria[option.id] = option.detail.isEmpty ? NSNull() : option.detail as Any
            }
            return ["type": "choice", "instructions": readingInstructions, "criteria": criteria]
        case .yesNo:
            return ["type": "noul", "instructions": readingInstructions]
        case .score:
            let ids = question.offeredIds
            let details = question.options.map(\.detail)
            let levels = details.count == ids.count && !details.contains(where: \.isEmpty)
                ? details : ids
            return ["type": "score", "instructions": readingInstructions, "criteria": levels]
        }
    }

    /// Jev's reply checked the way `validate_choice` does: the answer is of
    /// the type asked, names an offered id, covers exactly the offered set,
    /// sums to 1 within the wire tolerance, and names a mode. Anything else
    /// is nil — a malformed reply never becomes an action.
    static func answer(from data: Data, question: DecisionQuestion) -> DecisionAnswer? {
        let decoded: SystemOneResponse
        do {
            decoded = try JSONDecoder().decode(SystemOneResponse.self, from: data)
        } catch {
            return nil
        }
        guard decoded.answers.count == 1, let raw = decoded.answers[questionKey] else { return nil }
        switch question.kind {
        case .choice:
            guard raw.type == "choice", let choice = raw.choice,
                  let probabilities = raw.probabilities, let confidence = raw.confidence
            else { return nil }
            return checked(
                choice: choice, probabilities: probabilities, confidence: confidence,
                ids: question.offeredIds)
        case .score:
            // Jev numbers levels from "0"; Core offers "1"..."n".
            guard raw.type == "score", let probabilities = raw.probabilities,
                  let confidence = raw.confidence
            else { return nil }
            var shifted: [String: Double] = [:]
            for (level, p) in probabilities {
                guard let index = Int(level), String(index) == level else { return nil }
                shifted[String(index + 1)] = p
            }
            guard let choice = shifted.max(by: { $0.value < $1.value })?.key else { return nil }
            return checked(
                choice: choice, probabilities: shifted, confidence: confidence,
                ids: question.offeredIds)
        case .yesNo:
            guard raw.type == "noul", let yes = raw.noul, yes.isFinite, (0...1).contains(yes)
            else { return nil }
            let distribution = ["yes": yes, "no": 1 - yes]
            return DecisionAnswer(
                choice: yes >= 0.5 ? "yes" : "no", distribution: distribution,
                confidence: DecisionMath.sharpness(distribution))
        }
    }

    private static func checked(
        choice: String, probabilities: [String: Double], confidence: Double, ids: [String]
    ) -> DecisionAnswer? {
        guard ids.contains(choice), Set(probabilities.keys) == Set(ids) else { return nil }
        guard confidence.isFinite, (0...1).contains(confidence) else { return nil }
        guard probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return nil
        }
        let sum = probabilities.values.reduce(0, +)
        guard abs(sum - 1) < sumTolerance else { return nil }
        let peak = probabilities.values.max() ?? 0
        guard let named = probabilities[choice], named >= peak - 1e-6 else { return nil }
        let normalized = probabilities.mapValues { $0 / sum }
        return DecisionAnswer(choice: choice, distribution: normalized, confidence: confidence)
    }
}

/// `POST /v1/systemone` reply, trimmed to what the adapter reads. Fields
/// are optional because each answer type carries a different subset; the
/// per-kind checks above decide which ones must be present.
private struct SystemOneResponse: Decodable {
    struct Answer: Decodable {
        let type: String
        let choice: String?
        let probabilities: [String: Double]?
        let confidence: Double?
        let noul: Double?
    }

    let answers: [String: Answer]
}
