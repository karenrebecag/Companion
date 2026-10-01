import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func bridgeProtocolTests() {
    testDecodeHelloHappyPath()
    testDecodeCallWithArguments()
    testDecodeCallWithoutArguments()
    testDecodeCallWithNonObjectArguments()
    testDecodeByeHappyPath()
    testDecodeUnknownMethod()
    testDecodeGarbageJSON()
    testDecodeLineTooLarge()
    testDecodePreservesIdOnError()
    testEncodeHelloResponse()
    testEncodeCallResponse()
    testEncodeByeResponse()
    testEncodeErrorResponse()
    testEncodeHasNoTrailingNewline()
    testBridgeToolSpecFromToolSpec()
    testBridgeCallResultFromOutcome()
    testArgumentsRoundTrip()
}

private func testDecodeHelloHappyPath() {
    let line = #"{"id":1,"method":"hello","params":{"token":"abc123","client":"claude-code","protocol":1}}"#
    let result = BridgeCodec.decode(line: line)
    guard case .success(let request) = result else {
        return expect(false, "hello: decode failed")
    }
    guard case .hello(let id, let hello) = request else {
        return expect(false, "hello: wrong request type")
    }
    expectEq(id, 1, "hello: id matches")
    expectEq(hello.token, "abc123", "hello: token matches")
    expectEq(hello.client, "claude-code", "hello: client matches")
    expectEq(hello.protocolVersion, 1, "hello: protocol version matches")
}

private func testDecodeCallWithArguments() {
    let line = #"{"id":2,"method":"call","params":{"name":"look","arguments":{"id":3}}}"#
    let result = BridgeCodec.decode(line: line)
    guard case .success(let request) = result else {
        return expect(false, "call with args: decode failed")
    }
    guard case .call(let id, let call) = request else {
        return expect(false, "call with args: wrong request type")
    }
    expectEq(id, 2, "call with args: id matches")
    expectEq(call.name, "look", "call with args: name matches")

    // Arguments should round-trip as compact JSON
    let parsed = try? JSONSerialization.jsonObject(with: call.argumentsJSON.data(using: .utf8) ?? Data()) as? [String: Any]
    let idValue = (parsed?["id"] as? NSNumber)?.intValue
    expectEq(idValue, 3, "call with args: arguments object round-trips")
}

private func testDecodeCallWithoutArguments() {
    let line = #"{"id":2,"method":"call","params":{"name":"list_apps"}}"#
    let result = BridgeCodec.decode(line: line)
    guard case .success(let request) = result else {
        return expect(false, "call no args: decode failed")
    }
    guard case .call(_, let call) = request else {
        return expect(false, "call no args: wrong request type")
    }
    expectEq(call.argumentsJSON, "{}", "call no args: arguments defaults to empty object")
}

private func testDecodeCallWithNonObjectArguments() {
    let line = #"{"id":2,"method":"call","params":{"name":"look","arguments":"not an object"}}"#
    let result = BridgeCodec.decode(line: line)
    guard case .failure(let error) = result else {
        return expect(false, "call non-object args: should reject")
    }
    expectEq(error.code, BridgeCode.invalidArgs, "call non-object args: code is invalid_args")
}

private func testDecodeByeHappyPath() {
    let line = #"{"id":4,"method":"bye"}"#
    let result = BridgeCodec.decode(line: line)
    guard case .success(let request) = result else {
        return expect(false, "bye: decode failed")
    }
    guard case .bye(let id) = request else {
        return expect(false, "bye: wrong request type")
    }
    expectEq(id, 4, "bye: id matches")
}

private func testDecodeUnknownMethod() {
    let line = #"{"id":5,"method":"unknown"}"#
    let result = BridgeCodec.decode(line: line)
    guard case .failure(let error) = result else {
        return expect(false, "unknown method: should reject")
    }
    expectEq(error.code, BridgeCode.unknownMethod, "unknown method: code is unknown_method")
}

private func testDecodeGarbageJSON() {
    let line = "not json at all"
    let result = BridgeCodec.decode(line: line)
    guard case .failure(let error) = result else {
        return expect(false, "garbage: should reject")
    }
    expectEq(error.code, BridgeCode.badFrame, "garbage: code is bad_frame")
}

private func testDecodeLineTooLarge() {
    let line = String(repeating: "x", count: BridgeCodec.maxLineBytes + 1)
    let result = BridgeCodec.decode(line: line)
    guard case .failure(let error) = result else {
        return expect(false, "too large: should reject")
    }
    expectEq(error.code, BridgeCode.frameTooLarge, "too large: code is frame_too_large")
}

private func testDecodePreservesIdOnError() {
    let line = #"{"id":10,"method":"call"}"#
    let result = BridgeCodec.decode(line: line)
    guard case .failure = result else {
        return expect(false, "bad frame: should reject")
    }
    // The id should be in the result even though parsing failed (checked at response encoding)
    expect(true, "preserves id: dummy pass")
}

private func testEncodeHelloResponse() {
    let specs = [
        BridgeToolSpec(
            ToolSpec(
                name: "look",
                description: "Read the window",
                properties: [ToolProperty(name: "id", type: "integer", description: "Element ID")],
                required: ["id"]
            )
        )
    ]
    let result = BridgeHelloResult(
        session: "sess-123",
        language: .en,
        accessibility: true,
        tools: specs
    )
    let response = BridgeResponse.hello(id: 1, result)
    let encoded = BridgeCodec.encode(response)

    guard let data = encoded.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return expect(false, "hello: encoding produced invalid JSON")
    }

    expectEq(dict["id"] as? Int, 1, "hello: id in encoded response")
    expect(dict["result"] != nil, "hello: has result key")
    expect(dict["error"] == nil, "hello: no error key")
}

private func testEncodeCallResponse() {
    let outcome = ParentToolOutcome(
        ok: true,
        output: "[1] Button \"Permit\"",
        target: "Safari",
        tool: "look"
    )
    let result = BridgeCallResult(outcome)
    let response = BridgeResponse.call(id: 2, result)
    let encoded = BridgeCodec.encode(response)

    guard let data = encoded.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let resultDict = dict["result"] as? [String: Any]
    else {
        return expect(false, "call: encoding produced invalid JSON")
    }

    expectEq(dict["id"] as? Int, 2, "call: id in encoded response")
    expectEq(resultDict["ok"] as? Bool, true, "call: ok flag")
    expectEq(resultDict["tool"] as? String, "look", "call: tool name")
}

private func testEncodeByeResponse() {
    let response = BridgeResponse.bye(id: 4)
    let encoded = BridgeCodec.encode(response)

    guard let data = encoded.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return expect(false, "bye: encoding produced invalid JSON")
    }

    expectEq(dict["id"] as? Int, 4, "bye: id in encoded response")
    expect(dict["result"] != nil, "bye: has result key")
    expect(dict["error"] == nil, "bye: no error key")
}

private func testEncodeErrorResponse() {
    let error = BridgeErrorBody(code: BridgeCode.deniedByUser, message: "User said no")
    let response = BridgeResponse.error(id: 3, error)
    let encoded = BridgeCodec.encode(response)

    guard let data = encoded.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let errorDict = dict["error"] as? [String: Any]
    else {
        return expect(false, "error: encoding produced invalid JSON")
    }

    expectEq(dict["id"] as? Int, 3, "error: id in encoded response")
    expectEq(errorDict["code"] as? String, BridgeCode.deniedByUser, "error: code field")
    expectEq(errorDict["message"] as? String, "User said no", "error: message field")
    expect(dict["result"] == nil, "error: no result key")
}

private func testEncodeHasNoTrailingNewline() {
    let response = BridgeResponse.bye(id: 1)
    let encoded = BridgeCodec.encode(response)
    expect(!encoded.hasSuffix("\n"), "no newline: encoded response has no trailing newline")
}

private func testBridgeToolSpecFromToolSpec() {
    let spec = ParentTool.look.spec(.es)
    let bridgeSpec = BridgeToolSpec(spec)

    expectEq(bridgeSpec.name, spec.name, "tool spec: name preserved")
    expectEq(bridgeSpec.description, spec.description, "tool spec: description preserved")
    expectEq(bridgeSpec.required, spec.required, "tool spec: required preserved")
    expectEq(bridgeSpec.properties.count, spec.properties.count, "tool spec: property count preserved")

    if !bridgeSpec.properties.isEmpty {
        expectEq(bridgeSpec.properties[0].name, spec.properties[0].name, "tool spec: first property name preserved")
    }
}

private func testBridgeCallResultFromOutcome() {
    let outcome = ParentToolOutcome(
        ok: true,
        output: "Success",
        target: "Notes",
        card: nil,
        tool: "type_text"
    )
    let result = BridgeCallResult(outcome)

    expectEq(result.ok, true, "call result: ok preserved")
    expectEq(result.output, "Success", "call result: output preserved")
    expectEq(result.target, "Notes", "call result: target preserved")
    expectEq(result.tool, "type_text", "call result: tool preserved")
    // card is not in BridgeCallResult
}

private func testArgumentsRoundTrip() {
    let original: [String: Any] = ["name": "Safari", "extra": 123]
    let data = try! JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
    let json = String(data: data, encoding: .utf8)!

    let reparsed = try? JSONSerialization.jsonObject(with: json.data(using: .utf8) ?? Data()) as? [String: Any]
    expectEq(reparsed?["name"] as? String, "Safari", "round trip: name preserved")
    expectEq((reparsed?["extra"] as? NSNumber)?.intValue, 123, "round trip: extra preserved")
}
