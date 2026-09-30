import ApplicationServices
import CompanionCore
import CoreGraphics
import Foundation

/// The hold key, heard from any app. A default (consuming) HID tap on FN:
/// Accessibility, not Input Monitoring. Solo FN is swallowed so Globe does
/// not also fire; FN+another key passes through. FN opens the mic on the
/// way down and a tap or chord cancels it (15d-1); past the threshold it
/// says `.confirmed`. The dictation key still never arms on a tap.
package final class HoldKeyTap: @unchecked Sendable {
    package let events: AsyncStream<HoldKeyEvent>
    private let continuation: AsyncStream<HoldKeyEvent>.Continuation
    private let keyCode: Int64
    /// 15b-1: which side's bit counts. FN (`.maskSecondaryFn`) has no
    /// left/right ambiguity; the dictation tap sets this to the exact
    /// device-specific bit (`DictationKey.deviceFlag`) so the OTHER side
    /// typing a symbol never arms it (§11, measured risk).
    private let flag: CGEventFlags
    /// 15b-1: FN still swallows (Globe must not also fire). The dictation
    /// tap never does — an eaten modifier gets stuck mid-air (§8).
    private let swallowsRelease: Bool
    private let tapThreshold: TimeInterval
    /// 15d-1: FN opens the mic on the way down (Incredible: +3 ms); a tap
    /// or chord then cancels it. The dictation tap keeps waiting for the
    /// threshold: typing a symbol with its modifier must not open the mic.
    private let armsOnDown: Bool
    private let lock = NSLock()
    private var classifier: HoldKeyClassifier
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var armWork: DispatchWorkItem?
    private var armGeneration = 0
    private let now: @Sendable () -> TimeInterval

    package init(
        keyCode: Int64 = 63,
        flag: CGEventFlags = .maskSecondaryFn,
        swallowsRelease: Bool = true,
        tapThreshold: TimeInterval = 0.25,
        armsOnDown: Bool = true,
        now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.keyCode = keyCode
        self.flag = flag
        self.swallowsRelease = swallowsRelease
        self.tapThreshold = tapThreshold
        self.armsOnDown = armsOnDown
        self.classifier = HoldKeyClassifier(tapThreshold: tapThreshold)
        self.now = now
        (events, continuation) = AsyncStream.makeStream(of: HoldKeyEvent.self)
    }

    /// Pure: does this transition belong to OUR key — code and the exact
    /// device-side bit must both match, so Opción Izquierda (raw bit
    /// `0x20`, typing `@` on a Spanish keyboard) never counts as the Opción
    /// Derecha dictation tap's own key (§11, measured risk). Shared by
    /// `handle`'s own arm decision, which needs this and nothing else — it
    /// must still arm a tap that never swallows.
    private static func matches(
        code: Int64, flags: CGEventFlags, keyCode: Int64, flag: CGEventFlags
    ) -> Bool {
        code == keyCode && flags.contains(flag)
    }

    /// Pure: whether a MATCHING transition should be swallowed. FN still is
    /// (Globe must not also fire); the dictation tap never is (§8, a
    /// modifier eaten mid-air gets stuck).
    package static func consumes(
        code: Int64, flags: CGEventFlags, keyCode: Int64, flag: CGEventFlags,
        swallowsRelease: Bool
    ) -> Bool {
        matches(code: code, flags: flags, keyCode: keyCode, flag: flag) && swallowsRelease
    }

    /// False when Accessibility is missing or the tap could not be made.
    @discardableResult
    package func start() -> Bool {
        guard lock.withLock({ port == nil }) else { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let consume = Unmanaged<HoldKeyTap>.fromOpaque(refcon)
                    .takeUnretainedValue()
                    .handle(type: type, event: event)
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon)
        else { return false }
        lock.withLock { self.port = port }
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()
            let live = lock.withLock { () -> Bool in
                guard self.port === port else { return false }
                runLoop = loop
                return true
            }
            guard live else { return }
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            while lock.withLock({ self.port === port }) {
                CFRunLoopRunInMode(.defaultMode, 1, false)
            }
        }
        thread.name = "companion.holdkey"
        thread.start()
        return true
    }

    deinit { stop() }

    package func stop() {
        lock.withLock { armWork?.cancel(); armWork = nil }
        let stopped: (CFMachPort, CFRunLoop?)? = lock.withLock {
            guard let port else { return nil }
            defer {
                self.port = nil
                runLoop = nil
            }
            return (port, runLoop)
        }
        guard let stopped else { return }
        CGEvent.tapEnable(tap: stopped.0, enable: false)
        CFMachPortInvalidate(stopped.0)
        if let loop = stopped.1 { CFRunLoopStop(loop) }
    }

    /// True = swallow the event so Globe / FN+arrow do not also see it.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = lock.withLock({ port }) { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown || type == .keyUp {
            if code != keyCode {
                let out: HoldKeyEvent? = lock.withLock {
                    guard classifier.isDown else { return nil }
                    armGeneration += 1
                    armWork?.cancel()
                    armWork = nil
                    return classifier.chord()
                }
                if let out { continuation.yield(out) }
            }
            return false
        }
        guard type == .flagsChanged, code == keyCode else { return false }
        let keyIsDown = Self.matches(code: code, flags: event.flags, keyCode: keyCode, flag: flag)
        let stamp = now()
        if keyIsDown, armsOnDown {
            let out = lock.withLock { classifier.press(at: stamp) }
            if let out {
                continuation.yield(out)
                // The mic is open; `.confirmed` at the threshold is what lets
                // network work and a cut of the reply in flight start.
                scheduleArm()
            }
            return false
        }
        if keyIsDown {
            let began = lock.withLock { () -> Bool in
                let idle = !classifier.isDown
                _ = classifier.begin(at: stamp)
                return idle && classifier.isDown
            }
            if began { scheduleArm() }
            return false
        }
        let out: HoldKeyEvent? = lock.withLock {
            armGeneration += 1
            armWork?.cancel()
            armWork = nil
            return classifier.up(at: stamp)
        }
        switch out {
        case .released:
            continuation.yield(.released)
            return swallowsRelease
        case .tapped:
            // FN swallows the Globe tap; do not teach or open the mic. The
            // dictation tap never swallows anything (§8).
            return swallowsRelease
        case .cancelled:
            // 15d-1: the mic opened on the way down; the session drops it.
            continuation.yield(.cancelled)
            return swallowsRelease
        case .pressed, .confirmed, nil:
            return false
        }
    }

    private func scheduleArm() {
        let generation: Int = lock.withLock {
            armGeneration += 1
            return armGeneration
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let stamp = self.now()
            let out = self.lock.withLock { () -> HoldKeyEvent? in
                guard self.armGeneration == generation else { return nil }
                return self.classifier.confirm(at: stamp)
            }
            if let out { self.continuation.yield(out) }
        }
        lock.withLock {
            armWork?.cancel()
            armWork = work
        }
        DispatchQueue.global(qos: .userInteractive).asyncAfter(
            deadline: .now() + tapThreshold, execute: work)
    }
}