import CompanionCore
import Foundation

/// A job's end waiting for its gap, with when it started waiting.
struct ParkedAnnouncement: Sendable {
    let announcement: JobAnnouncement
    let parkedAt: TimeInterval
}

/// A pending approval and when the voice said its question, if it did.
struct ApprovalSighting: Sendable {
    let requestId: String
    var announcedAt: TimeInterval?
}

/// A job's end, said by the voice (16h-2). Split out of VoiceSessionPumps:
/// this file owns the notice's whole life — parked, said in a gap, cut,
/// dropped — and the one lock that keeps two notices from talking at once.
/// Not `private`, but still actor-isolated by the actor itself.
extension VoiceSession {
    func jobAnnounce(_ announcement: JobAnnouncement) async {
        if machine.snapshot.pipeline == .realtime {
            pendingAnnouncements.append(announcement.instruction)
            await flushAnnouncements()
            return
        }
        guard !voiceClosed else { return drop(1, reason: "voice-closed") }
        // The job ran in the background while the voice went on; its end
        // waits for a gap instead of talking over the user or cutting a
        // reply. A hold's own rest is such a gap.
        parkedAnnouncements.append(ParkedAnnouncement(announcement: announcement, parkedAt: now()))
        await flushAnnouncements()
        publishAnnouncing()
    }

    /// Code review 2026-09-25 (HIGH-B): classic has no model behind the
    /// synthesizer, so the instruction is never spoken; the classic runtime
    /// says our line and a summary turn through `TurnMouth`. One at a time:
    /// the next waits until this one's audio ended or something of ours
    /// stopped it (`cutAnnouncement`). Not when the task ends: the task
    /// ends once the text is queued, and `begin()` of the next notice would
    /// cut the audio still playing.
    func flushParkedAnnouncement() {
        let fresh = parkedAnnouncements.filter { now() - $0.parkedAt <= AnnouncementGap.maxAge }
        if fresh.count < parkedAnnouncements.count {
            drop(parkedAnnouncements.count - fresh.count, reason: "stale")
            parkedAnnouncements = fresh
        }
        defer { publishAnnouncing() }
        guard !parkedAnnouncements.isEmpty, machine.snapshot.pipeline != .realtime,
              AnnouncementGap.isOpen(machine.snapshot), !announcementUnlogged
        else { return }
        let next = parkedAnnouncements.removeFirst()
        announceTask?.cancel()
        announcementUnlogged = true
        let classic = classic
        announceTask = Task { await classic.announce(next.announcement) }
    }

    /// A press over the announcement, or any stop of ours: what already
    /// sounded is its `said=`, and the lock is free again.
    func cutAnnouncement() async {
        announceTask?.cancel()
        announceTask = nil
        // Already logged means its audio already ended: nothing to silence.
        guard announcementUnlogged else { return }
        await logAnnouncementSaid()
        await synthesizer.stop()
    }

    /// 15f-3: the specialist's outcome is spoken outside any turn, so the
    /// turn's own `said=` never saw it. Written once the audio is done (or
    /// cut), from what the synthesizer actually said; the flag is read now,
    /// not at the start — the job may outlive the setting it began under.
    func logAnnouncementSaid() async {
        guard announcementUnlogged else { return }
        announcementUnlogged = false
        publishAnnouncing()
        guard configProvider.current.debugTranscripts,
              let said = await synthesizer.spokenSoFar() else { return }
        classic.transcripts?.said(said)
    }

    /// The one sounding goes quiet and the waiting ones are dropped: a stop,
    /// a voice she closed, a failure.
    func silenceAnnouncements(reason: String) async {
        await cutAnnouncement()
        if !parkedAnnouncements.isEmpty {
            drop(parkedAnnouncements.count, reason: reason)
            parkedAnnouncements = []
        }
        publishAnnouncing()
    }

    private func drop(_ count: Int, reason: String) {
        droppedAnnouncements += count
        Log.app("voice: job notice dropped reason=\(reason) count=\(count)")
    }

    /// The reducer learns when a notice starts or stops sounding or waiting,
    /// so a Stop at rest can silence it (S2).
    func publishAnnouncing() {
        let now = announcementUnlogged || !parkedAnnouncements.isEmpty
        guard now != publishedAnnouncing else { return }
        publishedAnnouncing = now
        eventBox.yield(.announcing(now))
    }
}
