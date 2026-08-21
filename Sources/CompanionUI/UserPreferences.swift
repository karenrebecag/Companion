import CompanionCore
import Foundation

/// Preferences the window owns. Kept out of Config (which describes the
/// product) because these are this user's choices and must survive relaunch.
public enum UserProfile {
    nonisolated private static let key = "companion.ownerName"

    nonisolated public static var ownerName: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
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
