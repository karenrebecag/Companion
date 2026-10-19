import Foundation

/// Within one round of tool calls, an identical read is answered from the
/// first result instead of running again: two identical `find_places` calls
/// drew two identical cards (QA 606). Only reads are memoised, and any call
/// that may change the screen or a file clears the memo, so a read after a
/// click still sees what the click did.
package struct ToolCallMemo: Sendable {
    package enum Step: Equatable, Sendable {
        case run
        /// The index of the earlier call whose answer this one repeats.
        case reuse(Int)
    }

    private var firstCall: [String: Int] = [:]

    package init() {}

    package mutating func step(name: String, arguments: String, index: Int) -> Step {
        guard ActionBand.reads.contains(name) else {
            firstCall = [:]
            return .run
        }
        let key = name + "\u{0}" + arguments
        if let first = firstCall[key] { return .reuse(first) }
        firstCall[key] = index
        return .run
    }
}
