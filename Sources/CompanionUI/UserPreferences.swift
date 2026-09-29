import AppKit
import CompanionCore
import Foundation

/// Preferences the window owns. Kept out of Config (which describes the
/// product) because these are this user's choices and must survive relaunch.
/// The app's language: the system's unless the user picked one. Stored as
/// the raw code so an unknown value (a downgrade, a hand-edited default)
/// resolves to the source language instead of crashing.
public enum LanguagePreference {
    nonisolated private static let key = "companion.language"

    /// nil means "follow the system", which is not the same as English.
    nonisolated public static var stored: AppLanguage? {
        get {
            UserDefaults.standard.string(forKey: key)
                .flatMap(AppLanguage.init(rawValue:))
        }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key) }
    }

    nonisolated public static var current: AppLanguage {
        AppLanguage.resolved(
            preferred: stored, system: Locale.preferredLanguages)
    }
}

public enum UserProfile {
    nonisolated private static let nameKey = "companion.ownerName"
    nonisolated private static let aboutKey = "companion.ownerAbout"
    nonisolated private static let instructionsKey = "companion.ownerInstructions"

    nonisolated public static var ownerName: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    nonisolated public static var about: String {
        get { UserDefaults.standard.string(forKey: aboutKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: aboutKey) }
    }

    nonisolated public static var instructions: String {
        get { UserDefaults.standard.string(forKey: instructionsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: instructionsKey) }
    }

    public static var avatarURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/avatar.png")
    }

    @MainActor
    public static var avatarImage: NSImage? {
        let url = avatarURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    @MainActor
    public static func setAvatar(from source: URL) -> Bool {
        let dest = avatarURL
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            NotificationCenter.default.post(
                name: .companionProfileDidChange, object: nil)
            return true
        } catch {
            return false
        }
    }
}

public enum AppearancePreference: String, CaseIterable, Equatable {
    case light, dark, auto

    public static let key = "companionAppearance"

    public var label: String {
        switch self {
        case .light: Localized.string("appearance.light")
        case .dark: Localized.string("appearance.dark")
        case .auto: Localized.string("appearance.auto")
        }
    }

    public var symbol: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .auto: "circle.lefthalf.filled"
        }
    }

    public static var stored: AppearancePreference {
        get {
            AppearancePreference(rawValue:
                UserDefaults.standard.string(forKey: key) ?? "") ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(
                name: .companionChromeDidChange, object: nil)
        }
    }
}

public enum WorkdirPreference {
    nonisolated public static let key = "companionWorkdir"

    nonisolated public static var stored: String? {
        get {
            let value = UserDefaults.standard.string(forKey: key)
            return value.flatMap { isAllowed($0) ? $0 : nil }
        }
        set {
            guard let newValue, isAllowed(newValue) else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            // The home folder is a valid choice and a bad memory. It reaches
            // everything, so remembering that you once said yes hands the
            // specialist your whole account on every future launch. The
            // reference draws the same line: trust for the home directory is
            // held for the session and never written to disk.
            guard !isHome(newValue) else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    nonisolated static func isHome(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath().path
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path == home
    }

    nonisolated public static var validated: String? {
        guard let stored, isAllowed(stored) else { return nil }
        return URL(fileURLWithPath: stored).resolvingSymlinksInPath().path
    }

    /// The directory the specialist actually runs in. With no folder chosen,
    /// it is the home tree — full reach, the specialist's toolbox is not
    /// fenced to a subfolder. This reverses the Wave 9h default by the owner's
    /// call: Companion is meant to match the Claude Code CLI, where the user
    /// scopes the work in the conversation, not a standing sandbox. `acceptEdits`
    /// still auto-accepts only edits, and commands still ask through the voice
    /// sheet — reach is wide, the permission gate stays.
    nonisolated public static var effective: String {
        validated ?? FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath().path
    }

    nonisolated public static var label: String? {
        validated.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// File tools treat workdir as the sandbox. The whole disk is not a folder.
    nonisolated public static func isAllowed(
        _ path: String,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: resolved.path, isDirectory: &isDir),
              isDir.boolValue
        else { return false }
        let homePath = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        let candidate = resolved.path
        if candidate == "/" || candidate == "/Users" { return false }
        return candidate == homePath || candidate.hasPrefix(homePath + "/")
    }
}

public enum VoiceProfile {
    nonisolated private static let voiceKey = "companion.voice"
    nonisolated private static let speedKey = "companion.voice.speed"
    nonisolated private static let volumeKey = "companion.voice.volume"
    nonisolated private static let turnDetectionTypeKey = "companion.voice.turnDetectionType"
    nonisolated private static let turnDetectionMsKey = "companion.voice.turnDetectionMs"
    nonisolated private static let turnDetectionEagernessKey = "companion.voice.turnDetectionEagerness"
    nonisolated private static let toneKey = "companion.voice.tone"
    nonisolated private static let echoCancellationKey = "companion.voice.echoCancellation"
    nonisolated private static let modeKey = "companion.voice.mode"
    /// 15b-2: the dictation key setting (§4 API `DictationKey`).
    nonisolated private static let dictationKeyKey = "companion.voice.dictationKey"

    nonisolated public static var stored: VoiceID {
        get {
            guard let raw = UserDefaults.standard.string(forKey: voiceKey),
                  let voice = VoiceID(rawValue: raw)
            else { return .marin }
            return voice
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: voiceKey) }
    }

    /// Full voice settings persisted to UserDefaults. Used by ConfigProvider
    /// to construct the effective Config on each session open.
    nonisolated public static var settings: VoiceSettings {
        get {
            let voice = stored
            let speed = Double(UserDefaults.standard.double(forKey: speedKey))
            let volume = Double(UserDefaults.standard.double(forKey: volumeKey))
            let tone = UserDefaults.standard.string(forKey: toneKey) ?? ""
            let aec = UserDefaults.standard.bool(forKey: echoCancellationKey)
            let mode = UserDefaults.standard.string(forKey: modeKey)
                .flatMap(VoiceMode.init(rawValue:)) ?? .automatic
            // A stray/hand-edited value (or a downgrade from a newer build)
            // must resolve to the shipped default, never crash (same
            // contract `mode` already has).
            let dictationKey = UserDefaults.standard.string(forKey: dictationKeyKey)
                .flatMap(DictationKey.init(rawValue:)) ?? .rightOption

            let turnDetection: TurnDetection
            let detectionType = UserDefaults.standard.string(
                forKey: turnDetectionTypeKey) ?? "serverVAD"
            if detectionType == "semanticVAD" {
                let eagernessRaw = UserDefaults.standard.string(
                    forKey: turnDetectionEagernessKey) ?? "auto"
                let eagerness = Eagerness(rawValue: eagernessRaw) ?? .auto
                turnDetection = .semanticVAD(eagerness: eagerness)
            } else {
                let ms = Int(UserDefaults.standard.double(forKey: turnDetectionMsKey))
                turnDetection = .serverVAD(silenceMs: ms > 0 ? ms : 700)
            }

            return VoiceSettings(
                voice: voice,
                speed: speed > 0 ? speed : 1.0,
                volume: volume > 0 ? volume : 1.0,
                turnDetection: turnDetection,
                tone: tone,
                echoCancellation: aec,
                mode: mode,
                dictationKey: dictationKey
            )
        }
        set {
            // Code review 2026-09-23 (medio): read before writing — every
            // voice control (a volume drag fires many times a second)
            // writes through this same setter, so the App layer must only
            // rebuild its `HoldKeyTap` when this ONE field actually moved.
            let previousDictationKey = settings.dictationKey
            stored = newValue.voice
            UserDefaults.standard.set(newValue.speed, forKey: speedKey)
            UserDefaults.standard.set(newValue.volume, forKey: volumeKey)
            UserDefaults.standard.set(newValue.tone, forKey: toneKey)
            UserDefaults.standard.set(newValue.echoCancellation, forKey: echoCancellationKey)
            UserDefaults.standard.set(newValue.mode.rawValue, forKey: modeKey)
            UserDefaults.standard.set(newValue.dictationKey.rawValue, forKey: dictationKeyKey)

            let (detType, ms, eagerness) = turnDetectionComponents(newValue.turnDetection)
            UserDefaults.standard.set(detType, forKey: turnDetectionTypeKey)
            if let ms { UserDefaults.standard.set(ms, forKey: turnDetectionMsKey) }
            if let eagerness { UserDefaults.standard.set(eagerness, forKey: turnDetectionEagernessKey) }

            if previousDictationKey != newValue.dictationKey {
                NotificationCenter.default.post(
                    name: .companionDictationKeyDidChange, object: nil)
            }
        }
    }

    nonisolated private static func turnDetectionComponents(
        _ detection: TurnDetection
    ) -> (type: String, ms: Int?, eagerness: String?) {
        switch detection {
        case .serverVAD(let silenceMs):
            return ("serverVAD", silenceMs, nil)
        case .semanticVAD(let eagerness):
            return ("semanticVAD", nil, eagerness.rawValue)
        }
    }
}

public extension VoiceID {
    /// Capitalised for display; the raw values are the API's own names.
    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum InterfaceSound {
    nonisolated private static let key = "companion.interfaceSounds"

    /// Default on: missing key means the user never turned them off.
    nonisolated public static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Wave 17 (spec §3 "Ajuste", P1): "Agentes › Prestar las manos a otros
/// agentes". Default OFF everywhere — a missing key must never open a
/// socket nobody asked for. Posts on every real change so `CompanionMain`
/// can start or stop the bridge listener without a relaunch, the same shape
/// `companionDictationKeyDidChange` already uses for the FN tap.
public enum HandsLendingPreference {
    nonisolated private static let key = "companion.lendHands"

    nonisolated public static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            guard newValue != enabled else { return }
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: .companionHandsLendingDidChange, object: nil)
        }
    }
}

/// Wave 16d: the words the ear should get right, as the user typed them.
public enum VocabularyPreference {
    nonisolated private static let key = "companion.vocabulary"

    nonisolated public static var text: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    nonisolated public static var words: [String] { Vocabulary.parse(text) }
}

/// Whether the thinking phase carries its background chord.
public enum ThinkingSoundPref {
    nonisolated private static let key = "companion.thinkingSound"

    nonisolated public static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// DM1c-3 (wave-dm1-router.md §8): the "Decidir en local" Settings toggle.
/// Off by default — a missing key must never turn the router on for someone
/// who has never seen the switch. `StoredConfigProvider` ORs this with the
/// `COMPANION_DECISION` env override, which stays the escape hatch for a
/// headless run with no Settings pane to click.
public enum DecisionPreference {
    nonisolated private static let key = "companion.decision.enabled"
    /// Swappable so a test writes into its own suite, never the user's.
    nonisolated(unsafe) public static var store: UserDefaults = .standard

    nonisolated public static var enabled: Bool {
        get { store.object(forKey: key) as? Bool ?? false }
        set { store.set(newValue, forKey: key) }
    }
}

/// Which provider this user settled on, and — for a local runtime — which tag.
/// Stored apart from the key: choosing Ollama is a preference, not a secret,
/// and it has to survive a relaunch or "use the model on my Mac" is a click
/// the user repeats every morning.
public enum ProviderPreference {
    nonisolated private static let nameKey = "companion.provider"
    nonisolated private static let modelKey = "companion.provider.model"
    nonisolated private static let orderKey = "companion.provider.order"

    // Debugging 2026-09-28: Swift Testing runs `@Test` functions in parallel
    // by default, and `startupPathTests`/`providerOrderTests` (same file)
    // both read/write this preference. A shared `UserDefaults.standard` let
    // one dispatcher's `forget()`/`accept(_:)` land mid-turn in the other —
    // same class of bug `Log`'s task-local capture already solved for the
    // sink. Production code never calls `scoped`, so it always sees
    // `.standard`.

    /// `UserDefaults` predates `Sendable` and is marked unavailable for it;
    /// this box is the same `@unchecked` shape `Log`'s own sink uses.
    /// `nonisolated`: this target defaults every declaration to `@MainActor`,
    /// but `store` below reads this off the actor.
    nonisolated private struct DefaultsBox: @unchecked Sendable {
        let defaults: UserDefaults
    }

    // Spelled out instead of `@TaskLocal` sugar: the synthesized `$override`
    // backing storage inherits this target's default `@MainActor` isolation
    // and `store` below needs to read it from a nonisolated context.
    nonisolated private static let override = TaskLocal<DefaultsBox?>(wrappedValue: nil)

    nonisolated private static var store: UserDefaults { override.get()?.defaults ?? .standard }

    /// Test seam: binds every read/write this task tree makes (including
    /// the non-detached `Task` `onAppear`'s probe spawns) to `defaults`
    /// instead of the process-wide store.
    public static func scoped<R>(
        to defaults: UserDefaults,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> R
    ) async rethrows -> R {
        try await override.withValue(
            DefaultsBox(defaults: defaults), operation: body, isolation: isolation)
    }

    nonisolated public static var name: String? {
        get { store.string(forKey: nameKey) }
        set { store.set(newValue, forKey: nameKey) }
    }

    nonisolated public static var localModel: String? {
        get { store.string(forKey: modelKey) }
        set { store.set(newValue, forKey: modelKey) }
    }

    /// Provider ids, best first. Stored as ids and not display names because
    /// the name is copy — it can be translated or reworded, and a preference
    /// keyed by copy breaks the day someone edits a string.
    nonisolated public static var order: [String] {
        get { store.stringArray(forKey: orderKey) ?? [] }
        set { store.set(newValue, forKey: orderKey) }
    }

    /// Rebuilt rather than stored as one blob: a half-written pair (a name
    /// with no tag) must read as "nothing chosen", not as a path that will
    /// fail on the first message.
    nonisolated public static var acceptedPath: LocalPath? {
        switch name {
        case LocalPath.appleFM.providerName:
            return .appleFM
        case LocalPath.ollama(model: "").providerName:
            guard let model = localModel, !model.isEmpty else { return nil }
            return .ollama(model: model)
        default:
            return nil
        }
    }

    /// Accepting a local path is also an opinion about the ladder: someone who
    /// chose to talk to their own Mac wants that first, not as a fallback.
    nonisolated public static func accept(_ path: LocalPath) {
        name = path.providerName
        localModel = path.model
        var next = order.filter { $0 != path.providerId }
        next.insert(path.providerId, at: 0)
        order = next
    }

    nonisolated public static func forget() {
        store.removeObject(forKey: nameKey)
        store.removeObject(forKey: modelKey)
        store.removeObject(forKey: orderKey)
    }
}
