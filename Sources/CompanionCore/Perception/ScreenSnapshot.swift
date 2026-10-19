import Foundation

// What the verifier and the control chooser read of a window: one bounded
// walk, numbered once, diffable against another read. Values of secure
// fields never leave here, whatever the adapter handed over.

package struct SnapshotElement: Sendable, Equatable {
    /// Numbered in walk order within one read; a diff matches by role and label, never by id.
    package var id: Int
    package var role: String
    /// A text line carries its words here, since AX gives it no label.
    package var label: String
    package var value: String?
    package var secure: Bool
    package var enabled: Bool
    package var focused: Bool

    package init(
        id: Int, role: String, label: String, value: String?, secure: Bool, enabled: Bool, focused: Bool
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.value = secure ? nil : value
        self.secure = secure
        self.enabled = enabled
        self.focused = focused
    }

    fileprivate init(_ node: ScanNode, id: Int) {
        let isText = ScreenRoles.isText(node.role)
        let words = isText ? (node.value ?? node.label) : node.label
        let raw = node.secure || isText ? nil : node.value.map(TurnRedaction.redact)
        self.init(
            id: id, role: node.role, label: TurnRedaction.redact(words),
            value: raw?.isEmpty == true ? nil : raw,
            secure: node.secure, enabled: node.enabled, focused: node.focused)
    }
}

package struct ScreenSnapshot: Sendable, Equatable {
    package var window: String
    package var elements: [SnapshotElement]
    /// The walk was cut by its budget: an element missing here may exist.
    package var partial: Bool

    package init(window: String, elements: [SnapshotElement], partial: Bool) {
        self.window = window
        self.elements = elements
        self.partial = partial
    }

    package init(walk: ScreenWalk) {
        self.init(
            window: walk.window,
            elements: walk.nodes.enumerated().map { SnapshotElement($0.element, id: $0.offset + 1) },
            partial: walk.partial)
    }
}

/// What changed between two reads of one window. An element is the same one
/// across reads when its role and label match; the n-th repeat of a pair
/// matches the n-th repeat.
package struct ScreenDiff: Sendable, Equatable {
    package struct Change: Sendable, Equatable {
        package var before: SnapshotElement
        package var after: SnapshotElement
    }

    package var appeared: [SnapshotElement]
    package var disappeared: [SnapshotElement]
    package var changed: [Change]
    /// Either read was cut, so a missing element is not proof it went away.
    package var partial: Bool

    package var isEmpty: Bool { appeared.isEmpty && disappeared.isEmpty && changed.isEmpty }

    package init(before: ScreenSnapshot, after: ScreenSnapshot) {
        let oldKeys = Self.keys(before.elements)
        let newKeys = Self.keys(after.elements)
        let old = Dictionary(uniqueKeysWithValues: zip(oldKeys, before.elements))
        let new = Dictionary(uniqueKeysWithValues: zip(newKeys, after.elements))
        appeared = zip(newKeys, after.elements).filter { old[$0.0] == nil }.map(\.1)
        disappeared = zip(oldKeys, before.elements).filter { new[$0.0] == nil }.map(\.1)
        changed = zip(newKeys, after.elements).compactMap { key, element in
            guard let previous = old[key],
                  previous.value != element.value || previous.enabled != element.enabled
                    || previous.focused != element.focused
            else { return nil }
            return Change(before: previous, after: element)
        }
        partial = before.partial || after.partial
    }

    private struct Key: Hashable {
        var role: String
        var label: String
        var repeatIndex: Int
    }

    private static func keys(_ elements: [SnapshotElement]) -> [Key] {
        var seen: [Key: Int] = [:]
        return elements.map { element in
            let stem = Key(role: element.role, label: element.label, repeatIndex: 0)
            let index = seen[stem, default: 0]
            seen[stem] = index + 1
            return Key(role: stem.role, label: stem.label, repeatIndex: index)
        }
    }
}

/// Reads again after an action until the window differs from `before`, on a
/// fixed backoff. `read` and `pause` are injected so a test drives both.
package struct ScreenReread: Sendable {
    /// One try per entry, each after its pause: four tries in about 2.9 s.
    package static let backoff: [Duration] = [
        .milliseconds(200), .milliseconds(400), .milliseconds(800), .milliseconds(1500),
    ]

    package struct Outcome: Sendable, Equatable {
        /// The last read that succeeded.
        package var snapshot: ScreenSnapshot?
        package var diff: ScreenDiff?
        package var tries: Int

        /// True when the window changed; a result that is not changed is what
        /// the verifier reports as "nothing moved", after all tries.
        package var changed: Bool { diff.map { !$0.isEmpty } ?? false }
    }

    private let read: @Sendable () async -> ScreenSnapshot?
    private let pause: @Sendable (Duration) async -> Void

    package init(
        read: @escaping @Sendable () async -> ScreenSnapshot?,
        pause: @escaping @Sendable (Duration) async -> Void
    ) {
        self.read = read
        self.pause = pause
    }

    /// Stops at the first try whose diff is not empty.
    package func reread(after before: ScreenSnapshot) async -> Outcome {
        var outcome = Outcome(snapshot: nil, diff: nil, tries: 0)
        for delay in Self.backoff {
            await pause(delay)
            outcome.tries += 1
            guard let snapshot = await read() else { continue }
            let diff = ScreenDiff(before: before, after: snapshot)
            outcome.snapshot = snapshot
            outcome.diff = diff
            if !diff.isEmpty { break }
        }
        return outcome
    }
}
