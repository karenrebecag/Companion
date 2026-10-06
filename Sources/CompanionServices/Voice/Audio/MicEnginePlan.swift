/// What an engine was built for. Voice processing pins both buses at build
/// time, so a different input needs a different engine, not a re-tap.
package struct MicEngineBuild: Equatable, Sendable {
    package var input: UInt32?
    package var voiceProcessing: Bool

    package init(input: UInt32?, voiceProcessing: Bool) {
        self.input = input
        self.voiceProcessing = voiceProcessing
    }
}

package enum MicEngineAction: Equatable, Sendable {
    case reuse
    case rebuild
}

package enum MicEnginePlan {
    package static func decide(
        built: MicEngineBuild?, wantedInput: UInt32?, wantVoiceProcessing: Bool
    ) -> MicEngineAction {
        guard let built else { return .rebuild }
        let same = built.input == wantedInput && built.voiceProcessing == wantVoiceProcessing
        return same ? .reuse : .rebuild
    }
}

package struct MicPlainRetry: Equatable, Sendable {
    package var retry: Bool
    package var persistVeto: Bool

    package init(retry: Bool, persistVeto: Bool) {
        self.retry = retry
        self.persistVeto = persistVeto
    }
}

/// How long a voice-processing veto holds: a failed init says something about
/// the machine, a failed pin only about this session's devices.
package enum MicVetoScope: Equatable, Sendable {
    case lasting
    case thisSession
}

extension MicEnginePlan {
    /// After a start fails on a dead graph: whether to try again without
    /// voice processing, and whether that says something lasting about the
    /// machine. A pin that failed only for this session is not written down.
    /// `attemptedVoiceProcessing` is what the failed attempt used: the
    /// teardown that follows a failed start has already cleared the live flag.
    package static func plainRetry(
        attemptedVoiceProcessing: Bool, offThisSession: Bool
    ) -> MicPlainRetry {
        MicPlainRetry(
            retry: attemptedVoiceProcessing || offThisSession, persistVeto: attemptedVoiceProcessing)
    }

    package static func vetoScope(persistVeto: Bool) -> MicVetoScope {
        persistVeto ? .lasting : .thisSession
    }
}
