import CompanionCore
import Foundation
import Network

/// Optimistic by default: a false "no internet" is worse than one failed
/// attempt, so the probe only reports offline once the path monitor says so.
public final class NetworkReachability: ReachabilityProbing, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.withLock { online = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "companion.reachability"))
    }

    deinit { monitor.cancel() }

    public var isOnline: Bool {
        get async { current() }
    }

    // withLock keeps the critical section out of the async context.
    private func current() -> Bool {
        lock.withLock { online }
    }
}

/// For composition roots and tests that never go to the network.
public struct AssumeOnline: ReachabilityProbing {
    public init() {}
    public var isOnline: Bool { get async { true } }
}
