import Foundation

/// One thing the host saw while the key was held, as Incredible's hold observations
/// (referencia local): where the user went, what they clicked, selected, copied or typed.
package struct HoldObservation: Sendable, Equatable {
    package enum Event: Sendable, Equatable {
        case surfaceChanged(app: String?, title: String?, url: String?)
        case clicked(element: String)
        case typed(String)
        case hovered
        case selectedText(String)
        case selectedFiles([String])
        case copied(String)
        case dialogOpened(title: String)
    }

    package let atMs: Int
    package let event: Event

    package init(atMs: Int, event: Event) {
        self.atMs = atMs
        self.event = event
    }
}

/// Everything one hold has observed so far. The whole list travels each time, as in
/// Incredible, so an item keeps its id from one batch to the next.
package struct HoldObservationBatch: Sendable, Equatable {
    package let generation: Int
    package let events: [HoldObservation]

    package init(generation: Int, events: [HoldObservation]) {
        self.generation = generation
        self.events = events
    }
}

/// The port the app's hold drives: one generation at a time, started and stopped in order.
package protocol HoldObserving: AnyObject, Sendable {
    func start(generation: Int, onBatch: @escaping @Sendable (HoldObservationBatch) -> Void) async
    func stop() async
}

/// What the orb shows for one observation. `detail` and `siteURL` carry what the user
/// touched, whole: they are for the view only, never for logs.
package struct HoldItem: Sendable, Equatable, Identifiable {
    package enum Kind: String, Sendable, Equatable, CaseIterable {
        case file, selectedText, copied, window, tab, button, cell, typed, dialog

        /// Only what the user hands over stacks by the orb; the rest only flashes on it.
        package var stacks: Bool { self == .file || self == .selectedText || self == .copied }
    }

    package let id: String
    package let kind: Kind
    package let label: String
    package var detail: String?
    package var appName: String?
    package var siteURL: String?
    package let tMs: Int

    package init(id: String, kind: Kind, label: String, detail: String? = nil, appName: String? = nil,
                 siteURL: String? = nil, tMs: Int) {
        self.id = id
        self.kind = kind
        self.label = label
        self.detail = detail
        self.appName = appName
        self.siteURL = siteURL
        self.tMs = tMs
    }

    /// How it reads inside the transcript: one line, quoted when it is the user's own text.
    /// A label must not close its own brackets, or a page title could write into the transcript.
    package var woven: String {
        let line = HoldCollect.oneLine(label)
            .replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        return kind == .selectedText || kind == .copied ? "\u{201C}\(line)\u{201D}" : line
    }
}

package enum HoldCollect {
    /// Longest label before it is cut with an ellipsis.
    package static let labelLimit = 42
    /// A click followed this soon by a window or tab is what opened it: only the window stays.
    package static let clickOpensWithinMs = 800

    package static func items(from observations: [HoldObservation]) -> [HoldItem] {
        var items: [HoldItem] = []
        var lastApp: String?
        for (index, observation) in observations.enumerated() {
            items += item(observation, index: index, previousApp: lastApp).filter { !$0.label.isEmpty }
            if case .surfaceChanged(let app, _, _) = observation.event { lastApp = app }
        }
        return items.enumerated().filter { index, item in
            guard item.kind == .button || item.kind == .cell else { return true }
            return !items[(index + 1)...].contains {
                ($0.kind == .window || $0.kind == .tab)
                    && $0.tMs >= item.tMs && $0.tMs - item.tMs <= clickOpensWithinMs
            }
        }.map(\.element)
    }

    /// Ids name the moment and the position, never what was touched.
    private static func item(_ observation: HoldObservation, index: Int, previousApp: String?) -> [HoldItem] {
        let t = observation.atMs
        let id = "\(t):\(index)"
        switch observation.event {
        case .surfaceChanged(let app, let rawTitle, let rawURL):
            let title = present(rawTitle)
            if let url = present(rawURL) {
                let label = title ?? (webHost(url).map(withoutWWW) ?? lastComponent(url))
                return [HoldItem(id: "tab:\(id)", kind: .tab, label: label, detail: url, appName: app,
                                 siteURL: url, tMs: t)]
            }
            if let app, app == previousApp { return [] }
            let label = if let app, let title { "\(app) \u{2014} \(title)" } else { title ?? app ?? "" }
            return [HoldItem(id: "window:\(id)", kind: .window, label: label, appName: app, tMs: t)]
        case .clicked(let element):
            let cell = element.range(of: #"^cell\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            return [HoldItem(id: "click:\(id)", kind: cell ? .cell : .button, label: oneLine(element), tMs: t)]
        case .typed(let text):
            return [HoldItem(id: "typed:\(id)", kind: .typed, label: short(text), detail: text, tMs: t)]
        case .hovered:
            return []
        case .selectedText(let text):
            return [HoldItem(id: "selected:\(id)", kind: .selectedText, label: short(text), detail: text, tMs: t)]
        case .selectedFiles(let paths):
            return paths.enumerated().map { position, path in
                HoldItem(id: "file:\(id).\(position)", kind: .file, label: lastComponent(path), detail: path, tMs: t)
            }
        case .copied(let text):
            return [HoldItem(id: "copied:\(id)", kind: .copied, label: short(text), detail: text, tMs: t)]
        case .dialogOpened(let title):
            return [HoldItem(id: "dialog:\(id)", kind: .dialog, label: oneLine(title), tMs: t)]
        }
    }

    private static func present(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func short(_ text: String) -> String {
        let line = oneLine(text)
        return line.count > labelLimit ? String(line.prefix(labelLimit)) + "\u{2026}" : line
    }

    static func lastComponent(_ path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }

    private static func withoutWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The host of a web address, or nil when it is not one. A bare "name:" that is not a
    /// port (mailto:, javascript:) is a scheme of its own, not a host.
    package static func webHost(_ address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasScheme = trimmed.range(of: #"^[a-z][a-z0-9+.-]*://"#, options: [.regularExpression, .caseInsensitive])
            != nil
        let otherScheme = trimmed.range(of: #"^[a-z][a-z0-9+.-]*:(?!//)(?!\d)"#,
                                        options: [.regularExpression, .caseInsensitive]) != nil
        guard hasScheme || !otherScheme,
              let url = URL(string: hasScheme ? trimmed : "https://" + trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return host
    }

    /// Records a handed-over item once at the word index where it arrived. Nothing else is
    /// woven: what was typed, clicked or visited only flashes on the orb.
    package static func mark(_ marks: [Int: [String]], _ item: HoldItem, atWord index: Int) -> [Int: [String]] {
        guard item.kind.stacks else { return marks }
        let at = max(0, index)
        let current = marks[at] ?? []
        guard !current.contains(item.woven) else { return marks }
        var next = marks
        next[at] = current + [item.woven]
        return next
    }

    /// The transcript with each mark in brackets before the word it arrived at; marks past
    /// the last word follow it, in index order.
    package static func weave(_ text: String, marks: [Int: [String]]) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, !marks.isEmpty else { return text }
        let bracketed = { (index: Int) in (marks[index] ?? []).map { "[\($0)]" } }
        var out: [String] = []
        for (index, word) in words.enumerated() {
            out += bracketed(index) + [word]
        }
        for index in marks.keys.filter({ $0 >= words.count }).sorted() {
            out += bracketed(index)
        }
        return out.joined(separator: " ")
    }
}

package struct HoldStackEntry: Sendable, Equatable {
    package let item: HoldItem
    /// When it joined the stack, in whole milliseconds so the cutoffs are exact at any clock.
    package let atMs: Int

    package init(item: HoldItem, atMs: Int) {
        self.item = item
        self.atMs = atMs
    }
}

/// The few items stacked over the orb: newest first, each leaving on its own clock.
package enum HoldStack {
    package static let limit = 3
    package static let leaveAfterMs = 1400
    package static let dropAfterMs = 1700

    package static func push(_ stack: [HoldStackEntry], _ item: HoldItem, atMs now: Int) -> [HoldStackEntry] {
        if stack.first?.item.id == item.id { return stack }
        let rest = stack.filter { $0.item.id != item.id }
        return Array(([HoldStackEntry(item: item, atMs: now)] + rest).prefix(limit))
    }

    package static func leaving(_ entry: HoldStackEntry, nowMs: Int) -> Bool {
        nowMs - entry.atMs >= leaveAfterMs
    }

    package static func prune(_ stack: [HoldStackEntry], nowMs: Int) -> [HoldStackEntry] {
        stack.filter { nowMs - $0.atMs < dropAfterMs }
    }

    /// The orb swallows while any item is on its way out.
    package static func gulping(_ stack: [HoldStackEntry], nowMs: Int) -> Bool {
        stack.contains { leaving($0, nowMs: nowMs) && nowMs - $0.atMs < dropAfterMs }
    }
}
