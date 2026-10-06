import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

@Suite("ClearHistory")
struct ClearHistoryUITests {
    @Test @MainActor func confirmLeavesAnEmptyThreadAndCancelDeletesNothing() async throws {
        let store = ScriptedHistoryStore()
        let model = ChatViewModel(
            chat: FakeChatProvider(),
            secrets: TestSecretStore([.openAI: "sk-test"]),
            store: store,
            config: .default)
        await model.appendUser("hello")
        let id = model.conversationId
        expect(!model.messages.isEmpty, "the thread has the chat")
        expectEq(store.clears, 0, "seeding does not clear")

        try model.applyHistoryClear(.cancel)
        expectEq(store.clears, 0, "cancel does not call the delete")
        expectEq(model.conversationId, id, "cancel keeps the thread")
        expectEq(model.messages.count, 1, "cancel keeps the messages")
        expect(try store.load(id) != nil, "cancel keeps the stored chat")

        try model.applyHistoryClear(.confirm)
        expectEq(store.clears, 1, "confirm deletes once")
        expect(model.messages.isEmpty, "the live thread is empty")
        expect(model.recents.isEmpty, "recents are empty")
        expect(model.streaming.isEmpty, "nothing is still streaming")
        expect(model.conversationId != id, "the deleted id is not the live thread")
        expect(try store.load(id) == nil, "the stored chat is gone")
        expect(try store.list().isEmpty, "the store is empty")

        await model.appendUser("after")
        expectEq(model.messages.count, 1, "a later message is a new thread")
        expect(try store.load(id) == nil, "the deleted chat does not come back")
        expectEq(try store.list().count, 1, "only the new thread is stored")
    }

    @Test @MainActor func failedClearLeavesTheThread() async throws {
        let store = ScriptedHistoryStore()
        store.clearError = PersistenceError.io
        let model = ChatViewModel(
            chat: FakeChatProvider(),
            secrets: TestSecretStore([.openAI: "sk-test"]),
            store: store,
            config: .default)
        await model.appendUser("hello")
        let id = model.conversationId
        do {
            try model.applyHistoryClear(.confirm)
            expect(false, "a failed clear throws")
        } catch let error as PersistenceError {
            expectEq(error, .io, "a failed clear throws io")
        } catch {
            expect(false, "a failed clear throws PersistenceError")
        }
        expectEq(model.conversationId, id, "a failed clear keeps the thread")
        expectEq(model.messages.count, 1, "a failed clear keeps the messages")
        expect(try store.load(id) != nil, "a failed clear keeps the file")
    }

    @Test @MainActor func clearRowButtonPresentsTheDialog() {
        let history = HistoryClearModel()
        let page = SettingsSystemPage(
            chat: nil, updates: nil, storageLabel: "",
            history: history)
        expect(!history.presented, "the dialog starts closed")
        page.pressClearRow()
        expect(history.presented, "the row's button opens the confirmation")
        expect(!history.busy, "opening deletes nothing")
    }

    @Test @MainActor func confirmIsDisabledWithoutAChat() async {
        let history = HistoryClearModel()
        history.present()
        let chat = ChatViewModel(
            chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
            store: ScriptedHistoryStore(), config: .default)
        expect(!history.canConfirm(chat: nil), "no chat, nothing to clear")
        expect(history.canConfirm(chat: chat), "a chat can be cleared")
        await history.confirm(chat: nil)
        expect(history.presented, "a confirm with no chat leaves the dialog up")
        expect(!history.busy, "and starts nothing")
        expectEq(history.errorText, nil, "and says nothing went wrong")
    }

    @Test @MainActor func failedClearShowsTheFallbackError() async {
        let store = ScriptedHistoryStore()
        store.clearError = PersistenceError.io
        let chat = ChatViewModel(
            chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
            store: store, config: .default)
        await chat.appendUser("hello")
        let history = HistoryClearModel()
        await Localized.scoped(to: .en) {
            history.present()
            await history.confirm(chat: chat)
            expectEq(
                history.errorText, "That didn't work. Try again in a moment.",
                "a failed clear says so, inline")
        }
        expect(history.presented, "a failed clear stays open")
        expect(!history.busy, "and can be tried again")
        expectEq(chat.messages.count, 1, "the thread is untouched")

        store.clearError = nil
        await history.confirm(chat: chat)
        expect(!history.presented, "a clear that works closes the dialog")
        expectEq(history.errorText, nil, "and drops the old error")
        expect(chat.messages.isEmpty, "and the thread is empty")
    }

    @Test @MainActor func closeAndBackdropIgnoredWhileClearing() {
        let chat = ChatViewModel(
            chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
            store: ScriptedHistoryStore(), config: .default)
        let history = HistoryClearModel()
        history.present()
        expect(history.begin(chat: chat), "confirm arms the delete")
        expect(history.busy, "it is running")
        history.close()
        expect(history.presented, "the X and the backdrop do nothing while it runs")
        expect(!history.begin(chat: chat), "a second press does not start another delete")
        history.finish(cleared: false)
        expect(!history.busy, "a failure frees the buttons")
        history.close()
        expect(!history.presented, "and then close works")
        expectEq(history.errorText, nil, "closing drops the error")
    }

    @Test @MainActor func clearHistoryRowLivesInSystemDataSection() async {
        let panels = SettingsInventory.panels.filter { $0.titleKey == "settings.history.row" }
        expectEq(panels.map(\.tab), [.system], "the row is a System panel, not a Privacy one")
        let entry = SettingsInventory.searchEntries.first { $0.id == "settings-clear-history" }
        expectEq(entry?.page, "system", "the search lands on System")
        await Localized.scoped(to: .en) {
            expectEq(Localized.string("settings.history.label"), "Data", "under a card called Data")
        }
    }

    @Test @MainActor func settingsSearchFindsClearHistory() async {
        await Localized.scoped(to: .en) {
            let entries = SettingsInventory.searchEntries
            let entry = entries.first { $0.id == "settings-clear-history" }
            expectEq(entry?.title, "Clear chat history", "the entry carries the row's title")
            for word in [
                "clear", "history", "delete", "erase", "conversations", "chats", "reset", "wipe", "forget",
            ] {
                let found = SettingsSearch.match(word, in: entries).map(\.id)
                expect(found.contains("settings-clear-history"), "'\(word)' finds the row, got \(found)")
            }
        }
    }

    @Test func searchKeywordsMatchButRankBelowTitles() {
        let entries = [
            SettingsSearch.Entry(
                id: "kw", page: "x", title: "Chats", subtitle: "", keywords: ["wipe"]),
            SettingsSearch.Entry(id: "title", page: "x", title: "Wipe", subtitle: ""),
        ]
        expectEq(SettingsSearch.match("wipe", in: entries).map(\.id), ["title", "kw"], "title first")
        expect(SettingsSearch.match("forget", in: entries).isEmpty, "a word nobody carries finds nothing")
    }

    @Test @MainActor func historyCopyMatchesIncrediblesWording() async {
        let en: [String: String] = [
            "settings.history.label": "Data",
            "settings.history.row": "Clear chat history",
            "settings.history.row.subtitle":
                "Erases your chats with Companion, and the tasks started in them, from this computer. Connected apps, dictation and your files are not touched.",
            "settings.history.action": "Clear…",
            "settings.history.title": "Clear your chat history?",
            "settings.history.blurb":
                "This erases your chats with Companion, and the tasks started in them, from this computer. Connected apps, dictation and anything saved to your files stay as they are. There's no undo.",
            "settings.history.cancel": "Cancel",
            "settings.history.confirm": "Clear chat history",
            "settings.history.clearing": "Clearing…",
            "settings.history.error": "That didn't work. Try again in a moment.",
            "settings.history.a11y": "Clear your chat history",
        ]
        let es: [String: String] = [
            "settings.history.label": "Datos",
            "settings.history.row": "Borrar historial de chats",
            "settings.history.row.subtitle":
                "Borra de este equipo tus chats con Companion y las tareas iniciadas en ellos. No toca las apps conectadas, el dictado ni tus archivos.",
            "settings.history.action": "Borrar…",
            "settings.history.title": "¿Borrar tu historial de chats?",
            "settings.history.blurb":
                "Esto borra de este equipo tus chats con Companion y las tareas iniciadas en ellos. Las apps conectadas, el dictado y todo lo guardado en tus archivos se quedan como están. No se puede deshacer.",
            "settings.history.cancel": "Cancelar",
            "settings.history.confirm": "Borrar historial de chats",
            "settings.history.clearing": "Borrando…",
            "settings.history.error": "Eso no funcionó. Inténtalo de nuevo en un momento.",
            "settings.history.a11y": "Borrar tu historial de chats",
        ]
        await Localized.scoped(to: .en) {
            for (key, text) in en { expectEq(Localized.string(key), text, "en \(key)") }
        }
        await Localized.scoped(to: .es) {
            for (key, text) in es { expectEq(Localized.string(key), text, "es \(key)") }
        }
    }

    @Test func dialogIsAsWideAsIncrediblesAlert() {
        expectEq(HistoryClearDialog.maxWidth, 440, "the alert dialog is 440 wide")
    }
}

private final class ScriptedHistoryStore: ConversationStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: ConversationRecord] = [:]
    var clearError: Error?
    private(set) var clears = 0

    func list() throws -> [ConversationMeta] {
        lock.withLock {
            records.values.map {
                ConversationMeta(id: $0.id, title: $0.title, updatedAt: $0.updatedAt)
            }
        }
    }

    func save(_ record: ConversationRecord) throws {
        lock.withLock { records[record.id] = record }
    }

    func load(_ id: String) throws -> ConversationRecord? {
        lock.withLock { records[id] }
    }

    func clearHistory() throws {
        try lock.withLock {
            clears += 1
            if let clearError { throw clearError }
            records.removeAll()
        }
    }
}
