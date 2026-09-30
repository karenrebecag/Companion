import Foundation

/// What an action leaves on the island once done: a check per thing the app
/// can PROVE it did (16h-3, spec 16h criterion 3). The lines are the same
/// effect lines the voice may claim (`ParentToolCopy.status`), so the receipt
/// never says more than the app is allowed to say aloud. The invariant is
/// "the receipt is a subset of the proven lines": everything on it has proof,
/// not everything with proof has to be on it (the cap keeps the latest).
package struct ReceiptLine: Sendable, Equatable {
    package let text: String
    /// A read-back confirmed it. Without one the app did it and says so, but
    /// does not claim to have checked.
    package let verified: Bool

    package init(text: String, verified: Bool) {
        self.text = text
        self.verified = verified
    }
}

package struct ActionReceipt: Sendable, Equatable {
    /// A receipt is a glance, not a log: the latest few.
    package static let maxLines = 4
    package static let maxLineLength = 120

    package let entries: [ReceiptLine]
    package var lines: [String] { entries.map(\.text) }

    package init?(lines: [String]) {
        self.init(entries: lines.map { ReceiptLine(text: $0, verified: false) })
    }

    package init?(entries: [ReceiptLine]) {
        var kept: [ReceiptLine] = []
        for raw in entries {
            let text = Self.bounded(raw.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty else { continue }
            // The same line proven later is the same line, now checked.
            if let index = kept.firstIndex(where: { $0.text == text }) {
                kept[index] = ReceiptLine(text: text, verified: kept[index].verified || raw.verified)
            } else {
                kept.append(ReceiptLine(text: text, verified: raw.verified))
            }
        }
        guard !kept.isEmpty else { return nil }
        self.entries = Array(kept.suffix(Self.maxLines))
    }

    /// The newest lines win when two receipts of one turn join.
    package func merging(_ other: ActionReceipt) -> ActionReceipt {
        ActionReceipt(entries: entries + other.entries) ?? self
    }

    /// A status line names a target (an app, a URL): one line, capped, with
    /// the cut visible.
    private static func bounded(_ text: String) -> String {
        // Hygiene first: invisible scalars must not spend the cap or travel.
        let flat = TextHygiene.oneLine(text).trimmingCharacters(in: .whitespaces)
        guard flat.unicodeScalars.count > maxLineLength else { return flat }
        return String(String.UnicodeScalarView(flat.unicodeScalars.prefix(maxLineLength))) + "…"
    }
}

/// The rule that keeps "done" honest: a change is a receipt line only when it
/// succeeded and, for typing, a read-back showed the text in the field.
package enum ReceiptProof {
    package static func entry(tool: String, outcome: ParentToolOutcome, language: AppLanguage) -> ReceiptLine? {
        guard let hands = ParentTool(rawValue: tool), hands.changesSomething, outcome.ok else { return nil }
        // Typing is the one change with a read-back (`TypedProof`); an
        // unread typing is an attempt, and an attempt has no check.
        if hands == .typeText, !outcome.verified { return nil }
        // A URL shows where it went, not what it carried: no query, no
        // fragment, no credentials.
        var shown = outcome
        shown.target = display(target: outcome.target)
        return ReceiptLine(
            text: TextHygiene.oneLine(ParentToolCopy.status(tool, shown, language)),
            verified: hands == .typeText && outcome.verified)
    }

    static func display(target: String) -> String {
        guard !target.contains(where: \.isWhitespace), var parts = URLComponents(string: target),
              let scheme = parts.scheme?.lowercased(), scheme.count > 1
        else { return target }
        if ["http", "https"].contains(scheme), let host = parts.host {
            return host + (parts.path == "/" ? "" : parts.path)
        }
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.string ?? target
    }

    package static func line(tool: String, outcome: ParentToolOutcome, language: AppLanguage) -> String? {
        entry(tool: tool, outcome: outcome, language: language)?.text
    }
}
