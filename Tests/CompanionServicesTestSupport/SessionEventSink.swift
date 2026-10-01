import CompanionCore

/// The one thing the voice harness asks of a session model: take an event.
/// A seam so this target never imports CompanionUI; the integration tests
/// make `SessionModel` conform (SessionModel+EventSink.swift).
@MainActor
package protocol SessionEventSink: AnyObject, Sendable {
    @discardableResult
    func send(_ event: SessionEvent) -> [SessionEffect]
}
