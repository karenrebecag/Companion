import Foundation

/// Wave 15f-1: the hold brain sometimes writes the `delegate` call as plain
/// content — `{"goal":…,"context":…}`, alone or after a short sentence —
/// and the mouth read it aloud while nothing was delegated. This scanner
/// sits between the model's text and the mouth.
///
/// The rule for braces: a `{` whose first non-blank character is `"` opens a
/// JSON candidate, and a candidate is never speakable — it becomes a
/// `Handoff` when it closes as an object with a non-empty `goal`, and is
/// dropped otherwise (no goal, invalid, unclosed at the end, or past
/// `maxObjectChars`). Any other `{` is prose ("llaves { }"), so a brace in a
/// sentence is still said. A `{` right after an uncommitted `{` takes over
/// as the candidate start, so a doubled brace never lets the object through.
package struct HandoffInText: Sendable, Equatable {
    /// Past this, an open candidate is not a tool call the model meant to
    /// write; it stops being stored (memory stays bounded) but keeps being
    /// counted and swallowed until it closes.
    package static let maxObjectChars = 2000

    package struct Step: Sendable, Equatable {
        package var speakable = ""
        package var handoff: Handoff?
        package var handoffChars = 0
        package var droppedChars = 0

        package init() {}
    }

    private var held = ""
    private var heldCount = 0
    private var depth = 0
    private var committed = false
    private var inString = false
    private var escaped = false
    private var overflow = false

    package init() {}

    package mutating func feed(_ piece: String) -> Step {
        var step = Step()
        for char in piece {
            if depth == 0 {
                if char == "{" {
                    open()
                } else {
                    step.speakable.append(char)
                }
                continue
            }
            hold(char)
            if committed {
                scanCandidate(char, into: &step)
            } else if char == "\"" {
                committed = true
                inString = true
            } else if char == "{" {
                // Code review 2026-09-25 (LOW-1): in "{{"goal"…}}" the inner
                // brace is the object; the outer one is only prose.
                step.speakable += String(held.dropLast())
                open()
            } else if !char.isWhitespace || heldCount > Self.maxObjectChars {
                // Not JSON after all: the brace and what followed are prose.
                step.speakable += held
                reset()
            }
        }
        return step
    }

    /// End of the stream: a candidate still open was cut off and is dropped;
    /// a lone brace with only blanks after it was prose.
    package mutating func finish() -> Step {
        var step = Step()
        guard depth > 0 else { return step }
        if committed {
            step.droppedChars = heldCount
        } else {
            step.speakable = held
        }
        reset()
        return step
    }

    private mutating func open() {
        reset()
        depth = 1
        held = "{"
        heldCount = 1
    }

    private mutating func hold(_ char: Character) {
        heldCount += 1
        guard !overflow else { return }
        if heldCount > Self.maxObjectChars, committed {
            overflow = true
            held = ""
        } else {
            held.append(char)
        }
    }

    private mutating func scanCandidate(_ char: Character, into step: inout Step) {
        if inString {
            if escaped {
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "\"" {
                inString = false
            }
            return
        }
        switch char {
        case "\"": inString = true
        case "{": depth += 1
        case "}":
            depth -= 1
            if depth == 0 { close(into: &step) }
        default: break
        }
    }

    private mutating func close(into step: inout Step) {
        let found = overflow
            ? nil : Handoff.parse(toolName: "delegate", arguments: held)
        if let found, step.handoff == nil {
            step.handoff = found
            step.handoffChars = heldCount
        } else {
            step.droppedChars += heldCount
        }
        reset()
    }

    private mutating func reset() {
        held = ""
        heldCount = 0
        depth = 0
        committed = false
        inString = false
        escaped = false
        overflow = false
    }
}
