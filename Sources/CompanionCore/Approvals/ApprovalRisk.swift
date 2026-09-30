import Foundation

/// Wave 20c D1. What a spoken "yes" may settle. `resolve_approval` is a call
/// the MODEL makes, and any text the model reads (a page, a Slack message)
/// can plant the words that make it call it: so an approval is answered by
/// the user, and the model only gets the requests whose worst case is small.
package enum ApprovalRisk: Sendable, Equatable {
    case low
    case high

    /// Allowlist, not denylist: a tool nobody classified is `high`, so a new
    /// tool needs the sheet's click until someone decides otherwise.
    private static let lowTools: Set<String> = [
        // open_url is NOT here: the gate raises its sheet only for a host the
        // user never said, so a spoken yes there opens an un-said host — the
        // exfil sink. It takes the click.
        ParentTool.look.rawValue,
        ParentTool.see.rawValue,
        ParentTool.readFocused.rawValue,
        ParentTool.listApps.rawValue,
        ParentTool.readSkill.rawValue,
        NativeTool.findPlaces.rawValue,
    ]

    package static func of(toolName: String) -> ApprovalRisk {
        lowTools.contains(toolName) ? .low : .high
    }
}
