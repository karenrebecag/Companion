import CompanionServices
import CompanionTestKit
import Testing

// The voice-processing unit pins both buses when the engine is built. An
// engine reused for another input, or after teardown, keeps a stale pin.

private let built = MicEngineBuild(input: 5, voiceProcessing: true)

@Suite struct MicEnginePlanTests {
    @Test func theSameDeviceKeepsTheEngine() {
        expectEq(MicEnginePlan.decide(built: built, wantedInput: 5, wantVoiceProcessing: true),
                 .reuse, "mismo dispositivo: no se reconstruye")
    }

    @Test func aDifferentDeviceRebuildsTheEngine() {
        expectEq(MicEnginePlan.decide(built: built, wantedInput: 7, wantVoiceProcessing: true),
                 .rebuild, "otro dispositivo: se reconstruye")
    }

    @Test func theSystemDefaultMovingRebuildsTheEngine() {
        let onDefault = MicEngineBuild(input: 5, voiceProcessing: true)
        expectEq(MicEnginePlan.decide(built: onDefault, wantedInput: 8, wantVoiceProcessing: true),
                 .rebuild, "el del sistema se movió: se reconstruye")
    }

    @Test func aTornDownEngineIsRebuiltAndPinnedAgain() {
        expectEq(MicEnginePlan.decide(built: nil, wantedInput: 5, wantVoiceProcessing: true),
                 .rebuild, "tras apagarlo: se fija de nuevo")
        expectEq(MicEnginePlan.decide(built: nil, wantedInput: nil, wantVoiceProcessing: false),
                 .rebuild, "tras apagarlo sin dispositivo: también")
    }

    @Test func changingVoiceProcessingRebuildsTheEngine() {
        expectEq(MicEnginePlan.decide(built: built, wantedInput: 5, wantVoiceProcessing: false),
                 .rebuild, "sin cancelación de eco: se reconstruye")
        let plain = MicEngineBuild(input: 5, voiceProcessing: false)
        expectEq(MicEnginePlan.decide(built: plain, wantedInput: 5, wantVoiceProcessing: false),
                 .reuse, "plano y mismo dispositivo: se conserva")
    }

    @Test func anUnresolvedInputKeepsAnEngineBuiltWithoutOne() {
        let blind = MicEngineBuild(input: nil, voiceProcessing: false)
        expectEq(MicEnginePlan.decide(built: blind, wantedInput: nil, wantVoiceProcessing: false),
                 .reuse, "sin id en ambos lados: no hay nada que cambiar")
    }
}

@Suite struct ProbeGenerationTests {
    @Test func onlyTheLatestStartIsCurrent() {
        let gate = ProbeGeneration()
        let first = gate.begin()
        let second = gate.begin()
        expect(!gate.isCurrent(first), "generación: el arranque superado ya no es el vigente")
        expect(gate.isCurrent(second), "generación: el último es el vigente")
        gate.invalidate()
        expect(!gate.isCurrent(second), "generación: parar retira también al último")
    }
}

@Suite struct MicPlainRetryTests {
    @Test func aFailedVoiceProcessingStartRetriesAndRemembers() {
        expectEq(MicEnginePlan.plainRetry(attemptedVoiceProcessing: true, offThisSession: false),
                 MicPlainRetry(retry: true, persistVeto: true), "vpio falló: reintenta y lo recuerda")
        expectEq(MicEnginePlan.plainRetry(attemptedVoiceProcessing: true, offThisSession: true),
                 MicPlainRetry(retry: true, persistVeto: true), "vpio vivo y sesión: lo recuerda")
    }

    @Test func aPinFallbackRetriesWithoutWritingTheVeto() {
        expectEq(MicEnginePlan.plainRetry(attemptedVoiceProcessing: false, offThisSession: true),
                 MicPlainRetry(retry: true, persistVeto: false), "pin falló: reintenta sin vetar")
    }

    @Test func aPlainEngineFailingIsNotRetried() {
        expectEq(MicEnginePlan.plainRetry(attemptedVoiceProcessing: false, offThisSession: false),
                 MicPlainRetry(retry: false, persistVeto: false), "plano: no hay a qué volver")
    }

    // teardown clears the live flag when engine.start() fails; the decision
    // rests on what the failed attempt used, not on what is left.
    @Test func aVoiceProcessingAttemptStaysRetryableAfterItsTeardown() {
        expectEq(MicEnginePlan.plainRetry(attemptedVoiceProcessing: true, offThisSession: false),
                 MicPlainRetry(retry: true, persistVeto: true), "vpio intentado: reintenta y lo recuerda")
    }
}

@Suite struct MicVetoScopeTests {
    @Test func aVoiceProcessingFailureIsRememberedForGood() {
        expectEq(MicEnginePlan.vetoScope(persistVeto: true), .lasting, "vpio falló: veto duradero")
    }

    @Test func aPinFailureOnlyLastsThisSession() {
        expectEq(MicEnginePlan.vetoScope(persistVeto: false), .thisSession, "pin falló: solo esta sesión")
    }
}
