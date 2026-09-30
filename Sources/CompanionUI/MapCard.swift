import CompanionCore
import MapKit
import SwiftUI

/// Renders a LocationsBlock as a map with location pins.
struct MapCard: View {
    let block: LocationsBlock

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            // Title
            Text(block.title ?? Localized.string("map.title"))
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.foreground)

            // Map
            Map(position: $position, interactionModes: []) {
                ForEach(block.locations, id: \.stableId) { loc in
                    Annotation(loc.name,
                               coordinate: CLLocationCoordinate2D(
                                   latitude: loc.lat,
                                   longitude: loc.lng
                               )) {
                        // Simple pin view
                        Image(systemName: "location.fill")
                            .foregroundStyle(Semantic.accent)
                            .onTapGesture {
                                selectedId = loc.stableId
                            }
                            .accessibilityLabel(loc.name)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { selectedId = loc.stableId }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: CardMetrics.map)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Semantic.border, lineWidth: Stroke.hairline)
            )

            // Location list
            VStack(alignment: .leading, spacing: Space.x2) {
                ForEach(block.locations, id: \.stableId) { loc in
                    locationRow(loc)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func locationRow(_ loc: LocationsBlock.Location) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(alignment: .top, spacing: Space.x3) {
                Image(systemName: "location.fill")
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.accent)
                    .frame(width: CardMetrics.iconColumn, alignment: .center)

                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(loc.name)
                        .font(.uiLabel)
                        .foregroundStyle(Semantic.foreground)
                    if let address = loc.address, !address.isEmpty {
                        Text(address)
                            .font(Font.uiCaption)
                            .foregroundStyle(Semantic.mutedForeground)
                    }
                    if let url = loc.url, let parsed = URL(string: url) {
                        Link(destination: parsed) {
                            Text(Localized.string("map.open"))
                                .font(Font.uiCaption)
                                .foregroundStyle(Semantic.accent)
                        }
                    }
                }
            }
        }
    }
}
