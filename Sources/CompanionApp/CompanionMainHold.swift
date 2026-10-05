import CompanionCore
import CompanionServices
import CompanionUI
import Foundation

extension AppDelegate {
    func makeHoldObserver() -> HoldObserver {
        let accessibility = AccessibilityPermission()
        return HoldObserver(surface: SystemHoldSurface(trusted: { accessibility.isTrusted() }),
                            now: { Int(ProcessInfo.processInfo.systemUptime * 1000) })
    }

    /// The observer follows the session's hold, not key events, so a hold ended by the
    /// island's pointer, a stop or an error also stops the looking.
    func followHolds(_ session: SessionModel) {
        guard let companion = screenOverlays?.holdCompanion else { return }
        let sync = HoldObservationSync(
            observer: makeHoldObserver(), companion: companion,
            words: { HoldObservationSync.words(in: session.projection.partial) })
        holdSync = sync
        _ = sync.follow(session)
    }
}
