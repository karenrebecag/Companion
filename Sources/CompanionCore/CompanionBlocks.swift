import Foundation

public struct LocationsBlock: Sendable, Equatable {
    public struct Location: Sendable, Equatable {
        public var id: String?
        public var name: String
        public var eyebrow: String?
        public var address: String?
        public var lat: Double
        public var lng: Double
        public var url: String?

        /// Stable even when the specialist omits id.
        public var stableId: String { id ?? "\(lat),\(lng)" }

        public init(
            id: String? = nil,
            name: String,
            eyebrow: String? = nil,
            address: String? = nil,
            lat: Double,
            lng: Double,
            url: String? = nil
        ) {
            self.id = id
            self.name = name
            self.eyebrow = eyebrow
            self.address = address
            self.lat = lat
            self.lng = lng
            self.url = url
        }
    }

    public var title: String?
    public var locations: [Location]

    public init(title: String? = nil, locations: [Location]) {
        self.title = title
        self.locations = locations
    }

    /// Only the fields Mapbox JS reads; "</" is escaped so a name cannot
    /// close the embedding <script> tag.
    public var locatorJSON: String {
        struct Pin: Encodable {
            let id: String
            let name: String
            let lat: Double
            let lng: Double
        }
        let pins = locations.map {
            Pin(id: $0.stableId, name: $0.name, lat: $0.lat, lng: $0.lng)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(pins)
        } catch {
            return "[]"
        }
        guard let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json.replacingOccurrences(of: "</", with: "<\\/")
    }
}

public struct GalleryBlock: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public var path: String?
        public var url: String?
        public var caption: String?

        /// Local disk or https only: plain http does not travel.
        /// Paths must be absolute and must not contain traversal components.
        public var isRenderable: Bool {
            if let p = path {
                // Path must be absolute (start with /) and contain no ".." components.
                guard p.hasPrefix("/") else { return false }
                let components = p.split(separator: "/", omittingEmptySubsequences: true)
                guard !components.contains("..") else { return false }
                return true
            }
            guard let url, let parsed = URL(string: url) else { return false }
            return parsed.scheme == "https"
        }

        public init(path: String? = nil, url: String? = nil, caption: String? = nil) {
            self.path = path
            self.url = url
            self.caption = caption
        }
    }

    public var title: String?
    public var images: [Item]

    public init(title: String? = nil, images: [Item]) {
        self.title = title
        self.images = images
    }
}

public enum CompanionBlocks: Sendable {
    public static let locationsLanguage = "companion:locations"
    public static let galleryLanguage = "companion:gallery"

    /// Nil sends the fence back to a CodeBlock so broken JSON stays visible.
    public static func locations(_ body: String) -> LocationsBlock? {
        guard let dict = jsonObject(body),
              let list = dict["locations"] as? [Any],
              !list.isEmpty
        else { return nil }

        var parsed: [LocationsBlock.Location] = []
        parsed.reserveCapacity(list.count)
        for raw in list {
            guard let loc = location(from: raw) else { return nil }
            parsed.append(loc)
        }
        guard parsed.allSatisfy({
            (-90...90).contains($0.lat) && (-180...180).contains($0.lng)
        }) else { return nil }
        return LocationsBlock(title: dict["title"] as? String, locations: parsed)
    }

    public static func gallery(_ body: String) -> GalleryBlock? {
        guard let dict = jsonObject(body),
              let list = dict["images"] as? [Any]
        else { return nil }

        var items: [GalleryBlock.Item] = []
        items.reserveCapacity(list.count)
        for raw in list {
            guard let item = galleryItem(from: raw) else { return nil }
            items.append(item)
        }
        let renderable = items.filter(\.isRenderable)
        guard !renderable.isEmpty else { return nil }
        return GalleryBlock(title: dict["title"] as? String, images: renderable)
    }

    private static func jsonObject(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8) else { return nil }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
        return raw as? [String: Any]
    }

    private static func location(from raw: Any) -> LocationsBlock.Location? {
        guard let dict = raw as? [String: Any],
              let name = dict["name"] as? String,
              let lat = jsonDouble(dict["lat"]),
              let lng = jsonDouble(dict["lng"])
        else { return nil }
        // Validate URL scheme: only https or nil allowed (plain http and javascript: rejected).
        if let rawURL = dict["url"] as? String {
            guard let parsed = URL(string: rawURL), parsed.scheme == "https"
            else { return nil }
        }
        return LocationsBlock.Location(
            id: dict["id"] as? String,
            name: name,
            eyebrow: dict["eyebrow"] as? String,
            address: dict["address"] as? String,
            lat: lat,
            lng: lng,
            url: dict["url"] as? String
        )
    }

    private static func galleryItem(from raw: Any) -> GalleryBlock.Item? {
        guard let dict = raw as? [String: Any] else { return nil }
        return GalleryBlock.Item(
            path: dict["path"] as? String,
            url: dict["url"] as? String,
            caption: dict["caption"] as? String
        )
    }

    /// JSONSerialization boxes numbers as NSNumber. `is Bool` is true for
    /// NSNumber(1), so reject with CFBoolean identity instead.
    private static func jsonDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.doubleValue
        }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}

extension MarkdownSplitter {
    /// An unclosed fence is code through the end: streaming arrives half-done.
    static func splitFences(_ text: String) -> [Kind] {
        var kinds: [Kind] = []
        var inCode = false
        var lang = ""
        var buffer: [String] = []
        func flush() {
            let body = buffer.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                kinds.append(inCode
                    ? .code(language: lang, body: body) : .prose(body))
            }
            buffer = []
        }
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                flush()
                if inCode {
                    inCode = false
                } else {
                    inCode = true
                    lang = String(t.dropFirst(3))
                        .trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            buffer.append(line)
        }
        flush()
        return kinds
    }
}
