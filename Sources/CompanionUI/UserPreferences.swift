import AppKit
import CompanionCore
import Foundation

/// Preferences the window owns. Kept out of Config (which describes the
/// product) because these are this user's choices and must survive relaunch.
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
        case .light: "Claro"
        case .dark: "Oscuro"
        case .auto: "Sistema"
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
            return (value?.isEmpty == false) ? value : nil
        }
        set {
            if let newValue, isAllowed(newValue) {
                UserDefaults.standard.set(
                    URL(fileURLWithPath: newValue).resolvingSymlinksInPath().path,
                    forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    nonisolated public static var validated: String? {
        guard let stored, isAllowed(stored) else { return nil }
        return URL(fileURLWithPath: stored).resolvingSymlinksInPath().path
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
                echoCancellation: aec
            )
        }
        set {
            stored = newValue.voice
            UserDefaults.standard.set(newValue.speed, forKey: speedKey)
            UserDefaults.standard.set(newValue.volume, forKey: volumeKey)
            UserDefaults.standard.set(newValue.tone, forKey: toneKey)
            UserDefaults.standard.set(newValue.echoCancellation, forKey: echoCancellationKey)

            let (detType, ms, eagerness) = turnDetectionComponents(newValue.turnDetection)
            UserDefaults.standard.set(detType, forKey: turnDetectionTypeKey)
            if let ms { UserDefaults.standard.set(ms, forKey: turnDetectionMsKey) }
            if let eagerness { UserDefaults.standard.set(eagerness, forKey: turnDetectionEagernessKey) }
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

/// Whether the thinking phase carries its background chord.
public enum ThinkingSoundPref {
    nonisolated private static let key = "companion.thinkingSound"

    nonisolated public static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
