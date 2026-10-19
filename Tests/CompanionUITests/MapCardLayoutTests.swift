import CoreLocation
@testable import CompanionUI
import Testing

@Test func mapFitHoldsEveryPlaceAndStopsAtMaxZoom() {
    let spread = [
        CLLocationCoordinate2D(latitude: 19.40, longitude: -99.17),
        CLLocationCoordinate2D(latitude: 19.35, longitude: -99.16),
    ]
    guard let region = MapCardLayout.fitRegion(spread) else {
        Issue.record("fitRegion devolvio nil con dos lugares")
        return
    }
    for place in spread {
        #expect(abs(place.latitude - region.center.latitude) <= region.span.latitudeDelta / 2)
        #expect(abs(place.longitude - region.center.longitude) <= region.span.longitudeDelta / 2)
    }

    let twins = [
        CLLocationCoordinate2D(latitude: 19.4, longitude: -99.1),
        CLLocationCoordinate2D(latitude: 19.4001, longitude: -99.1001),
    ]
    #expect(MapCardLayout.fitRegion(twins)?.span.latitudeDelta == MapCardLayout.minSpan)
}

@Test func headerPluralAndZoomBounds() {
    #expect(MapCardLayout.pluralKey("map.found", count: 1) == "map.found.one")
    #expect(MapCardLayout.pluralKey("map.count", count: 6) == "map.count.other")
    #expect(MapCardLayout.zoomed(MapCardLayout.minDistance, zoomIn: true) == MapCardLayout.minDistance)
    #expect(MapCardLayout.zoomed(MapCardLayout.maxDistance, zoomIn: false) == MapCardLayout.maxDistance)
}
