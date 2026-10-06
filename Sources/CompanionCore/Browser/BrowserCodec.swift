import Foundation

/// Wave 18. JSONL codec for the socket between the relay and the app. The
/// direction is fixed: the extension says hello and answers; only the app
/// calls. An inbound `call` is therefore an error, never a request.
package enum BrowserCodec {
    /// JSONSerialization bridges `true` to 1, so a boolean would pass `as? Int`
    /// as a valid id; it is refused here.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Double(number.intValue) == number.doubleValue ? number.intValue : nil
    }

    private static func fail(_ code: String, _ message: String) -> Result<BrowserInbound, BridgeErrorBody> {
        .failure(BridgeErrorBody(code: code, message: message))
    }

    package static func decode(line: String) -> Result<BrowserInbound, BridgeErrorBody> {
        guard line.utf8.count <= BrowserWire.maxLineBytes else {
            return fail(BridgeCode.frameTooLarge, "Line exceeds \(BrowserWire.maxLineBytes) bytes")
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(line.utf8))
        } catch {
            return fail(BridgeCode.badFrame, "Invalid JSON")
        }
        guard let envelope = parsed as? [String: Any] else {
            return fail(BridgeCode.badFrame, "Invalid JSON")
        }
        if let method = envelope["method"] as? String {
            guard method == "hello" else {
                return fail(BridgeCode.unknownMethod, "Unknown method: \(method)")
            }
            return decodeHello(envelope)
        }
        if let error = envelope["error"] as? [String: Any] {
            guard let code = error["code"] as? String else { return fail(BridgeCode.badFrame, "Invalid error") }
            let body = BridgeErrorBody(
                code: BrowserSanitize.code(code),
                message: BrowserSanitize.message(error["message"] as? String ?? ""),
                reason: BrowserSanitize.reason(error["reason"]))
            return .success(.error(id: integer(envelope["id"]), body))
        }
        guard let id = integer(envelope["id"]) else { return fail(BridgeCode.badFrame, "Missing or invalid id") }
        guard let result = envelope["result"] as? [String: Any] else {
            return fail(BridgeCode.badFrame, "Missing result")
        }
        return decodeResult(id: id, result)
    }

    private static func decodeHello(_ envelope: [String: Any]) -> Result<BrowserInbound, BridgeErrorBody> {
        guard let id = integer(envelope["id"]) else { return fail(BridgeCode.badFrame, "Missing or invalid id") }
        let params = envelope["params"] as? [String: Any] ?? [:]
        guard let ext = params["extension"] as? String, let token = params["token"] as? String,
              let version = params["version"] as? String, let protocolVersion = integer(params["protocol"]),
              let kind = (params["browser"] as? String).flatMap(BrowserKind.init(rawValue:))
        else { return fail(BridgeCode.badFrame, "Invalid hello params") }
        let hello = BrowserHello(
            extensionID: ext, browser: kind, version: version,
            protocolVersion: protocolVersion, token: token)
        return .success(.hello(id: id, hello))
    }

    private static func decodeResult(id: Int, _ result: [String: Any]) -> Result<BrowserInbound, BridgeErrorBody> {
        if let raw = result["page"] as? [String: Any] {
            guard let page = page(raw) else { return fail(BridgeCode.badFrame, "Invalid page") }
            return .success(.page(id: id, page))
        }
        if let raw = result["tabs"] as? [[String: Any]] {
            let tabs = raw.compactMap(tab)
            guard tabs.count == raw.count else { return fail(BridgeCode.badFrame, "Invalid tab") }
            return .success(.tabs(id: id, tabs))
        }
        if let raw = result["tab"] as? [String: Any] {
            guard let opened = tab(raw) else { return fail(BridgeCode.badFrame, "Invalid tab") }
            return .success(.opened(id: id, opened))
        }
        if let done = result["done"] as? String { return .success(.done(id: id, message: BrowserSanitize.done(done))) }
        return fail(BridgeCode.badFrame, "Unknown result")
    }

    private static func tab(_ raw: [String: Any]) -> BrowserTab? {
        guard let id = integer(raw["id"]) else { return nil }
        return BrowserTab(id: id, title: raw["title"] as? String ?? "", url: raw["url"] as? String ?? "",
                          active: raw["active"] as? Bool ?? false,
                          controlled: raw["controlled"] as? Bool ?? false,
                          opener: integer(raw["opener"]),
                          createdAt: (raw["createdAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) },
                          loading: raw["loading"] as? Bool ?? false)
    }

    private static func page(_ raw: [String: Any]) -> BrowserPage? {
        guard let tab = integer(raw["tab"]), let generation = integer(raw["generation"]),
              let origin = raw["origin"] as? String, let url = raw["url"] as? String
        else { return nil }
        let rawElements = raw["elements"] as? [[String: Any]] ?? []
        let elements = rawElements.compactMap(element)
        guard elements.count == rawElements.count else { return nil }
        return BrowserPage(
            tab: tab, origin: origin, url: url, title: raw["title"] as? String ?? "",
            text: raw["text"] as? String ?? "", generation: generation, elements: elements,
            truncated: raw["truncated"] as? Bool ?? false)
    }

    private static func element(_ raw: [String: Any]) -> BrowserElement? {
        guard let id = integer(raw["id"]) else { return nil }
        return BrowserElement(
            id: id, frame: integer(raw["frame"]) ?? 0, role: raw["role"] as? String ?? "",
            label: raw["label"] as? String ?? "", context: raw["context"] as? String ?? "",
            inputType: raw["inputType"] as? String, autocomplete: raw["autocomplete"] as? String,
            value: raw["value"] as? String, frameOrigin: raw["frameOrigin"] as? String,
            href: raw["href"] as? String, fieldName: raw["fieldName"] as? String,
            fieldId: raw["fieldId"] as? String, states: BrowserSanitize.states(raw["states"]),
            submit: raw["submit"] as? String)
    }

    // MARK: Encode

    package static func encode(_ message: BrowserOutbound) -> String {
        let envelope: [String: Any]
        switch message {
        case .helloOK(let id):
            envelope = ["id": id, "result": ["ok": true]]
        case .call(let id, let command):
            let (name, arguments) = wire(command)
            envelope = ["id": id, "method": "call", "params": ["name": name, "arguments": arguments]]
        case .error(let id, let body):
            envelope = ["id": id.map { $0 as Any } ?? NSNull(),
                        "error": ["code": body.code, "message": body.message]]
        }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: envelope, options: [.sortedKeys, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        } catch {
            // Only strings, ints and bools go in; unreachable, and an empty
            // object is dropped by the peer instead of crashing the relay.
            return "{}"
        }
    }

    private static func wire(_ command: BrowserCommand) -> (String, [String: Any]) {
        switch command {
        case .tabs:
            return (BrowserTool.tabs.rawValue, [:])
        case .read(let tab, let query):
            return (BrowserTool.read.rawValue, query.wireArguments.merging(["tab": tab]) { _, tab in tab })
        case .click(let tab, let generation, let element):
            return (BrowserTool.click.rawValue, ["tab": tab, "generation": generation, "element": element])
        case .doubleClick(let tab, let generation, let element):
            return (BrowserTool.doubleClick.rawValue, ["tab": tab, "generation": generation, "element": element])
        case .rightClick(let tab, let generation, let element):
            return (BrowserTool.rightClick.rawValue, ["tab": tab, "generation": generation, "element": element])
        case .type(let tab, let generation, let element, let text):
            return (BrowserTool.type.rawValue,
                    ["tab": tab, "generation": generation, "element": element, "text": text])
        case .select(let tab, let generation, let element, let option):
            return (BrowserTool.select.rawValue,
                    ["tab": tab, "generation": generation, "element": element, "option": option])
        case .scroll(let tab, let dx, let dy):
            return (BrowserTool.scroll.rawValue, ["tab": tab, "dx": dx, "dy": dy])
        case .scrollTo(let tab, let generation, let element):
            return (BrowserTool.scroll.rawValue, ["tab": tab, "generation": generation, "element": element])
        case .hover(let tab, let generation, let element):
            return (BrowserTool.hover.rawValue, ["tab": tab, "generation": generation, "element": element])
        case .press(let tab, let key, let times, let generation, let element):
            return (BrowserTool.press.rawValue,
                    ["tab": tab, "key": key, "times": times,
                     "generation": generation.map { $0 as Any } ?? NSNull(),
                     "element": element.map { $0 as Any } ?? NSNull()])
        case .dragTo(let tab, let generation, let element, let to):
            return (BrowserTool.drag.rawValue, ["tab": tab, "generation": generation, "element": element, "to": to])
        case .dragBy(let tab, let generation, let element, let dx, let dy):
            return (BrowserTool.drag.rawValue,
                    ["tab": tab, "generation": generation, "element": element, "dx": dx, "dy": dy])
        case .clickAt(let tab, let generation, let x, let y):
            return (BrowserTool.clickAt.rawValue, ["tab": tab, "generation": generation, "x": x, "y": y])
        case .navigate(let tab, let url):
            return (BrowserTool.navigate.rawValue, ["tab": tab, "url": url.absoluteString])
        case .open(let url):
            return (BrowserTool.open.rawValue, ["url": url.absoluteString])
        case .take(let tab):
            return (BrowserTool.take.rawValue, ["tab": tab])
        case .release(let tab):
            return (BrowserTool.release.rawValue, ["tab": tab])
        }
    }
}
