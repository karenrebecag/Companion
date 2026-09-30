import Foundation

/// Wave 16o-3: what was under the cursor while the user spoke, so "this" and
/// "here" have a referent. Held for the turn in flight only, never persisted.
package struct PointedElement: Sendable, Equatable {
    package var app: String
    /// The Accessibility role (AXButton, AXLink...), as the app reports it.
    package var role: String
    /// Title, value or description, whichever the element has, flattened.
    package var text: String
    /// Seconds since the hold began.
    package var at: TimeInterval

    package init(app: String, role: String, text: String, at: TimeInterval) {
        self.app = app
        self.role = role
        self.text = text
        self.at = at
    }

    func sameElement(as other: PointedElement) -> Bool {
        app == other.app && role == other.role && text == other.text
    }
}

package enum PointerTrace {
    /// The block informs the turn; a cursor wandering for a minute must not
    /// become the turn (ContextBlock.Caps rationale).
    package static let maxItems = 8

    /// One entry per stop of the cursor: a sample every 100 ms over the same
    /// element is one referent, first seen time kept. Elements with no text
    /// carry nothing a model could name.
    package static func collapse(_ samples: [PointedElement]) -> [PointedElement] {
        var out: [PointedElement] = []
        var last: PointedElement?
        for sample in samples where !sample.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defer { last = sample }
            if let last, last.sameElement(as: sample) { continue }
            out.append(sample)
            if out.count == maxItems { break }
        }
        return out
    }
}
