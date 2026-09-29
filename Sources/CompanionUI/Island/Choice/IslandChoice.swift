import CompanionCore
import SwiftUI

// Wave 16m-6: the question with options (Incredible's `answer-card`). What
// the card measures, what the keys do and how a pick is read off the
// transcript live here, in code a test can call; the views are in
// IslandChoiceCard.swift.

/// `answer-card` (docs/research/incredible-isla-componentes.md §5): 340-440
/// wide, padding 18 × 20, gap 14. The option tile is the one 16l measured.
public nonisolated enum IslandChoiceMetrics {
    public static let minWidth: CGFloat = 340
    public static let maxWidth: CGFloat = 440
    public static let paddingY: CGFloat = 18
    public static let paddingX: CGFloat = 20
    public static let gap: CGFloat = 14
    /// Own value (not measured): an option that can no longer be picked.
    public static let unavailableAlpha = 0.45
    /// Own value: composer, reply and a two-line question take ~330 of the
    /// 592 pt the shape can grow to, so past this the list scrolls inside the
    /// card instead of pushing the field off the canvas.
    public static let listMaxHeight: CGFloat = 260

    /// 340-440 is a clamp on what the words ask for, capped by the room.
    static func width(available: CGFloat, ideal: CGFloat) -> CGFloat {
        min(available, min(max(ideal, minWidth), maxWidth))
    }

    /// A card asked for its ideal width (no proposal) takes the widest one.
    static let unbounded: CGFloat = 10_000
}

/// The keys of an open question: arrows walk the options, Return picks the
/// one under the cursor, 1-9 pick by position. The card only sees keys while
/// it holds the keyboard, so the digits never collide with the composer.
nonisolated enum IslandChoiceKeys {
    enum Key: Equatable { case up, down, enter, digit(Int) }
    enum Named: Equatable { case up, down, enter, other }
    enum Outcome: Equatable { case none, focus(Int), choose(Int) }

    /// Only what the card understands: a bare arrow, Return, or one ASCII
    /// digit 1-9. Anything with a modifier, and every other script's digits,
    /// stays out ("٣", "½" and "３" are digits to Swift, not shortcuts).
    static func key(_ named: Named, characters: String, hasModifiers: Bool) -> Key? {
        guard !hasModifiers else { return nil }
        switch named {
        case .up: return .up
        case .down: return .down
        case .enter: return .enter
        case .other:
            let scalars = Array(characters.unicodeScalars)
            guard scalars.count == 1, (0x31 ... 0x39).contains(scalars[0].value) else { return nil }
            return .digit(Int(scalars[0].value) - 0x30)
        }
    }

    static func outcome(for key: Key, focused: Int?, count: Int) -> Outcome {
        guard count > 0 else { return .none }
        switch key {
        case .down:
            return .focus(focused.map { ($0 + 1) % count } ?? 0)
        case .up:
            return .focus(focused.map { ($0 + count - 1) % count } ?? count - 1)
        case .enter:
            guard let focused, (0 ..< count).contains(focused) else { return .none }
            return .choose(focused)
        case .digit(let number):
            return (1 ... count).contains(number) ? .choose(number - 1) : .none
        }
    }
}

enum IslandChoiceCopy {
    /// "Rápido, 2 of 3", then whether it is the pick or no longer available.
    static func optionAccessibility(
        index: Int, count: Int, label: String, resolution: ChoiceBlock.Resolution
    ) -> String {
        let position = String(format: Localized.string("island.choice.option"), label, index + 1, count)
        switch resolution {
        case .open: return position
        case .chosen(let picked) where picked == index:
            return position + ", " + Localized.string("island.choice.selected")
        case .chosen, .passed:
            return position + ", " + Localized.string("island.choice.unavailable")
        }
    }
}

/// What the island reads off the chat.
enum IslandChoice {
    /// Focus belongs to one card: once another reply replaces it, the old
    /// card's focus counts for nothing (a `@FocusState` does not report its
    /// own view leaving, and a stuck flag would hold the island open).
    static func isFocused(focusedID: UUID?, liveID: UUID?) -> Bool {
        guard let focusedID else { return false }
        return focusedID == liveID
    }

    /// One question per turn: the first fence that parses.
    static func block(in message: ChatMessage) -> ChoiceBlock? {
        // Cheap guard: this runs for the latest reply on every render.
        guard message.role == .assistant, !message.isStatus,
              message.text.contains(CompanionBlocks.choiceLanguage)
        else { return nil }
        for block in AnswerBlocks.blocks(from: message.text) {
            if case .choice(let choice) = block { return choice }
        }
        return nil
    }

    /// The user's next message answers the question: the label she sent
    /// marks the pick, anything else closes it without a mark. A message
    /// that ran into a failed turn answers nothing (she can ask again), and a
    /// question read back from disk has no live turn behind it.
    static func resolution(
        of block: ChoiceBlock, messageID: UUID, in messages: [ChatMessage]
    ) -> ChoiceBlock.Resolution {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return .open }
        var cursor = index + 1
        while cursor < messages.count {
            let message = messages[cursor]
            cursor += 1
            guard message.role == .user, !message.isStatus else { continue }
            if cursor < messages.count, messages[cursor].isFailure { continue }
            let resolved = block.resolution(reply: message.text)
            // A turn with only attachments still moved on.
            return resolved == .open ? .passed : resolved
        }
        return messages[index].restored ? .passed : .open
    }
}

extension IslandChoice {
    enum Tile: Equatable { case idle, cursor, picked, unavailable }
    struct Pending: Equatable {
        let index: Int
        let label: String
    }
}

/// What the card remembers between a click and the message landing. Pure, so
/// the rules (one send, released when the label is gone from the queue and
/// the thread) are tested without a view.
struct IslandChoiceState: Equatable {
    var pending: IslandChoice.Pending?

    /// The thread decides once it has the answer; until then only a pick that
    /// `choose` accepted and that still waits in the queue counts.
    func effective(resolution: ChoiceBlock.Resolution, queued: [String]) -> ChoiceBlock.Resolution {
        if resolution != .open { return resolution }
        guard let pending, queued.contains(pending.label) else { return .open }
        return .chosen(pending.index)
    }

    static func tile(index: Int, resolution: ChoiceBlock.Resolution, cursor: Int?) -> IslandChoice.Tile {
        switch resolution {
        case .open: cursor == index ? .cursor : .idle
        case .chosen(let picked): picked == index ? .picked : .unavailable
        case .passed: .unavailable
        }
    }

    /// True when the label was sent. `resolution` and `queued` are read live
    /// by the caller at click time, not from the last render: a digit right
    /// after a click must see the click.
    @discardableResult
    mutating func pick(
        _ index: Int, block: ChoiceBlock, resolution: ChoiceBlock.Resolution, queued: [String],
        send: (String) -> Bool
    ) -> Bool {
        guard effective(resolution: resolution, queued: queued) == .open,
              block.options.indices.contains(index)
        else { return false }
        let label = block.options[index].label
        guard send(label) else { return false }
        pending = IslandChoice.Pending(index: index, label: label)
        return true
    }
}
