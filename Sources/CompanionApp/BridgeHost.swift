import CompanionCore
import CompanionServices
import CompanionUI
import Foundation

/// Wave 17-2. Owns the local bridge end to end: the listener (one socket,
/// `~/Library/Application Support/Companion/bridge/`), the session (one
/// connection at a time), and the two couplings a headless service cannot
/// have on its own — the approval sheet, through the same `ParentToolGuard`
/// seam `VoiceSession` wires (see `VoiceSession.swift` ~262), and the pin
/// with Karen's own turn ("the voice wins", spec §3).
@MainActor
final class BridgeHost {
    private let listener: BridgeListener
    private let session: BridgeSession
    private var started = false
    /// Review finding (2026-09-28): pausing on every non-idle kind paused
    /// the bridge on `.hover` too — a mouse pass over the island. Tracked so
    /// `resume()` fires exactly once, on the first non-turn kind after a
    /// turn, not on every hover-in/out while at rest.
    private var lastKindWasTurn = false

    init(
        tools: any ParentToolExecuting,
        approvals: Approvals,
        language: @escaping @Sendable () -> AppLanguage,
        accessibility: @escaping @Sendable () -> Bool,
        sessionModel: SessionModel
    ) {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/bridge")
        let parentGuard = ParentToolGuard(
            approvals: approvals,
            onRequest: { request in
                Task { @MainActor in sessionModel.send(.job(.approvalRequested(request))) }
            },
            onRemembered: nil)

        // The listener's `onConnection` needs the session; the session
        // needs the listener's `token`. `BridgeListener.token` already
        // exists on the instance before `start()` (it is only empty until
        // then), so the session side captures `listener` directly; the
        // listener side reads the session through this lock-guarded box,
        // set once, right below, before `apply(enabled:)` can ever start it.
        let sessionBox = SessionBox()
        let listener = BridgeListener(
            directory: directory,
            onConnection: { connection in
                guard let session = sessionBox.value else { return }
                Task.detached { await session.serve(connection) }
            })
        let session = BridgeSession(
            tools: tools,
            guard: parentGuard,
            token: { listener.token },
            language: language,
            accessibility: accessibility,
            onState: { state in
                Task { @MainActor in
                    sessionModel.send(.handsLent(client: Self.client(for: state)))
                }
            },
            onAction: { _ in
                Task { @MainActor in sessionModel.send(.handsActed) }
            })
        sessionBox.value = session
        self.listener = listener
        self.session = session

        // "La voz de Karen gana" (spec §3, "al empezar un hold o enviar un
        // chat"): only `.listening`/`.processing` are her own turn
        // (`SessionKind.isUsersTurn`) — `.hover` is rest, same as `.idle`,
        // and must not pause the bridge on a mouse pass. `resume()` fires
        // once, on the first non-turn kind after a turn, so it re-pins on
        // whatever app she left in front without re-pinning on every hover.
        sessionModel.onKindChange = { [weak self, weak session] kind in
            guard let self, let session else { return }
            let isTurn = kind.isUsersTurn
            defer { self.lastKindWasTurn = isTurn }
            if isTurn {
                Task { await session.pause() }
            } else if self.lastKindWasTurn {
                Task { await session.resume() }
            }
        }
    }

    /// Starts or stops the listener to match the "Lend your hands" setting.
    /// A failure to start is logged, never thrown up to the caller — the
    /// bridge is optional; the rest of the app must keep running without it.
    func apply(enabled: Bool) {
        guard enabled != started else { return }
        if enabled {
            do {
                try listener.start()
                started = true
            } catch {
                Log.bridge("listener: could not start")
            }
        } else {
            listener.stop()
            started = false
        }
    }

    /// "Corte" (spec §3): the island chip and the status menu both land
    /// here.
    func stopHands() {
        Task { await session.stop() }
    }

    /// The chip names the client once the sheet is up or past it
    /// (`.awaitingApproval`, `.open`, `.paused`) — never for a bare `.listed`
    /// (hello received, nothing asked yet) or a closed/idle session.
    private static func client(for state: BridgeState) -> String? {
        switch state {
        case .awaitingApproval, .open, .paused: "Claude Code"
        case .idle, .listed, .closed: nil
        }
    }
}

/// A lock-guarded box, the same shape `BridgeListener` itself uses for its
/// cross-thread state: `onConnection` runs on the accept thread, never
/// `@MainActor`, so it cannot just read a stored property off `BridgeHost`.
/// `nonisolated` throughout: `CompanionApp`'s default isolation is
/// `@MainActor` (Package.swift), which this box must opt out of on purpose.
private final class SessionBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var _value: BridgeSession?

    nonisolated var value: BridgeSession? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
