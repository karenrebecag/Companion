import AppKit
import ApplicationServices
import CompanionCore
import Foundation

// MARK: - Channel ports

public protocol FocusedAppSensing: Sendable {
    func focusedApp() async -> String?
}

/// Wave 16h-3: the title of the window in front, next to the app's name.
public protocol FocusedWindowSensing: Sendable {
    func focusedWindow() async -> String?
}

public protocol OpenDocumentsSensing: Sendable {
    func openDocuments() async -> [String]
}

public protocol ClipboardSensing: Sendable {
    func clipboard() async -> ClipboardSummary?
}

/// What `ClipboardSensor` reads, behind a port so a test never touches the
/// real board (macOS 15.4+ may show a system alert per programmatic read).
public protocol PasteboardReading: Sendable {
    var changeCount: Int { get }
    var string: String? { get }
    var fileURLs: [URL] { get }
    var hasImage: Bool { get }
    /// True when the current owner marked its content
    /// `org.nspasteboard.ConcealedType` or `...TransientType` — the
    /// convention password managers use to opt out of clipboard history and
    /// sync (H4, security review 2026-09-25). Never read past this flag.
    var concealed: Bool { get }
}

// MARK: - Composite

/// One activation, all channels (corpus spec 09), under one budget. The
/// channel reads run detached; the wait races them against the deadline and
/// walks away from whatever did not arrive — a blocking Accessibility call
/// on a busy app must not hold the turn.
public final class SystemContextSensor: ContextSensing, @unchecked Sendable {
    private let focused: any FocusedAppSensing
    private let documents: any OpenDocumentsSensing
    private let clipboardSensor: any ClipboardSensing
    private let window: (any FocusedWindowSensing)?
    private let location: UserLocationSource?
    private let islandEvents: (any IslandEventSource)?
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var lastSense: Date?

    public init(
        focused: any FocusedAppSensing,
        documents: any OpenDocumentsSensing,
        clipboard: any ClipboardSensing,
        window: (any FocusedWindowSensing)? = nil,
        location: UserLocationSource? = nil,
        islandEvents: (any IslandEventSource)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.focused = focused
        self.documents = documents
        self.clipboardSensor = clipboard
        self.window = window
        self.location = location
        self.islandEvents = islandEvents
        self.now = now
    }

    public func sense(_ channels: ContextChannels, budget: Duration) async -> TurnContext {
        let stamp = now()
        var ctx = TurnContext(source: .typed, timestamp: stamp, sinceLastTurn: since(stamp))
        // HACK: the detached reads are not cancelled at the deadline — an
        // AX call is synchronous and would not honor cancellation anyway, so a
        // slow channel keeps its pool thread until it returns and writes into
        // a box nobody reads. Upgrade trigger: repeated slow AX reads observed
        // in the field (turns arriving without documents), or an async AX API.
        let box = ResultBox()
        var expected = 0
        if channels.contains(.focusedApp) {
            expected += 1
            let focused = self.focused
            Task.detached { box.put(.app(await focused.focusedApp())) }
        }
        if channels.contains(.focusedApp), let window {
            expected += 1
            Task.detached { box.put(.window(await window.focusedWindow())) }
        }
        if channels.contains(.location), let location {
            expected += 1
            // Never `prompting`: a turn must not put up the Location dialog.
            Task.detached { box.put(.location(await location.current(prompting: false))) }
        }
        if channels.contains(.openDocuments) {
            expected += 1
            let documents = self.documents
            Task.detached { box.put(.documents(await documents.openDocuments())) }
        }
        if channels.contains(.clipboard) {
            expected += 1
            let clipboard = self.clipboardSensor
            Task.detached { box.put(.clipboard(await clipboard.clipboard())) }
        }
        // Not the environment: the app's own facts, so no channel gates them.
        // Taken here, per sense, so a turn hears each fact exactly once.
        if let batch = islandEvents?.pending() {
            ctx.islandEvents = batch.events
            ctx.islandEventsThrough = batch.through
        }
        guard expected > 0 else { return ctx }
        await box.wait(for: expected, budget: budget)
        for result in box.drain() {
            switch result {
            case .app(let name): ctx.focusedApp = name
            case .window(let title): ctx.focusedWindow = title
            case .location(let city): ctx.location = city
            case .documents(let list): ctx.openDocuments = list
            case .clipboard(let summary): ctx.clipboard = summary
            }
        }
        return ctx
    }

    public func acknowledgeIslandEvents(through: Int) {
        islandEvents?.acknowledge(through: through)
    }

    private func since(_ stamp: Date) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        let previous = lastSense
        lastSense = stamp
        return previous.map { stamp.timeIntervalSince($0) }
    }

    private enum ChannelResult: Sendable {
        case app(String?)
        case window(String?)
        case location(UserLocation?)
        case documents([String])
        case clipboard(ClipboardSummary?)
    }

    /// Results land here from detached tasks; `wait` returns when all are
    /// in or the budget is spent, whichever comes first.
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [ChannelResult] = []
        private var waiter: CheckedContinuation<Void, Never>?
        private var target = Int.max

        func put(_ result: ChannelResult) {
            lock.lock()
            results.append(result)
            let done = results.count >= target
            let waiter = done ? self.waiter : nil
            if done { self.waiter = nil }
            lock.unlock()
            waiter?.resume()
        }

        func wait(for count: Int, budget: Duration) async {
            let deadline = Task {
                do {
                    try await Task.sleep(for: budget)
                } catch {
                    // Cancelled: every result arrived first; nothing to release.
                    return
                }
                self.release()
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if results.count >= count {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                target = count
                waiter = continuation
                lock.unlock()
            }
            deadline.cancel()
        }

        private func release() {
            lock.lock()
            let waiter = self.waiter
            self.waiter = nil
            lock.unlock()
            waiter?.resume()
        }

        func drain() -> [ChannelResult] {
            lock.lock()
            defer { lock.unlock() }
            return results
        }
    }
}

// MARK: - Adapters

/// The app in front — the one BEFORE Companion when Companion is in front.
/// Talking to Companion means bringing its window up, so "frontmost" would
/// always be us (spec 10a §7): activations are watched and the last one
/// that was not ours is what gets reported.
public final class FrontmostAppSensor: FocusedAppSensing, @unchecked Sendable {
    private let selfBundleID: String
    private let lock = NSLock()
    private var lastOther: String?
    private var lastOtherProcess: pid_t?
    private var ownInFront = false
    /// Wave 16a: told of every app that comes to the front, so the sight can
    /// prime its Accessibility tree before the user speaks about it.
    public var onActivate: (@Sendable (pid_t, String) -> Void)? {
        get { lock.withLock { activationHook } }
        set { lock.withLock { activationHook = newValue } }
    }
    private var activationHook: (@Sendable (pid_t, String) -> Void)?
    private var observer: (any NSObjectProtocol)?

    /// The process the document sensor should read: the last app in front
    /// that was not us. Nil until one has been seen — never our own.
    public var lastOtherPID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return lastOtherProcess
    }

    public var lastOtherName: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastOther
    }

    public init(selfBundleID: String, watch: Bool = false) {
        self.selfBundleID = selfBundleID
        if let current = NSWorkspace.shared.frontmostApplication, watch {
            noteActivation(
                name: current.localizedName ?? "", bundleID: current.bundleIdentifier ?? "",
                pid: current.processIdentifier)
        }
        guard watch else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            self?.noteActivation(
                name: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "",
                pid: app.processIdentifier)
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// True while Companion's own window is the active app — the typed chat.
    public var selfInFront: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ownInFront
    }

    public func noteActivation(name: String, bundleID: String, pid: pid_t = 0) {
        lock.lock()
        ownInFront = bundleID == selfBundleID
        lock.unlock()
        guard bundleID != selfBundleID, !name.isEmpty else { return }
        if pid > 0 { onActivate?(pid, bundleID) }
        lock.lock()
        lastOther = name
        lastOtherProcess = pid > 0 ? pid : nil
        lock.unlock()
    }

    public func focusedApp() async -> String? {
        current()
    }

    private func current() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastOther
    }
}

/// Window titles and document paths of the app in front, through the
/// Accessibility tree. Trust is read on EVERY call, never cached: the grant
/// can appear or vanish (a re-sign drops it) while the app runs. Never asks
/// for the permission — that is the Settings row's job, once, with words.
public final class OpenDocumentsSensor: OpenDocumentsSensing, @unchecked Sendable {
    private let trusted: @Sendable () -> Bool
    private let pid: @Sendable () -> pid_t?
    private let windows: @Sendable (pid_t) -> [String]

    /// `pid` is the app to read — the last one in front that was not us,
    /// from `FrontmostAppSensor` — never `frontmostApplication`, which is
    /// Companion itself whenever the user is talking to it.
    public init(
        trusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        pid: @escaping @Sendable () -> pid_t?,
        windows: @escaping @Sendable (pid_t) -> [String] = { OpenDocumentsSensor.windows(of: $0) }
    ) {
        self.trusted = trusted
        self.pid = pid
        self.windows = windows
    }

    public func openDocuments() async -> [String] {
        // HACK: the pid was captured at activation; if that process exited
        // and macOS handed the number to another one before this read, the
        // titles come from the wrong app (read-only, same AX trust). No
        // pid-to-identity check without holding an NSRunningApplication.
        // Upgrade trigger: a sensed document that belongs to no visible app.
        guard trusted(), let pid = pid() else { return [] }
        return windows(pid)
    }

    /// `kAXDocumentAttribute` is a file URL when the app is document-based;
    /// otherwise the title is the best summary there is (spec 09: summaries,
    /// not an AX dump).
    public static func windows(of pid: pid_t) -> [String] {
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return [] }
        return windows.compactMap { window in
            if let document = attribute(kAXDocumentAttribute, of: window),
               let url = URL(string: document), url.isFileURL {
                return url.path
            }
            return attribute(kAXTitleAttribute, of: window)
        }
    }

    static func attribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty
        else { return nil }
        return text
    }
}

/// The title of the window in front of the app in front (16h-3), through the
/// same Accessibility trust and the same pid as the documents sensor.
public final class FocusedWindowSensor: FocusedWindowSensing, @unchecked Sendable {
    private let trusted: @Sendable () -> Bool
    private let pid: @Sendable () -> pid_t?
    private let title: @Sendable (pid_t) -> String?

    public init(
        trusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        pid: @escaping @Sendable () -> pid_t?,
        title: @escaping @Sendable (pid_t) -> String? = { FocusedWindowSensor.title(of: $0) }
    ) {
        self.trusted = trusted
        self.pid = pid
        self.title = title
    }

    public func focusedWindow() async -> String? {
        guard trusted(), let pid = pid() else { return nil }
        return title(pid)
    }

    public static func title(of pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        // Checked one line above: the type id says this is an AXUIElement.
        return OpenDocumentsSensor.attribute(kAXTitleAttribute, of: window as! AXUIElement)
    }
}

/// Reads the board only when it changed since the last look: what the user
/// copied an hour ago is not context for this turn, and every programmatic
/// read is one macOS may warn about.
public final class ClipboardSensor: ClipboardSensing, @unchecked Sendable {
    private let pasteboard: any PasteboardReading
    fileprivate let lock = NSLock()
    fileprivate var lastSeen: Int?

    public init(pasteboard: any PasteboardReading = SystemPasteboard()) {
        self.pasteboard = pasteboard
    }

    public func clipboard() async -> ClipboardSummary? {
        guard noteChange(pasteboard.changeCount) else { return nil }
        guard !pasteboard.concealed else {
            Log.app("clipboard: concealed, skipped")
            return nil
        }
        if let text = pasteboard.string, !text.isEmpty {
            return ClipboardSummary(kind: .text, preview: text)
        }
        let files = pasteboard.fileURLs
        if !files.isEmpty {
            // Names, not paths: the path is the user's business until they
            // hand it over.
            return ClipboardSummary(
                kind: .files, preview: files.map(\.lastPathComponent).joined(separator: ", "))
        }
        if pasteboard.hasImage {
            return ClipboardSummary(kind: .image, preview: "")
        }
        return nil
    }
}

extension ClipboardSensor {
    private func noteChange(_ count: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let changed = lastSeen != count
        lastSeen = count
        return changed
    }
}

public struct SystemPasteboard: PasteboardReading {
    public init() {}
    public var changeCount: Int { NSPasteboard.general.changeCount }
    public var string: String? { NSPasteboard.general.string(forType: .string) }
    public var fileURLs: [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? [])
            .filter(\.isFileURL)
    }
    public var hasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self])
    }
    public var concealed: Bool {
        let marked: Set<NSPasteboard.PasteboardType> = [
            .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType"),
        ]
        return (NSPasteboard.general.pasteboardItems ?? []).contains {
            !marked.isDisjoint(with: Set($0.types))
        }
    }
}
