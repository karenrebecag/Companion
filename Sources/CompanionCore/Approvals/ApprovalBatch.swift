import Foundation

/// The coalescer: the sheets one model step needs become one sheet with a
/// list and one answer. Each member keeps its own request, so each still
/// redeems its own ticket once the batch is approved.
package enum ApprovalBatch {
    /// Only a confirm shares a sheet. A critical keeps its own sheet with its
    /// whole preview, and an MCP request is never folded into a list it could not
    /// be audited in.
    package static func shareable(_ band: ActionBand, isMCP: Bool) -> Bool {
        band == .confirm && !isMCP
    }

    /// The destination a call writes or opens, for spotting two calls on one target.
    package static func target(of request: ApprovalRequest) -> String? {
        let arguments = ToolArguments.parse(request.inputJSON) ?? [:]
        for key in ["path", "url", "host"] {
            if let value = arguments[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// nil below two members: one action keeps the sheet it always had.
    package static func make(members: [ApprovalRequest], requestId: String) -> ApprovalRequest? {
        guard members.count >= 2, !members.contains(where: \.isMCP) else { return nil }
        var batch = ApprovalRequest(
            requestId: requestId, toolName: members[0].toolName,
            summary: members.map(\.summary).joined(separator: "; "), inputJSON: "{}")
        batch.members = members
        return batch
    }

    package static func display(_ members: [ApprovalRequest], language: AppLanguage) -> ApprovalDisplay {
        // Each action's full preview, unshortened: the sheet scrolls, it never cuts what runs.
        let lines = members.map { member -> String in
            let display = ApprovalCopy.display(for: member, language: language)
            return ["• " + display.title, display.preview].compactMap { $0 }.joined(separator: "\n")
        }
        let subject = language == .en
            ? "\(members.count) actions need your OK"
            : "\(members.count) acciones esperan tu permiso"
        return ApprovalDisplay(
            mark: .symbol("checklist"), lead: nil, subject: subject, trail: nil,
            preview: lines.joined(separator: "\n\n"), showsRemember: false)
    }
}
