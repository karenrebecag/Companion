import CompanionCore
import Foundation

/// Watches turn snapshots and drives the thinking sound. Fed by a callback
/// from the view model rather than iterating the snapshot stream: that stream
/// has a single consumer, and a second iterator would steal elements from it.
public final class AmbienceObserver: @unchecked Sendable {
    private let lock = NSLock()
    private let sound: any ThinkingSounding
    private let isEnabled: @Sendable () -> Bool
    private var previous: TurnState = .idle
    private var active = false

    public init(
        sound: any ThinkingSounding,
        isEnabled: @escaping @Sendable () -> Bool
    ) {
        self.sound = sound
        self.isEnabled = isEnabled
    }

    public func observe(_ state: TurnState) {
        lock.lock()
        let cue = AmbienceCue.forTransition(from: previous, to: state)
        previous = state
        // Track what actually started: a suppressed start (toggle off) must
        // not produce a stop on exit — the sound never existed.
        var action: AmbienceCue = .none
        switch cue {
        case .start where !active && isEnabled():
            active = true
            action = .start
        case .stop where active:
            active = false
            action = .stop
        default:
            break
        }
        lock.unlock()
        switch action {
        case .start: sound.start()
        case .stop: sound.stop()
        case .none: break
        }
    }
}
