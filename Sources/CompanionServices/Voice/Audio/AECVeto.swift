import Foundation

/// Remembers that Voice Processing cannot start on this machine, across app
/// launches. See MicCapture for why the prototype made this persistent.
public protocol AECVetoStoring: Sendable {
    var isVetoed: Bool { get nonmutating set }
}

public struct UserDefaultsAECVeto: AECVetoStoring {
    private static let key = "companion.aecVetoed"
    public init() {}
    public var isVetoed: Bool {
        get { UserDefaults.standard.bool(forKey: Self.key) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.key) }
    }
}

/// Test double; also useful for composition roots that never want AEC.
public final class InMemoryAECVeto: AECVetoStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool
    public init(_ initial: Bool = false) { value = initial }
    public var isVetoed: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
