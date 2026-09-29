import Foundation

/// Wave 20c D1. What a spoken "yes" may settle. `resolve_approval` is a call
/// the MODEL makes, and any text the model reads (a page, a Slack message)
/// can plant the words that make it call it: so an approval is answered by
/// the user, and the model only gets the requests whose worst case is small.
public enum ApprovalRisk: Sendable, Equatable {
    case low
    case high

    /// Allowlist, not denylist: a tool nobody classified is `high`, so a new
    /// tool needs the sheet's click until someone decides otherwise.
    private static let lowTools: Set<String> = [
        // Has its own host gate; the sheet only confirms the destination.
        ParentTool.openURL.rawValue,
        ParentTool.look.rawValue,
        ParentTool.see.rawValue,
        ParentTool.readFocused.rawValue,
        ParentTool.listApps.rawValue,
        ParentTool.readSkill.rawValue,
        NativeTool.findPlaces.rawValue,
    ]

    public static func of(toolName: String) -> ApprovalRisk {
        lowTools.contains(toolName) ? .low : .high
    }
}
