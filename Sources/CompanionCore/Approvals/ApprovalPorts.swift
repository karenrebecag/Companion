import Foundation

/// One number, two readers: the actor that denies on the deadline and the
/// sheet's countdown ring must agree, or the ring lies (19-1b).
public enum ApprovalTiming {
    /// 60, was 120: two minutes of ring read as forever (Karen, 19-1c).
    public static let autoDeny: TimeInterval = 60
}

/// The user's answer to a permission request. `remember` is the sheet's
/// toggle (Wave 10c 3B.3): keep this decision for the session.
public struct ApprovalResponse: Sendable, Equatable {
    public var requestId: String
    public var approved: Bool
    public var remember: Bool
    /// The deadline denied it, nobody answered: a caller that counts refusals
    /// (the bridge's cool-down) must not count silence as one.
    public var timedOut: Bool

    public init(requestId: String, approved: Bool, remember: Bool = false, timedOut: Bool = false) {
        self.requestId = requestId
        self.approved = approved
        self.remember = remember
        self.timedOut = timedOut
    }
}

/// Where a permission is asked and answered. In Core since Wave 10c: the
/// chat layer gates `open_url` through the same actor the specialist uses,
/// and the chat layer cannot see Services.
public protocol ApprovalsProvider: Sendable {
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse
    func resolve(requestId: String, approved: Bool) async -> Bool
    /// `remember` keeps the decision for the process's life, keyed by
    /// `ApprovalKey`. Providers without a memory take the default.
    func resolve(requestId: String, approved: Bool, remember: Bool) async -> Bool
    /// A decision already taken for this request's key, or nil to ask.
    func remembered(_ approval: ApprovalRequest) async -> Bool?
}

extension ApprovalsProvider {
    public func resolve(requestId: String, approved: Bool, remember: Bool) async -> Bool {
        await resolve(requestId: requestId, approved: approved)
    }

    public func remembered(_ approval: ApprovalRequest) async -> Bool? { nil }
}
