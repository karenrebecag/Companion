import CompanionCore
import Foundation
import Observation

/// What a pick hands back to the field: the new words, the mention that now
/// stands in them, and a file to attach when the pick was one.
package struct MentionPick: Equatable {
    package let draft: String
    package let fallbackDraft: String
    package let mention: Mention?
    package let attach: URL?

    /// A file pick that could not be attached leaves no trace: not the
    /// `@name` in the words and not a mention that promises a file.
    func applied(attach: (URL) -> Bool) -> (draft: String, mention: Mention?) {
        if let url = self.attach, !attach(url) { return (fallbackDraft, nil) }
        return (draft, mention)
    }
}

/// The `@` selector (16m-7). Decides what is listed and what a key or a click
/// does; the view only paints `rows` and forwards keys. Contacts come first,
/// and only if the system permission exists: the dialog is requested the
/// first time she types `@`, never at launch, and never twice.
@Observable
@MainActor
final class MentionSelectorModel {
    enum Row: Equatable, Identifiable {
        case candidate(MentionCandidate)
        /// The default of a contact opened for its channels: the name alone.
        case nameOnly(MentionCandidate)
        case channel(MentionCandidate, MentionChannel)

        var id: String {
            switch self {
            case .candidate(let item): "c|\(item.kind.rawValue)|\(item.id)"
            case .nameOnly(let item): "n|\(item.id)"
            case .channel(let item, let channel): "h|\(item.id)|\(channel.id)"
            }
        }

        var title: String {
            switch self {
            case .candidate(let item), .nameOnly(let item): item.name
            case .channel(_, let channel): channel.value
            }
        }

        var kind: MentionCandidate.Kind {
            switch self {
            case .candidate(let item), .nameOnly(let item), .channel(let item, _): item.kind
            }
        }
    }

    private(set) var rows: [Row] = []
    private(set) var cursor: Int?
    private(set) var isRequestingAccess = false
    /// True when contacts are on and the query is empty: the list says so
    /// instead of leaving her to wonder where the people are.
    private(set) var suggestsTyping = false
    var onPick: (MentionPick) -> Void = { _ in }

    private let sources: MentionSources
    private var draft = ""
    private var active: MentionTrigger.Active?
    private var dismissed: MentionTrigger.Active?
    private var openedContact: MentionCandidate?
    private var epoch = 0
    private var asked = false
    private var work: Task<Void, Never>?
    /// The one system dialog in flight, shared by every refresh that needs
    /// the answer; owned by none of them, so a keystroke never cancels it.
    private var accessTask: Task<Void, Never>?
    /// What the rows on screen answer; a click on rows of another query is ignored.
    private var rowsToken: MentionTrigger.Active?
    /// Once she moves the cursor it stays on its row (by id) when others
    /// arrive; until then it follows the top row.
    private var moved = false

    var isOpen: Bool { !rows.isEmpty }

    init(sources: MentionSources) {
        self.sources = sources
    }

    /// The field changed. Anything that is not an `@` in the middle of a
    /// name closes the list without touching a source.
    func update(draft: String) {
        self.draft = draft
        guard let next = MentionTrigger.active(in: draft) else {
            close()
            dismissed = nil
            return
        }
        if dismissed == next { return }
        dismissed = nil
        if active == next, openedContact == nil { return }
        if active != next { moved = false }
        active = next
        openedContact = nil
        refresh(next)
    }

    /// True when the key was the selector's; false leaves it to the field.
    func press(_ key: MentionKeys.Key) -> Bool {
        guard isOpen else { return false }
        switch MentionKeys.outcome(key, cursor: cursor, count: rows.count, inChannels: openedContact != nil) {
        case .pass: return false
        case .move(let index):
            cursor = index
            moved = true
        case .choose(let index): choose(index)
        case .expand(let index): expand(index)
        case .back:
            if let next = active {
                openedContact = nil
                refresh(next)
            }
        case .close: dismiss()
        }
        return true
    }

    func choose(_ index: Int) {
        guard rows.indices.contains(index), let active, rowsToken == active else { return }
        let row = rows[index]
        let item: MentionCandidate
        var channel: MentionChannel?
        switch row {
        case .candidate(let candidate), .nameOnly(let candidate): item = candidate
        case .channel(let candidate, let picked):
            item = candidate
            channel = picked
        }
        let words = MentionTrigger.inserting(item.name, into: draft, replacing: active)
        guard words != draft else {
            close()
            return
        }
        let attach = item.kind == .file ? URL(fileURLWithPath: item.id) : nil
        close()
        let bare = String(draft.dropLast(active.token.count))
        onPick(MentionPick(draft: words, fallbackDraft: bare, mention: Mention(candidate: item, channel: channel), attach: attach))
    }

    /// The pointer moved onto a row: it takes the cursor, as a menu does.
    func hover(_ index: Int) {
        if rows.indices.contains(index) {
            cursor = index
            moved = true
        }
    }

    func dismiss() {
        dismissed = active
        close()
    }

    // MARK: - private

    private func close() {
        work?.cancel()
        epoch += 1
        rows = []
        cursor = nil
        active = nil
        openedContact = nil
        suggestsTyping = false
        rowsToken = nil
        moved = false
        // A pending dialog is not undone by closing the list; the flag
        // clears when it answers.
    }

    private enum Source { case apps, files, people }

    /// Each source publishes when it arrives: a slow Spotlight never holds
    /// back the apps or the people.
    private func refresh(_ trigger: MentionTrigger.Active) {
        work?.cancel()
        epoch += 1
        let mine = epoch
        let query = trigger.query
        work = Task { [weak self] in
            guard let self else { return }
            var apps: [MentionCandidate] = []
            var files: [MentionCandidate] = []
            var people: [MentionCandidate] = []
            let sources = self.sources
            await withTaskGroup(of: (Source, [MentionCandidate]).self) { group in
                group.addTask { (.apps, await sources.connectedApps()) }
                group.addTask { (.files, await sources.recentFiles()) }
                if sources.contacts != nil { group.addTask { (.people, await self.people(matching: query)) } }
                for await (source, found) in group {
                    guard mine == self.epoch else {
                        group.cancelAll()
                        return
                    }
                    switch source {
                    case .apps: apps = found
                    case .files: files = found
                    case .people:
                        people = found
                        self.suggestsTyping = query.isEmpty && sources.contacts?.access() == .granted
                    }
                    self.publish(MentionRanking.rank(people + apps + files, query: query), for: trigger)
                }
            }
        }
    }

    private func people(matching query: String) async -> [MentionCandidate] {
        guard let contacts = sources.contacts else { return [] }
        await askOnce(contacts)
        guard contacts.access() == .granted else { return [] }
        return await contacts.search(query, limit: MentionRanking.maxRows)
    }

    private func askOnce(_ contacts: any ContactsProviding) async {
        if let accessTask {
            await accessTask.value
            return
        }
        guard !asked, contacts.access() == .notDetermined else { return }
        asked = true
        isRequestingAccess = true
        let task = Task {
            _ = await contacts.requestAccess()
            isRequestingAccess = false
            accessTask = nil
        }
        accessTask = task
        await task.value
    }

    private func publish(_ ranked: [MentionCandidate], for trigger: MentionTrigger.Active) {
        let next = ranked.map(Row.candidate)
        rowsToken = trigger
        guard next != rows else { return }
        let held = moved ? cursor.flatMap { rows.indices.contains($0) ? rows[$0].id : nil } : nil
        rows = next
        if next.isEmpty {
            cursor = nil
        } else if let held, let index = next.firstIndex(where: { $0.id == held }) {
            cursor = index
        } else {
            cursor = 0
            moved = false
        }
    }

    private func expand(_ index: Int) {
        guard rows.indices.contains(index), case .candidate(let item) = rows[index],
              item.kind == .contact, let contacts = sources.contacts else { return }
        work?.cancel()
        epoch += 1
        let mine = epoch
        work = Task { [weak self] in
            let channels = await contacts.channels(ofContact: item.id)
            guard let self, mine == epoch, !channels.isEmpty else { return }
            openedContact = item
            rows = [.nameOnly(item)] + channels.map { .channel(item, $0) }
            cursor = 0
        }
    }
}

/// Words for the selector: VoiceOver hears the name, what kind of source it
/// is, and where it sits in the list.
enum MentionCopy {
    static func accessibility(_ row: MentionSelectorModel.Row, index: Int, count: Int) -> String {
        let kind = Localized.string("mention.kind." + row.kind.rawValue)
        return String(format: Localized.string("mention.row"), row.title, kind, index + 1, count)
    }

    static func hint(canExpand: Bool) -> String {
        Localized.string(canExpand ? "mention.hint.contact" : "mention.hint")
    }
}

/// Incredible's mention picker (docs/research/incredible-isla-componentes.md
/// §3): padding 4, at most 240 tall, radius 11; each item 6 × 8, radius 7,
/// 13 px, hover in the accent at 16 %. Pinned in Mention16m7SelectorTests.
/// Arc's suggestion list: the island menu's panel and rows.
enum MentionMetrics {
    static let padding: CGFloat = IslandArc.Menu.padding
    static let maxHeight: CGFloat = 240
    static let radius: CGFloat = IslandArc.Menu.radius
    static let itemMinHeight: CGFloat = IslandArc.Menu.itemMinHeight
    static let itemPaddingY: CGFloat = Space.x1_5
    static let itemPaddingX: CGFloat = IslandArc.Menu.itemPaddingX
    static let itemRadius: CGFloat = IslandArc.Menu.itemRadius
    static let itemFontSize: CGFloat = 13
    static let highlight = ArcTone.surfaceMuted
}
