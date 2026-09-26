import CompanionCore
import CompanionServices
import Foundation

// Wave 15g. Fakes de los puertos de las manos: nada toca otra app; cada
// uno registra lo que se le pidió para que el test lo compare.

final class FakeHands: TextInjecting, FocusedReading, KeyPressing, WindowRaising,
    @unchecked Sendable {
    private let lock = NSLock()
    var field: FocusedField?
    var text: String?
    var windows: [String] = []
    var injectResult: InjectionResult?
    private(set) var injected: [(text: String, pid: Int32)] = []
    private(set) var pressed: [(key: NamedKey, pid: Int32)] = []
    private(set) var raised: [(title: String, pid: Int32)] = []

    init(field: FocusedField? = nil, text: String? = nil, windows: [String] = []) {
        self.field = field
        self.text = text
        self.windows = windows
    }

    func inject(_ text: String, into field: FocusedField) async -> InjectionResult {
        lock.withLock { injected.append((text, field.pid)) }
        return injectResult ?? .injected(text.count, via: .ax)
    }

    func focusedField(pid: Int32) -> FocusedField? {
        guard let field, field.pid == pid else { return nil }
        return field
    }

    func read(pid: Int32) -> String? {
        guard let field, field.pid == pid, !field.secure else { return nil }
        return text
    }

    func press(_ key: NamedKey, pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pressed.append((key, pid))
        return true
    }

    func raise(titleContaining title: String, pid: Int32) -> String? {
        guard let index = WindowTitles.match(windows, containing: title) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        raised.append((windows[index], pid))
        return windows[index]
    }
}

/// The pid the sensor reports, one read at a time: a list lets a test move
/// the user to another app between the capture and the injection.
final class ScriptedTarget: @unchecked Sendable {
    private let lock = NSLock()
    private var pids: [Int32?]

    init(_ pids: [Int32?]) { self.pids = pids }

    func next() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return pids.count > 1 ? pids.removeFirst() : pids.first ?? nil
    }
}

func handsRunner(
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
