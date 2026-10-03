import Foundation

/// Wave 18. The browser wire, in two framings of the same JSON: native
/// messaging on the extension side (uint32 little-endian length + body) and
/// JSONL on the app's socket. Pure shapes; the relay and the channel actor
/// live in Services.

package enum BrowserWire {
    /// Chrome's own ceiling for a message from a native host is 1 MB; the
    /// same number bounds what we accept from the extension.
    package static let maxNativeBytes = 1_048_576
    /// The socket line is capped like the bridge's (BridgeListener closes on
    /// a longer one), so the relay must never forward more than this.
    package static let maxLineBytes = BridgeCodec.maxLineBytes
}

package enum BrowserWireError: Error, Sendable, Equatable {
    case frameTooLarge(Int)
    case truncated
    case badJSON
}

// MARK: - Native framing

/// Incremental decoder for the stdio side. Bytes arrive in arbitrary chunks;
/// complete frames come out. After an oversize prefix the stream cannot be
/// resynchronised, so the decoder stays poisoned instead of guessing.
package struct NativeFrameDecoder: Sendable {
    private let limit: Int
    private var buffer = Data()
    private var poisoned = false

    package init(limit: Int = BrowserWire.maxNativeBytes) {
        self.limit = limit
    }

    /// Frames are read through a cursor and the consumed prefix is dropped
    /// once per push, so a push carrying many frames is linear, not quadratic.
    package mutating func push(_ bytes: Data) -> [Result<Data, BrowserWireError>] {
        guard !poisoned else { return [] }
        buffer.append(bytes)
        var out: [Result<Data, BrowserWireError>] = []
        var cursor = buffer.startIndex
        while buffer.endIndex - cursor >= 4 {
            let length = (0..<4).reduce(0) { $0 | Int(buffer[cursor + $1]) << (8 * $1) }
            if length > limit {
                poisoned = true
                buffer = Data()
                out.append(.failure(.frameTooLarge(length)))
                return out
            }
            let end = cursor + 4 + length
            guard buffer.endIndex >= end else { break }
            out.append(.success(Data(buffer[(cursor + 4)..<end])))
            cursor = end
        }
        buffer = Data(buffer[cursor...])
        return out
    }

    /// Called at EOF: leftover bytes mean the peer died mid-frame, which the
    /// caller must treat as an error instead of waiting for the rest.
    package func finish() -> BrowserWireError? {
        !poisoned && !buffer.isEmpty ? .truncated : nil
    }
}

package enum NativeFrameEncoder {
    package static func encode(_ json: Data) throws(BrowserWireError) -> Data {
        guard json.count <= BrowserWire.maxNativeBytes else { throw .frameTooLarge(json.count) }
        let length = UInt32(json.count)
        let prefix = Data((0..<4).map { UInt8(truncatingIfNeeded: length >> (8 * UInt32($0))) })
        return prefix + json
    }
}

// MARK: - Messages

package enum BrowserKind: String, Sendable, Codable {
    case chrome
    case comet
}

package struct BrowserHello: Sendable, Equatable {
    package var extensionID: String
    package var browser: BrowserKind
    package var version: String
    package var protocolVersion: Int
    package var token: String

    package init(extensionID: String, browser: BrowserKind, version: String, protocolVersion: Int, token: String) {
        self.extensionID = extensionID
        self.browser = browser
        self.version = version
        self.protocolVersion = protocolVersion
        self.token = token
    }
}

package struct BrowserElement: Sendable, Equatable {
    package var id: Int
    package var frame: Int
    package var role: String
    package var label: String
    package var context: String
    package var inputType: String?
    package var autocomplete: String?
    package var value: String?
    /// Origin of the frame the element lives in, only when it differs from
    /// the page's (nil = same origin as the page).
    package var frameOrigin: String?
    /// Absolute http(s) target of a link; nil for anything else.
    package var href: String?
    /// The field's `name` and `id`, kept so identifier-based sensitivity rules
    /// (otp, pin, cvv...) can run here too.
    package var fieldName: String?
    package var fieldId: String?
    /// Words from `knownStates` only, in that order. The page sets them, so they are a hint for
    /// the model and never an input to a verdict: a page could mark its own Delete as disabled.
    package var states: [String]

    /// The order the model reads them in, whatever order the page produced.
    package static let knownStates = [
        "disabled", "expanded", "collapsed", "checked", "unchecked", "mixed", "pressed", "selected", "haspopup",
    ]

    /// P4: for a field inside a form, the label of the button its Enter would
    /// press ("" when that button has none); nil outside a form.
    package var submit: String?

    package init(
        id: Int, frame: Int, role: String, label: String, context: String,
        inputType: String?, autocomplete: String?, value: String?,
        frameOrigin: String? = nil, href: String? = nil, fieldName: String? = nil, fieldId: String? = nil,
        states: [String] = [],
        submit: String? = nil
    ) {
        self.id = id
        self.frame = frame
        self.role = role
        self.label = label
        self.context = context
        self.inputType = inputType
        self.autocomplete = autocomplete
        self.value = value
        self.frameOrigin = frameOrigin
        self.href = href
        self.fieldName = fieldName
        self.fieldId = fieldId
        self.states = states
        self.submit = submit
    }
}

package struct BrowserPage: Sendable, Equatable {
    package var tab: Int
    package var origin: String
    package var url: String
    package var title: String
    package var text: String
    /// Element ids are only valid for the generation that listed them: every
    /// read bumps it, so a click on an old id fails as `stale_id`.
    package var generation: Int
    package var elements: [BrowserElement]
    package var truncated: Bool

    package init(
        tab: Int, origin: String, url: String, title: String, text: String,
        generation: Int, elements: [BrowserElement], truncated: Bool
    ) {
        self.tab = tab
        self.origin = origin
        self.url = url
        self.title = title
        self.text = text
        self.generation = generation
        self.elements = elements
        self.truncated = truncated
    }
}

package struct BrowserTab: Sendable, Equatable {
    package var id: Int
    package var title: String
    package var url: String
    package var active: Bool
    /// Wave 18b: in the extension's "Companion" group. Ownership itself lives
    /// in the app (`BrowserLease`); this is only what the strip shows.
    package var controlled: Bool
    /// The tab that opened this one, and when this one was born; both nil
    /// when the worker did not see it being created.
    package var opener: Int?
    package var createdAt: Date?
    /// A new tab whose page had not loaded when the extension stopped waiting; without it the
    /// model would read an empty page right away and report the site as blank. Only `open` sets it.
    package var loading: Bool

    package init(
        id: Int, title: String, url: String, active: Bool,
        controlled: Bool = false, opener: Int? = nil, createdAt: Date? = nil, loading: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.active = active
        self.controlled = controlled
        self.opener = opener
        self.createdAt = createdAt
        self.loading = loading
    }
}

package enum BrowserCommand: Sendable, Equatable {
    case tabs
    case read(tab: Int, selector: String?)
    case click(tab: Int, generation: Int, element: Int)
    case doubleClick(tab: Int, generation: Int, element: Int)
    case rightClick(tab: Int, generation: Int, element: Int)
    case type(tab: Int, generation: Int, element: Int, text: String)
    /// Without an element the key goes to the page's focus: generation and element are both nil.
    case press(tab: Int, key: String, times: Int, generation: Int?, element: Int?)
    case navigate(tab: Int, url: URL)
    case open(url: URL)
    case take(tab: Int)
    case release(tab: Int)
}

package enum BrowserInbound: Sendable, Equatable {
    case hello(id: Int, BrowserHello)
    case tabs(id: Int, [BrowserTab])
    /// The answer to `open`: one tab, not a list, so a reply to `tabs` and a
    /// reply to `open` can never be mistaken for each other.
    case opened(id: Int, BrowserTab)
    case page(id: Int, BrowserPage)
    case done(id: Int, message: String)
    case error(id: Int?, BridgeErrorBody)
}

package enum BrowserOutbound: Sendable, Equatable {
    case helloOK(id: Int)
    case call(id: Int, BrowserCommand)
    case error(id: Int?, BridgeErrorBody)
}
