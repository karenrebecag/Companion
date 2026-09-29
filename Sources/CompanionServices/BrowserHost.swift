import CompanionCore
import Foundation

/// Wave 18-3c. Owns the browser socket end to end: the listener
/// (`browser.sock`), the channel that speaks to the extension, the presence
/// the tool lists follow, and the install/remove the Settings buttons press.
/// It lives in Services, not the composition root, because nothing in it needs
/// the approval sheet or the session: only the runner does, and it brings its
/// own tickets. That keeps the start condition and the tool lists testable.
public final class BrowserHost: @unchecked Sendable {
    public let presence = BrowserPresence()
    /// Two runners over one channel: each keeps its own page cache and
    /// tickets, so a yes spoken in the conversation cannot be spent by a
    /// bridge peer (and the peer's calls never spend the user's).
    private let conversationRunner: BrowserToolRunner
    private let bridgeRunner: BrowserToolRunner
    private let listener: BridgeListener
    private let installer: NativeHostInstaller
    private let lock = NSLock()
    private var started = false

    public init(
        directory: URL, installer: NativeHostInstaller,
        language: @escaping @Sendable () -> AppLanguage,
        commanding: (any BrowserCommanding)? = nil
    ) {
        self.installer = installer
        let box = ChannelBox()
        let listener = BridgeListener(
            directory: directory, socketName: "browser.sock", tokenName: "browser.token",
            onConnection: { connection in
                guard let channel = box.value else { return }
                Task.detached { await channel.attach(connection) }
            })
        let channel = BrowserChannel(presence: presence, token: { listener.token })
        box.value = channel
        self.listener = listener
        let commander: any BrowserCommanding = commanding ?? channel
        self.conversationRunner = BrowserToolRunner(channel: commander, presence: presence, language: language)
        self.bridgeRunner = BrowserToolRunner(channel: commander, presence: presence, language: language)
    }

    // MARK: Lifecycle

    /// X12: the browser's listener is independent of "lend your hands" and
    /// only exists once the user connected a browser, so a user who never did
    /// has no extra socket open.
    public func startIfInstalled() {
        guard !installer.installed().isEmpty else { return }
        start()
    }

    public func stop() {
        lock.withLock {
            guard started else { return }
            listener.stop()
            started = false
        }
    }

    /// Writes the manifest, then starts listening. A failed install never
    /// leaves a listener behind.
    public func connect() -> BrowserLinkOutcome {
        let installed: [BrowserKind]
        do {
            installed = try installer.install()
        } catch NativeHostInstaller.Failure.unstableExecutablePath {
            return .moveApp
        } catch NativeHostInstaller.Failure.symlinkAtDestination {
            return .symlink
        } catch {
            Log.browser("install failed")
            return .failed
        }
        guard !installed.isEmpty else { return .noBrowser }
        return start() ? .done : .failed
    }

    public func remove() -> BrowserLinkOutcome {
        let result = installer.removeReporting()
        // A manifest that was removed no longer authorizes a listener, even
        // if another browser's manifest could not be touched.
        if result.failure == nil || !result.removed.isEmpty { stop() }
        switch result.failure {
        case nil:
            return .done
        case NativeHostInstaller.Failure.symlinkAtDestination?:
            return .symlink
        default:
            Log.browser("remove failed")
            return .failed
        }
    }

    public var status: BrowserLinkStatus {
        if installer.installed().isEmpty { return .notInstalled }
        if let browser = presence.browser { return .connected(browser) }
        return .disconnected
    }

    // MARK: Tool lists

    /// Chat and both voice modes: the parent's tools, the connected apps' and
    /// the browser's.
    public func conversationTools(
        parent: any ParentToolExecuting, apps: any ParentToolExecuting
    ) -> CompositeParentTools {
        CompositeParentTools([parent, apps, conversationRunner])
    }

    /// The bridge lends the hands and the browser, never Karen's connected apps.
    public func bridgeTools(parent: any ParentToolExecuting) -> CompositeParentTools {
        CompositeParentTools([parent, bridgeRunner])
    }

    @discardableResult
    private func start() -> Bool {
        lock.withLock {
            if started { return true }
            do {
                try listener.start()
                started = true
            } catch {
                Log.browser("listener: could not start")
            }
            return started
        }
    }
}

/// `onConnection` runs on the accept thread and needs the channel, which in
/// turn needs the listener's token: one is built first and the other filled in.
private final class ChannelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var channel: BrowserChannel?

    var value: BrowserChannel? {
        get { lock.withLock { channel } }
        set { lock.withLock { channel = newValue } }
    }
}
