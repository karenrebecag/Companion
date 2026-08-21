import CompanionCore
import Foundation

/// Preferences the window owns. Kept out of Config (which describes the
/// product) because these are this user's choices and must survive relaunch.
public enum UserProfile {
    private static let key = "companion.ownerName"

    public static var ownerName: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

public enum VoiceProfile {
    private static let key = "companion.voice"

    public static var stored: VoiceID {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let voice = VoiceID(rawValue: raw)
            else { return .marin }
            return voice
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

public extension VoiceID {
    /// Capitalised for display; the raw values are the API's own names.
    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}
