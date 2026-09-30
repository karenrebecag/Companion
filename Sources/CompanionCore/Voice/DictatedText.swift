import Foundation

/// The words a hold pasted, carried to the island's result card (16m-4). A
/// type of its own, not a String, so that interpolating anything that holds
/// it (a projection, an event, an island state) can never print the user's
/// document into a log line: the words are readable only through `value`.
public struct DictatedText: Sendable, Equatable, ExpressibleByStringLiteral,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(stringLiteral value: String) {
        self.value = value
    }

    /// Redacted on purpose: `"\(projection)"` and any log line built from a
    /// value that holds the words print this, never the user's document.
    public var description: String { "<dictated text: \(value.count) chars>" }
    public var debugDescription: String { description }

    /// `dump` and `Mirror` read stored properties, not descriptions.
    public var customMirror: Mirror { Mirror(self, children: []) }
}
