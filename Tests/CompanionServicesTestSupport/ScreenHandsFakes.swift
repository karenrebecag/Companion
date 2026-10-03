import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import Foundation

// Wave 15g. Fakes de los puertos de las manos: nada toca otra app; cada
// uno registra lo que se le pidió para que el test lo compare.

package final class FakeHands: TextInjecting, FocusedReading, KeyPressing, WindowRaising,
    @unchecked Sendable {
    private let lock = NSLock()
    package var field: FocusedField?
    package var text: String?
    package var windows: [String] = []
    package var injectResult: InjectionResult?
    package private(set) var injected: [(text: String, pid: Int32)] = []
    package private(set) var pressed: [(key: NamedKey, pid: Int32)] = []
    package private(set) var raised: [(title: String, pid: Int32)] = []
    package private(set) var pressedChords: [(chord: KeyChord, pid: Int32)] = []
    /// False makes the port report that the event could not be posted.
    package var chordsPost = true

    package init(field: FocusedField? = nil, text: String? = nil, windows: [String] = []) {
        self.field = field
        self.text = text
        self.windows = windows
    }

    package func inject(_ text: String, into field: FocusedField) async -> InjectionResult {
        lock.withLock { injected.append((text, field.pid)) }
        return injectResult ?? .injected(text.count, via: .ax)
    }

    package func focusedField(pid: Int32) -> FocusedField? {
        guard let field, field.pid == pid else { return nil }
        return field
    }

    package func read(pid: Int32) -> String? {
        guard let field, field.pid == pid, !field.secure else { return nil }
        return text
    }

    package func press(_ key: NamedKey, pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pressed.append((key, pid))
        return true
    }

    package func press(chord: KeyChord, pid: Int32) -> Bool {
        lock.withLock { pressedChords.append((chord, pid)) }
        return chordsPost
    }

    package func raise(titleContaining title: String, pid: Int32) -> String? {
        guard let index = WindowTitles.match(windows, containing: title) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        raised.append((windows[index], pid))
        return windows[index]
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
