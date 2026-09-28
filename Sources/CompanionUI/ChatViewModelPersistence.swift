import CompanionCore
import Foundation

/// Disk persistence, conversation restore, and idle rollover. Split out of
/// ChatViewModel when it crossed the 400-line gate.
extension ChatViewModel {
    func loadMostRecent() throws {
        recents = try store.list()
        guard let meta = recents.first, let record = try store.load(meta.id) else {
            conversationId = UUID().uuidString
            messages = []
            lastActivity = nil
            return
        }
        restore(record)
        rolloverIfDue()
    }

    func restore(_ record: ConversationRecord) {
        conversationId = record.id
        lastActivity = record.updatedAt
        messages = Self.messages(of: record)
    }

    static func messages(of record: ConversationRecord) -> [ChatMessage] {
        record.messages.map { item in
            if item.role == "status" {
                return ChatMessage(isStatus: true, text: item.text)
            }
            return ChatMessage(role: TurnRole(rawValue: item.role), text: item.text)
        }
    }

    func persist() {
        let stored = messages.map { message -> ConversationMessage in
            let role = message.isStatus ? "status" : (message.role?.rawValue ?? "assistant")
            return ConversationMessage(role: role, text: message.text)
        }
        guard !stored.isEmpty else { return }
        let title = messages.first { $0.role == .user }
            .map { String($0.text.prefix(48)) }
            ?? Localized.string("thread.untitled")
        let timestamp = now()
        lastActivity = timestamp
        let record = ConversationRecord(
            id: conversationId, title: title, updatedAt: timestamp, messages: stored)
        do {
            try store.save(record)
            recents = try store.list()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }

    /// What the policy needs to know right now: the thread's own clock plus
    /// the guards nothing here must strand in another conversation.
    func activity() -> ConversationActivity {
        ConversationActivity(
            lastActivity: lastActivity,
            turnInFlight: busy,
            jobRunning: session.projection.job != nil,
            approvalsPending: !session.projection.approvalQueue.isEmpty,
            liveRealtime: session.projection.pipeline == .realtime
                && (session.projection.voice == .live || session.projection.voice == .muted))
    }

    func rolloverIfDue() {
        guard ConversationRollover.shouldRollover(activity(), now: now()) else { return }
        rollOver()
    }

    /// Wave 15a: past the idle window with nothing open, the stale thread is
    /// archived (it is already on disk, untouched) and a blank one starts.
    /// Never calls `persist()` — that would re-stamp the old thread's
    /// `updatedAt` and it would never expire.
    private func rollOver() {
        conversationId = UUID().uuidString
        messages = []
        streaming = ""
        lastActivity = nil
        log("conversation: rolled over after idle window")
    }

    /// `applicationDidBecomeActive` (§10 of the spec): a voice turn already
    /// under way decides this for itself once it reaches `historyTurns()` or
    /// `appendUser`, so this entry point only admits a resting chrome.
    public func rolloverIfIdle() {
        guard session.projection.kind == .idle || session.projection.kind == .hover else { return }
        rolloverIfDue()
    }
}
