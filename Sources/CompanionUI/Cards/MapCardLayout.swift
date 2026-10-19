import CoreLocation
import MapKit

/// The decisions behind the locator card that need no view: where the list
/// sits, how the header counts, and where the camera lands.
nonisolated enum MapCardLayout {
    /// Measured on the card's content width. Below it the list stacks under
    /// the map, because a name and address next to a map need room to wrap.
    static let sideBySideMinWidth: CGFloat = 560
    static let listFraction: CGFloat = 0.36

    /// The margin around the places when the camera fits them.
    static let fitPadding: CLLocationDegrees = 1.3
    /// The tightest a fit may zoom. Two places a block apart stay a
    /// neighbourhood, not a street each.
    static let minSpan: CLLocationDegrees = 0.01

    static let zoomStep: Double = 2
    static let minDistance: Double = 100
    static let maxDistance: Double = 5_000_000

    static func isSideBySide(width: CGFloat) -> Bool {
        width >= sideBySideMinWidth
    }

    static func listWidth(for width: CGFloat) -> CGFloat {
        width * listFraction
    }

    static func foundKey(count: Int) -> String {
        count == 1 ? "map.found.one" : "map.found.other"
    }

    static func fitRegion(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max()
        else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * fitPadding, minSpan),
            longitudeDelta: max((maxLng - minLng) * fitPadding, minSpan))
        return MKCoordinateRegion(center: center, span: span)
    }

    static func zoomed(_ distance: Double, zoomIn: Bool) -> Double {
        let next = zoomIn ? distance / zoomStep : distance * zoomStep
        return min(max(next, minDistance), maxDistance)
    }
}
