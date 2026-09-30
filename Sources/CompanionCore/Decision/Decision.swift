import Foundation

/// Heads the cascade asks. The id is the wire name of one question; an
/// adapter never invents a head Core did not ask for.
package enum DecisionHead {
    package static let action = "action"
    package static let app = "app"
    package static let site = "site"
    package static let file = "file"
    package static let skill = "skill"
    package static let query = "query"
    package static let text = "text"
    package static let goal = "goal"
    package static let submit = "submit"
    package static let volume = "volume"
    package static let shortcut = "shortcut"
    package static let media = "media"
    package static let system = "system"
    package static let scrollDirection = "scroll_dir"
    package static let scrollAmount = "scroll_amount"
}

/// The three shapes on Jev's wire, so a TypeSafe adapter can sit behind
/// this port later without a Core change. The cascade itself asks `choice`:
/// a 4B's yes/no head is not a gate.
package enum DecisionQuestionKind: String, Sendable, Equatable {
    case choice
    case yesNo
    case score
}

package struct DecisionOption: Sendable, Equatable {
    package var id: String
    package var detail: String

    package init(id: String, detail: String = "") {
        self.id = id
        self.detail = detail
    }
}

package struct DecisionQuestion: Sendable, Equatable {
    package var id: String
    package var kind: DecisionQuestionKind
    package var instructions: String
    package var options: [DecisionOption]
    /// Score questions only. Clamped to 2...10 when the ids are read.
    package var levels: Int

    package init(
        id: String,
        kind: DecisionQuestionKind,
        instructions: String,
        options: [DecisionOption] = [],
        levels: Int = 2
    ) {
        self.id = id
        self.kind = kind
        self.instructions = instructions
        self.options = options
        self.levels = levels
    }

    /// The only ids a valid answer may name. Score and yes/no do not trust
    /// a caller-supplied option list: the wire shape fixes the set.
    package var offeredIds: [String] {
        switch kind {
        case .yesNo:
            return ["yes", "no"]
        case .score:
            let n = min(10, max(2, levels))
            return (1...n).map(String.init)
        case .choice:
            return options.map(\.id)
        }
    }

    func reversed() -> DecisionQuestion {
        var copy = self
        copy.options.reverse()
        return copy
    }
}

package struct DecisionAnswer: Sendable, Equatable {
    package var choice: String?
    package var distribution: [String: Double]
    package var confidence: Double

    package init(choice: String?, distribution: [String: Double], confidence: Double) {
        self.choice = choice
        self.distribution = distribution
        self.confidence = confidence
    }

    package func validated(for question: DecisionQuestion) -> DecisionAnswer? {
        validated(against: question.offeredIds)
    }

    /// Jev's `validate_choice`: the named id is one that was offered, the
    /// distribution covers exactly that set and sums to 1, and the name is
    /// a mode of the distribution. Anything else is not an action.
    package func validated(against ids: [String]) -> DecisionAnswer? {
        guard !ids.isEmpty, Set(ids).count == ids.count else { return nil }
        guard let choice, ids.contains(choice) else { return nil }
        guard Set(distribution.keys) == Set(ids) else { return nil }
        guard confidence.isFinite, (0...1).contains(confidence) else { return nil }
        var sum = 0.0
        var peak = -1.0
        for id in ids {
            guard let p = distribution[id], p.isFinite, (0...1).contains(p) else { return nil }
            sum += p
            if p > peak { peak = p }
        }
        guard abs(sum - 1) < 0.02 else { return nil }
        guard let named = distribution[choice], named >= peak - 1e-6 else { return nil }
        let sharp = DecisionMath.sharpness(distribution)
        return DecisionAnswer(
            choice: choice, distribution: distribution, confidence: min(confidence, sharp))
    }
}

package enum DecisionMath {
    /// `(n · pMax − 1) / (n − 1)`. A flat distribution is 0; a point mass is 1.
    /// One claimed confidence cannot outvote the mass.
    package static func sharpness(_ distribution: [String: Double]) -> Double {
        let n = distribution.count
        guard n > 1, let peak = distribution.values.max(), peak.isFinite else {
            return n == 1 ? 1 : 0
        }
        let raw = (Double(n) * peak - 1) / Double(n - 1)
        return min(1, max(0, raw))
    }

    /// Two option orders, blended into one distribution. Split out of
    /// `average` so a tie — no single winner — still hands back the masses:
    /// that is exactly the input `ArbitrationShortlist.build` needs.
    package static func blend(
        _ first: DecisionAnswer, _ second: DecisionAnswer, ids: [String]
    ) -> [String: Double]? {
        guard !ids.isEmpty, Set(ids).count == ids.count else { return nil }
        var merged: [String: Double] = [:]
        var sum = 0.0
        for id in ids {
            let p = ((first.distribution[id] ?? 0) + (second.distribution[id] ?? 0)) / 2
            guard p.isFinite, p >= 0 else { return nil }
            merged[id] = p
            sum += p
        }
        guard sum > 0 else { return nil }
        if abs(sum - 1) >= 0.02 {
            for id in ids { merged[id] = (merged[id] ?? 0) / sum }
        }
        return merged
    }

    /// Two option orders, averaged. A tie is nil: position bias is not
    /// broken by picking a side. Discovery E6.
    package static func average(
        _ first: DecisionAnswer, _ second: DecisionAnswer, ids: [String]
    ) -> DecisionAnswer? {
        guard let merged = blend(first, second, ids: ids) else { return nil }
        let peak = merged.values.max() ?? 0
        let winners = ids.filter { abs((merged[$0] ?? 0) - peak) < 1e-9 }
        guard winners.count == 1, let choice = winners.first else { return nil }
        let answer = DecisionAnswer(
            choice: choice, distribution: merged, confidence: sharpness(merged))
        return answer.validated(against: ids)
    }
}

/// One question in, one distribution out. Nil is a failed judgement, and a
/// failed judgement never becomes an action.
package protocol DecisionProvider: Sendable {
    func answer(_ question: DecisionQuestion) async -> DecisionAnswer?
}
