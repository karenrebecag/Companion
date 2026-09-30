import Foundation

package enum SoundCue: Sendable, Equatable {
    case confirm, alert

    package static func forLevel(_ level: NoticeLevel) -> SoundCue {
        level == .error ? .alert : .confirm
    }
}

package protocol InterfaceSounding: Sendable {
    func play(_ cue: SoundCue)
}
