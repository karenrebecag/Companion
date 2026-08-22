import CompanionCore
import AppKit
import SwiftUI

struct SettingsLine<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.x1) {
                if !title.isEmpty {
                    Text(title)
                        .font(.uiLabel)
                        .foregroundStyle(Semantic.foreground)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.x3)
            trailing()
        }
    }
}

struct SettingsMultiline: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(title)
                .font(.uiLabel)
                .foregroundStyle(Semantic.foreground)
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.uiBody)
                .foregroundStyle(Semantic.foreground)
                .lineLimit(3 ... 6)
                .padding(.horizontal, Space.x3)
                .padding(.vertical, Space.x2)
                .background(Semantic.surface)
                .focused($focused)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(
                            focused ? Semantic.borderStrong : Semantic.border,
                            lineWidth: Stroke.hairline)
                )
        }
    }
}

struct SettingsAppPane: View {
    var chat: ChatViewModel?
    var updates: UpdateState?
    @Binding var fontDelta: Int
    @Binding var interfaceSounds: Bool
    @Binding var storageLabel: String
    @Binding var confirmPurge: Bool
    @State private var thinkingSound = ThinkingSoundPref.enabled
    @State private var hotkeyLabel = ""
    /// Bumped on a language change so every string on screen repaints.
    @State var languageTick = 0

    // La carpeta y el especialista viven en la barra superior, siempre a un
    // click; duplicarlos aqui creaba dos controles para el mismo estado.
    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            appearanceBlock
            hotkeyBlock
            soundBlock
            systemBlock
        }
        .onAppear { hotkeyLabel = voiceHotkey }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionShortcutsDidChange)
        ) { _ in
            hotkeyLabel = voiceHotkey
        }
    }

    private var appearanceBlock: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(Localized.string("settings.app.header"))
                .typeEyebrow()
            Text(Localized.string("settings.app.blurb"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
            HStack(spacing: Space.x2) {
                ForEach(AppearancePreference.allCases, id: \.self) { pref in
                    themeCard(pref)
                }
            }
            SettingsLine(
                title: Localized.string("settings.app.textSize"),
                subtitle: Localized.string("settings.app.textSize.subtitle")
            ) { fontStepper }
            SettingsLine(
                title: Localized.string("settings.app.typeface"),
                subtitle: Localized.string("settings.app.typeface.subtitle")
            ) { EmptyView() }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.x2),
                    GridItem(.flexible(), spacing: Space.x2),
                    GridItem(.flexible(), spacing: Space.x2),
                ],
                spacing: Space.x2
            ) {
                ForEach(AppTypeface.allCases, id: \.self) { face in
                    typeCard(face)
                }
            }
            SettingsLine(
                title: Localized.string("settings.app.accent"),
                subtitle: Localized.string("settings.app.accent.subtitle")
            ) {
                SettingsItem(
                    title: "",
                    value: Highlight.stored.label,
                    options: Highlight.allCases.map { ($0, $0.label) },
                    rainbow: { $0 == .standard },
                    swatch: { $0 == .standard ? nil : $0.swatch }
                ) { highlight in
                    Highlight.stored = highlight
                }
            }
            languageRow
        }
        .id(languageTick)
    }

    private var hotkeyBlock: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(Localized.string("settings.app.shortcut.header"))
                .typeEyebrow()
            SettingsLine(
                title: Localized.string("settings.app.shortcut.talk"),
                subtitle: Localized.string("settings.app.shortcut.subtitle")
            ) {
                Text(hotkeyLabel)
                    .font(.uiMono)
                    .foregroundStyle(Semantic.foreground)
                    .padding(.horizontal, Space.x3)
                    .padding(.vertical, Space.x2)
                    .background(Capsule().fill(Semantic.surface))
                    .overlay(
                        Capsule().stroke(Semantic.border, lineWidth: Stroke.hairline))
            }
            ShortcutCaptureField { keyCode, modifiers in
                var set = ShortcutSet.load()
                set.shortcuts.removeAll { $0.action == .toggleVoice }
                set.shortcuts.append(Shortcut(
                    action: .toggleVoice, keyCode: keyCode, modifiers: modifiers))
                set.save()
            }
        }
    }

    private var soundBlock: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(Localized.string("settings.app.sound.header"))
                .typeEyebrow()
            Toggle(Localized.string("settings.app.sound.interface"), isOn: $interfaceSounds)
                .font(.uiLabel)
                .foregroundStyle(Semantic.foreground)
                .tint(Semantic.accent)
                .onChange(of: interfaceSounds) { _, on in
                    InterfaceSound.enabled = on
                }
            Toggle(isOn: $thinkingSound) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(Localized.string("settings.app.sound.thinking"))
                        .font(.uiLabel)
                        .foregroundStyle(Semantic.foreground)
                    Text(Localized.string("settings.app.sound.thinking.subtitle"))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            }
            .toggleStyle(.switch)
            .tint(Semantic.accent)
            .onChange(of: thinkingSound) { _, on in
                ThinkingSoundPref.enabled = on
            }
        }
    }

    private var systemBlock: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(Localized.string("settings.app.system.header"))
                .typeEyebrow()
            VStack(alignment: .leading, spacing: Space.x2) {
                Text(Localized.string("settings.app.version"))
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                Text(appVersion)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                if let updates {
                    if let available = updates.available {
                        Link(
                            String(
                                format: Localized.string(
                                    "settings.app.version.see"),
                                available.tag),
                            destination: available.pageURL)
                        .font(.uiLabel)
                        .foregroundStyle(Semantic.accent)
                    } else {
                        AppButton(
                            updates.checking
                                ? Localized.string("settings.app.version.checking") : Localized.string("settings.app.version.check"),
                            kind: .ghost,
                            enabled: !updates.checking
                        ) {
                            updates.requestCheck()
                        }
                    }
                }
            }
            SettingsLine(
                title: Localized.string("settings.app.attachments"),
                subtitle: storageLabel
            ) {
                AppButton(
                    Localized.string("settings.purge.confirm"),
                    kind: .destructive,
                    enabled: chat?.hasStoredAttachments ?? false
                ) {
                    confirmPurge = true
                }
            }
        }
    }

    private var fontStepper: some View {
        HStack(spacing: Space.x1) {
            fontStep("minus", enabled: fontDelta > TypeScale.min) {
                fontDelta = TypeScale.nudge(-1)
            }
            Text(TypeScale.displayLabel(fontDelta))
                .font(.uiLabel)
                .foregroundStyle(Semantic.foreground)
                .frame(minWidth: Space.x6)
                .multilineTextAlignment(.center)
                .accessibilityLabel(String(
                    format: Localized.string("settings.app.textSize.label"),
                    TypeScale.displayLabel(fontDelta)))
            fontStep("plus", enabled: fontDelta < TypeScale.max) {
                fontDelta = TypeScale.nudge(1)
            }
        }
    }

    private func fontStep(
        _ symbol: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.uiCaption)
                .foregroundStyle(
                    enabled ? Semantic.foreground : Semantic.mutedForeground)
                .frame(
                    width: SettingsOverlayMetrics.stepHit,
                    height: SettingsOverlayMetrics.stepHit)
                .background(Circle().fill(Semantic.surface))
                .overlay(
                    Circle().stroke(Semantic.border, lineWidth: Stroke.hairline))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(
            symbol == "plus" ? Localized.string("settings.app.textSize.bigger") : Localized.string("settings.app.textSize.smaller"))
    }

    private func themeCard(_ pref: AppearancePreference) -> some View {
        let selected = AppearancePreference.stored == pref
        return Button {
            withAnimation(.springSelect) {
                AppearancePreference.stored = pref
                if let window = NSApp.keyWindow {
                    WindowChrome.applyAppearance(window)
                }
            }
        } label: {
            VStack(spacing: Space.x2) {
                Image(systemName: pref.symbol)
                    .font(Fonts.sans(TypeSize.md))
                    .foregroundStyle(
                        selected ? Semantic.foreground : Semantic.mutedForeground)
                Text(pref.label)
                    .font(.uiCaption)
                    .foregroundStyle(
                        selected ? Semantic.foreground : Semantic.mutedForeground)
            }
            .frame(maxWidth: .infinity)
            .frame(height: SettingsOverlayMetrics.cardHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Semantic.surface.opacity(selected ? 1 : 0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(
                        selected ? Semantic.foreground.opacity(0.65) : Semantic.border,
                        lineWidth: selected ? Stroke.thin : Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(pref.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func typeCard(_ face: AppTypeface) -> some View {
        let selected = AppTypeface.stored == face
        return Button {
            AppTypeface.stored = face
        } label: {
            VStack(spacing: Space.x2) {
                Text("Aa")
                    .font(Fonts.sample(face, size: TypeSize.lg))
                    .foregroundStyle(
                        selected ? Semantic.foreground : Semantic.mutedForeground)
                Text(face.label)
                    .font(.uiCaption)
                    .foregroundStyle(
                        selected ? Semantic.foreground : Semantic.mutedForeground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: SettingsOverlayMetrics.cardHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Semantic.surface.opacity(selected ? 1 : 0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(
                        selected ? Semantic.foreground.opacity(0.65) : Semantic.border,
                        lineWidth: selected ? Stroke.thin : Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(face.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var voiceHotkey: String {
        ShortcutSet.load().shortcut(for: .toggleVoice)?.displayKey()
            ?? "⌘⌥Espacio"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Localized.string("settings.app.version.unknown")
    }
}
