import Foundation

/// "Siempre permitir" is bounded to one host and one kind of action: uploading a
/// file to that site. An address is not offered: its query is the channel a
/// payload leaves by, so a host kept open would carry anything sent to it.
package struct AlwaysAllowRule: Sendable, Hashable, Codable {
    package let tool: String
    package let host: String

    package init(tool: String, host: String) {
        self.tool = tool
        self.host = host.lowercased()
    }

    package static func from(_ request: ApprovalRequest) -> AlwaysAllowRule? {
        guard !request.isMCP, request.members.isEmpty else { return nil }
        let arguments = ToolArguments.parse(request.inputJSON) ?? [:]
        switch request.toolName {
        case BrowserTool.setFiles.rawValue:
            guard let host = arguments["host"] as? String, !host.isEmpty else { return nil }
            return AlwaysAllowRule(tool: request.toolName, host: host)
        default:
            return nil
        }
    }
}

/// The rules the user kept, as a value: sorted and without repeats, so the list
/// in Ajustes reads the same however it was built.
package struct AlwaysAllowList: Sendable, Equatable, Codable {
    package private(set) var rules: [AlwaysAllowRule]

    package init(rules: [AlwaysAllowRule] = []) {
        var seen = Set<AlwaysAllowRule>()
        self.rules = rules
            .filter { seen.insert($0).inserted }
            .sorted { ($0.host, $0.tool) < ($1.host, $1.tool) }
    }

    package func allows(_ request: ApprovalRequest) -> Bool {
        guard let rule = AlwaysAllowRule.from(request) else { return false }
        return rules.contains(rule)
    }

    package func adding(_ rule: AlwaysAllowRule) -> AlwaysAllowList {
        AlwaysAllowList(rules: rules + [rule])
    }

    package func removing(_ rule: AlwaysAllowRule) -> AlwaysAllowList {
        AlwaysAllowList(rules: rules.filter { $0 != rule })
    }
}
