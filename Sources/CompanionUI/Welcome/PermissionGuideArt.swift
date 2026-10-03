import CompanionCore
import SwiftUI

/// The picture that says why a permission is asked: a drawn miniature of the
/// macOS surface where the user grants it, with a pointer on the control.
/// Native shapes and SF Symbols only, so it follows the scheme and the type
/// of the app instead of a bitmap that would go stale with macOS.
struct PermissionGuideArt: View {
    /// The guide frame is square (Incredible: aspect-ratio 1) and the brief
    /// sizes it at 240.
    static let defaultSize: CGFloat = 240

    let kind: WelcomePermission
    var size: CGFloat = Self.defaultSize

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        ZStack {
            frame.fill(Semantic.surfaceSecondary)
            scene
        }
        .frame(width: size, height: size)
        .clipShape(frame)
        .overlay(frame.stroke(Semantic.border, lineWidth: Stroke.hairline))
        .elevation(.rest)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(for: kind))
    }

    static func accessibilityText(for kind: WelcomePermission) -> String {
        Localized.string("welcome.guide." + kind.rawValue)
    }

    @ViewBuilder private var scene: some View {
        switch kind {
        case .microphone: microphoneDialog
        case .accessibility: settingsRow(symbol: "accessibility")
        case .screenRecording: screenScene
        case .speechRecognition: speechScene
        }
    }

    private var microphoneDialog: some View {
        VStack(spacing: size * 0.05) {
            symbol("mic.fill", scale: 0.16)
            lines(widths: [0.5, 0.36])
            Capsule().fill(Semantic.primary)
                .frame(width: size * 0.3, height: size * 0.09)
                .overlay { pointer.offset(x: size * 0.1, y: size * 0.07) }
        }
        .padding(size * 0.08)
        .frame(width: size * 0.66)
        .background(card)
    }

    private func settingsRow(symbol name: String) -> some View {
        HStack(spacing: size * 0.06) {
            symbol(name, scale: 0.14)
            lines(widths: [0.22, 0.14])
            toggle.overlay { pointer.offset(x: size * 0.04, y: size * 0.07) }
        }
        .padding(size * 0.07)
        .frame(width: size * 0.8)
        .background(card)
    }

    private var screenScene: some View {
        VStack(spacing: size * 0.06) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Semantic.foreground, lineWidth: Stroke.medium)
                .frame(width: size * 0.5, height: size * 0.3)
                .overlay { symbol("record.circle", scale: 0.12) }
            settingsRow(symbol: "display").scaleEffect(0.82)
        }
    }

    private var speechScene: some View {
        VStack(spacing: size * 0.06) {
            symbol("waveform", scale: 0.2)
            Image(systemName: "arrow.down")
                .foregroundStyle(Semantic.mutedForeground)
            lines(widths: [0.56, 0.42, 0.5]).padding(size * 0.06).background(card)
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(Semantic.surface)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Semantic.border, lineWidth: Stroke.hairline))
    }

    private func symbol(_ name: String, scale: CGFloat) -> some View {
        Image(systemName: name)
            .resizable().scaledToFit()
            .frame(width: size * scale, height: size * scale)
            .foregroundStyle(Semantic.foreground)
    }

    private func lines(widths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: size * 0.03) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                Capsule().fill(Semantic.border)
                    .frame(width: size * width, height: size * 0.03)
            }
        }
    }

    private var toggle: some View {
        Capsule().fill(Semantic.primary)
            .frame(width: size * 0.17, height: size * 0.1)
            .overlay(alignment: .trailing) {
                Circle().fill(Semantic.primaryForeground)
                    .frame(width: size * 0.08, height: size * 0.08)
                    .padding(size * 0.01)
            }
    }

    private var pointer: some View {
        Image(systemName: "cursorarrow")
            .resizable().scaledToFit()
            .frame(width: size * 0.09, height: size * 0.09)
            .foregroundStyle(Semantic.foreground)
            .shadow(color: Semantic.surface, radius: 1)
    }
}
