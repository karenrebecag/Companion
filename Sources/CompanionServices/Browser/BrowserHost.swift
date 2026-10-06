import CompanionCore
import Foundation

/// Wave 18-3c. Owns the browser socket end to end: the listener
/// (`browser.sock`), the channel that speaks to the extension, the presence
/// the tool lists follow, and the install/remove the Settings buttons press.
/// It lives in Services, not the composition root, because nothing in it needs
/// the approval sheet or the session: only the runner does, and it brings its
/// own tickets. That keeps the start condition and the tool lists testable.
package final class BrowserHost: @unchecked Sendable {
    package let presence = BrowserPresence()
    /// Two runners over one channel: each keeps its own page cache and
    /// tickets, so a yes spoken in the conversation cannot be spent by a
    /// bridge peer (and the peer's calls never spend the user's).
    private let conversationRunner: BrowserToolRunner
    private let bridgeRunner: BrowserToolRunner
    /// One lease for both runners: a tab is one, so whoever holds it, the other
    /// caller must see it held.
    private let leases: BrowserLeases
    private static let bridgeCaller = "bridge"
    private let commander: any BrowserCommanding
    private var sweeper: Task<Void, Never>?
    private let sweepEvery: Duration
    private let listener: BridgeListener
    private let installer: NativeHostInstaller
    private let lock = NSLock()
    private var started = false

    package init(
        directory: URL, installer: NativeHostInstaller,
        language: @escaping @Sendable () -> AppLanguage,
        commanding: (any BrowserCommanding)? = nil,
        sweepEvery: Duration = .seconds(30),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sweepEvery = sweepEvery
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
        let leases = BrowserLeases(epoch: presence.epoch, now: now)
        self.leases = leases
        self.commander = commander
        self.conversationRunner = BrowserToolRunner(
            channel: commander, presence: presence, language: language,
            leases: leases, caller: BrowserToolRunner.chatCaller)
        // HACK: the bridge serves one session at a time, so one id covers it.
        // Per-connection ids when the bridge admits several agents at once.
        self.bridgeRunner = BrowserToolRunner(
            channel: commander, presence: presence, language: language,
            leases: leases, caller: Self.bridgeCaller)
    }

    // MARK: Lifecycle

    /// X12: the browser's listener is independent of "lend your hands" and
    /// only exists once the user connected a browser, so a user who never did
    /// has no extra socket open.
    package func startIfInstalled() {
        guard !installer.installed().isEmpty else { return }
        start()
    }

    package func stop() {
        lock.withLock {
            guard started else { return }
            listener.stop()
            sweeper?.cancel()
            sweeper = nil
            started = false
        }
    }

    /// Writes the manifest, then starts listening. A failed install never
    /// leaves a listener behind.
    package func connect() -> BrowserLinkOutcome {
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

    package func remove() -> BrowserLinkOutcome {
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

    package var status: BrowserLinkStatus {
        if installer.installed().isEmpty { return .notInstalled }
        if let browser = presence.browser { return .connected(browser) }
        return .disconnected
    }

    /// The bundle id the connected extension is speaking for, or nil.
    /// Injected into the hands as a `() -> String?` so the guard can
    /// distinguish three states: nobody connected, this browser connected,
    /// a different browser connected.
    package func connectedBundle() -> String? {
        presence.browser.map { Self.bundle(for: $0) }
    }

    /// True only for the bundle ids the host ships manifests for. The web
    /// guard asks this so every other Chromium browser (Brave, Edge, Arc,
    /// Vivaldi, Opera, Chromium...) is refused with a clear
    /// `browser_unsupported` and the agent does not retry it.
    package static func supportsExtension(bundle: String) -> Bool {
        Self.bundle(for: .chrome) == bundle || Self.bundle(for: .comet) == bundle
    }

    /// Which Chromium-family bundle id the connected extension serves.
    /// Chrome covers Chrome's own bundle; the family is wide (Brave, Edge,
    /// Vivaldi, Arc, Chromium, Opera), but each ships its own Companion
    /// extension in the future.
    static func bundle(for kind: BrowserKind) -> String {
        switch kind {
        case .chrome: "com.google.Chrome"
        case .comet: "ai.perplexity.comet"
        }
    }

    /// A name safe to embed in a refusal message: control characters and
    /// newlines can hide a different instruction from the model; a long
    /// name is a place the message can break in surprising ways. The
    /// bundle id is the fallback when the name is missing or empty.
    package static func displayName(name: String?, bundle: String) -> String {
        guard let name else { return bundle }
        let cleaned = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? bundle : String(trimmed.prefix(40))
    }

    /// Display name for a known browser bundle, used for the connected
    /// browser the guard does not have a pid for. Unknown bundles fall
    /// back to the bundle id, which is the same string the agent already
    /// uses to identify the target.
    package static func displayName(forBundle bundle: String) -> String {
        switch bundle {
        case "com.google.Chrome": return "Google Chrome"
        case "ai.perplexity.comet": return "Comet"
        default: return bundle
        }
    }

    /// The bridge's caller id is shared by every session, so a session that
    /// ends (or a new one that starts) must not leave its tabs to the next
    /// client, which would skip the take sheet. The leases clear before this
    /// returns; the returned task finishes telling the extension.
    @discardableResult
    package func bridgeSessionChanged() -> Task<Void, Never> {
        let tabs = leases.releaseAll(owner: Self.bridgeCaller)
        let leases = leases, commander = commander
        return Task.detached { await leases.giveBack(tabs, channel: commander) }
    }

    // MARK: Tool lists

    /// Chat and both voice modes: the parent's tools, the connected apps' and
    /// the browser's.
    package func conversationTools(
        parent: any ParentToolExecuting, apps: any ParentToolExecuting
    ) -> CompositeParentTools {
        CompositeParentTools([parent, apps, conversationRunner])
    }

    /// The bridge lends the hands and the browser, never Karen's connected apps.
    package func bridgeTools(parent: any ParentToolExecuting) -> CompositeParentTools {
        CompositeParentTools([parent, bridgeRunner])
    }

    @discardableResult
    private func start() -> Bool {
        lock.withLock {
            if started { return true }
            do {
                try listener.start()
                started = true
                startSweeper()
            } catch {
                Log.browser("listener: could not start")
            }
            return started
        }
    }
}

extension BrowserHost {
    /// Gives idle tabs back on a clock, not only when someone calls a tool.
    /// Called with `lock` held.
    fileprivate func startSweeper() {
        guard sweeper == nil else { return }
        let leases = leases, commander = commander, presence = presence, every = sweepEvery
        sweeper = Task.detached {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: every)
                } catch {
                    return
                }
                await leases.sweep(channel: commander, epoch: presence.epoch)
            }
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
