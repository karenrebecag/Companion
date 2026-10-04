import AppKit
import ApplicationServices
import CompanionCore

// Incredible's hold observations (referencia local, crate workflow-recording): while the
// voice key is held the host polls where the user is and what they copied, and reports
// the whole hold each time something changes. Nothing is observed outside a hold, and
// nothing observed is ever logged.

/// Where the user is: the frontmost app and its focused window.
package struct HoldSurface: Sendable, Equatable {
    package let app: String?
    package let title: String?
    package let url: String?
    /// The dialog or sheet up over it, by its title; nil when there is none.
    package let dialog: String?
    /// Longer than any label the overlay can show; a hostile page title is cut here.
    package static let textLimit = 512

    package init(app: String?, title: String?, url: String? = nil, dialog: String? = nil) {
        self.app = app
        self.title = title
        self.url = url
        self.dialog = dialog
    }

    /// A dialog coming and going over the same window is not another place.
    func samePlace(as other: HoldSurface?) -> Bool {
        guard let other else { return false }
        return app == other.app && title == other.title && url == other.url
    }

    func capped() -> HoldSurface {
        HoldSurface(app: app, title: title.map { String($0.prefix(Self.textLimit)) }, url: url,
                    dialog: dialog.map { String($0.prefix(Self.textLimit)) })
    }

    func with(dialog: String?) -> HoldSurface {
        HoldSurface(app: app, title: title, url: url, dialog: dialog)
    }
}

package protocol HoldSurfaceReading: Sendable {
    /// Nil when it cannot be read right now; that is not a move.
    func surface() -> HoldSurface?
}

/// Turns successive looks at the screen and the board into observations.
struct HoldSampler {
    private var lastSurface: HoldSurface?
    private var lastCount: Int
    /// Looks in a row the open dialog was not found; one miss is a failed read, not a close.
    private var dialogMissed = 0
    private(set) var events: [HoldObservation] = []

    init(surface: HoldSurface?, changeCount: Int) {
        lastSurface = surface
        lastCount = changeCount
    }

    /// True when something new was observed.
    mutating func sample(surface: HoldSurface?, pasteboard: any PasteboardReading, atMs: Int) -> Bool {
        let before = events.count
        if let seen = surface.map({ keepingLast($0.capped()) }) {
            let moved = !seen.samePlace(as: lastSurface)
            if moved {
                events.append(HoldObservation(atMs: atMs, event: .surfaceChanged(
                    app: seen.app, title: seen.title, url: seen.url)))
            }
            lastSurface = dialogSeen(seen, moved: moved, atMs: atMs)
        }
        let count = pasteboard.changeCount
        if count != lastCount {
            lastCount = count
            // A password manager marks what it copies; it is never read.
            if !pasteboard.concealed, let text = pasteboard.string, !text.isEmpty {
                events.append(HoldObservation(atMs: atMs, event: .copied(String(text.prefix(HoldObserver.copyLimit)))))
            }
        }
        return events.count != before
    }

    /// A dialog is new where it was not before: over another place, or another dialog.
    private mutating func dialogSeen(_ seen: HoldSurface, moved: Bool, atMs: Int) -> HoldSurface {
        if let dialog = seen.dialog {
            dialogMissed = 0
            if moved || dialog != lastSurface?.dialog {
                events.append(HoldObservation(atMs: atMs, event: .dialogOpened(title: dialog)))
            }
            return seen
        }
        if !moved, let open = lastSurface?.dialog, dialogMissed == 0 {
            dialogMissed += 1
            return seen.with(dialog: open)
        }
        dialogMissed = 0
        return seen
    }

    /// What cannot be read for one look in the same app is what was there: a missing
    /// title keeps the window, a missing address on the same window keeps the page.
    private func keepingLast(_ surface: HoldSurface) -> HoldSurface {
        guard let last = lastSurface, last.app == surface.app else { return surface }
        if surface.title == nil {
            return HoldSurface(app: surface.app, title: last.title, url: surface.url ?? last.url,
                               dialog: surface.dialog ?? last.dialog)
        }
        if surface.url == nil, surface.title == last.title {
            return HoldSurface(app: surface.app, title: surface.title, url: last.url, dialog: surface.dialog)
        }
        return surface
    }
}

/// Watches one hold at a time.
package actor HoldObserver: HoldObserving {
    /// How often it looks while the key is held.
    package static let interval = Duration.milliseconds(150)
    /// Longer than any chip or woven line can show; the rest is never kept.
    package static let copyLimit = 4096

    private let surface: any HoldSurfaceReading
    private let pasteboard: any PasteboardReading
    private let now: @Sendable () -> Int
    private let polls: Bool
    private let interval: Duration
    private var sampler: HoldSampler?
    private var generation = 0
    private var onBatch: (@Sendable (HoldObservationBatch) -> Void)?
    private var loop: Task<Void, Never>?

    /// `polls: false` leaves the looking to `tick()`, for tests.
    package init(surface: any HoldSurfaceReading, pasteboard: any PasteboardReading = SystemPasteboard(),
                 now: @escaping @Sendable () -> Int, polls: Bool = true,
                 interval: Duration = HoldObserver.interval) {
        self.surface = surface
        self.pasteboard = pasteboard
        self.now = now
        self.polls = polls
        self.interval = interval
    }

    package func start(generation: Int, onBatch: @escaping @Sendable (HoldObservationBatch) -> Void) {
        stop()
        self.generation = generation
        self.onBatch = onBatch
        // What was already there when the hold began is the starting point, not a move.
        sampler = HoldSampler(surface: surface.surface(), changeCount: pasteboard.changeCount)
        guard polls else { return }
        loop = Task { [weak self, interval] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                await self?.tick(generation: generation)
            }
        }
    }

    package func stop() {
        loop?.cancel()
        loop = nil
        sampler = nil
        onBatch = nil
    }

    package func tick() { tick(generation: generation) }

    /// A loop that outlived its hold must not report into the next one.
    private func tick(generation expected: Int) {
        guard expected == generation, var current = sampler else { return }
        let changed = current.sample(surface: surface.surface(), pasteboard: pasteboard, atMs: now())
        sampler = current
        if changed { onBatch?(HoldObservationBatch(generation: generation, events: current.events)) }
    }
}

/// The frontmost app other than Companion and, when Accessibility allows reading them,
/// its main window's title and page, and the dialog over it.
package struct SystemHoldSurface: HoldSurfaceReading {
    private let trusted: @Sendable () -> Bool
    private let selfBundleID: String?
    /// A hung app must not stall the observer's actor for the default six seconds.
    static let axTimeout: Float = 0.2

    package init(trusted: @escaping @Sendable () -> Bool, selfBundleID: String? = Bundle.main.bundleIdentifier) {
        self.trusted = trusted
        self.selfBundleID = selfBundleID
    }

    /// Only web pages, and only their site: a path, query or fragment can carry a token
    /// (/reset/<token>), credentials are never kept, and the overlay shows the site anyway.
    package static func pageURL(_ raw: String) -> String? {
        guard var parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              parts.host?.isEmpty == false
        else { return nil }
        parts.scheme = scheme
        parts.user = nil
        parts.password = nil
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        return parts.string
    }

    package func surface() -> HoldSurface? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != selfBundleID
        else { return nil }
        guard trusted() else { return HoldSurface(app: app.localizedName, title: nil) }
        let application = Self.bounded(AXUIElementCreateApplication(app.processIdentifier))
        let focused = AXRead.element(kAXFocusedWindowAttribute, of: application).map(Self.bounded)
        let focusedIsDialog = focused.map(Self.isDialog) ?? false
        // The main window is where the user is; a dialog takes focus but is not a move, and
        // with no main window behind it there is no window title to report this look.
        let main = AXRead.element(kAXMainWindowAttribute, of: application).map(Self.bounded)
            ?? (focusedIsDialog ? nil : focused)
        let title = main.map { AXRead.string(kAXTitleAttribute, of: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        let dialog = focusedIsDialog ? focused.flatMap(Self.named) : main.flatMap(Self.sheet)
        return HoldSurface(app: app.localizedName, title: title, url: main.flatMap(Self.webAddress), dialog: dialog)
    }

    /// Floating palettes (inspectors, tool windows) are not dialogs the user opened.
    static let dialogSubroles: Set<String> = ["AXDialog", "AXSystemDialog"]

    /// An element's timeout does not reach the elements read from it: each one is bounded.
    private static func bounded(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, axTimeout)
        return element
    }

    private static func isDialog(_ window: AXUIElement) -> Bool {
        dialogSubroles.contains(AXRead.string(kAXSubroleAttribute, of: window))
    }

    // HACK: a fixed element and time budget per look. Searching once per window and caching
    // the web area is the upgrade when a real page keeps missing it.
    static let webAreaSearch = 200
    static let webAreaBudget: Duration = .milliseconds(60)

    private static func webAddress(in window: AXUIElement) -> String? {
        var queue = [window]
        var visited = 0
        let deadline = ContinuousClock.now + webAreaBudget
        while !queue.isEmpty, visited < webAreaSearch, ContinuousClock.now < deadline {
            let element = queue.removeFirst()
            visited += 1
            AXUIElementSetMessagingTimeout(element, AXPointerProbe.messagingTimeout)
            if AXRead.string(kAXRoleAttribute, of: element) == "AXWebArea" {
                return url(of: element).flatMap(pageURL)
            }
            queue += AXRead.elements(kAXChildrenAttribute, of: element) ?? []
        }
        return nil
    }

    private static func url(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success
        else { return nil }
        return (value as? URL)?.absoluteString ?? value as? String
    }

    /// A sheet over the window (Save, Print), by its name.
    private static func sheet(over window: AXUIElement) -> String? {
        (AXRead.elements(kAXChildrenAttribute, of: window) ?? [])
            .lazy.map(bounded)
            .first { AXRead.string(kAXRoleAttribute, of: $0) == kAXSheetRole }
            .flatMap(named)
    }

    /// AppKit's Save and Print sheets often have no title; their description or, last, the
    /// system's own word for them still says a dialog opened.
    private static func named(_ element: AXUIElement) -> String? {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXRoleDescriptionAttribute]
            .lazy.map { AXRead.string($0, of: element) }
            .first { !$0.isEmpty }
    }
}
