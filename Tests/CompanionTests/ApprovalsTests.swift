import Foundation
import Testing

@testable import CompanionCore
@testable import CompanionServices

@Test @MainActor
func approvalsActorCanRequestApproval() throws {
    let result = try runAsync {
        let clock = MockClock()
        let approvals = Approvals(clock: clock)

        let request = ApprovalRequest(
            requestId: "req-1",
            toolName: "run_shell",
            summary: "rm -rf /",
            inputJSON: "{}"
        )

        let task = Task {
            let response = await approvals.request(request)
            return response
        }

        try? await Task.sleep(nanoseconds: 10_000_000) // Let request start
        let approved = await approvals.resolve(requestId: "req-1", approved: true)

        let response = await task.value
        return (response, approved)
    }

    let (response, didResolve) = result
    expectEq(response.requestId, "req-1", "response has correct requestId")
    expect(response.approved, "resolved as approved")
    expect(didResolve, "resolve returned success")
}

@Test @MainActor
func approvalsCanDenyRequest() throws {
    let result = try runAsync {
        let clock = MockClock()
        let approvals = Approvals(clock: clock)

        let request = ApprovalRequest(
            requestId: "req-2",
            toolName: "write_file",
            summary: "write dangerous.txt",
            inputJSON: "{}"
        )

        let task = Task {
            let response = await approvals.request(request)
            return response
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
        let denied = await approvals.resolve(requestId: "req-2", approved: false)

        let response = await task.value
        return (response, denied)
    }

    let (response, didResolve) = result
    expectEq(response.requestId, "req-2", "response has correct requestId")
    expect(!response.approved, "resolved as denied")
    expect(didResolve, "resolve returned success")
}

/// 16. El timeout de verdad: con `timeout: 0.05` la solicitud se niega sola
/// y la entrada pendiente desaparece. Sustituye al `expect(true)` de antes.
@Test @MainActor
func approvalsAutoDenyAfterTimeout() throws {
    let result = try runAsync {
        let approvals = Approvals(clock: MockClock(), timeout: 0.05)
        let request = ApprovalRequest(
            requestId: "req-3", toolName: "edit_file", summary: "edit something", inputJSON: "{}")
        let response = await approvals.request(request)
        let late = await approvals.resolve(requestId: "req-3", approved: true)
        return (response, late)
    }
    expect(!result.0.approved, "timeout: se niega sola")
    expectEq(result.0.requestId, "req-3", "timeout: la respuesta es la de la solicitud")
    expect(!result.1, "timeout: ya no hay nada pendiente que resolver")
}

/// 15. `resolve` reanuda `request` sin dormir: menos de 5 ms después.
@Test @MainActor
func approvalsResolveWakesWithoutPolling() throws {
    let elapsed = try runAsync {
        let approvals = Approvals(clock: MockClock())
        let request = ApprovalRequest(
            requestId: "req-fast", toolName: "run_shell", summary: "", inputJSON: "{}")
        let task = Task { await approvals.request(request) }
        try await Task.sleep(nanoseconds: 20_000_000)
        let start = ContinuousClock.now
        _ = await approvals.resolve(requestId: "req-fast", approved: true)
        _ = await task.value
        return ContinuousClock.now - start
    }
    expect(elapsed < .milliseconds(5), "sin polling: despierta en \(elapsed)")
}

/// 17. `resolve(remember: true)` viaja en la respuesta y queda en la memoria
/// del actor: la siguiente solicitud con la misma clave no espera a nadie.
@Test @MainActor
func approvalsRememberForTheSession() throws {
    let result = try runAsync {
        let approvals = Approvals(clock: MockClock())
        let first = ApprovalRequest(
            requestId: "w1", toolName: "write_file", summary: "",
            inputJSON: #"{"path":"~/Desktop/a.md","content":"x"}"#)
        let task = Task { await approvals.request(first) }
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = await approvals.resolve(requestId: "w1", approved: true, remember: true)
        let response = await task.value
        let same = ApprovalRequest(
            requestId: "w2", toolName: "write_file", summary: "",
            inputJSON: #"{"path":"~/Desktop/b.md","content":"y"}"#)
        let other = ApprovalRequest(
            requestId: "w3", toolName: "write_file", summary: "",
            inputJSON: #"{"path":"~/Docs/c.md","content":"z"}"#)
        return (response, await approvals.remembered(same), await approvals.remembered(other))
    }
    expect(result.0.remember, "recordar: la respuesta lo dice")
    expectEq(result.1, true, "recordar: la misma clave ya está decidida")
    expect(result.2 == nil, "recordar: otra clave sigue preguntando")
}

@Test @MainActor
func approvalsResolveReturnsFalseForUnknownRequest() throws {
    let result = try runAsync {
        let clock = MockClock()
        let approvals = Approvals(clock: clock)

        let resolved = await approvals.resolve(requestId: "unknown-req", approved: true)
        return resolved
    }

    expect(!result, "resolve returns false for unknown request")
}

@Test @MainActor
func approvalsCannotResolveRequestTwice() throws {
    let result = try runAsync {
        let clock = MockClock()
        let approvals = Approvals(clock: clock)

        let request = ApprovalRequest(
            requestId: "req-4",
            toolName: "run_shell",
            summary: "test",
            inputJSON: "{}"
        )

        let task = Task {
            let response = await approvals.request(request)
            return response
        }

        // Reintentar hasta que la solicitud este registrada, en vez de dormir
        // 50 ms y confiar: bajo carga la tarea no habia arrancado y el primer
        // resolve caia en "unknown request".
        var first = false
        for _ in 0..<500 where !first {
            first = await approvals.resolve(requestId: "req-4", approved: true)
            if !first { try? await Task.sleep(nanoseconds: 1_000_000) }
        }

        // Esperar la ENTREGA, no un reloj: cuando la respuesta llega, el
        // pendiente ya se retiro. Dormir 10 ms asumia que el waiter alcanzaba
        // a despertarse, y cuando no lo hacia el segundo resolve encontraba la
        // solicitud viva y la resolvia — el test fallaba por su propia prisa,
        // no por el codigo.
        let response = await task.value
        let second = await approvals.resolve(requestId: "req-4", approved: false)
        return (first, second, response)
    }

    let (first, second, response) = result
    expect(first, "first resolve succeeds")
    expect(!second, "second resolve fails")
    expect(response.approved, "response reflects first resolution")
}

@Test @MainActor
func approvalsMultiplePendingRequests() throws {
    let result = try runAsync {
        let clock = MockClock()
        let approvals = Approvals(clock: clock)

        let req1 = ApprovalRequest(
            requestId: "req-5",
            toolName: "write_file",
            summary: "write 1",
            inputJSON: "{}"
        )
        let req2 = ApprovalRequest(
            requestId: "req-6",
            toolName: "run_shell",
            summary: "run 2",
            inputJSON: "{}"
        )

        let task1 = Task {
            let response = await approvals.request(req1)
            return response
        }
        let task2 = Task {
            let response = await approvals.request(req2)
            return response
        }

        try? await Task.sleep(nanoseconds: 10_000_000)

        // Resolve in different order than requested
        await approvals.resolve(requestId: "req-6", approved: true)
        await approvals.resolve(requestId: "req-5", approved: false)

        let response1 = await task1.value
        let response2 = await task2.value

        return (response1, response2)
    }

    let (r1, r2) = result
    expect(!r1.approved, "req1 denied")
    expect(r2.approved, "req2 approved")
}
