import CompanionCore
import Foundation

/// Wave 18b. The one `BrowserLease` of a browser, behind a lock and a clock.
/// It is shared by the conversation's runner and the bridge's because a tab
/// is one: whoever holds it, both must see the same owner. The lease itself
/// is pure; this only adds the epoch reset and the sweep.
final class BrowserLeases: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: @Sendable () -> Date
    private var lease = BrowserLease()
    private var seenEpoch: Int
    /// The last full listing, for the synchronous gate to foresee adoption.
    private var listing: [BrowserTab] = []

    init(epoch: Int, now: @escaping @Sendable () -> Date = { Date() }) {
        self.seenEpoch = epoch
        self.clock = now
    }

    /// A reconnect means the extension dissolved its group at disconnect, so
    /// nobody controls anything any more. Called from every runner entry.
    func sync(epoch: Int) {
        lock.withLock {
            guard epoch != seenEpoch else { return }
            seenEpoch = epoch
            lease.releaseAll()
            listing = []
        }
    }

    func owner(of tab: Int) -> String? { lock.withLock { lease.owner(of: tab, now: clock()) } }

    func authorize(tab: Int, caller: String, allowTake: Bool) -> BrowserLease.Denial? {
        lock.withLock { lease.authorize(tab: tab, caller: caller, now: clock(), allowTake: allowTake) }
    }

    func acquire(tab: Int, caller: String) {
        lock.withLock { lease.acquire(tab: tab, caller: caller, now: clock()) }
    }

    func touch(tab: Int, caller: String) {
        lock.withLock { lease.touch(tab: tab, caller: caller, now: clock()) }
    }

    func release(tab: Int) { lock.withLock { lease.release(tab: tab) } }

    func spawnOwner(of tab: Int, in tabs: [BrowserTab]) -> String? {
        lock.withLock { spawnOwnerLocked(of: tab, in: tabs) }
    }

    /// Who would inherit `tab` per the last listing seen, without asking the
    /// browser: lets the gate judge a child on its first write.
    func foreseenSpawnOwner(of tab: Int) -> String? {
        lock.withLock { spawnOwnerLocked(of: tab, in: listing) }
    }

    private func spawnOwnerLocked(of tab: Int, in tabs: [BrowserTab]) -> String? {
        guard let candidate = tabs.first(where: { $0.id == tab }), let opener = candidate.opener,
              let openerURL = tabs.first(where: { $0.id == opener })?.url
        else { return nil }
        return lease.spawnOwner(of: candidate, openerURL: openerURL, now: clock())
    }

    /// Taken before asking the browser for its tabs; see `noteListing`.
    var sequence: Int { lock.withLock { lease.sequence } }

    /// A tab missing from a full listing no longer exists, unless it was
    /// acquired after the listing was requested (`asOf`).
    func noteListing(_ tabs: [BrowserTab], asOf: Int) {
        lock.withLock {
            lease.prune(keeping: Set(tabs.map(\.id)), asOf: asOf)
            listing = tabs
        }
    }

    /// Synchronous on purpose: the next session's first call must already
    /// find the tabs unowned. Telling the extension follows in `giveBack`.
    func releaseAll(owner: String) -> [Int] { lock.withLock { lease.releaseAll(owner: owner) } }

    func giveBack(_ tabs: [Int], channel: any BrowserCommanding) async {
        for tab in tabs {
            // WHY: this runs detached, so a new session may have taken the tab
            // since; releasing it now would undo that take.
            guard owner(of: tab) == nil else { continue }
            if case .failure(let error) = await channel.send(.release(tab: tab), timeout: BrowserToolRunner.actTimeout) {
                Log.browser("release code=\(error.code)")
            }
        }
    }

    /// Gives back what sat idle for ten minutes. HACK: driven by the host's
    /// timer, so a tab can stay grouped up to one tick past the limit; a push
    /// from the extension would be exact.
    func sweep(channel: any BrowserCommanding, epoch: Int) async {
        sync(epoch: epoch)
        let stale = lock.withLock { lease.expire(now: clock()) }
        await giveBack(stale, channel: channel)
    }
}
