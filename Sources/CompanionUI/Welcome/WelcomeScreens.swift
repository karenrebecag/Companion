import CompanionCore
import CompanionUIPro
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
    var size = Container.hero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The welcome text under the orb carries the meaning, so the orb
        // itself is hidden from VoiceOver rather than given a label.
        VoiceOrb(
            state: VoiceOrbState(state),
            muted: false,
            inputLevel: Self.levels(state: state, level: level).input,
            outputLevel: Self.levels(state: state, level: level).output,
            size: size,
            palette: .surface(colorScheme: colorScheme),
            accessibilityLabel: "")
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// Welcome has one level, the mic test's or the hello's: it belongs to
    /// whoever is talking, and nil elsewhere lets the orb rest.
    static func levels(state: TurnState, level: Double) -> (input: Double?, output: Double?) {
        switch state {
        case .listening: (level, nil)
        case .speaking: (nil, level)
        default: (nil, nil)
        }
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
            WelcomeOrb(state: .speaking, level: 0.3, size: Container.heroCompact)
            WelcomeNameForm(name: $name)
                .onChange(of: name) { _, value in
                    UserProfile.ownerName = value.trimmingCharacters(in: .whitespaces)
                }
            HStack(spacing: Space.x2) {
                ForEach([AppLanguage.es, .en], id: \.self) { choice in
                    Button(Localized.string("welcome.language." + choice.rawValue)) {
                        language = choice
                        LanguagePreference.stored = choice
                    }
                    .buttonStyle(CapsuleChipStyle(ink: .choice(selected: language == choice), density: .regular))
                }
            }
        }
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
                    .buttonStyle(CapsuleChipStyle(ink: .choice(selected: true), density: .regular))
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
    /// The group whose Allow was pressed last; the guide follows it until
    /// that permission is granted.
    @State private var acting: WelcomePermission?

    var body: some View {
        let granted = welcome.facts.granted
        let active = PermissionGuide.active(granted: granted, acting: acting)
        // Nothing state-dependent is drawn before the first read of the
        // machine, so a resume neither flashes wrong states nor pops badges.
        if let states = PermissionGuide.states(granted: granted, acting: acting, hydrated: welcome.hasRefreshed) {
            HStack(alignment: .center, spacing: Space.x8) {
                // The minimum window is shorter than the four groups; a shorter
                // column is centred against the guide.
                GeometryReader { viewport in
                    ScrollView {
                        VStack(spacing: Space.x5) {
                            WelcomeHeading(
                                title: Localized.string("welcome.permissions.title"),
                                body_: Localized.string("welcome.permissions.body"))
                            VStack(spacing: Space.x3) {
                                ForEach(WelcomePermission.allCases, id: \.self) { permission in
                                    group(permission, state: states[permission] ?? .upcoming)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(maxWidth: .infinity)
                PermissionGuideAside(active: active)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func group(_ permission: WelcomePermission, state: PermissionGuide.GroupState) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.cardSm, style: .continuous)
        return HStack(spacing: Space.x3) {
            PermissionStepBadge(number: PermissionGuide.number(of: permission), state: state)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(Localized.string("welcome.permission." + permission.rawValue))
                    .font(GeistFont.uiLabel).foregroundStyle(Semantic.foreground)
                Text(Localized.string("welcome.permission." + permission.rawValue + ".why"))
                    .font(GeistFont.uiCaption).foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.x2)
            if state != .granted {
                Button(Localized.string("welcome.permission.allow")) { allow(permission) }
                    .buttonStyle(CapsuleChipStyle(ink: .choice(selected: true), density: .regular))
            }
        }
        .padding(Space.x5)
        .background(shape.fill(state == .active ? Semantic.surfaceSecondary : Semantic.surface))
        .overlay(shape.stroke(Semantic.border, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .contain)
    }

    private func allow(_ permission: WelcomePermission) {
        acting = permission
        Task {
            await welcome.request(permission)
            // The prompt shows once; after a deny only Settings can.
            if !welcome.facts.granted.contains(permission) { openURL(permission.settingsLink) }
            acting = PermissionGuide.acting(
                afterFinishing: permission, current: acting, granted: welcome.facts.granted)
        }
    }
}

/// The 24 px numbered circle; granted, it turns green and pops once.
struct PermissionStepBadge: View {
    let number: Int
    let state: PermissionGuide.GroupState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pops = 0

    var body: some View {
        Circle().fill(fill)
            .frame(width: Space.x6, height: Space.x6)
            .overlay {
                if state == .granted {
                    Image(systemName: "checkmark").font(GeistFont.uiCaption).bold()
                } else {
                    Text(verbatim: String(number)).font(GeistFont.uiCaption)
                }
            }
            .foregroundStyle(state == .active ? Semantic.background : Semantic.foreground)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: pops) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in Self.bounceTrack }
            .onChange(of: state) { old, new in
                if PermissionGuide.bounces(from: old, to: new, reduceMotion: reduceMotion) { pops += 1 }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PermissionGuide.stepLabel(number: number))
            .accessibilityValue(PermissionGuide.stateLabel(state))
    }

    private static let samples = 12

    private static var bounceTrack: some Keyframes<CGFloat> {
        let scales: [CGFloat] = PermissionGuide.bounceScales(count: samples)
        let step: Double = MotionTime.stepGranted / Double(samples - 1)
        return KeyframeTrack {
            MoveKeyframe(scales[0])
            for scale in scales.dropFirst() {
                LinearKeyframe(scale, duration: step)
            }
        }
    }

    private var fill: Color {
        switch state {
        case .active: Semantic.foreground
        case .granted: Semantic.successMuted
        case .upcoming: Semantic.surfaceSecondary
        }
    }
}

struct WelcomeHoldKey: View {
    @Environment(\.openURL) private var openURL
    private static let keyboard = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    var body: some View {
        VStack(spacing: Space.x6) {
            Keycap("fn", size: .hero)
                .accessibilityLabel(Localized.string("welcome.holdKey.cap"))
            WelcomeHeading(
                title: Localized.string("welcome.holdKey.title"),
                body_: Localized.string("welcome.holdKey.body"))
            VStack(spacing: Space.x2) {
                Text(Localized.string("welcome.holdKey.globe"))
                    .font(GeistFont.uiCaption).foregroundStyle(Semantic.mutedForeground)
                    .multilineTextAlignment(.center)
                Button(Localized.string("welcome.holdKey.openKeyboard")) { openURL(Self.keyboard) }
                    .buttonStyle(CapsuleChipStyle(ink: .choice(selected: false), density: .regular))
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
            Keycap("fn", size: .hero)
                .accessibilityLabel(Localized.string("welcome.holdKey.cap"))
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
