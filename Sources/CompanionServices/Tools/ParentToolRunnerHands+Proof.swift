import CompanionCore
import Foundation

/// Setting the selected text can succeed while the app ignores it, so a
/// typed count means nothing until the field is read back. A second try by
/// paste is only safe when the field is exactly what it was before typing:
/// a field that changed but does not match (text longer than the clipped
/// read, a caret mid-document, an app that rewrites what it gets) may well
/// hold the text already, and pasting again would type it twice. Those end
/// "not read back", the same line the voice path upgrades from a later
/// `read_focused`.
extension HandsAct {
    /// A slow app may not have updated the value by the time AX returns.
    static let readBackSettle: UInt64 = 150_000_000
    static let notLanded = "the text did not reach the field; look at the screen before retrying"

    private enum ReadBack {
        case landed, unchanged, unknown
    }

    func verifyLanding(
        text: String, target: FocusedField, count: Int, route: InjectionRoute,
        baseline: String?, before: Int?
    ) async -> ParentToolOutcome {
        guard let baseline, let before else { return unverified(count: count, route: route, before: before) }
        var seen = readBack(text: text, baseline: baseline, before: before)
        if seen != .landed {
            do {
                try await Task.sleep(nanoseconds: Self.readBackSettle)
            } catch {
                // Cancelled: the second read still runs, it costs one AX call.
            }
            seen = readBack(text: text, baseline: baseline, before: before)
        }
        switch seen {
        case .landed: return verifiedOutcome(count: count, route: route, before: before)
        case .unknown: return unverified(count: count, route: route, before: before)
        case .unchanged: break
        }
        // A paste route that left the field untouched would only fail again.
        guard route == .ax else { return fail("not_landed", Self.notLanded) }
        // The read-back waited; Command-V goes to whatever has focus now, so
        // the target is checked again before the paste, not only before the
        // first attempt.
        guard !moved else { return fail("target_changed", Self.appMoved) }
        switch await hands.injector.paste(text, into: target) {
        case .failed(.fieldGone):
            return fail("target_changed", Self.appMoved)
        case .failed(.needsAccessibility):
            return fail("needs_accessibility", BridgeMessages.needsAccessibility)
        case .failed(.refused):
            return fail("not_landed", Self.notLanded)
        case .injected(_, let pasteRoute):
            switch readBack(text: text, baseline: baseline, before: before) {
            case .landed: return verifiedOutcome(count: count, route: pasteRoute, before: before)
            case .unknown: return unverified(count: count, route: pasteRoute, before: before)
            case .unchanged: return fail("not_landed", Self.notLanded)
            }
        }
    }

    /// `unchanged` is the only proof that nothing landed: the value is
    /// byte for byte the baseline. Anything else that does not match, an
    /// unreadable field included, is `unknown`.
    private func readBack(text: String, baseline: String, before: Int) -> ReadBack {
        guard let value = hands.reader.read(pid: pid) else { return .unknown }
        if TypedProof.verifies(typed: text, read: FocusedText.clip(value), before: before) { return .landed }
        return value == baseline ? .unchanged : .unknown
    }

    private func unverified(count: Int, route: InjectionRoute, before: Int?) -> ParentToolOutcome {
        Log.app("hands: type_text typed chars=\(count) via=\(route.rawValue) pid=\(pid) verified=false")
        return ParentToolOutcome(
            ok: true, output: "typed \(count) chars" + TypedProof.unverifiedNote,
            tool: tool.rawValue, fieldPID: pid, typedBefore: before)
    }

    private func verifiedOutcome(count: Int, route: InjectionRoute, before: Int) -> ParentToolOutcome {
        Log.app("hands: type_text typed chars=\(count) via=\(route.rawValue) pid=\(pid) verified=true")
        return ParentToolOutcome(
            ok: true, output: "typed \(count) chars" + TypedProof.verifiedNote,
            tool: tool.rawValue, verified: true, fieldPID: pid, typedBefore: before)
    }
}
