import ApplicationServices
import CompanionCore
import Foundation

/// Keeps at most one handle alive, for the pid the hands are acting on.
/// An observer per window leaks run-loop sources (AltTab learned it the
/// hard way), so a new target releases the old one before it is created.
final class SingleObserverSlot<Handle: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private var current: (pid: Int32, handle: Handle)?

    func handle(for pid: Int32, make: () -> Handle?, release: (Handle) -> Void) -> Handle? {
        lock.withLock {
            if let current, current.pid == pid { return current.handle }
            if let current {
                release(current.handle)
                self.current = nil
            }
            guard let made = make() else { return nil }
            current = (pid, made)
            return made
        }
    }
}

/// The hands' eyes after an action (Accessibility notifications), the way
/// the references do it: one `AXObserver` per process on the application
/// element, its source on the main run loop in common modes. Notifications
/// say that something moved, never that the action worked, so the summary
/// built from them never claims success or failure.
package final class AXChangeWatcher: AXChangeWatching, @unchecked Sendable {
    private let trust: @Sendable () -> Bool
    private let slot = SingleObserverSlot<AXObservation>()

    package init(trust: @escaping @Sendable () -> Bool) {
        self.trust = trust
    }

    package func begin(pid: Int32) -> any AXChangeWatch {
        guard trust(),
              let observation = slot.handle(
                for: pid, make: { AXObservation(pid: pid) }, release: { $0.close() })
        else {
            Log.app("hands: change observer unavailable pid=\(pid)")
            return UnwatchedChange()
        }
        return ObservedChange(observation: observation)
    }
}

private struct UnwatchedChange: AXChangeWatch {
    func settle(_ timing: SettleTiming) async -> ChangeReport {
        ChangeReport(changes: [], watching: false)
    }

    func cancel() {}
}

/// One hand call's view of an observation: it reads only what arrived after
/// its own mark, and while it is open the observer is allowed to read the
/// app's attributes (outside a call the notifications are ignored).
private final class ObservedChange: AXChangeWatch, @unchecked Sendable {
    private let observation: AXObservation
    private let mark: Int
    private let lock = NSLock()
    private var finished = false

    init(observation: AXObservation) {
        self.observation = observation
        mark = observation.attach()
    }

    func settle(_ timing: SettleTiming) async -> ChangeReport {
        await ChangeSettler.wait(
            timing,
            now: { ProcessInfo.processInfo.systemUptime },
            sleep: { seconds in
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    // A cancelled turn ends the wait: the loop checks the flag.
                }
            },
            lastEvent: { [observation, mark] in observation.lastEventTime(since: mark) })
        let changes = observation.changes(since: mark)
        let watching = !observation.isClosed
        finish()
        Log.app("hands: observed changes=\(changes.count) watching=\(watching) pid=\(observation.pid)")
        // A closed observer (the target moved to another app mid-wait) saw
        // nothing: that is "could not watch", never "nothing changed".
        return ChangeReport(changes: changes, watching: watching)
    }

    func cancel() { finish() }

    private func finish() {
        let first = lock.withLock {
            defer { finished = true }
            return !finished
        }
        if first { observation.detach() }
    }
}

/// What a hand call needs from the observer's state, guarded by one lock:
/// the log of notifications and how many calls are listening right now.
private final class ObservationState: @unchecked Sendable {
    static let retention: TimeInterval = 30
    static let messagingTimeout: Float = 0.1

    private let lock = NSLock()
    private var log = AXChangeLog(retention: retention)
    private var listeners = 0
    private var closed = false

    var isClosed: Bool { lock.withLock { closed } }

    func close() { lock.withLock { closed = true } }

    func attach() -> Int {
        lock.withLock {
            listeners += 1
            return log.sequence
        }
    }

    func detach() { lock.withLock { listeners = max(0, listeners - 1) } }

    func changes(since mark: Int) -> [AXChange] {
        lock.withLock { log.changes(since: mark, now: ProcessInfo.processInfo.systemUptime) }
    }

    func lastEventTime(since mark: Int) -> TimeInterval? {
        lock.withLock { log.lastEventTime(since: mark) }
    }

    /// Runs on the main thread, inside the notification. Attribute reads can
    /// block up to the messaging timeout, so a notification nobody is
    /// waiting for costs nothing: the check comes before any read.
    func ingest(element: AXUIElement, name: String) {
        guard lock.withLock({ listeners > 0 }),
              let notification = AXNotification(rawValue: name),
              let change = Self.classify(element: element, notification: notification)
        else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock { log.append(change, at: now) }
    }

    private static func classify(element: AXUIElement, notification: AXNotification) -> AXChange? {
        switch notification {
        case .windowCreated:
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            let dialog = AXScreen.dialogSubroles.contains(AXRead.string(kAXSubroleAttribute, of: element))
                || AXRead.string(kAXRoleAttribute, of: element) == kAXSheetRole
            return AXChange(
                kind: notification.kind(isDialog: dialog),
                title: AXRead.string(kAXTitleAttribute, of: element))
        case .focusedWindowChanged, .mainWindowChanged:
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            return AXChange(
                kind: notification.kind(isDialog: false),
                title: AXRead.string(kAXTitleAttribute, of: element))
        case .titleChanged:
            // The notification also fires for buttons and tabs; only a
            // window's title is "the window title".
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            guard AXRead.string(kAXRoleAttribute, of: element) == kAXWindowRole else { return nil }
            return AXChange(
                kind: notification.kind(isDialog: false),
                title: AXRead.string(kAXTitleAttribute, of: element))
        case .sheetCreated, .focusedUIElementChanged, .valueChanged, .elementDestroyed:
            return AXChange(kind: notification.kind(isDialog: false))
        }
    }
}

/// The AX pieces of one observation, released together on the main thread.
/// Callbacks also run there, so teardown is strictly after any callback that
/// was already running: the refcon the callback holds is never freed under it.
private final class Teardown: @unchecked Sendable {
    let observer: AXObserver
    let application: AXUIElement
    let source: CFRunLoopSource
    let refcon: UnsafeMutableRawPointer

    init(observer: AXObserver, application: AXUIElement, source: CFRunLoopSource,
         refcon: UnsafeMutableRawPointer) {
        self.observer = observer
        self.application = application
        self.source = source
        self.refcon = refcon
    }

    func run() {
        for notification in AXNotification.allCases {
            AXObserverRemoveNotification(observer, application, notification.rawValue as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopSourceInvalidate(source)
        Unmanaged<ObservationState>.fromOpaque(refcon).release()
    }
}

/// A live observer for one process. The observer itself is kept (a local
/// would be released when `init` returns), and the state it reports into is
/// retained once for the C callback and released only by `Teardown`.
final class AXObservation: @unchecked Sendable {
    let pid: Int32
    private let state = ObservationState()
    private let lock = NSLock()
    private var teardown: Teardown?

    init?(pid: Int32) {
        self.pid = pid
        var created: AXObserver?
        guard AXObserverCreate(pid, axChangeCallback, &created) == .success, let observer = created
        else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, ObservationState.messagingTimeout)
        let refcon = Unmanaged.passRetained(state).toOpaque()
        let added = AXNotification.allCases.filter {
            AXObserverAddNotification(observer, application, $0.rawValue as CFString, refcon) == .success
        }
        guard !added.isEmpty else {
            Unmanaged<ObservationState>.fromOpaque(refcon).release()
            return nil
        }
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        teardown = Teardown(observer: observer, application: application, source: source, refcon: refcon)
    }

    deinit { close() }

    var isClosed: Bool { state.isClosed }

    func attach() -> Int { state.attach() }

    func detach() { state.detach() }

    func changes(since mark: Int) -> [AXChange] { state.changes(since: mark) }

    func lastEventTime(since mark: Int) -> TimeInterval? { state.lastEventTime(since: mark) }

    func close() {
        guard let pending = lock.withLock({ () -> Teardown? in
            defer { teardown = nil }
            return teardown
        }) else { return }
        state.close()
        if Thread.isMainThread {
            pending.run()
        } else {
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { pending.run() }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }
}

private let axChangeCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    Unmanaged<ObservationState>.fromOpaque(refcon).takeUnretainedValue()
        .ingest(element: element, name: notification as String)
}
