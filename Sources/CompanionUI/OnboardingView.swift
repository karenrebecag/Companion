import CompanionCore
import SwiftUI

/// First run. The key used to be the only door; now it is the upgrade, and the
/// screen shows whichever way in this Mac actually has.
///
/// Layout (2026-08-26): hero orb over whisper-light washes, then the
/// eyebrow → display title → muted blurb hierarchy, then the state's own
/// content, and a full-width pill CTA — the R-06 shape system's round pole.
public struct OnboardingView: View {
    @Bindable var model: ChatViewModel

    public init(model: ChatViewModel) {
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .top) {
            washes
            VStack(alignment: .leading, spacing: Space.none) {
                Spacer(minLength: Space.x8)
                hero
                Spacer(minLength: Space.x8)
                header
                Spacer(minLength: Space.x6)
                stateContent
                Spacer()
                footer
            }
            .padding(.horizontal, Space.x8)
            .padding(.bottom, Space.x6)
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Barely-there color fields: a glow under the hero and a faint tint on
    /// the top of the sheet, both from the accent at whisper opacity.
    private var washes: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Wash.field, .clear],
                    startPoint: .top, endPoint: .center)
                RadialGradient(
                    colors: [Wash.hero, .clear],
                    center: .init(x: 0.5, y: 0.22),
                    startRadius: 0,
                    endRadius: geo.size.width / 2)
            }
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        Orb(
            state: .idle,
            levels: VoiceLevels(mic: 0, agent: 0),
            accentColor: Semantic.accent)
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x2) {
                Image(systemName: "waveform")
                    .font(.uiEyebrow)
                Text("COMPANION")  // token-exempt: nombre del producto.
                    .font(.uiEyebrow)
                    .tracking(Tracking.wide, at: TypeSize.micro)
            }
            .foregroundStyle(Semantic.accentText)

            (Text(Localized.string("onboarding.title.l1"))
                + Text(verbatim: "\n")
                + Text(Localized.string("onboarding.title.l2")))
                .font(.uiDisplay)
                .bold()
                .tracking(Tracking.tighter, at: TypeSize.display)
                .foregroundStyle(Semantic.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text(blurb)
                .font(.uiBody)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The headline follows the state: promising a local model before the
    /// probe answers is how a launch ends up contradicting itself.
    private var blurb: String {
        switch model.startup {
        case .probing:
            return Localized.string("onboarding.probing")
        case .base:
            return Localized.string("onboarding.base.blurb")
        case .none, .premium:
            return Localized.string("onboarding.blurb")
        }
    }

    @ViewBuilder private var stateContent: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            switch model.startup {
            case .probing:
                HStack(spacing: Space.x2) {
                    ProgressView()
                        .controlSize(.small)
                    Text(Localized.string("onboarding.probing"))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            case .base(let paths):
                VStack(spacing: Space.x2) {
                    ForEach(paths, id: \.providerName) { path in
                        AppButton(
                            pathTitle(path), kind: .primary,
                            shape: .pill, fullWidth: true
                        ) {
                            model.acceptLocalBase(path)
                        }
                    }
                }
            case .none:
                Text(Localized.string("onboarding.local.missing"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            case .premium:
                EmptyView()
            }

            keyEntry
        }
    }

    @ViewBuilder private var keyEntry: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(Localized.string("onboarding.key.optional"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)

            AppField(
                title: nil,
                placeholder: "sk-proj-...",
                text: $model.onboardingKey,
                error: model.onboardingBusy ? nil : model.errorText,
                secure: true,
                onSubmit: { Task { await model.submitOnboarding() } })

            if model.onboardingBusy {
                HStack(spacing: Space.x2) {
                    ProgressView()
                        .controlSize(.small)
                    Text(Localized.string("onboarding.verifying"))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Space.x3) {
            AppButton(
                Localized.string("onboarding.continue"),
                kind: hasLocalPath ? .secondary : .primary,
                shape: .pill, fullWidth: true,
                enabled: !cannotContinue
            ) {
                Task { await model.submitOnboarding() }
            }

            Link(destination: URL(string: "https://platform.openai.com/api/keys")!) {
                Text(Localized.string("onboarding.getKey"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.accentText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func pathTitle(_ path: LocalPath) -> String {
        guard let model = path.model else {
            return Localized.string("onboarding.local.apple")
        }
        return String(format: Localized.string("onboarding.local.ollama"), model)
    }

    private var hasLocalPath: Bool {
        if case .base = model.startup { return true }
        return false
    }

    private var cannotContinue: Bool {
        model.onboardingBusy
            || model.onboardingKey.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }
}
