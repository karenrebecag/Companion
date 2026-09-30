import Foundation

/// What the model keeps of a specialist's report, which is not what the reader
/// keeps.
///
/// The thread and the model's history used to be the same array, and a full
/// report entering as an `assistant` turn did three things at once: it ate the
/// window, it taught the model that IT writes reports (against a prompt asking
/// for two to four sentences), and it let the model re-read a result it never
/// produced. Measured on a real session: one report was 23% of the entire
/// history.
///
/// The budget is the low end of the 1,000–2,000 token range Anthropic
/// documents for what a subagent should hand back — roughly 4,000 characters.
/// Deliberately not the prototype's 160, which bought agility at the price of
/// never being able to answer a follow-up without delegating again.
package enum ConversationMemory: Sendable {
    package static let defaultBudget = 4000

    package static func recall(
        _ text: String, budget: Int = defaultBudget
    ) -> String {
        let text = withoutCards(text)
        guard text.count > budget else { return text }

        let cut = MarkdownSplitter.reportCut(text)
        var kept = MarkdownSplitter.plainText(cut.summary)
        // The summary is normally a line or two, but nothing guarantees it:
        // one unbroken wall of prose is a single block, and without this the
        // budget was advice rather than a limit.
        if kept.count > budget { kept = String(kept.prefix(budget)) }
        // The summary alone is usually a line or two; spend the rest of the
        // budget on detail so a follow-up question still has something to
        // stand on.
        for part in cut.detail {
            let next = MarkdownSplitter.plainText([part])
            if kept.count + next.count + 1 > budget { break }
            kept += "\n" + next
        }
        if kept.isEmpty { kept = String(text.prefix(budget)) }
        return kept + "\n\n" + note
    }

    /// What replaces the turns that fall out of the history window.
    ///
    /// The window used to just truncate: whatever did not fit vanished, and
    /// the model started forgetting things the user distinctly remembers
    /// saying. The documented alternative is compaction — distilling the
    /// contents so the agent continues with minimal degradation — because
    /// context is a finite resource, not a bucket that empties from the top.
    ///
    /// HACK: the distillation is local, not modelled. A faithful summary needs
    /// a model call; this keeps the opening request and a count of what
    /// happened after it, which is the part that gives the rest its meaning.
    /// Upgrade trigger: the first time someone has to repeat something this
    /// note should have carried, pay for the call.
    package static func compaction(
        of dropped: [Turn], language: AppLanguage = .en
    ) -> Turn? {
        guard !dropped.isEmpty else { return nil }
        let opening = dropped.first { $0.role == .user }?.content ?? ""
        let exchanges = dropped.filter { $0.role == .user }.count
        let text: String
        switch language {
        case .en:
            text = "[Summary of \(exchanges) earlier exchanges. It opened "
                + "with: «\(opening)». The detail is on screen, not here.]"
        case .es:
            text = "[Resumen de \(exchanges) intercambios anteriores. Empezó "
                + "con: «\(opening)». El detalle está en pantalla, no aquí.]"
        }
        // A context note, not a turn anybody took: attributing it to the user
        // or the assistant would put words in a mouth.
        return Turn(role: .system, content: text)
    }

    /// Card payloads hydrate the interface, not the model's context — the
    /// same separation the Apps SDK draws when it forwards `_meta` to the
    /// component and keeps it out of the transcript. Ours used to depend on
    /// length: a long report dropped its cards and a short one shipped the raw
    /// JSON into memory. Same data, two destinations, nobody's decision.
    ///
    /// A marker stays behind on purpose. Deleting the card in silence would
    /// leave the model believing it showed nothing, and it would offer again
    /// what is already on screen.
    static func withoutCards(_ text: String) -> String {
        var out: [String] = []
        var insideCard = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if insideCard {
                if trimmed.hasPrefix("```") { insideCard = false }
                continue
            }
            guard trimmed.hasPrefix("```") else {
                out.append(line)
                continue
            }
            let language = trimmed.dropFirst(3)
                .trimmingCharacters(in: .whitespaces)
            // Only companion: fences are interface. An ordinary code fence is
            // content the model needs.
            guard language.hasPrefix("companion:") else {
                out.append(line)
                continue
            }
            insideCard = true
            out.append(marker(for: language))
        }
        return out.joined(separator: "\n")
    }

    private static func marker(for language: String) -> String {
        switch language {
        case CompanionBlocks.locationsLanguage:
            return "[tarjeta de mapa mostrada en pantalla]"
        case CompanionBlocks.galleryLanguage:
            return "[tarjeta de galería mostrada en pantalla]"
        case CompanionBlocks.statsLanguage:
            return "[tarjeta de cifras mostrada en pantalla]"
        case CompanionBlocks.tableLanguage:
            return "[tabla mostrada en pantalla]"
        case CompanionBlocks.chartLanguage:
            return "[gráfica mostrada en pantalla]"
        default:
            return "[tarjeta mostrada en pantalla]"
        }
    }

    /// Never a silent cut: without this the model reads the fragment as the
    /// whole answer and starts reasoning from a report that was never finished.
    private static let note =
        "[Resumen. El informe completo está en pantalla; pídelo si necesitas "
        + "el detalle.]"
}
