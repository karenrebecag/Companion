import Foundation

/// Wave 18b. Who may use which tab, as Incredible's ownership.js decides it:
/// a tab is used only by the caller that owns it, and an owner that went
/// quiet loses it. Pure value; the clock is always passed in.
package struct BrowserLease: Sendable, Equatable {
    /// Another caller may take a tab whose owner has not acted for this long.
    package static let takeoverAfter: TimeInterval = 120
    /// A tab nobody used for this long goes back to the user.
    package static let idleRelease: TimeInterval = 600
    /// A tab opened by a controlled page is the page owner's if it was born
    /// within this long after that owner last acted.
    package static let spawnWindow: TimeInterval = 10

    package enum Denial: Sendable, Equatable {
        case notControlled
        case busy
    }

    private struct Entry: Sendable, Equatable {
        var owner: String
        var lastActed: Date
        var sequence: Int
    }

    private var entries: [Int: Entry] = [:]
    /// Counts acquisitions. A tab listing is stamped with it when asked for, so
    /// a reply that was true before a tab was acquired cannot drop that tab.
    package private(set) var sequence = 0

    package init() {}

    /// The live owner: an entry idle past `idleRelease` counts as absent even
    /// before the sweep clears it, or a stale owner would skip the take sheet.
    package func owner(of tab: Int, now: Date) -> String? { live(tab, now: now)?.owner }

    /// Nil means the caller may proceed. `allowTake` is for `browser_take`
    /// only: it lets an unowned or long-idle tab be claimed, never one whose
    /// owner is still active.
    package func authorize(tab: Int, caller: String, now: Date, allowTake: Bool) -> Denial? {
        // WHY an expired entry counts as absent here: the sweep that clears it
        // runs on a timer, and a stale owner must not keep a tab in between.
        guard let entry = live(tab, now: now) else { return allowTake ? nil : .notControlled }
        if entry.owner == caller { return nil }
        let idle = now.timeIntervalSince(entry.lastActed)
        return allowTake && idle >= Self.takeoverAfter ? nil : .busy
    }

    package mutating func acquire(tab: Int, caller: String, now: Date) {
        sequence += 1
        entries[tab] = Entry(owner: caller, lastActed: now, sequence: sequence)
    }

    /// Only the owner's own act keeps the tab warm; a denied caller's does not.
    package mutating func touch(tab: Int, caller: String, now: Date) {
        guard var entry = entries[tab], entry.owner == caller else { return }
        entry.lastActed = now
        entries[tab] = entry
    }

    package mutating func release(tab: Int) { entries[tab] = nil }

    package mutating func releaseAll() { entries.removeAll() }

    /// Drops what one caller holds and returns the tabs so the extension can
    /// be told; used when a bridge session ends and the next is a stranger.
    package mutating func releaseAll(owner: String) -> [Int] {
        let held = entries.filter { $0.value.owner == owner }.keys.sorted()
        for tab in held { entries[tab] = nil }
        return held
    }

    /// A tab the browser no longer lists cannot be controlled; its id could be
    /// reused by nothing, but the entry would keep a caller's claim alive.
    /// `asOf` is `sequence` when the listing was requested: a tab acquired
    /// after that is one the listing could not know, so it stays.
    package mutating func prune(keeping present: Set<Int>, asOf: Int) {
        entries = entries.filter { present.contains($0.key) || $0.value.sequence > asOf }
    }

    /// Drops every tab idle for `idleRelease` and returns them so the caller
    /// can tell the extension to give them back.
    package mutating func expire(now: Date) -> [Int] {
        let stale = entries.filter { now.timeIntervalSince($0.value.lastActed) >= Self.idleRelease }.keys.sorted()
        for tab in stale { entries[tab] = nil }
        return stale
    }

    /// The owner a tab inherits from the page that opened it, or nil. Never
    /// for a browser-internal or new-tab page: those are the user's. Never for
    /// another origin either: a controlled page can `window.open` any site, and
    /// adopting it would hand the agent that site's session without consent.
    package func spawnOwner(of tab: BrowserTab, openerURL: String, now: Date) -> String? {
        guard entries[tab.id] == nil, let opener = tab.opener, let created = tab.createdAt,
              let parent = live(opener, now: now), !Self.isInternal(tab.url),
              !openerURL.isEmpty, BrowserPolicy.sameOrigin(tab.url, openerURL)
        else { return nil }
        let after = created.timeIntervalSince(parent.lastActed)
        return after >= 0 && after <= Self.spawnWindow ? parent.owner : nil
    }

    private func live(_ tab: Int, now: Date) -> Entry? {
        guard let entry = entries[tab], now.timeIntervalSince(entry.lastActed) < Self.idleRelease else { return nil }
        return entry
    }

    private static func isInternal(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return lowered.isEmpty || lowered.hasPrefix("chrome://") || lowered.hasPrefix("chrome-search://")
            || lowered.hasPrefix("edge://") || lowered.hasPrefix("about:") || lowered.contains("newtab")
    }
}
