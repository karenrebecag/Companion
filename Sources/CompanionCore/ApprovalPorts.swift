import Foundation

/// The user's answer to a permission request. `remember` is the sheet's
/// toggle (Wave 10c 3B.3): keep this decision for the session.
public struct ApprovalResponse: Sendable, Equatable {
    public var requestId: String
    public var approved: Bool
    public var remember: Bool

    public init(requestId: String, approved: Bool, remember: Bool = false) {
        self.requestId = requestId
        self.approved = approved
        self.remember = remember
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
