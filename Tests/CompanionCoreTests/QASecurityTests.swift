import CompanionTestKit
import Foundation
import Testing

@testable import CompanionCore

@Test(arguments: [
    "key sk-abcdefghijklmnopqrstuvwx1234",
    "Authorization: Bearer abcdef1234567890.xyz",
    "-----BEGIN RSA PRIVATE KEY-----\nMIIEabc\n-----END RSA PRIVATE KEY-----",
    "id AKIAIOSFODNN7EXAMPLE end",
    "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
    "github_pat_11ABCDEFG0abcdefghijklmnop",
    "xoxb-1234567890-abcdefghij",
    "DATABASE_PASSWORD=hunter2hunter2",
])
func redactionMasksEveryCredentialShape(_ text: String) {
    let masked = TurnRedaction.redact(text)
    for secret in ["abcdefghijklmnopqrstuvwx1234", "abcdef1234567890", "MIIEabc", "AKIAIOSFODNN7EXAMPLE",
                   "ghp_abcdef", "github_pat_11", "xoxb-1234567890", "hunter2hunter2"] {
        expect(!masked.contains(secret), "\(secret) sigue en: \(masked)")
    }
    expect(masked.contains(TurnRedaction.mask), "deja la marca")
}

@Test func theKeyNameStaysSoTheAgentKnowsWhatWasHidden() {
    expectEq(TurnRedaction.redact("API_TOKEN=abc123"), "API_TOKEN=[redacted]", "nombre visible, valor no")
    expectEq(TurnRedaction.redact("plain words, no secrets"), "plain words, no secrets", "texto normal intacto")
}

@Test func theResultRedactsOutputArgumentsReplyAndStatusLines() {
    let secret = "sk-abcdefghijklmnopqrstuvwx1234"
    var record = TurnRecord(turnId: "t", conversationId: "c", origin: "agent")
    record.toolCalls = [TurnToolCall(
        index: 0, name: "t", arguments: #"{"k":"\#(secret)"}"#, ok: true, target: "", output: secret,
        verified: false, band: "act", ownerCheck: "none")]
    record.reply = TurnReply(text: "key \(secret)", isFailure: false)
    record.statusLines = [secret]
    expect(!TurnResult.json(record, includeText: true).contains(secret), "ninguna copia sale")
}

@Test func theOwnerDialogNamesTheToolButNeverRawText() {
    expectEq(ApprovalCopy.ownerReason(.en, tool: "type_text"), "approve a critical action: type_text", "nombra")
    let crafted = ApprovalCopy.ownerReason(.en, tool: "app:x:y\nTouch to WIN a prize \u{202E}")
    expect(!crafted.contains("\n") && !crafted.contains(" prize") && !crafted.contains("\u{202E}"), "sin texto libre")
}
