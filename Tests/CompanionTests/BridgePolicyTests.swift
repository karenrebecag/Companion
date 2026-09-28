import CompanionCore
import Foundation
import Testing

@Test @MainActor func bridgePolicyTests() {
    testCallBeforeHello()
    testCallAfterStop()
    testRateLimitingWriteTools()
    testReadToolsNeverCount()
    testPauseRejectsCalls()
    testResumeAllowsCalls()
    testHelloWhileOpenRejectsBusy()
    testOpenWithExpiration()
    testDisconnectedResetsToIdle()
    testBudgetExpiresAfterWindow()
    testPausePreservesExpiry()
    testHelloTransitionsToListed()
    testFirstCallFromListedNeedsApproval()
    testApprovedThenAdmitProceeds()
    testDeniedThenAdmitFails()
    testHelloWhileListedProceedsStaysListed()
}

private func testCallBeforeHello() {
    var policy = BridgePolicy()
    let now = Date()

    let verdict = policy.admit(tool: "look", now: now)
    guard case .reject(let code) = verdict else {
        return expect(false, "before hello: should reject")
    }
    expectEq(code, BridgeCode.noSession, "before hello: code is no_session")
}

private func testCallAfterStop() {
    var policy = BridgePolicy()
    let now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)  // Triggers needsApproval
    policy.approved(until: nil, now: now)
    policy.stop()

    let verdict = policy.admit(tool: "look", now: now)
    guard case .reject(let code) = verdict else {
        return expect(false, "after stop: should reject")
    }
    expectEq(code, BridgeCode.sessionClosed, "after stop: code is session_closed")
}

private func testRateLimitingWriteTools() {
    var policy = BridgePolicy()
    var now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)  // Triggers needsApproval
    policy.approved(until: nil, now: now)

    // Fill the budget: 30 writes
    for i in 0 ..< 30 {
        let verdict = policy.admit(tool: "click", now: now)
        guard case .proceed = verdict else {
            return expect(false, "write \(i): should proceed")
        }
    }

    // 31st should be rate limited
    let verdict31 = policy.admit(tool: "click", now: now)
    guard case .reject(let code) = verdict31 else {
        return expect(false, "write 31: should reject")
    }
    expectEq(code, BridgeCode.rateLimited, "write 31: code is rate_limited")
}

private func testReadToolsNeverCount() {
    var policy = BridgePolicy()
    var now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)  // Triggers needsApproval
    policy.approved(until: nil, now: now)

    // Fill the write budget
    for _ in 0 ..< 30 {
        _ = policy.admit(tool: "click", now: now)
    }

    // Read tools should still work
    for tool in ["look", "read_focused", "list_apps"] {
        let verdict = policy.admit(tool: tool, now: now)
        guard case .proceed = verdict else {
            return expect(false, "read \(tool): should proceed despite full write budget")
        }
    }
}

private func testPauseRejectsCalls() {
    var policy = BridgePolicy()
    let now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)  // Triggers needsApproval
    policy.approved(until: nil, now: now)
    policy.pause()

    let verdict = policy.admit(tool: "look", now: now)
    guard case .reject(let code) = verdict else {
        return expect(false, "pause: should reject")
    }
    expectEq(code, BridgeCode.busy, "pause: code is busy")
}

private func testResumeAllowsCalls() {
    var policy = BridgePolicy()
    let now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)  // Triggers needsApproval
    policy.approved(until: nil, now: now)
    policy.pause()
    policy.resume(now: now)

    let verdict = policy.admit(tool: "look", now: now)
    guard case .proceed = verdict else {
        return expect(false, "resume: should proceed")
    }
}

private func testHelloWhileOpenRejectsBusy() {
    var policy = BridgePolicy()
    let now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)  // Triggers needsApproval
    policy.approved(until: nil, now: now)

    let verdict = policy.helloReceived(now: now)
    guard case .reject(let code) = verdict else {
        return expect(false, "hello while open: should reject")
    }
    expectEq(code, BridgeCode.busy, "hello while open: code is busy")
}

private func testOpenWithExpiration() {
    var policy = BridgePolicy()
    var now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)  // Triggers needsApproval
    let expiresAt = now.addingTimeInterval(10)
    policy.approved(until: expiresAt, now: now)

    // Admit while valid
    let beforeExpiry = policy.admit(tool: "look", now: now)
    guard case .proceed = beforeExpiry else {
        return expect(false, "before expiry: should proceed")
    }

    // Advance past expiration
    now = expiresAt.addingTimeInterval(1)

    // Next admit should close the session
    let afterExpiry = policy.admit(tool: "look", now: now)
    guard case .reject(let code) = afterExpiry else {
        return expect(false, "after expiry: should reject")
    }
    expectEq(code, BridgeCode.sessionClosed, "after expiry: code is session_closed")

    // State should be closed
    expect(!policy.isOpen, "after expiry: isOpen is false")
}

private func testDisconnectedResetsToIdle() {
    var policy = BridgePolicy()
    let now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)  // Triggers needsApproval
    policy.approved(until: nil, now: now)

    // State is open
    expect(policy.isOpen, "before disconnected: isOpen is true")

    // Disconnect
    policy.disconnected()

    // State is idle
    expect(!policy.isOpen, "after disconnected: isOpen is false")

    // A new hello should proceed
    let verdict = policy.helloReceived(now: now)
    guard case .proceed = verdict else {
        return expect(false, "hello after disconnect: should proceed")
    }
}

private func testBudgetExpiresAfterWindow() {
    var policy = BridgePolicy()
    var now = Date()

    _ = policy.helloReceived(now: now)
    policy.approved(until: nil, now: now)

    // Fill budget at t=0
    for _ in 0 ..< 30 {
        _ = policy.admit(tool: "click", now: now)
    }

    // 31st at t=0 is rate limited
    var verdict = policy.admit(tool: "click", now: now)
    guard case .reject(let code) = verdict else {
        return expect(false, "31st at t=0: should be rate_limited")
    }
    expectEq(code, BridgeCode.rateLimited, "31st at t=0: rate_limited")

    // At t=61s, old writes have expired (>60s old), so one more write should proceed
    now = now.addingTimeInterval(61)
    verdict = policy.admit(tool: "click", now: now)
    guard case .proceed = verdict else {
        return expect(false, "first write at t=61: should proceed")
    }
}

private func testPausePreservesExpiry() {
    var policy = BridgePolicy()
    var now = Date()

    _ = policy.helloReceived(now: now)
    let expiresAt = now.addingTimeInterval(3600)
    policy.approved(until: expiresAt, now: now)

    // Pause
    policy.pause()

    // Resume before expiry
    now = now.addingTimeInterval(10)
    policy.resume(now: now)

    // Session should still expire at original time
    let verdict = policy.admit(tool: "look", now: now)
    guard case .proceed = verdict else {
        return expect(false, "before resumed expiry: should proceed")
    }

    // Resume after expiry
    var policy2 = BridgePolicy()
    now = Date()
    _ = policy2.helloReceived(now: now)
    let expiresAt2 = now.addingTimeInterval(5)
    policy2.approved(until: expiresAt2, now: now)
    policy2.pause()

    now = now.addingTimeInterval(10)
    policy2.resume(now: now)

    // Should be closed after expiry
    let verdict2 = policy2.admit(tool: "look", now: now)
    guard case .reject(let code) = verdict2 else {
        return expect(false, "after resumed expiry: should reject")
    }
    expectEq(code, BridgeCode.sessionClosed, "after resumed expiry: session_closed")
}

private func testHelloTransitionsToListed() {
    var policy = BridgePolicy()
    let now = Date()

    let verdict = policy.helloReceived(now: now)
    guard case .proceed = verdict else {
        return expect(false, "hello from idle: should proceed")
    }
    expect(policy.isListed, "hello from idle: state is listed")
}

private func testFirstCallFromListedNeedsApproval() {
    var policy = BridgePolicy()
    let now = Date()

    _ = policy.helloReceived(now: now)

    let verdict = policy.admit(tool: "look", now: now)
    guard case .needsApproval = verdict else {
        return expect(false, "first call from listed: should need approval")
    }
    expect(!policy.isOpen, "first call from listed: state is awaitingApproval")
}

private func testApprovedThenAdmitProceeds() {
    var policy = BridgePolicy()
    let now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)
    policy.approved(until: nil, now: now)

    let verdict = policy.admit(tool: "look", now: now)
    guard case .proceed = verdict else {
        return expect(false, "after approved: should proceed")
    }
    expect(policy.isOpen, "after approved: isOpen is true")
}

private func testDeniedThenAdmitFails() {
    var policy = BridgePolicy()
    let now = Date()

    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)
    policy.denied()

    let verdict = policy.admit(tool: "look", now: now)
    guard case .reject(let code) = verdict else {
        return expect(false, "after denied: should reject")
    }
    expectEq(code, BridgeCode.sessionClosed, "after denied: session_closed")
}

private func testHelloWhileListedProceedsStaysListed() {
    var policy = BridgePolicy()
    let now = Date()

    _ = policy.helloReceived(now: now)
    expect(policy.isListed, "first hello: listed")

    // Another hello while listed should proceed and stay listed
    let verdict = policy.helloReceived(now: now)
    guard case .proceed = verdict else {
        return expect(false, "hello while listed: should proceed")
    }
    expect(policy.isListed, "hello while listed: still listed")
}
