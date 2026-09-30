import CompanionCore
import SwiftUI

/// Wave 16k-2b (spec §9.2.2, D1 layout, D2/§9.6 audited phases): the
/// "Connecting Slack" modal. Renders `AppsModel`'s own `connectPhase` — no
/// timer lives here; the 3 s poll runs in the model, this view only paints.
package enum ConnectingSheetMetrics {
    // 16k-2d: Incredible's real modal (captured live 2026-09-28) is a
    // centered composition — big title, 72pt icon lockup, one centered
    // action — not a leading-aligned card.
    package static let maxWidth: CGFloat = 520
    // Only the 72 icon was read off the capture; the sheet width, track and dot
    // are Companion's own.
    package static let icon: CGFloat = 72
    package static let trackWidth: CGFloat = 120
    package static let dot: CGFloat = 8
}

struct ConnectingSheet: View {
    let app: CatalogApp
    let phase: ConnectPoll.Phase
    let showsHint: Bool
    let onOpenAgain: () -> Void
    let onRetry: () -> Void
    let onFinish: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: Space.x5) {
            Text(ConnectingCopy.title(phase, app: app.name))
                .font(Fonts.sans(TypeSize.display).weight(.semibold))
                .tracking(Tracking.title, at: TypeSize.display)
                .foregroundStyle(Semantic.foreground)
                .multilineTextAlignment(.center)
            track
            Text(ConnectingCopy.body(phase, app: app.name))
                .typeRole(.body)
                .foregroundStyle(bodyForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showsHint {
                Text(Localized.string("apps.connecting.hint"))
                    .typeRole(.micro)
                    .foregroundStyle(Semantic.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
            Text(Localized.string("apps.panel.privacy"))
                .typeRole(.micro)
                .foregroundStyle(Semantic.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.x8)
        .padding(.vertical, Space.x8)
        .frame(maxWidth: ConnectingSheetMetrics.maxWidth)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Semantic.background))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Semantic.border, lineWidth: Stroke.hairline))
        .overlay(alignment: .topTrailing) { closeButton.padding(Space.x4) }
    }

    private var closeButton: some View {
        CloseButton(action: onClose)
    }

    private var track: some View {
        HStack(spacing: Space.x4) {
            CompanionMarkIcon()
            ConnectTrack(complete: phase == .complete)
            AppIconView(icon: app.icon, size: ConnectingSheetMetrics.icon, padding: Space.x3)
                .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Semantic.surface))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
        }
    }

    private var bodyForeground: Color {
        if case .failed = phase { return Semantic.destructive }
        return Semantic.mutedForeground
    }

    @ViewBuilder
    private var buttons: some View {
        switch phase {
        case .initiating, .waiting:
            AppButton(Localized.string("apps.connecting.openAgain"), kind: .secondary, action: onOpenAgain)
        case .timedOut:
            HStack(spacing: Space.x2) {
                AppButton(Localized.string("apps.connecting.retry"), action: onRetry)
                AppButton(Localized.string("apps.connecting.openAgain"), kind: .secondary, action: onOpenAgain)
            }
        case .complete:
            AppButton(Localized.string("apps.connecting.letsGo"), action: onFinish)
        case .failed:
            EmptyView()
        }
    }
}

/// The Companion side of the track. A plain glyph in a rounded tile: the
/// modal names who connects, it does not need an animated identity.
private struct CompanionMarkIcon: View {
    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.uiBody)
            .foregroundStyle(Semantic.primaryForeground)
            .frame(width: ConnectingSheetMetrics.icon, height: ConnectingSheetMetrics.icon)
            .background(RoundedRectangle(cornerRadius: AppsMetrics.iconRadius).fill(Semantic.primary))
            .accessibilityHidden(true)
    }
}

/// Two icons joined by a line with a traveling dot (spec §9.2 D1); reduced
/// motion keeps the dot still instead of animating it. On complete, a check
/// replaces the dot on the same track.
private struct ConnectTrack: View {
    let complete: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var traveling = false

    private var span: CGFloat { ConnectingSheetMetrics.trackWidth / 2 - ConnectingSheetMetrics.dot / 2 }

    var body: some View {
        ZStack {
            Capsule()
                .fill(Semantic.borderChrome)
                .frame(width: ConnectingSheetMetrics.trackWidth, height: Stroke.hairline)
            if complete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.uiBody)
                    .foregroundStyle(IslandInk.green)
            } else {
                Circle()
                    .fill(Semantic.primary)
                    .frame(width: ConnectingSheetMetrics.dot, height: ConnectingSheetMetrics.dot)
                    .offset(x: reduceMotion ? 0 : (traveling ? span : -span))
                    .onAppear(perform: startTraveling)
            }
        }
        .frame(width: ConnectingSheetMetrics.trackWidth)
        .accessibilityHidden(true)
    }

    private func startTraveling() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: MotionTime.layout * 2).repeatForever(autoreverses: true)) {
            traveling = true
        }
    }
}

enum ConnectingCopy {
    static func title(_ phase: ConnectPoll.Phase, app: String) -> String {
        switch phase {
        case .initiating, .waiting:
            String(format: Localized.string("apps.connecting.title.progress"), app)
        case .complete:
            String(format: Localized.string("apps.connecting.title.complete"), app)
        case .timedOut:
            String(format: Localized.string("apps.connecting.title.timedOut"), app)
        case .failed:
            String(format: Localized.string("apps.connecting.title.failed"), app)
        }
    }

    static func body(_ phase: ConnectPoll.Phase, app: String) -> String {
        switch phase {
        case .initiating, .waiting:
            String(format: Localized.string("apps.connecting.body"), app)
        case .complete:
            String(format: Localized.string("apps.connecting.complete"), app)
        case .timedOut:
            String(format: Localized.string("apps.connecting.timedOut"), app)
        case .failed(let message):
            message
        }
    }
}
