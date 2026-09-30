import Foundation

package struct SiteCandidate: Sendable, Equatable {
    package var name: String
    package var url: String

    package init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

package struct FileCandidate: Sendable, Equatable {
    package var path: String

    package init(path: String) {
        self.path = path
    }
}

/// What N0 is willing to let a model choose. An app that is not installed,
/// a host the user did not say, and a string that is not in the utterance
/// are not options.
package enum CandidateSets {
    package static let volumeOps: [DecisionOption] = [
        DecisionOption(id: "up", detail: "louder"),
        DecisionOption(id: "down", detail: "quieter"),
        DecisionOption(id: "mute", detail: "mute"),
        DecisionOption(id: "unmute", detail: "unmute"),
        DecisionOption(id: "max", detail: "maximum"),
    ]

    package static let shortcuts: [DecisionOption] = [
        DecisionOption(id: "enter", detail: "press return"),
        DecisionOption(id: "escape", detail: "press escape"),
        DecisionOption(id: "copy", detail: "copy"),
        DecisionOption(id: "paste", detail: "paste"),
        DecisionOption(id: "undo", detail: "undo"),
        DecisionOption(id: "redo", detail: "redo"),
        DecisionOption(id: "select_all", detail: "select all"),
        DecisionOption(id: "save", detail: "save"),
        DecisionOption(id: "find", detail: "find in the page"),
        DecisionOption(id: "new_tab", detail: "new browser tab"),
        DecisionOption(id: "close_tab_or_window", detail: "close this tab or window"),
        DecisionOption(id: "reopen_closed_tab", detail: "reopen the last closed tab"),
        DecisionOption(id: "quit_app", detail: "quit the application"),
        DecisionOption(id: "reload", detail: "reload the page"),
        DecisionOption(id: "browser_back", detail: "go back"),
        DecisionOption(id: "next_tab", detail: "next tab"),
        DecisionOption(id: "previous_tab", detail: "previous tab"),
        DecisionOption(id: "fullscreen", detail: "full screen"),
        DecisionOption(id: "zoom_in", detail: "zoom in"),
        DecisionOption(id: "zoom_out", detail: "zoom out"),
        DecisionOption(id: "send_message", detail: "send the message"),
    ]

    package static let scrollDirections: [DecisionOption] = [
        DecisionOption(id: "up", detail: "up"),
        DecisionOption(id: "down", detail: "down"),
        DecisionOption(id: "top", detail: "jump to the top"),
        DecisionOption(id: "bottom", detail: "jump to the bottom"),
    ]

    package static let scrollAmounts: [DecisionOption] = [
        DecisionOption(id: "line", detail: "a little"),
        DecisionOption(id: "page", detail: "a page"),
        DecisionOption(id: "lots", detail: "a lot"),
    ]

    package static let mediaOps: [DecisionOption] = [
        DecisionOption(id: "play", detail: "play"),
        DecisionOption(id: "pause", detail: "pause"),
        DecisionOption(id: "next", detail: "next"),
        DecisionOption(id: "previous", detail: "previous"),
    ]

    package static let systemOps: [DecisionOption] = [
        DecisionOption(id: "lock", detail: "lock the screen"),
        DecisionOption(id: "sleep_display", detail: "sleep the display"),
        DecisionOption(id: "show_desktop", detail: "show the desktop"),
        DecisionOption(id: "toggle_dark_mode", detail: "toggle dark mode"),
        DecisionOption(id: "empty_trash", detail: "empty the trash"),
        DecisionOption(id: "screenshot", detail: "take a screenshot"),
    ]

    /// Generic hosts only. A personal URL does not belong in a closed list
    /// the model can pick without the user having said it.
    package static let allowlist: [SiteCandidate] = [
        SiteCandidate(name: "youtube", url: "https://www.youtube.com"),
        SiteCandidate(name: "google", url: "https://www.google.com"),
        SiteCandidate(name: "github", url: "https://www.github.com"),
        SiteCandidate(name: "wikipedia", url: "https://www.wikipedia.org"),
        SiteCandidate(name: "stackoverflow", url: "https://www.stackoverflow.com"),
        SiteCandidate(name: "amazon", url: "https://www.amazon.com"),
        SiteCandidate(name: "twitter", url: "https://www.twitter.com"),
    ]

    package static func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    package static func normalized(_ text: String) -> String {
        tokens(text).joined(separator: " ")
    }

    /// At most `limit` installed apps the utterance actually names. A 4B
    /// chooses badly past a handful of options (discovery E5).
    package static func appCandidates(
        _ utterance: String, apps: [String], limit: Int = 5
    ) -> [DecisionOption] {
        rankedApps(utterance, apps: apps)
            .prefix(max(0, limit))
            .map { DecisionOption(id: $0.name) }
    }

    package static func siteCandidates(
        _ utterance: String, sites: [SiteCandidate]
    ) -> [DecisionOption] {
        let words = Set(tokens(utterance))
        return sites.compactMap { site in
            let name = fold(site.name)
            guard name.count >= 3, words.contains(name) else { return nil }
            return DecisionOption(id: site.name, detail: site.url)
        }
    }

    package static func fileCandidates(
        _ utterance: String, files: [FileCandidate]
    ) -> [DecisionOption] {
        ranked(files, score: { fileScore(utterance, $0.path) }, id: \.path)
            ?? cueFallback(files, utterance: utterance, cues: fileCues, id: \.path)
    }

    package static func skillCandidates(
        _ utterance: String, skills: [String]
    ) -> [DecisionOption] {
        let rows = skills.filter { $0.count >= 2 }
        return ranked(rows, score: { skillScore(utterance, $0) }, id: { $0 })
            ?? cueFallback(rows, utterance: utterance, cues: skillCues, id: { $0 })
    }

    /// Spans cut out of the utterance. The model picks one; nothing here
    /// writes a word the user did not say.
    package static func textSpans(_ utterance: String) -> [DecisionOption] {
        var found: [String] = []
        func add(_ raw: String?) {
            guard let raw else { return }
            let text = clean(raw)
            guard !text.isEmpty, fold(utterance).contains(fold(text)) else { return }
            guard !found.contains(where: { fold($0) == fold(text) }) else { return }
            found.append(text)
        }
        add(quoted(utterance))
        add(afterMarker(utterance))
        if let typed = peel(utterance, verbs: typeVerbs) {
            add(stripSubmit(typed))
            add(typed)
        }
        if let query = peel(utterance, verbs: searchVerbs) {
            add(query)
        }
        add(stripSubmit(utterance))
        add(utterance)
        return found.prefix(6).enumerated().map {
            DecisionOption(id: "c\($0.offset)", detail: $0.element)
        }
    }

    /// The user named something N0 can already run — an app, a site, or a
    /// closed-set word (volume, media, system, scroll). A `none` answer on
    /// top of that is the doubtful none that goes to arbitration.
    package static func stronglyDirected(
        _ utterance: String, apps: [String], sites: [SiteCandidate]
    ) -> Bool {
        if let best = rankedApps(utterance, apps: apps).first, best.score >= 0.9 {
            return true
        }
        if !siteCandidates(utterance, sites: sites).isEmpty { return true }
        // Floor 5 keeps "play" an exact token, so it cannot fire on "display".
        return hasCue(utterance, closedSetCues, prefixFloor: 5)
    }

    /// Closed-set vocabulary the parent runs without an app or site named.
    private static let closedSetCues = [
        "volumen", "volume", "mute", "silencia", "papelera", "trash", "pausa", "pause",
        "reproduce", "play", "scroll", "desplaza", "captura", "screenshot",
    ]

    // MARK: - ranking

    private struct Ranked {
        var name: String
        var score: Double
    }

    private static func rankedApps(_ utterance: String, apps: [String]) -> [Ranked] {
        var seen: Set<String> = []
        var ranked: [Ranked] = []
        for raw in apps {
            let name: String
            do { name = try ParentToolPolicy.appName(raw) } catch { continue }
            guard seen.insert(fold(name)).inserted else { continue }
            let score = appScore(utterance, name)
            guard score >= 0.8 else { continue }
            ranked.append(Ranked(name: name, score: score))
        }
        ranked.sort { $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score }
        return ranked
    }

    private static func appScore(_ utterance: String, _ name: String) -> Double {
        // Two-letter names match crumbs ("to", "el"). A real app name is longer.
        if containsPhrase(utterance, name), tokens(name).allSatisfy({ $0.count >= 3 }) {
            return 0.96
        }
        let parts = tokens(name)
        if parts.count > 1, parts.allSatisfy({ $0.count >= 3 && containsPhrase(utterance, $0) }) {
            return 0.9
        }
        var best = 0.0
        let foldedName = fold(name)
        for token in tokens(utterance) where token.count >= 4 {
            best = max(best, prefixScore(token, foldedName))
        }
        return best
    }

    private static func fileScore(_ utterance: String, _ path: String) -> Double {
        let stem = stem(path)
        guard stem.count >= 3 else { return 0 }
        if containsPhrase(utterance, stem) { return 0.96 }
        return tokens(utterance).map { prefixScore($0, stem) }.max() ?? 0
    }

    private static func skillScore(_ utterance: String, _ name: String) -> Double {
        let folded = fold(name)
        if containsPhrase(utterance, folded) { return 0.96 }
        return tokens(utterance).map { prefixScore($0, folded) }.max() ?? 0
    }

    private struct Scored<T> {
        var row: T
        var score: Double
    }

    private static func ranked<T>(
        _ rows: [T], score: (T) -> Double, id: (T) -> String
    ) -> [DecisionOption]? {
        var hits: [Scored<T>] = []
        for row in rows {
            let value = score(row)
            if value >= 0.8 { hits.append(Scored(row: row, score: value)) }
        }
        hits.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return id(lhs.row) < id(rhs.row)
        }
        guard !hits.isEmpty else { return nil }
        return hits.prefix(5).map { hit in
            let name = id(hit.row)
            return DecisionOption(id: name, detail: name)
        }
    }

    /// One unnamed file, and a word that says the user wants a file, is the
    /// menu. Two unnamed files would be a guess, which is generating.
    private static func cueFallback<T>(
        _ rows: [T], utterance: String, cues: [String], id: (T) -> String
    ) -> [DecisionOption] {
        guard rows.count == 1, hasCue(utterance, cues) else { return [] }
        return rows.map { DecisionOption(id: id($0), detail: id($0)) }
    }

    private static let fileCues = [
        "archivo", "file", "document", "documento", "foto", "photo", "video",
        "spreadsheet", "presentacion", "presentation", "resume", "config", "nota",
    ]
    private static let skillCues = ["skill", "skills", "habilidad", "habilidades"]

    private static func hasCue(_ utterance: String, _ cues: [String], prefixFloor: Int = 4) -> Bool {
        tokens(utterance).contains { token in
            cues.contains { cue in token == cue || (cue.count >= prefixFloor && token.hasPrefix(cue)) }
        }
    }

    private static func stem(_ path: String) -> String {
        let base = (path as NSString).lastPathComponent
        return fold((base as NSString).deletingPathExtension)
    }

    private static func prefixScore(_ a: String, _ b: String) -> Double {
        let n = zip(a, b).prefix(while: { $0.0 == $0.1 }).count
        guard n >= 5 else { return 0 }
        let ratio = Double(n) / Double(max(a.count, b.count))
        guard ratio >= 0.6 else { return 0 }
        return 0.7 + 0.2 * ratio
    }

    static func tokens(_ text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func containsPhrase(_ utterance: String, _ phrase: String) -> Bool {
        let words = tokens(phrase)
        guard !words.isEmpty else { return false }
        let hay = " " + tokens(utterance).joined(separator: " ") + " "
        return hay.contains(" " + words.joined(separator: " ") + " ")
    }
}

// MARK: - spans

private let typeVerbs = [
    "type", "write", "dictate", "enter", "escribe", "escribir", "teclea", "teclear", "dicta", "dictar",
]
private let searchVerbs = [
    "search for", "look up", "look for", "where are", "where is", "donde estan", "donde esta",
    "search", "google", "find", "busca", "buscar", "halla", "hallar", "encuentra",
]
private let politeness = ["por favor", "please", "can you", "could you", "puedes", "puede"]
private let markers = ["llamado ", "llamada ", "called ", "titled ", "named ", "que dice ", "saying "]
private let submitTails: Set<String> = ["send", "submit", "enter", "envia", "enviar", "enviarlo"]
private let joiners: Set<String> = ["and", "y", "then", "luego"]

private func peel(_ utterance: String, verbs: [String]) -> String? {
    var rest = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in politeness {
        if let next = consume(rest, prefix) {
            rest = next
            break
        }
    }
    for verb in verbs.sorted(by: { CandidateSets.fold($0).count > CandidateSets.fold($1).count }) {
        if let next = consume(rest, verb) { return next }
    }
    return nil
}

/// Diacritic folding is one character to one character for Latin text, so
/// the folded prefix length is the cut in the original. A cut that leaves
/// the utterance is dropped by `textSpans`.
private func consume(_ text: String, _ prefix: String) -> String? {
    let foldedText = CandidateSets.fold(text)
    let foldedPrefix = CandidateSets.fold(prefix).trimmingCharacters(in: .whitespaces)
    guard !foldedPrefix.isEmpty, foldedText.hasPrefix(foldedPrefix) else { return nil }
    guard text.count >= foldedPrefix.count else { return nil }
    let index = text.index(text.startIndex, offsetBy: foldedPrefix.count)
    let tail = text[index...]
    if foldedPrefix.last?.isLetter == true, let first = tail.first, first.isLetter {
        return nil
    }
    let trimmed = tail.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
}

private func stripSubmit(_ text: String) -> String {
    var words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard let last = words.last, submitTails.contains(CandidateSets.fold(last)) else { return text }
    words.removeLast()
    if let joiner = words.last, joiners.contains(CandidateSets.fold(joiner)) {
        words.removeLast()
    }
    let peeled = words.joined(separator: " ")
    return peeled.isEmpty ? text : peeled
}

private func clean(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = text.last, ".,?!;".contains(last) {
        text.removeLast()
        text = text.trimmingCharacters(in: .whitespaces)
    }
    return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func quoted(_ text: String) -> String? {
    let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("«", "»")]
    for (open, close) in pairs {
        guard let start = text.firstIndex(of: open) else { continue }
        let from = text.index(after: start)
        guard let end = text[from...].firstIndex(of: close), end > from else { continue }
        let inner = text[from..<end].trimmingCharacters(in: .whitespaces)
        if !inner.isEmpty { return inner }
    }
    return nil
}

private func afterMarker(_ text: String) -> String? {
    let folded = CandidateSets.fold(text)
    for marker in markers {
        guard let range = folded.range(of: CandidateSets.fold(marker)) else { continue }
        let offset = folded.distance(from: folded.startIndex, to: range.upperBound)
        guard offset <= text.count else { continue }
        let tail = text[text.index(text.startIndex, offsetBy: offset)...]
            .trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { return String(tail) }
    }
    return nil
}
