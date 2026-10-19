import CompanionCore
import MapKit
import SwiftUI

/// One place in the locator's list. The action leaves the card: the place's
/// own site when the data has one, otherwise the place in Apple Maps.
struct MapCardPlace: View {
    let location: LocationsBlock.Location
    let selected: Bool
    let onSelect: () -> Void

    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            if let eyebrow = location.eyebrow, !eyebrow.isEmpty {
                Text(eyebrow)
                    .font(.uiMicro)
                    .textCase(.uppercase)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            Text(location.name)
                .font(.uiLabel.weight(.medium))
                .foregroundStyle(Semantic.foreground)
            if let address = location.address, !address.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                    Image(systemName: "mappin")
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                    Text(address)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            }
            action
        }
        .padding(.horizontal, Space.x3)
        .padding(.vertical, Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Semantic.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(selected ? Semantic.accent : Semantic.border,
                        lineWidth: selected ? Stroke.medium : Stroke.hairline))
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Semantic.focusRing, lineWidth: Stroke.medium)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        .onTapGesture(perform: onSelect)
        // Activation only: a click must not draw the keyboard ring.
        .focusable(interactions: .activate)
        .focusEffectDisabled()
        .onKeyPress(keys: [.return, .space]) { _ in
            onSelect()
            return .handled
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var action: some View {
        if let url = location.url, let parsed = URL(string: url) {
            Link(destination: parsed) { actionChip(Localized.string("map.site")) }
                .buttonStyle(.plain)
        } else {
            Button { openInMaps() } label: { actionChip(Localized.string("map.inMaps")) }
                .buttonStyle(.plain)
        }
    }

    /// The accent chip: a tinted wash, accent ink, and an arrow for "leaves the card".
    private func actionChip(_ text: String) -> some View {
        HStack(spacing: Space.x1) {
            Text(text)
            Image(systemName: "arrow.up.right")
        }
        .font(.uiCaption.weight(.medium))
        .foregroundStyle(Semantic.accentText)
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x0_5)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Semantic.accentWash))
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: location.lat, longitude: location.lng))
        let item = MKMapItem(placemark: placemark)
        item.name = location.name
        item.openInMaps()
    }
}

/// A map pin: an accent disc with a pin glyph. The selected one gets an outline
/// ring set off from the disc, so the state reads without changing the fill.
struct MapCardPin: View {
    let selected: Bool

    var body: some View {
        Image(systemName: "mappin")
            .font(.uiCaption.weight(.medium))
            .foregroundStyle(Semantic.accentForeground)
            .frame(width: CardMetrics.pin, height: CardMetrics.pin)
            .background(Circle().fill(Semantic.accent))
            .overlay {
                if selected {
                    Circle()
                        .stroke(Semantic.accent, lineWidth: Stroke.medium)
                        .frame(width: CardMetrics.pinRing, height: CardMetrics.pinRing)
                }
            }
    }
}
