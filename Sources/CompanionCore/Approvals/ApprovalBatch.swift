import Foundation

/// The coalescer: the sheets one model step needs become one sheet with a
/// list and one answer. Each member keeps its own request, so each still
/// redeems its own ticket once the batch is approved.
package enum ApprovalBatch {
    /// nil below two members: one action keeps the sheet it always had, and an
    /// MCP request is never folded into a list it could not be audited in.
    package static func make(members: [ApprovalRequest], requestId: String) -> ApprovalRequest? {
        guard members.count >= 2, !members.contains(where: \.isMCP) else { return nil }
        var batch = ApprovalRequest(
            requestId: requestId, toolName: members[0].toolName,
            summary: members.map(\.summary).joined(separator: "; "), inputJSON: "{}")
        batch.members = members
        return batch
    }

    package static func display(_ members: [ApprovalRequest], language: AppLanguage) -> ApprovalDisplay {
        let lines = members.map { "• " + ApprovalCopy.display(for: $0, language: language).title }
        let subject = language == .en
            ? "\(members.count) actions need your OK"
            : "\(members.count) acciones esperan tu permiso"
        return ApprovalDisplay(
            mark: .symbol("checklist"), lead: nil, subject: subject, trail: nil,
            preview: lines.joined(separator: "\n"), showsRemember: false)
    }
}
