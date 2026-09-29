@testable import CompanionServices
import Foundation
import Testing

// QA 16k-3 (live 2026-09-28): the OpenAI 400 that silenced every Slack turn
// was undiagnosable until the provider's own error prose reached the log.
// What may reach it is the point of this file: the error object's fields,
// never the raw body — bodies echo request fragments and masked keys.

@Test func chatErrorBodySummaryTests() {
    let openAI = #"""
    {"error": {"message": "Invalid schema for function 'x': missing 'channel'.",
     "type": "invalid_request_error", "param": "tools[12].function.parameters",
     "code": "invalid_function_parameters"}}
    """#
    let summary = ChatSSEAttempt.errorSummary(openAI)
    expect(summary?.contains("missing 'channel'") == true,
           "summary: el message del error viaja")
    expect(summary?.contains("type=invalid_request_error") == true,
           "summary: el type viaja etiquetado")
    expect(summary?.contains("param=tools[12]") == true, "summary: el param viaja")

    // A 401 echoes the masked key; even masked, it never reaches the log.
    let leaky = #"{"error":{"message":"Incorrect API key provided: sk-proj-****abcd."}}"#
    let redacted = ChatSSEAttempt.errorSummary(leaky)
    expect(redacted?.contains("abcd") == false, "summary: lo con forma de key se redacta")
    expect(redacted?.contains("sk-…") == true, "summary: queda la marca de redaccion")

    // Long prose is capped; extra fields (metadata, failed_generation) die.
    let flood = #"{"error":{"message":"\#(String(repeating: "a", count: 900))","metadata":{"input_snippet":"secreto"}}}"#
    let capped = ChatSSEAttempt.errorSummary(flood)
    expect((capped?.count ?? 0) <= 340, "summary: el message se corta")
    expect(capped?.contains("secreto") == false, "summary: metadata nunca viaja")

    // Not JSON, or JSON without an error object: nothing to log.
    expect(ChatSSEAttempt.errorSummary("<html>bad gateway</html>") == nil,
           "summary: un body no-JSON no se loguea")
    expect(ChatSSEAttempt.errorSummary(#"{"ok":true}"#) == nil,
           "summary: sin objeto error no hay resumen")

    // A null param (OpenAI sends it) is dropped, not printed as <null>.
    let nullParam = #"{"error":{"message":"m","param":null}}"#
    expect(ChatSSEAttempt.errorSummary(nullParam)?.contains("param") == false,
           "summary: param null se omite")
}
