import Foundation

/// What the extension did about the native dialogs a page opened in a controlled tab. The message is
/// page text: it is cleaned and capped on decode and only ever shown quoted and labelled.
package struct BrowserDialog: Sendable, Equatable {
    package enum Kind: String, Sendable { case confirm, prompt, beforeunload }
    package enum Answer: String, Sendable { case no, `default` }

    package var kind: Kind
    package var answer: Answer
    package var destructive: Bool
    package var message: String

    package init(kind: Kind, answer: Answer, destructive: Bool, message: String) {
        self.kind = kind
        self.answer = answer
        self.destructive = destructive
        self.message = message
    }
}

package struct BrowserDialogReport: Sendable, Equatable {
    package static let maxEntries = 5

    package var dialogs: [BrowserDialog]
    /// Dialogs answered after the listed ones; a page can open them faster than anyone reads.
    package var more: Int

    package init(dialogs: [BrowserDialog], more: Int) {
        self.dialogs = dialogs
        self.more = more
    }

    /// Absent, empty or entirely invalid means no report; an entry the host cannot name is dropped.
    static func decode(_ raw: Any?, more: Any?) -> BrowserDialogReport? {
        guard let list = raw as? [[String: Any]] else { return nil }
        let dialogs = list.compactMap(entry).prefix(maxEntries)
        guard !dialogs.isEmpty else { return nil }
        let count = (more as? NSNumber)?.intValue ?? 0
        return BrowserDialogReport(dialogs: Array(dialogs), more: max(0, count))
    }

    private static func entry(_ raw: [String: Any]) -> BrowserDialog? {
        guard let kind = (raw["kind"] as? String).flatMap(BrowserDialog.Kind.init(rawValue:)),
              let answer = (raw["answer"] as? String).flatMap(BrowserDialog.Answer.init(rawValue:))
        else { return nil }
        return BrowserDialog(
            kind: kind, answer: answer, destructive: raw["destructive"] as? Bool ?? false,
            message: BrowserSanitize.dialogMessage(raw["message"] as? String ?? ""))
    }
}
