import CompanionCore
import SwiftUI

/// The words on a card, apart from the view so they can be asserted.
enum MicRowCopy {
    static func title(_ row: MicMenuRow) -> String {
        switch row {
        case .builtIn:
            Localized.string("settings.microphone.builtIn")
        case .systemDefault(let name, _, _):
            if let name, !name.isEmpty {
                String(format: Localized.string("settings.microphone.system.named"), name)
            } else {
                Localized.string("settings.microphone.system")
            }
        case .device(_, let name, _):
            name
        case .missing(_, let name):
            name
        }
    }

    static func subtitle(_ row: MicMenuRow) -> String? {
        switch row {
        case .builtIn:
            Localized.string("settings.microphone.builtIn.subtitle")
        case .systemDefault(_, let holding, _):
            Localized.string(holding
                ? "settings.microphone.system.holding"
                : "settings.microphone.system.follows")
        case .device:
            nil
        case .missing:
            Localized.string("settings.microphone.missing")
        }
    }

    static func tag(_ row: MicMenuRow) -> String? {
        switch row {
        case .builtIn: Localized.string("settings.microphone.recommended")
        case .missing: Localized.string("settings.microphone.notConnected")
        default: nil
        }
    }
}

struct SettingsMicrophonePopover: View {
    let model: SettingsMicrophoneModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                Text(Localized.string("settings.microphone"))
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                Text(Localized.string("settings.microphone.popup"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Space.x3) {
                    ForEach(model.resolved.rows) { row in
                        card(row)
                    }
                }
                if let notice = model.noticeText {
                    HStack(alignment: .center, spacing: Space.x3) {
                        Text(notice)
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Space.x2)
                        if model.canRetry {
                            SettingsPill(
                                title: Localized.string("settings.microphone.retry"),
                                action: model.retry)
                        }
                    }
                }
            }
            .padding(Space.x4)
        }
        .frame(width: 360)
    }

    private func card(_ row: MicMenuRow) -> some View {
        Button { model.choose(row) } label: {
            HStack(alignment: .center, spacing: Space.x3) {
                tick(row.selected)
                VStack(alignment: .leading, spacing: Space.x1) {
                    HStack(spacing: Space.x2) {
                        Text(MicRowCopy.title(row))
                            .font(.uiLabel)
                            .foregroundStyle(Semantic.foreground)
                        if let tag = MicRowCopy.tag(row) {
                            Text(tag)
                                .font(.uiCaption)
                                .foregroundStyle(Semantic.mutedForeground)
                        }
                    }
                    if let subtitle = MicRowCopy.subtitle(row) {
                        Text(subtitle)
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: Space.x2)
                if row.selected, model.testing { MicLevelBars(lit: model.litBars) }
            }
            .padding(Space.x3)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(row.selected ? Semantic.hover : Semantic.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(row.selected ? Semantic.foreground : Semantic.border,
                            lineWidth: Stroke.hairline))
            .opacity(row.enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!row.enabled)
        .accessibilityAddTraits(row.selected ? .isSelected : [])
    }

    private func tick(_ selected: Bool) -> some View {
        Circle()
            .fill(selected ? Semantic.foreground : Semantic.surface)
            .overlay(Circle().stroke(Semantic.border, lineWidth: selected ? 0 : Stroke.hairline))
            .frame(width: 24, height: 24)
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.surface)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Six stacked bars, the lowest first, lit from the probe's smoothed level.
private struct MicLevelBars: View {
    let lit: Int

    var body: some View {
        VStack(spacing: Space.x0_5) {
            ForEach((0..<6).reversed(), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < lit ? Semantic.foreground : Semantic.border)
                    .frame(width: 32, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
