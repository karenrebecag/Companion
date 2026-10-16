import CompanionCore
import CoreLocation
import Foundation
import MapKit

package struct FoundPlace: Sendable, Equatable {
    package var name: String
    package var address: String
    package var lat: Double
    package var lng: Double

    package init(name: String, address: String, lat: Double, lng: Double) {
        self.name = name
        self.address = address
        self.lat = lat
        self.lng = lng
    }
}

/// Port so a test never goes out to the network for a museum.
package protocol PlacesSearching: Sendable {
    func search(_ query: String, near: String?) async -> [FoundPlace]
}

/// What find_places answers with. A category ("cafeterías") wants places: a
/// street MapKit returns for it is named by its own address line and is not a
/// place to go to. An address ("Calle Durango 200") wants its street back.
package enum PlaceResults {
    private static let streetWords: Set<String> = [
        "calle", "av", "avenida", "blvd", "boulevard", "calzada", "paseo", "camino",
        "carretera", "privada", "cerrada", "callejón", "circuito", "andador", "eje", "prolongación",
    ]

    /// A house number or a street word first: the query names a location, not a kind of place.
    package static func isAddress(_ query: String) -> Bool {
        if query.contains(where: \.isNumber) { return true }
        let first = query.lowercased().split(separator: " ").first.map(String.init) ?? ""
        return streetWords.contains(first.trimmingCharacters(in: .punctuationCharacters))
    }

    package static func places(_ found: [FoundPlace], query: String) -> [FoundPlace] {
        let address = isAddress(query)
        return found.filter { place in
            let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return false }
            return address || !place.address.lowercased().hasPrefix(name.lowercased())
        }
    }
}

/// The trusted source for a map card. Native and key-free — the project
/// already draws with MapKit, so this adds no dependency, only a direction:
/// coordinates come from a lookup, never from a model's memory.
package struct MapKitPlacesSearch: PlacesSearching {
    /// Enough to answer "where is it"; more pins than this is a list, not a
    /// map, and the model can ask again with a narrower query.
    private let limit: Int

    /// A neighbourhood, not a city: "cafés near Roma Norte" must not reach
    /// Coyoacán. Wide enough to cover a barrio's edges from its centre.
    private static let radius: CLLocationDistance = 3_000

    package init(limit: Int = 8) {
        self.limit = limit
    }

    package func search(_ query: String, near: String?) async -> [FoundPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [near, query]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // Places, not addresses: a query for "cafeterías" with a street in its
        // text otherwise answers with the street.
        request.resultTypes = PlaceResults.isAddress(query) ? [.address, .pointOfInterest] : .pointOfInterest
        if let near, let center = await Self.center(of: near) {
            request.region = MKCoordinateRegion(
                center: center, latitudinalMeters: Self.radius, longitudinalMeters: Self.radius)
        }

        return await Self.places(request, limit: limit)
    }

    /// Where the "near" text is, so the search can be bounded to it.
    private static func center(of near: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = near
        request.resultTypes = .address
        guard let first = await places(request, limit: 1).first else { return nil }
        return CLLocationCoordinate2D(latitude: first.lat, longitude: first.lng)
    }

    /// Mapped to our own Sendable type INSIDE the callback: MapKit's response
    /// is not Sendable, so carrying it across the continuation is a data race
    /// the compiler is right to refuse. A failed lookup is "nothing found", not
    /// an error that breaks the turn: the same call LiveCapabilityProbe makes.
    private static func places(_ request: MKLocalSearch.Request, limit: Int) async -> [FoundPlace] {
        return await withCheckedContinuation { continuation in
            MKLocalSearch(request: request).start { response, _ in
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
