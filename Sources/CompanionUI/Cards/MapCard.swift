import CompanionCore
import MapKit
import SwiftUI

/// A place lookup as a locator: the list beside the map when the card is wide,
/// the map over a strip of place cards when it is narrow. Picking a place or a
/// pin selects the other and flies the camera to it.
struct MapCard: View {
    let block: LocationsBlock

    @State private var position: MapCameraPosition
    @State private var selectedId: String?
    @State private var camera: MapCamera?
    /// Gestures stay off until the map is clicked, so a trackpad scroll over
    /// the map scrolls the chat instead of zooming it.
    @State private var mapActive = false
    @State private var contentWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Close enough to read the street, far enough to keep the neighbours.
    private static let focusDistance: Double = 1_500

    init(block: LocationsBlock) {
        self.block = block
        _position = State(initialValue: Self.initialPosition(block))
    }

    private var count: Int { block.locations.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            header
            if MapCardLayout.isSideBySide(width: contentWidth) {
                HStack(alignment: .top, spacing: Space.x3) {
                    placeColumn
                    mapView(height: CardMetrics.locator)
                }
            } else {
                mapView(height: CardMetrics.map)
                placeStrip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .cardSurface()
        .onChange(of: selectedId) { _, id in
            guard let id, let loc = block.locations.first(where: { $0.stableId == id }) else { return }
            focus(Self.coordinate(loc))
        }
    }

    /// One heading. A model-supplied title keeps its words and the count
    /// moves to a quiet caption; without one the count is the heading.
    @ViewBuilder private var header: some View {
        if let title = block.title {
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                Text(title)
                    .font(.uiSubtitle)
                    .foregroundStyle(Semantic.foreground)
                Spacer(minLength: Space.x2)
                Text(countText(MapCardLayout.pluralKey("map.count", count: count)))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        } else {
            Text(countText(MapCardLayout.pluralKey("map.found", count: count)))
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.foreground)
        }
    }

    private func countText(_ key: String) -> String {
        String(format: Localized.string(key), count)
    }

    private static func coordinate(_ loc: LocationsBlock.Location) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lng)
    }

    private static func initialPosition(_ block: LocationsBlock) -> MapCameraPosition {
        let coordinates = block.locations.map(coordinate)
        if coordinates.count == 1, let only = coordinates.first {
            return .camera(MapCamera(centerCoordinate: only, distance: focusDistance))
        }
        if let region = MapCardLayout.fitRegion(coordinates) {
            return .region(region)
        }
        return .automatic
    }

    private func focus(_ center: CLLocationCoordinate2D) {
        let target = MapCamera(centerCoordinate: center, distance: Self.focusDistance)
        withAnimation(ChromeMotion.animation(.expoOut(MotionTime.panel), reduceMotion: reduceMotion)) {
            position = .camera(target)
        }
    }

    private func select(_ loc: LocationsBlock.Location) {
        selectedId = loc.stableId
    }

    private func mapView(height: CGFloat) -> some View {
        Map(position: $position, interactionModes: mapActive ? [.pan, .zoom] : []) {
            ForEach(block.locations, id: \.stableId) { loc in
                Annotation(loc.name, coordinate: Self.coordinate(loc)) {
                    Button {
                        select(loc)
                    } label: {
                        MapCardPin(selected: loc.stableId == selectedId)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: Localized.string("map.show"), loc.name))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onMapCameraChange { camera = $0.camera }
        .simultaneousGesture(TapGesture().onEnded { mapActive = true })
        .onHover { hovering in
            if !hovering { mapActive = false }
        }
        .overlay(alignment: .topTrailing) { zoomControls }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Semantic.border, lineWidth: Stroke.hairline))
    }

    private var zoomControls: some View {
        VStack(spacing: Space.none) {
            zoomButton(systemName: "plus", label: "map.zoomIn", zoomIn: true)
            zoomButton(systemName: "minus", label: "map.zoomOut", zoomIn: false)
        }
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Semantic.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Semantic.border, lineWidth: Stroke.hairline))
        .padding(Space.x2)
    }

    private func zoomButton(systemName: String, label: String, zoomIn: Bool) -> some View {
        Button {
            zoom(zoomIn: zoomIn)
        } label: {
            Image(systemName: systemName)
                .font(.uiLabel.weight(.medium))
                .foregroundStyle(Semantic.foreground)
                .frame(width: CardMetrics.zoomButton, height: CardMetrics.zoomButton)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Localized.string(label))
    }

    /// The buttons work with gestures off: they are the only zoom when the
    /// map is inactive.
    private func zoom(zoomIn: Bool) {
        guard let camera else { return }
        let target = MapCamera(
            centerCoordinate: camera.centerCoordinate,
            distance: MapCardLayout.zoomed(camera.distance, zoomIn: zoomIn),
            heading: camera.heading, pitch: camera.pitch)
        withAnimation(ChromeMotion.animation(.expoOut(MotionTime.panel), reduceMotion: reduceMotion)) {
            position = .camera(target)
        }
    }

    /// Wide: the list has the map's height and scrolls inside it. A fade at
    /// the bottom edge says there is more, once there is more to say.
    private var placeColumn: some View {
        ScrollView { placeList }
            .scrollIndicators(.hidden)
            .frame(width: MapCardLayout.listWidth(for: contentWidth), height: CardMetrics.locator)
            .overlay(alignment: .bottom) {
                if count > MapCardLayout.fadeThreshold {
                    LinearGradient(
                        colors: [.clear, Semantic.surface],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: Space.x8)
                        .allowsHitTesting(false)
                }
            }
    }

    /// Narrow: fixed-width cards that snap, with the next card cut at the
    /// edge as the cue that the strip scrolls.
    private var placeStrip: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.x2) {
                ForEach(block.locations, id: \.stableId) { loc in
                    placeCard(loc)
                        .frame(width: CardMetrics.placeCard)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private var placeList: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            ForEach(block.locations, id: \.stableId) { loc in
                placeCard(loc)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeCard(_ loc: LocationsBlock.Location) -> some View {
        MapCardPlace(location: loc, selected: loc.stableId == selectedId) {
            select(loc)
        }
    }
}
