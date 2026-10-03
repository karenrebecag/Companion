import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Audit M6: the constraints the hello declares are checked again where the
// call lands, so a client that skips the shim gets the same refusal.

private let typeText = ParentTool.typeText.spec(.en)
private let scroll = ParentTool.scroll.spec(.en)

@Test func aCallShapedLikeTheShimsPasses() {
    expect(BridgeArguments.violation(#"{"text":"hola"}"#, spec: typeText) == nil, "type_text: declared key")
    expect(BridgeArguments.violation(#"{"direction":"down","id":3}"#, spec: scroll) == nil, "scroll: both keys")
    expect(BridgeArguments.violation(#"{"direction":"up"}"#, spec: scroll) == nil, "scroll: optional left out")
    let exact = String(repeating: "a", count: ToolProperty.maxTextBytes)
    expect(BridgeArguments.violation(#"{"text":"\#(exact)"}"#, spec: typeText) == nil, "type_text: at the cap")
}

@Test func anUnknownKeyIsRefusedByName() {
    let out = BridgeArguments.violation(#"{"txet":"hola"}"#, spec: typeText)
    expectEq(out, "type_text: unknown argument `txet`", "the misspelled key is named")
}

@Test func typedTextOutsideItsBytesIsRefused() {
    let message = "type_text: `text` must contain 1-16000 UTF-8 bytes and no NUL"
    expectEq(BridgeArguments.violation(#"{"text":""}"#, spec: typeText), message, "empty")
    let euros = String(repeating: "€", count: 5_334)
    expectEq(BridgeArguments.violation(#"{"text":"\#(euros)"}"#, spec: typeText), message,
             "16002 bytes in 5334 characters: counted in bytes")
    expectEq(BridgeArguments.violation(#"{"text":"a\u0000b"}"#, spec: typeText), message, "NUL")
}

@Test func aDirectionOutsideTheEnumIsRefused() {
    expectEq(BridgeArguments.violation(#"{"direction":"sideways"}"#, spec: scroll),
             "scroll: `direction` must be one of: up, down, left, right, into_view", "names the choices")
}

@Test func aNULIsRefusedInAnyTopLevelString() {
    let menu = ParentTool.menu.spec(.en)
    expectEq(BridgeArguments.violation(#"{"path":"File\u0000"}"#, spec: menu),
             "menu: `path` must contain no NUL", "undeclared limits still refuse NUL")
}

@Test func theBrowsersTypedTextCarriesTheSameLimit() {
    let spec = BrowserTool.type.spec(.en)
    let text = spec.properties.first { $0.name == "text" }
    expectEq(text?.minLength, 1, "browser_type: at least one character")
    expectEq(text?.maxBytes, ToolProperty.maxTextBytes, "browser_type: Incredible's text limit")
}

@Test func thePressKeysAreAnAllowlistInTheHello() {
    let spec = BrowserTool.press.spec(.en)
    let key = spec.properties.first { $0.name == "key" }
    expectEq(key?.allowed, BrowserTool.pressKeys, "browser_press: only the listed keys")
    expectEq(BrowserTool.pressKeys, ["Enter", "Escape", "Tab", "Shift+Tab", "ArrowUp", "ArrowDown", "ArrowLeft",
                                     "ArrowRight", "Space", "Backspace", "Delete", "Home", "End", "PageUp", "PageDown"],
             "the same list as wire.js PRESS_KEYS")
    expectEq(spec.required, ["tab", "key"], "element and times are optional")
    expectEq(BridgeArguments.violation(#"{"tab":1,"key":"F5"}"#, spec: spec),
             "browser_press: `key` must be one of: " + BrowserTool.pressKeys.joined(separator: ", "), "F5 is refused")
}

@Test func theLimitsAreTheSameInEveryLanguage() {
    for language in [AppLanguage.en, .es] {
        let text = ParentTool.typeText.spec(language).properties.first
        expectEq(text?.maxBytes, ToolProperty.maxTextBytes, "\(language): type_text cap")
        let direction = ParentTool.scroll.spec(language).properties.first { $0.name == "direction" }
        expectEq(direction?.allowed, ["up", "down", "left", "right", "into_view"], "\(language): scroll enum")
    }
}

@Test func theHelloCarriesTheConstraintsOnlyWhereDeclared() throws {
    let data = try JSONEncoder().encode([BridgeToolSpec(typeText), BridgeToolSpec(scroll)])
    let specs = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    let properties = specs.compactMap { $0["properties"] as? [[String: Any]] }
    let text = properties[0][0]
    expectEq(text["minLength"] as? Int, 1, "hello: minLength")
    expectEq(text["maxBytes"] as? Int, ToolProperty.maxTextBytes, "hello: maxBytes")
    expect(text["enum"] == nil, "hello: no enum where none is declared")
    let direction = properties[1].first { $0["name"] as? String == "direction" }
    expectEq(direction?["enum"] as? [String], ["up", "down", "left", "right", "into_view"], "hello: enum")
    let id = properties[1].first { $0["name"] as? String == "id" }
    expectEq(Set(id?.keys.map { $0 } ?? []), ["name", "type", "description"], "hello: a plain property is unchanged")
}

/// Every real schema accepts a call built from its own declared keys, so
/// the check never refuses what the shim is told it may send.
@Test func everyRealSpecAcceptsItsOwnShape() {
    let specs = [AppLanguage.en, .es].flatMap { language in
        ParentTool.allCases.map { $0.spec(language) } + BrowserTool.allCases.map { $0.spec(language) }
    }
    for spec in specs {
        var arguments: [String: Any] = [:]
        for property in spec.properties {
            switch property.type {
            case "string": arguments[property.name] = property.allowed?.first ?? "x"
            case "integer", "number": arguments[property.name] = 1
            case "boolean": arguments[property.name] = true
            default: break
            }
        }
        let data = try! JSONSerialization.data(withJSONObject: arguments)
        let json = String(data: data, encoding: .utf8)!
        expect(BridgeArguments.violation(json, spec: spec) == nil, "\(spec.name): \(json)")
    }
}

@Test func typesAndUnparseableArgumentsAreLeftToTheRunner() {
    expect(BridgeArguments.violation(#"{"text":123}"#, spec: typeText) == nil, "a number in a string slot: the runner's call")
    expect(BridgeArguments.violation("not json", spec: typeText) == nil, "the codec already refuses a non-object")
}

@Test func theBrowsersLimitIsInEveryLanguageAndTheHello() throws {
    for language in [AppLanguage.en, .es] {
        let spec = BrowserTool.type.spec(language)
        let data = try JSONEncoder().encode(BridgeToolSpec(spec))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let text = (object["properties"] as? [[String: Any]])?.first { $0["name"] as? String == "text" }
        expectEq(text?["maxBytes"] as? Int, ToolProperty.maxTextBytes, "\(language): browser_type in the hello")
        expectEq(text?["minLength"] as? Int, 1, "\(language): at least one character")
    }
}

@Test func anEchoedKeyIsCapped() {
    let key = String(repeating: "k", count: 500)
    let out = BridgeArguments.violation(#"{"\#(key)":"x"}"#, spec: typeText) ?? ""
    expect(out.hasPrefix("type_text: unknown argument `") && out.count < 120, "the caller's key is not echoed whole: \(out.count)")
}
