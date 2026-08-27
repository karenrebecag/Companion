import CompanionCore
import SwiftUI

/// First run. The key used to be the only door; now it is the upgrade, and the
/// screen shows whichever way in this Mac actually has.
///
/// Estructura (review 2026-08-26): progressive disclosure — primero se ELIGE
/// el camino en dos radio cards (local o nube), luego se revela solo el flujo
/// elegido, y un único CTA anclado a la base hace la acción. Todo centrado en
/// la columna de lectura (`SheetColumn`), siempre en claro y blanco y negro.
public struct OnboardingView: View {
    @Bindable var model: ChatViewModel
    @State private var chosen: Choice?
    @State private var awaitingOllama = false

    private enum Choice { case local, cloud }

    public init(model: ChatViewModel) {
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .top) {
            washes
            SheetColumn {
                VStack(spacing: Space.none) {
                    Spacer(minLength: Space.x8)
                    hero
                    Spacer(minLength: Space.x8)
                    header
                    Spacer(minLength: Space.x6)
                    choices
                    disclosure
                    Spacer(minLength: Space.x6)
                    ctaArea
                    Spacer(minLength: Space.x6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Semantic.background)
        // The first screen is always light and black-and-white: clean paper
        // before the app's own accent enters (decision de Karen 2026-08-26).
        .environment(\.colorScheme, .light)
    }

    /// The chosen path, with an honest default: the way that is READY. A Mac
    /// with a local model starts local; one without starts on the faster
    /// cloud path.
    private var choice: Choice {
        chosen ?? (hasLocalPath ? .local : .cloud)
    }

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
            accentColor: Semantic.foreground)
        .frame(height: Container.hero)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: Space.x4) {
            HStack(spacing: Space.x2) {
                Image(systemName: "waveform")
                    .font(.uiEyebrow)
                Text("COMPANION")  // token-exempt: nombre del producto.
                    .font(.uiEyebrow)
                    .tracking(Tracking.wide, at: TypeSize.micro)
            }
            .foregroundStyle(Semantic.mutedForeground)

            (Text(Localized.string("onboarding.title.l1"))
                + Text(verbatim: "\n")
                + Text(Localized.string("onboarding.title.l2")))
                .font(.uiDisplay)
                .bold()
                .tracking(Tracking.tighter, at: TypeSize.display)
                .foregroundStyle(Semantic.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text(Localized.string("onboarding.blurb"))
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Elección

    private var choices: some View {
        VStack(spacing: Space.x2) {
            ChoiceCard(
                title: Localized.string("onboarding.choice.local.title"),
                subtitle: Localized.string("onboarding.choice.local.sub"),
                status: localStatus,
                selected: choice == .local
            ) { chosen = .local }
            ChoiceCard(
                title: Localized.string("onboarding.choice.cloud.title"),
                subtitle: Localized.string("onboarding.choice.cloud.sub"),
                status: nil,
                selected: choice == .cloud
            ) { chosen = .cloud }
        }
    }

    /// Visibility of system status: the scan is shown INSIDE the option it
    /// concerns — spinner while it runs, its verdict when it lands.
    private var localStatus: ChoiceStatus? {
        switch model.startup {
        case .probing:
            return ChoiceStatus(
                text: Localized.string("onboarding.probing"), busy: true)
        case .base(let paths):
            guard let first = paths.first else { return nil }
            let name = first.model
                ?? Localized.string("onboarding.local.apple.short")
            return ChoiceStatus(
                text: String(format: Localized.string("onboarding.local.ready"),
                             name),
                busy: false)
        case .none:
            return ChoiceStatus(
                text: Localized.string("onboarding.local.none.status"),
                busy: false)
        case .premium:
            return nil
        }
    }

    // MARK: - Disclosure del flujo elegido

    @ViewBuilder private var disclosure: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            switch choice {
            case .local:
                localDisclosure
            case .cloud:
                cloudDisclosure
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.x4)
    }

    @ViewBuilder private var localDisclosure: some View {
        if case .none = model.startup {
            Text(Localized.string("onboarding.ollama.what"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if awaitingOllama {
                HStack(spacing: Space.x2) {
                    ProgressView()
                        .controlSize(.small)
                    Text(Localized.string("onboarding.ollama.waiting"))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            }
        } else if case .base(let paths) = model.startup, paths.count > 1 {
            // More than one way in: the CTA takes the preferred one, the rest
            // stay reachable without hunting.
            ForEach(paths.dropFirst(), id: \.providerName) { path in
                AppButton(
                    pathTitle(path), kind: .ghost,
                    shape: .pill, fullWidth: true
                ) {
                    model.acceptLocalBase(path)
                }
            }
        }
    }

    @ViewBuilder private var cloudDisclosure: some View {
        Text(Localized.string("onboarding.key.optional"))
            .font(.uiCaption)
            .foregroundStyle(Semantic.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)

        AppField(
            title: nil,
            placeholder: "sk-proj-...",
            text: $model.onboardingKey,
            // An empty field has nothing to be wrong about: the error only
            // appears once there is a key to judge.
            error: model.onboardingBusy || model.onboardingKey.isEmpty
                ? nil : model.errorText,
            secure: true,
            neutral: true,
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

    // MARK: - CTA único, anclado

    @ViewBuilder private var ctaArea: some View {
        VStack(spacing: Space.x3) {
            switch choice {
            case .local:
                localCTA
            case .cloud:
                AppButton(
                    Localized.string("onboarding.continue"),
                    kind: .neutral, shape: .pill, fullWidth: true,
                    enabled: !cannotContinue
                ) {
                    Task { await model.submitOnboarding() }
                }
                Link(destination: URL(
                    string: "https://platform.openai.com/api/keys")!) {
                    Text(Localized.string("onboarding.getKey"))
                        .font(.uiCaption)
                        .underline()
                        .foregroundStyle(Semantic.mutedForeground)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var localCTA: some View {
        switch model.startup {
        case .probing:
            AppButton(
                Localized.string("onboarding.cta.probing"),
                kind: .neutral, shape: .pill, fullWidth: true,
                enabled: false
            ) {}
        case .base(let paths):
            if let first = paths.first {
                AppButton(
                    pathTitle(first), kind: .neutral,
                    shape: .pill, fullWidth: true
                ) {
                    model.acceptLocalBase(first)
                }
            }
        case .none:
            AppButton(
                Localized.string("onboarding.ollama.download"),
                kind: .neutral, shape: .pill, fullWidth: true
            ) {
                NSWorkspace.shared.open(
                    URL(string: "https://ollama.com/download/mac")!)
                awaitingOllama = true
            }
            if awaitingOllama {
                AppButton(
                    Localized.string("onboarding.ollama.installed"),
                    kind: .ghost, shape: .pill, fullWidth: true
                ) {
                    model.retryLocalProbe()
                }
            }
        case .premium:
            EmptyView()
        }
    }

    // MARK: - Helpers

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

// MARK: - Piezas

private struct ChoiceStatus {
    let text: String
    let busy: Bool
}

/// Radio card: choosing comes FIRST, the chosen flow reveals after — two live
/// forms side by side made one sentence point across the sheet (review
/// 2026-08-26). Selection reads by ring and dot, not by color.
private struct ChoiceCard: View {
    let title: String
    let subtitle: String
    let status: ChoiceStatus?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.x3) {
                Image(systemName: selected ? "inset.filled.circle" : "circle")
                    .font(.uiLabel)
                    .foregroundStyle(selected
                        ? Semantic.foreground : Semantic.mutedForeground)
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(title)
                        .font(.uiLabel)
                        .bold()
                        .foregroundStyle(Semantic.foreground)
                    Text(subtitle)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    if let status {
                        HStack(spacing: Space.x2) {
                            if status.busy {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(status.text)
                                .font(.uiCaption)
                                .foregroundStyle(Semantic.foreground)
                        }
                        .padding(.top, Space.x1)
                    }
                }
                Spacer(minLength: Space.none)
            }
            .padding(Space.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Semantic.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(
                        selected ? Semantic.foreground : Semantic.border,
                        lineWidth: selected ? Stroke.medium : Stroke.hairline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
