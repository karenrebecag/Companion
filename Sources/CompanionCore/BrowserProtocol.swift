import Foundation

/// Wave 18. The browser wire, in two framings of the same JSON: native
/// messaging on the extension side (uint32 little-endian length + body) and
/// JSONL on the app's socket. Pure shapes; the relay and the channel actor
/// live in Services.

public enum BrowserWire {
    /// Chrome's own ceiling for a message from a native host is 1 MB; the
    /// same number bounds what we accept from the extension.
    public static let maxNativeBytes = 1_048_576
    /// The socket line is capped like the bridge's (BridgeListener closes on
    /// a longer one), so the relay must never forward more than this.
    public static let maxLineBytes = BridgeCodec.maxLineBytes
}

public enum BrowserWireError: Error, Sendable, Equatable {
    case frameTooLarge(Int)
    case truncated
    case badJSON
}

// MARK: - Native framing

/// Incremental decoder for the stdio side. Bytes arrive in arbitrary chunks;
/// complete frames come out. After an oversize prefix the stream cannot be
/// resynchronised, so the decoder stays poisoned instead of guessing.
public struct NativeFrameDecoder: Sendable {
    private let limit: Int
    private var buffer = Data()
    private var poisoned = false

    public init(limit: Int = BrowserWire.maxNativeBytes) {
        self.limit = limit
    }

    /// Frames are read through a cursor and the consumed prefix is dropped
    /// once per push, so a push carrying many frames is linear, not quadratic.
    public mutating func push(_ bytes: Data) -> [Result<Data, BrowserWireError>] {
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
    public func finish() -> BrowserWireError? {
        !poisoned && !buffer.isEmpty ? .truncated : nil
    }
}

public enum NativeFrameEncoder {
    public static func encode(_ json: Data) throws(BrowserWireError) -> Data {
        guard json.count <= BrowserWire.maxNativeBytes else { throw .frameTooLarge(json.count) }
        let length = UInt32(json.count)
        let prefix = Data((0..<4).map { UInt8(truncatingIfNeeded: length >> (8 * UInt32($0))) })
        return prefix + json
    }
}

// MARK: - Messages

public enum BrowserKind: String, Sendable, Codable {
    case chrome
    case comet
}

public struct BrowserHello: Sendable, Equatable {
    public var extensionID: String
    public var browser: BrowserKind
    public var version: String
    public var protocolVersion: Int
    public var token: String

    public init(extensionID: String, browser: BrowserKind, version: String, protocolVersion: Int, token: String) {
        self.extensionID = extensionID
        self.browser = browser
        self.version = version
        self.protocolVersion = protocolVersion
        self.token = token
    }
}

public struct BrowserElement: Sendable, Equatable {
    public var id: Int
    public var frame: Int
    public var role: String
    public var label: String
    public var context: String
    public var inputType: String?
    public var autocomplete: String?
    public var value: String?
    /// Origin of the frame the element lives in, only when it differs from
    /// the page's (nil = same origin as the page).
    public var frameOrigin: String?
    /// Absolute http(s) target of a link; nil for anything else.
    public var href: String?
    /// The field's `name` and `id`, kept so identifier-based sensitivity rules
    /// (otp, pin, cvv...) can run here too.
    public var fieldName: String?
    public var fieldId: String?

    public init(
        id: Int, frame: Int, role: String, label: String, context: String,
        inputType: String?, autocomplete: String?, value: String?,
        frameOrigin: String? = nil, href: String? = nil, fieldName: String? = nil, fieldId: String? = nil
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
    }
}

public struct BrowserPage: Sendable, Equatable {
    public var tab: Int
    public var origin: String
    public var url: String
    public var title: String
    public var text: String
    /// Element ids are only valid for the generation that listed them: every
    /// read bumps it, so a click on an old id fails as `stale_id`.
    public var generation: Int
    public var elements: [BrowserElement]
    public var truncated: Bool

    public init(
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

public struct BrowserTab: Sendable, Equatable {
    public var id: Int
    public var title: String
    public var url: String
    public var active: Bool

    public init(id: Int, title: String, url: String, active: Bool) {
        self.id = id
        self.title = title
        self.url = url
        self.active = active
    }
}

public enum BrowserCommand: Sendable, Equatable {
    case tabs
    case read(tab: Int, selector: String?)
    case click(tab: Int, generation: Int, element: Int)
    case type(tab: Int, generation: Int, element: Int, text: String)
    case navigate(tab: Int, url: URL)
}

public enum BrowserInbound: Sendable, Equatable {
    case hello(id: Int, BrowserHello)
    case tabs(id: Int, [BrowserTab])
    case page(id: Int, BrowserPage)
    case done(id: Int, message: String)
    case error(id: Int?, BridgeErrorBody)
}

public enum BrowserOutbound: Sendable, Equatable {
    case helloOK(id: Int)
    case call(id: Int, BrowserCommand)
    case error(id: Int?, BridgeErrorBody)
}
