import CompanionCore
import Foundation

/// What the UI last painted, written by the views themselves (PR-5): the
/// island state is computed inside `IslandView` and the screen lives in
/// `CompanionRootView`'s private state, so a reconstruction from the session
/// would inspect something nobody saw.
@MainActor package final class InspectionMirror {
    package private(set) var island: PaintedIsland?
    package private(set) var screen: InspectedScreen?

    package init() {}

    /// The catalog sentence only for lines with no content in them: for the
    /// rest `IslandCopy.line` returns the goal, the follow-up or the error
    /// text itself.
    package func paint(_ state: IslandState) {
        let catalogText = state.line.carriesText ? nil : IslandCopy.line(state.line)
        island = PaintedIsland(state: state, catalogText: catalogText)
    }

    package func show(page: MainPage, settingsOpen: Bool, settingsTab: SettingsTab) {
        // The tab only means something while Settings is open; the root view
        // keeps the last one selected after it closes.
        screen = InspectedScreen(
            settingsOpen: settingsOpen,
            settingsTab: settingsOpen ? settingsTab.rawValue : nil,
            page: Self.name(of: page))
    }

    /// Exhaustive on purpose: a new page must pick a wire name, and the
    /// localized title is not one.
    private static func name(of page: MainPage) -> String {
        switch page {
        case .home: "home"
        case .apps: "apps"
        }
    }
}

/// The read port over what the app already holds. Nothing here writes: the
/// session and the chat are only read, and the mirror is written by the views.
/// Main-actor isolated like the models it reads; the bridge awaits each read,
/// which hops here (same pattern as `ChatViewModel: ConversationPresenting`).
@MainActor package final class SelfInspectionSource: SelfInspecting {
    private let sessionModel: SessionModel
    private let chat: ChatViewModel
    private let mirror: InspectionMirror
    private let languageStored: @MainActor () -> AppLanguage?

    package init(
        session: SessionModel,
        chat: ChatViewModel,
        mirror: InspectionMirror,
        languageStored: @escaping @MainActor () -> AppLanguage? = { LanguagePreference.stored }
    ) {
        self.sessionModel = session
        self.chat = chat
        self.mirror = mirror
        self.languageStored = languageStored
    }

    package func session() async -> SessionProjection {
        sessionModel.projection
    }

    package func island() async -> PaintedIsland? {
        mirror.island
    }

    package func screen() async -> InspectedScreen? {
        mirror.screen
    }

    /// The effective language is the one the app speaks right now, which is
    /// `Localized.language()`; reading the stored choice alone would answer
    /// "system" while the app talks Spanish.
    package func settings() async -> SettingsInspection {
        let voice = VoiceProfile.settings
        return SettingsInspection(
            languageStored: languageStored()?.rawValue,
            languageEffective: Localized.language().rawValue,
            appearance: AppearancePreference.stored.rawValue,
            voice: voice.voice.rawValue,
            volume: voice.volume,
            voiceMode: voice.mode.rawValue,
            dictationKey: voice.dictationKey,
            interfaceSounds: InterfaceSound.enabled,
            thinkingSound: ThinkingSoundPref.enabled,
            decision: DecisionPreference.enabled,
            handsLending: HandsLendingPreference.enabled,
            providerOrder: ProviderPreference.order,
            ownerName: UserProfile.ownerName,
            about: UserProfile.about,
            instructions: UserProfile.instructions,
            city: UserProfile.city,
            vocabularyWords: VocabularyPreference.words.count)
    }

    /// One input per message and nothing else: the conversation title is
    /// derived from the first user message and never enters the thread.
    package func activeThread() async -> [ThreadMessageInput] {
        chat.messages.map { message in
            ThreadMessageInput(
                role: message.role,
                isStatus: message.isStatus,
                origin: Self.origin(message.origin),
                isFailure: message.isFailure,
                restored: message.restored,
                attachments: message.attachments.count,
                text: message.text)
        }
    }

    /// Exhaustive so a new origin has to say how it goes on the wire.
    private static func origin(_ origin: MessageOrigin) -> ThreadMessageOrigin {
        switch origin {
        case .typed: .typed
        case .choice: .choice
        }
    }
}
