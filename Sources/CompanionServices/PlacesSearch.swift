import CompanionCore
import Foundation
import MapKit

public struct FoundPlace: Sendable, Equatable {
    public var name: String
    public var address: String
    public var lat: Double
    public var lng: Double

    public init(name: String, address: String, lat: Double, lng: Double) {
        self.name = name
        self.address = address
        self.lat = lat
        self.lng = lng
    }
}

/// Port so a test never goes out to the network for a museum.
public protocol PlacesSearching: Sendable {
    func search(_ query: String, near: String?) async -> [FoundPlace]
}

/// The trusted source for a map card. Native and key-free — the project
/// already draws with MapKit, so this adds no dependency, only a direction:
/// coordinates come from a lookup, never from a model's memory.
public struct MapKitPlacesSearch: PlacesSearching {
    /// Enough to answer "where is it"; more pins than this is a list, not a
    /// map, and the model can ask again with a narrower query.
    private let limit: Int

    public init(limit: Int = 8) {
        self.limit = limit
    }

    public func search(_ query: String, near: String?) async -> [FoundPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [near, query]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Mapped to our own Sendable type INSIDE the callback: MapKit's
        // response is not Sendable, so carrying it across the continuation is
        // a data race the compiler is right to refuse.
        let limit = self.limit
        return await withCheckedContinuation { continuation in
            MKLocalSearch(request: request).start { response, _ in
                // A failed lookup is "nothing found", not an error that breaks
                // the turn: the same call LiveCapabilityProbe already makes.
                let found = (response?.mapItems ?? []).prefix(limit).map { item in
                    FoundPlace(
                        name: item.name ?? "",
                        address: Self.address(of: item),
                        lat: item.placemark.coordinate.latitude,
                        lng: item.placemark.coordinate.longitude)
                }
                continuation.resume(returning: Array(found))
            }
        }
    }

    private static func address(of item: MKMapItem) -> String {
        let placemark = item.placemark
        let parts = [
            placemark.thoroughfare, placemark.subThoroughfare,
            placemark.locality, placemark.administrativeArea,
        ]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}
