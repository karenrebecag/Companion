import Foundation

public enum SoundCue: Sendable, Equatable {
    case confirm, alert

    public static func forLevel(_ level: NoticeLevel) -> SoundCue {
        level == .error ? .alert : .confirm
    }
}

public protocol InterfaceSounding: Sendable {
    func play(_ cue: SoundCue)
}
