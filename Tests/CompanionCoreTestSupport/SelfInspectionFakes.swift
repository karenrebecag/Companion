import CompanionCore
import Foundation

/// A `SelfInspecting` whose every answer the test sets. Lock-guarded because
/// the runner reads it from whatever task the bridge call runs on.
package final class FakeSelfInspecting: SelfInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var _projection = SessionProjection()
    private var _island: PaintedIsland?
    private var _screen: InspectedScreen?
    private var _settings = FakeSelfInspecting.settings()
    private var _thread: [ThreadMessageInput] = []

    package init() {}

    package var projection: SessionProjection {
        get { lock.withLock { _projection } }
        set { lock.withLock { _projection = newValue } }
    }
    package var painted: PaintedIsland? {
        get { lock.withLock { _island } }
        set { lock.withLock { _island = newValue } }
    }
    package var shownScreen: InspectedScreen? {
        get { lock.withLock { _screen } }
        set { lock.withLock { _screen = newValue } }
    }
    package var shownSettings: SettingsInspection {
        get { lock.withLock { _settings } }
        set { lock.withLock { _settings = newValue } }
    }
    package var thread: [ThreadMessageInput] {
        get { lock.withLock { _thread } }
        set { lock.withLock { _thread = newValue } }
    }

    package func session() async -> SessionProjection { projection }
    package func island() async -> PaintedIsland? { painted }
    package func screen() async -> InspectedScreen? { shownScreen }
    package func settings() async -> SettingsInspection { shownSettings }
    package func activeThread() async -> [ThreadMessageInput] { thread }

    /// Settings with `text` in every free-text field, so a test can look for
    /// it in what comes out.
    package static func settings(text: String = "") -> SettingsInspection {
        SettingsInspection(
            languageStored: nil, languageEffective: "es", appearance: "system", voice: "marin",
            volume: 0.8, voiceMode: "realtime", dictationKey: .rightOption, interfaceSounds: true,
            thinkingSound: false, decision: false, handsLending: true, providerOrder: ["openai"],
            ownerName: text, about: text, instructions: text, city: text, vocabularyWords: 2)
    }

    package static func message(
        _ text: String, role: TurnRole? = .user, isStatus: Bool = false
    ) -> ThreadMessageInput {
        ThreadMessageInput(
            role: role, isStatus: isStatus, origin: .typed, isFailure: false, restored: false,
            attachments: 0, text: text)
    }
}
