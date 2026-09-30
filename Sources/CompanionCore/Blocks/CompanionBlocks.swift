import Foundation

package struct LocationsBlock: Sendable, Equatable {
    package struct Location: Sendable, Equatable {
        package var id: String?
        package var name: String
        package var eyebrow: String?
        package var address: String?
        package var lat: Double
        package var lng: Double
        package var url: String?

        /// Stable even when the specialist omits id.
        package var stableId: String { id ?? "\(lat),\(lng)" }

        package init(
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

    package var title: String?
    package var locations: [Location]

    package init(title: String? = nil, locations: [Location]) {
        self.title = title
        self.locations = locations
    }

    /// Only the fields Mapbox JS reads; "</" is escaped so a name cannot
    /// close the embedding <script> tag.
    package var locatorJSON: String {
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

package struct GalleryBlock: Sendable, Equatable {
    package struct Item: Sendable, Equatable {
        package var path: String?
        package var url: String?
        package var caption: String?

        /// Local disk or https only: plain http does not travel.
        /// Paths must be absolute and must not contain traversal components.
        package var isRenderable: Bool {
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

        package init(path: String? = nil, url: String? = nil, caption: String? = nil) {
            self.path = path
            self.url = url
            self.caption = caption
        }
    }

    package var title: String?
    package var images: [Item]

    package init(title: String? = nil, images: [Item]) {
        self.title = title
        self.images = images
    }
}

/// Where a card's data came from.
///
/// The industry contract says the application supplies the data and the model
/// only selects what to show. Our CLI specialists cannot honour that — they run
/// their own tools and hand back text — so a fence stays their only channel.
/// What we refuse to do is present both with the same authority: a pin the
/// model wrote from memory looks exactly as confident as one that was looked
/// up, and that is the whole defect.
package enum CardSource: Sendable, Equatable {
    /// The app looked it up. Trusted.
    case tool
    /// The model wrote it into a fence. Unverified by construction.
    case model
}

package enum CardPayload: Sendable, Equatable {
    case locations(LocationsBlock)
    case gallery(GalleryBlock)
    /// Wave 20: figures, rows and series (Incredible's stat/table/chart).
    case stats(StatsBlock)
    case table(TableBlock)
    case chart(ChartBlock)
}

/// What the interface paints, travelling on its own channel — never through
/// the model's context, which is where a transcribed coordinate goes wrong.
package struct Card: Sendable, Equatable {
    package var payload: CardPayload
    package var source: CardSource

    package init(payload: CardPayload, source: CardSource) {
        self.payload = payload
        self.source = source
    }
}

package enum CompanionBlocks: Sendable {
    package static let locationsLanguage = "companion:locations"
    package static let galleryLanguage = "companion:gallery"

    /// Nil sends the fence back to a CodeBlock so broken JSON stays visible.
    package static func locations(_ body: String) -> LocationsBlock? {
        guard let dict = fenceObject(body),
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

    package static func gallery(_ body: String) -> GalleryBlock? {
        guard let dict = fenceObject(body),
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

    static func jsonArray(_ body: String) -> [Any]? {
        guard let data = body.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any]
        } catch {
            return nil
        }
    }

    /// A fence body is one message's card, never a dataset: past this it is
    /// refused before it is parsed. Documents and tool arguments have their
    /// own bounds and go through `jsonObject`, uncapped.
    package static let maxFenceBytes = 256 * 1024

    static func fenceObject(_ body: String) -> [String: Any]? {
        body.utf8.count <= maxFenceBytes ? jsonObject(body) : nil
    }

    static func jsonObject(_ body: String) -> [String: Any]? {
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
    static func jsonDouble(_ value: Any?) -> Double? {
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
    /// True when the text stops inside a fence: the model was cut, or is
    /// still writing. What such a fence holds is not a finished card.
    static func endsInsideFence(_ text: String) -> Bool {
        let fences = text.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        return fences.count % 2 == 1
    }

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
