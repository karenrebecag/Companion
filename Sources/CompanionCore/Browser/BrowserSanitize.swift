import Foundation

/// Wave 18 (security review M-A). Everything the extension answers with is
/// data from code that runs beside arbitrary web pages, and error codes and
/// notes end up in front of the model. Codes are an allowlist rather than a
/// filter, and free text is short and single-line, so neither can carry a
/// paragraph of instructions.
enum BrowserSanitize {
    static let fallbackCode = "browser_error"
    static let maxMessage = 300
    static let maxDone = 40

    private static let allowedCodes: Set<String> = [
        BridgeCode.staleId, BridgeCode.secureField, BridgeCode.invalidArgs, BridgeCode.timeout,
        BridgeCode.frameTooLarge, BridgeCode.busy, BridgeCode.notConnected, BridgeCode.badFrame,
        BridgeCode.unknownMethod, BridgeCode.badToken, BridgeCode.selectorNoMatch, BridgeCode.selectorHidden,
        BridgeCode.screenRecordingRequired, BridgeCode.screenLocked, BridgeCode.foregroundUnavailable,
        BridgeCode.permissionRequired, BridgeCode.debuggerRevoked, BridgeCode.debuggerUnavailable,
        BridgeCode.unreadablePage, BridgeCode.notTypable,
    ]

    /// A state is a fixed word, never page text: anything else is dropped rather than shown.
    static func states(_ raw: Any?) -> [String] {
        let sent = Set((raw as? [Any] ?? []).compactMap { $0 as? String })
        return BrowserElement.knownStates.filter(sent.contains)
    }

    static func code(_ raw: String) -> String {
        allowedCodes.contains(raw) ? raw : fallbackCode
    }

    static func message(_ raw: String) -> String { text(raw, limit: maxMessage) }

    static func done(_ raw: String) -> String { text(raw, limit: maxDone) }

    /// Line and paragraph separators are not Cc but break lines all the same.
    /// Runs of blanks collapse so a stripped break leaves one space, not a gap.
    /// Format, private-use, unassigned and surrogate scalars are dropped: they
    /// render as nothing (tag block, zero-width) or reorder text (bidi), which
    /// hides instructions from a human reading the same string. The cap counts
    /// scalars because a Character can absorb unbounded combining marks.
    private static func text(_ raw: String, limit: Int) -> String {
        var scalars = String.UnicodeScalarView()
        var lastWasBlank = false
        for scalar in raw.unicodeScalars {
            let blank: Bool
            switch scalar.properties.generalCategory {
            case .format, .privateUse, .unassigned, .surrogate: continue
            case .control, .lineSeparator, .paragraphSeparator: blank = true
            default: blank = scalar == " "
            }
            if blank {
                if !lastWasBlank { scalars.append(" ") }
            } else {
                scalars.append(scalar)
            }
            lastWasBlank = blank
        }
        var capped = String.UnicodeScalarView()
        capped.append(contentsOf: String(scalars).trimmingCharacters(in: .whitespaces).unicodeScalars.prefix(limit))
        return String(capped).trimmingCharacters(in: .whitespaces)
    }
}
