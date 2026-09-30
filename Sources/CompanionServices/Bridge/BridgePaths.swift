import Foundation

/// The one place that knows where the local sockets live, so the app that
/// listens and the relay process that connects cannot drift apart.
package enum BridgePaths {
    package static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/bridge")
    }
}
