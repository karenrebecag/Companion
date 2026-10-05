import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionTestKit
import Foundation

// Wave 15g. Fakes de los puertos de las manos: nada toca otra app; cada
// uno registra lo que se le pidió para que el test lo compare.

package final class FakeHands: TextInjecting, FocusedReading, KeyPressing, WindowRaising,
    @unchecked Sendable {
    // The runner calls these off the main actor while the test reads the
    // recordings and sets the config; every field is behind its own lock.
    @Guarded package var field: FocusedField?
    @Guarded package var text: String?
    @Guarded package var windows: [String] = []
    @Guarded package var injectResult: InjectionResult?
    @Guarded package private(set) var injected: [(text: String, pid: Int32)] = []
    @Guarded package private(set) var pastes: [(text: String, pid: Int32)] = []
    @Guarded package private(set) var pressed: [(key: NamedKey, pid: Int32)] = []
    @Guarded package private(set) var raised: [(title: String, pid: Int32)] = []
    @Guarded package private(set) var pressedChords: [(chord: KeyChord, pid: Int32)] = []
    /// False makes the port report that the event could not be posted.
    @Guarded package var chordsPost = true
    /// When true, `inject` reports success but never grows `text`: simulates
    /// a field that accepted the attribute call and ignored its value.
    @Guarded package var ignoresSetText = false
    /// When true, `paste` reports success but never grows `text`: simulates
    /// a field that ignored Command-V.
    @Guarded package var ignoresPaste = false
    /// Forces what `paste` reports, like `injectResult` does for `inject`.
    @Guarded package var pasteResult: InjectionResult?
    /// Reads after this many return nil: a field that was readable for the
    /// baseline and then stopped answering.
    @Guarded package var unreadableAfterReads: Int?
    /// The injected text reaches `text` only after this many more reads:
    /// an app that updates its value a beat after the call returns.
    @Guarded package var landsAfterReads = 0
    @Guarded private var pending: String?
    /// The app keeps the set but stores its own version of it (an
    /// autocorrect, a formatter): `text` becomes this instead of growing.
    @Guarded package var rewritesSetTextTo: String?
    /// Read every time the runner reaches for a field or a value, so a
    /// guard that short-circuits before the reader can be proved.
    @Guarded package private(set) var fieldLookups = 0
    @Guarded package private(set) var reads = 0

    package init(field: FocusedField? = nil, text: String? = nil, windows: [String] = []) {
        self.field = field
        self.text = text
        self.windows = windows
    }

    package func inject(_ text: String, into field: FocusedField) async -> InjectionResult {
        injected.append((text, field.pid))
        if let injectResult { return injectResult }
        if let rewritten = rewritesSetTextTo {
            self.text = rewritten
            return .injected(text.count, via: .ax)
        }
        if self.text != nil, !ignoresSetText {
            if landsAfterReads > 0 { pending = text } else { self.text! += text }
        }
        return .injected(text.count, via: .ax)
    }

    package func paste(_ text: String, into field: FocusedField) async -> InjectionResult {
        pastes.append((text, field.pid))
        if let pasteResult { return pasteResult }
        if self.text != nil, !ignoresPaste {
            self.text! += text
        }
        return .injected(text.count, via: .paste)
    }

    package func focusedField(pid: Int32) -> FocusedField? {
        fieldLookups += 1
        let current = field
        guard let current, current.pid == pid else { return nil }
        return current
    }

    package func read(pid: Int32) -> String? {
        reads += 1
        let current = field
        guard let current, current.pid == pid, !current.secure else { return nil }
        if let limit = unreadableAfterReads, reads > limit { return nil }
        if let late = pending {
            if landsAfterReads > 0 {
                landsAfterReads -= 1
            } else if text != nil {
                text! += late
                pending = nil
            }
        }
        return text
    }

    package func press(_ key: NamedKey, pid: Int32) -> Bool {
        pressed.append((key, pid))
        return true
    }

    package func press(chord: KeyChord, pid: Int32) -> Bool {
        pressedChords.append((chord, pid))
        return chordsPost
    }

    package func raise(titleContaining title: String, pid: Int32) -> String? {
        let current = windows
        guard let index = WindowTitles.match(current, containing: title) else { return nil }
        raised.append((current[index], pid))
        return current[index]
    }
}

/// The pid the sensor reports, one read at a time: a list lets a test move
/// the user to another app between the capture and the injection.
package final class ScriptedTarget: @unchecked Sendable {
    private let lock = NSLock()
    private var pids: [Int32?]

    package init(_ pids: [Int32?]) { self.pids = pids }

    package func next() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return pids.count > 1 ? pids.removeFirst() : pids.first ?? nil
    }
}

package func handsRunner(
    _ hands: FakeHands,
    target: ScriptedTarget = ScriptedTarget([7]),
    bundle: String = "com.apple.Notes",
    trusted: Bool = true
) -> ParentToolRunner {
    ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { trusted },
            target: { target.next() },
            bundleID: { _ in bundle }))
}

/// An app that is launched but not ready yet: its pid shows up after
/// `pidAfter` reads and its window after `windowAfter`, like a real launch.
package final class FakeAppWindows: AppWindowProbing, @unchecked Sendable {
    private let lock = NSLock()
    private let appPID: Int32
    private let pidAfter: Int
    private let windowAfter: Int
    private var pidReads = 0
    private var windowReads = 0
    package var reads: (pid: Int, window: Int) { lock.withLock { (pidReads, windowReads) } }

    package init(pid: Int32, pidAfter: Int = 0, windowAfter: Int = 0) {
        appPID = pid
        self.pidAfter = pidAfter
        self.windowAfter = windowAfter
    }

    package func pid(ofApp name: String) -> Int32? {
        lock.withLock {
            pidReads += 1
            return pidReads > pidAfter ? appPID : nil
        }
    }

    package func hasWindow(pid: Int32) -> Bool {
        lock.withLock {
            windowReads += 1
            return pid == appPID && windowReads > windowAfter
        }
    }
}
