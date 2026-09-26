import CompanionCore
import SwiftUI

// Wave 16c: the seven screens. Each says one thing; the container owns the
// stepper, Back, Skip and the black pill.

/// Title and one line under it, the same on every screen.
struct WelcomeHeading: View {
    let title: String
    var body_: String?

    var body: some View {
        VStack(spacing: Space.x3) {
            Text(title)
                .font(GeistFont.uiDisplay)
                .bold()
                .tracking(Tracking.tighter, at: TypeSize.display)
                .foregroundStyle(Semantic.foreground)
            if let body_ {
                Text(body_)
                    .font(GeistFont.uiSubtitle)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct WelcomeOrb: View {
    var state: TurnState = .idle
    var level = 0.0

    var body: some View {
        Orb(state: state, levels: VoiceLevels(mic: level, agent: 0), accentColor: Semantic.foreground)
            .frame(width: Container.hero, height: Container.hero)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

struct WelcomeCover: View {
    var body: some View {
        VStack(spacing: Space.x8) {
            WelcomeOrb()
            WelcomeHeading(
                title: Localized.string("welcome.cover.title"),
                body_: Localized.string("welcome.cover.body"))
        }
    }
}

struct WelcomeHello: View {
    @State private var name = UserProfile.ownerName
    @State private var language = LanguagePreference.current

    var body: some View {
        VStack(spacing: Space.x6) {
            WelcomeOrb(state: .speaking, level: 0.3)
            WelcomeHeading(
                title: Localized.string("welcome.hello.title"),
                body_: Localized.string("welcome.hello.body"))
            AppField(
                placeholder: Localized.string("welcome.hello.name"),
                text: $name, neutral: true)
                .onChange(of: name) { _, value in
                    UserProfile.ownerName = value.trimmingCharacters(in: .whitespaces)
                }
            HStack(spacing: Space.x2) {
                ForEach([AppLanguage.es, .en], id: \.self) { choice in
                    Button(Localized.string("welcome.language." + choice.rawValue)) {
                        language = choice
                        LanguagePreference.stored = choice
                    }
                    .buttonStyle(WelcomeChipStyle(selected: language == choice))
                }
            }
        }
    }
}

/// Incredible's chips: grey, the chosen one inked.
struct WelcomeChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GeistFont.uiLabel)
            .foregroundStyle(selected ? Semantic.primaryForeground : Semantic.foreground)
            .padding(.horizontal, Space.x4)
            .padding(.vertical, Space.x2)
            .background(Capsule().fill(selected ? Semantic.primary : Semantic.muted))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct WelcomeKeys: View {
    @Bindable var chat: ChatViewModel
    @Bindable var keys: KeysSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            WelcomeHeading(
                title: Localized.string("welcome.keys.title"),
                body_: Localized.string("welcome.keys.body"))
                .frame(maxWidth: .infinity)
            openAI
            recommended(.cerebras, field: $keys.cerebrasField, saved: keys.cerebrasSaved,
                        why: "welcome.keys.cerebras")
            recommended(.elevenLabs, field: $keys.elevenLabsField, saved: keys.elevenLabsSaved,
                        why: "welcome.keys.elevenLabs")
            if let error = keys.errorText {
                Text(error).font(GeistFont.uiCaption).foregroundStyle(Semantic.destructive)
            }
            if chat.needsOnboarding, case .base(let paths) = chat.startup, let local = paths.first {
                // ADR 001 kept a way in with no key at all; the welcome keeps it.
                Button(Localized.string("welcome.keys.local")) { chat.acceptLocalBase(local) }
                    .buttonStyle(.plain)
                    .font(GeistFont.uiCaption)
                    .underline()
                    .foregroundStyle(Semantic.mutedForeground)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var openAI: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            label("OpenAI", note: Localized.string("welcome.keys.required"))
            if !chat.needsOnboarding {
                saved
            } else {
                AppField(
                    placeholder: "sk-proj-…", text: $chat.onboardingKey,
                    error: chat.onboardingBusy || chat.onboardingKey.isEmpty ? nil : chat.errorText,
                    secure: true, neutral: true,
                    onSubmit: { Task { await chat.submitOnboarding() } })
                HStack(spacing: Space.x3) {
                    Button(Localized.string("welcome.keys.verify")) {
                        Task { await chat.submitOnboarding() }
                    }
                    .buttonStyle(WelcomeChipStyle(selected: true))
                    .disabled(chat.onboardingBusy || chat.onboardingKey.isEmpty)
                    if chat.onboardingBusy { ProgressView().controlSize(.small) }
                    Spacer()
                    Link(Localized.string("welcome.keys.where"),
                         destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(GeistFont.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            }
        }
    }

    private var saved: some View {
        HStack(spacing: Space.x2) {
            Image(systemName: "checkmark.circle.fill")
            Text(Localized.string("welcome.keys.saved"))
        }
        .font(GeistFont.uiCaption)
        .foregroundStyle(Semantic.foreground)
    }

    private func recommended(
        _ provider: KeysSettingsModel.Provider, field: Binding<String>, saved: Bool, why: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            label(provider == .cerebras ? "Cerebras" : "ElevenLabs",
                  note: Localized.string("welcome.keys.recommended"))
            Text(Localized.string(why))
                .font(GeistFont.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if saved {
                self.saved
            } else {
                AppField(placeholder: "", text: field, secure: true, neutral: true,
                         onSubmit: { keys.save(provider) })
            }
        }
    }

    private func label(_ name: String, note: String) -> some View {
        HStack(spacing: Space.x2) {
            Text(verbatim: name).font(GeistFont.uiLabel).bold().foregroundStyle(Semantic.foreground)
            Text(note).font(GeistFont.uiCaption).foregroundStyle(Semantic.mutedForeground)
        }
    }
}

struct WelcomePermissions: View {
    var welcome: WelcomeModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Space.x5) {
            WelcomeHeading(
                title: Localized.string("welcome.permissions.title"),
                body_: Localized.string("welcome.permissions.body"))
            VStack(spacing: Space.none) {
                ForEach(WelcomePermission.allCases, id: \.self) { permission in
                    row(permission)
                    if permission != WelcomePermission.allCases.last { Divider() }
                }
            }
            .padding(.horizontal, Space.x4)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Semantic.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Semantic.border, lineWidth: Stroke.hairline))
        }
    }

    private func row(_ permission: WelcomePermission) -> some View {
        let granted = welcome.facts.granted.contains(permission)
        return HStack(spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(Localized.string("welcome.permission." + permission.rawValue))
                    .font(GeistFont.uiLabel).foregroundStyle(Semantic.foreground)
                Text(Localized.string("welcome.permission." + permission.rawValue + ".why"))
                    .font(GeistFont.uiCaption).foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.x2)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Semantic.foreground)
                    .accessibilityLabel(Localized.string("permission.granted"))
            } else {
                Button(Localized.string("welcome.permission.allow")) {
                    Task {
                        await welcome.request(permission)
                        // The prompt shows once; after a deny only Settings can.
                        if !welcome.facts.granted.contains(permission) { openURL(permission.settingsLink) }
                    }
                }
                .buttonStyle(WelcomeChipStyle(selected: true))
            }
        }
        .padding(.vertical, Space.x3)
    }
}

/// The key, drawn as a key.
struct WelcomeKeycap: View {
    private static let side: CGFloat = 72

    var body: some View {
        Text(verbatim: "fn")
            .font(Fonts.mono(TypeSize.title, bold: true))
            .foregroundStyle(Semantic.foreground)
            .frame(width: Self.side, height: Self.side)
            // 16l: Incredible's large keycap — radius 12, a lip, a soft drop.
            .background(RoundedRectangle(cornerRadius: KeycapSize.large.radius).fill(Semantic.surface))
            .overlay(
                RoundedRectangle(cornerRadius: KeycapSize.large.radius)
                    .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
            .accessibilityLabel(Localized.string("welcome.holdKey.cap"))
    }
}

struct WelcomeHoldKey: View {
    @Environment(\.openURL) private var openURL
    private static let keyboard = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    var body: some View {
        VStack(spacing: Space.x6) {
            WelcomeKeycap()
            WelcomeHeading(
                title: Localized.string("welcome.holdKey.title"),
                body_: Localized.string("welcome.holdKey.body"))
            VStack(spacing: Space.x2) {
                Text(Localized.string("welcome.holdKey.globe"))
                    .font(GeistFont.uiCaption).foregroundStyle(Semantic.mutedForeground)
                    .multilineTextAlignment(.center)
                Button(Localized.string("welcome.holdKey.openKeyboard")) { openURL(Self.keyboard) }
                    .buttonStyle(WelcomeChipStyle(selected: false))
            }
        }
    }
}

struct WelcomeMicrophone: View {
    let level: Double
    let heard: Bool
    private static let barHeight: CGFloat = 8

    var body: some View {
        VStack(spacing: Space.x6) {
            WelcomeOrb(state: .listening, level: level)
            WelcomeHeading(
                title: Localized.string("welcome.microphone.title"),
                body_: Localized.string(heard ? "welcome.microphone.heard" : "welcome.microphone.body"))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Semantic.muted)
                    Capsule().fill(Semantic.foreground)
                        .frame(width: geometry.size.width * CGFloat(min(max(level, 0), 1)))
                }
            }
            .frame(height: Self.barHeight)
            .animation(.expoOut(MotionTime.fast), value: level)
            .accessibilityHidden(true)
        }
    }
}

/// Incredible's "It's your turn": the screen dims, the key, the exact
/// sentence. It ends only with a real hold (or Skip).
struct WelcomeYourTurn: View {
    let partial: String?

    var body: some View {
        VStack(spacing: Space.x8) {
            WelcomeKeycap()
            WelcomeHeading(
                title: Localized.string("welcome.yourTurn.title"),
                body_: Localized.string("welcome.yourTurn.body"))
            if let partial, !partial.isEmpty {
                Text(partial)
                    .font(GeistFont.uiSubtitle)
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(2)
                    .truncationMode(.head)
            }
        }
    }
}
