import CompanionCore
import MapKit
import SwiftUI

/// A place lookup as a map and a list. Each place has a numbered pin, and
/// picking a pin or a row selects the other: the camera moves to the place.
struct MapCard: View {
    let block: LocationsBlock

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Close enough to read the street, far enough to keep the neighbours.
    private static let focusDistance: Double = 1_500

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(block.title ?? Localized.string("map.title"))
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.foreground)

            Map(position: $position, interactionModes: []) {
                ForEach(Array(block.locations.enumerated()), id: \.element.stableId) { index, loc in
                    Annotation(loc.name, coordinate: Self.coordinate(loc)) {
                        Button {
                            selectedId = loc.stableId
                        } label: {
                            numberBadge(index + 1, selected: loc.stableId == selectedId)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(loc.name)
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

            VStack(alignment: .leading, spacing: Space.x2) {
                ForEach(Array(block.locations.enumerated()), id: \.element.stableId) { index, loc in
                    placeRow(index + 1, loc)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .onChange(of: selectedId) { _, id in
            guard let id, let loc = block.locations.first(where: { $0.stableId == id }) else { return }
            focus(Self.coordinate(loc))
        }
    }

    private static func coordinate(_ loc: LocationsBlock.Location) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lng)
    }

    private func focus(_ center: CLLocationCoordinate2D) {
        let camera = MapCamera(centerCoordinate: center, distance: Self.focusDistance)
        withAnimation(ChromeMotion.animation(.expoOut(MotionTime.panel), reduceMotion: reduceMotion)) {
            position = .camera(camera)
        }
    }

    private func placeRow(_ number: Int, _ loc: LocationsBlock.Location) -> some View {
        let selected = loc.stableId == selectedId
        return HStack(alignment: .top, spacing: Space.x3) {
            numberBadge(number, selected: selected)
            VStack(alignment: .leading, spacing: Space.x1) {
                Button {
                    selectedId = loc.stableId
                } label: {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text(loc.name)
                            .font(.uiLabel)
                            .foregroundStyle(Semantic.foreground)
                        if let address = loc.address, !address.isEmpty {
                            Text(address)
                                .font(.uiCaption)
                                .foregroundStyle(Semantic.mutedForeground)
                        }
                    }
                    .padding(Space.x2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(selected ? Semantic.sidebarSelected : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])

                if let url = loc.url, let parsed = URL(string: url) {
                    Link(destination: parsed) {
                        Text(Localized.string("map.open"))
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.accent)
                    }
                    .padding(.leading, Space.x2)
                }
            }
        }
    }

    private func numberBadge(_ number: Int, selected: Bool) -> some View {
        Text(verbatim: "\(number)")
            .font(.uiCaption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(selected ? Semantic.accentForeground : Semantic.accent)
            .frame(width: CardMetrics.iconColumn, height: CardMetrics.iconColumn)
            .background(Circle().fill(selected ? Semantic.accent : Semantic.hover))
    }
}
