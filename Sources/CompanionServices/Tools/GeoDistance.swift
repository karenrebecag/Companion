import Foundation

/// Great-circle distance between two lookups. Plain math on purpose: the
/// figure is read by the model, and it must not depend on a framework.
package enum GeoDistance {
    private static let earthRadius = 6_371_000.0

    package static func meters(from origin: FoundPlace, to place: FoundPlace) -> Double {
        let lat1 = origin.lat * .pi / 180
        let lat2 = place.lat * .pi / 180
        let dLat = lat2 - lat1
        let dLng = (place.lng - origin.lng) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Whole metres under a kilometre, one decimal above it: the precision a
    /// person walking to a place can use.
    package static func label(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1_000)
    }
}
