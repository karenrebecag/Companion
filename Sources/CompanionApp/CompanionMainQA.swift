import CompanionCore
import CompanionServices
import CompanionUI
import Foundation

/// Puente QA (PR-2): the pieces that let an outside agent drive a turn, built
/// once. One gate serves both roads (the chat's and the bridge's hands), so QA
/// mode has no sheets on either and nothing critical acts without the owner.
struct QAWiring {
    let gate: QAGate
    let waiter: TurnWaiter
    let runner: QARunner
}

extension AppDelegate {
    func installQAMode(
        env: LaunchEnvironment, sensing: SensingAndModel, source: SelfInspectionSource
    ) -> QAWiring {
        let model = sensing.model
        let waiter = TurnWaiter()
        // One ordered road each: tasks spawned per event could land a close
        // before its open and leave a wait believing a dialog is still up.
        let (turnEvents, turnEmitter) = AsyncStream.makeStream(of: (String, TurnSignal).self)
        let (ownerEvents, ownerEmitter) = AsyncStream.makeStream(of: (Bool, String).self)
        Task { for await (turnId, signal) in turnEvents { await waiter.signal(turnId: turnId, signal) } }
        Task { @MainActor in
            for await (open, tool) in ownerEvents { model.ownerCheckChanged(open: open, tool: tool) }
        }
        model.onTurnEvent = { turnId, signal in turnEmitter.yield((turnId, signal)) }
        let gate = QAGate(
            enabled: { QAScopePreference.enabled },
            owner: LocalAuthOwnerCheck(),
            disableQA: { QAScopePreference.disable() },
            language: { env.configProvider.current.language },
            ownerCheckChanged: { open, tool in ownerEmitter.yield((open, tool)) },
            classify: { request, call, said in QALiveBand.band(request: request, call: call, said: said) })
        model.qaGate = gate
        let runner = QARunner(
            driving: source, waiter: waiter, scope: { QAScopePreference.enabled },
            language: { env.configProvider.current.language })
        return QAWiring(gate: gate, waiter: waiter, runner: runner)
    }
}
