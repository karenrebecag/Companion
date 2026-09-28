import CompanionCore
import Testing

// Wave 16k-2b (spec §9.5 D2, audited against Incredible's binary §9.6): the
// connect attempt's own pure state machine. No I/O — AppsModel (16k-2b UI)
// drives it with events and an injected `now`, TurnMachine's own shape.

@Test func connectPollStartsInitiatingAndIgnoresATickBeforeTheBrowserOpens() {
    var poll = ConnectPoll(startedAt: 0)
    #expect(poll.phase == .initiating)
    // linkObtained alone does not open polling: the browser has not shown yet.
    poll.handle(.linkObtained, at: 1)
    #expect(poll.phase == .initiating)
    // A stray poll landing before browserOpened must not jump the queue.
    poll.handle(.accountMissing, at: 2)
    #expect(poll.phase == .initiating)
}

@Test func connectPollMovesToWaitingOnceTheBrowserOpens() {
    var poll = ConnectPoll(startedAt: 0)
    poll.handle(.linkObtained, at: 1)
    poll.handle(.browserOpened, at: 1)
    #expect(poll.phase == .waiting(attempts: 0))
    #expect(poll.isWaiting)
}

@Test func connectPollCountsAttemptsToFortyThenTimesOut() {
    var poll = ConnectPoll(startedAt: 0)
    poll.handle(.browserOpened, at: 0)
    var now: Double = 0
    for attempt in 1..<ConnectPoll.maxAttempts {
        now += ConnectPoll.interval
        poll.handle(.accountMissing, at: now)
        #expect(poll.phase == .waiting(attempts: attempt), "attempt \(attempt)")
    }
    now += ConnectPoll.interval
    poll.handle(.accountMissing, at: now)
    #expect(poll.phase == .timedOut, "attempt 40 (the audited ~2 min cap)")
    #expect(!poll.isWaiting, "a timed-out attempt is not still waiting")
}

@Test func connectPollShowsTheStillWaitingHintAfterSeveralAttempts() {
    var poll = ConnectPoll(startedAt: 0)
    poll.handle(.browserOpened, at: 0)
    #expect(!poll.showsStillWaitingHint, "attempt 0: too soon")
    for attempt in 1..<ConnectPoll.hintThreshold {
        poll.handle(.accountMissing, at: Double(attempt) * ConnectPoll.interval)
        #expect(!poll.showsStillWaitingHint, "attempt \(attempt): still too soon")
    }
    poll.handle(.accountMissing, at: Double(ConnectPoll.hintThreshold) * ConnectPoll.interval)
    #expect(poll.showsStillWaitingHint, "attempt \(ConnectPoll.hintThreshold): the hint shows")
}

// D2: "un timeout global duro... que corre desde initiating" — the clock
// does not wait for the first waiting tick to start counting.
@Test func connectPollGlobalTimeoutCrossesEvenWhileStillInitiating() {
    var poll = ConnectPoll(startedAt: 0)
    // No browserOpened yet: still initiating, well past the global cap.
    poll.handle(.linkObtained, at: ConnectPoll.overallTimeout + 1)
    #expect(poll.phase == .timedOut)
}

@Test func connectPollGlobalTimeoutCrossesWhileWaitingBeforeFortyAttempts() {
    var poll = ConnectPoll(startedAt: 0)
    poll.handle(.browserOpened, at: 0)
    poll.handle(.accountMissing, at: 3)
    #expect(poll.phase == .waiting(attempts: 1))
    // Attempt count is nowhere near 40, but the 150 s global cap has passed.
    poll.handle(.accountMissing, at: ConnectPoll.overallTimeout + 5)
    #expect(poll.phase == .timedOut)
}

// The alternative real ending named alongside the timeout: an explicit
// failure (the connectLink call itself erroring) while no link exists yet.
@Test func connectPollFailsExplicitlyWhenTheLinkNeverArrives() {
    var poll = ConnectPoll(startedAt: 0)
    poll.handle(.failure(message: "sin red"), at: 1)
    #expect(poll.phase == .failed(message: "sin red"))
}

@Test func connectPollAccountSeenWinsOverASimultaneousTick() {
    var poll = ConnectPoll(startedAt: 0)
    poll.handle(.browserOpened, at: 0)
    for attempt in 1..<ConnectPoll.maxAttempts {
        poll.handle(.accountMissing, at: Double(attempt) * ConnectPoll.interval)
    }
    // One more tick here would time out (attempt 40) — the account showing
    // up on this very check must still land on complete, not timedOut.
    poll.handle(.accountSeen, at: Double(ConnectPoll.maxAttempts) * ConnectPoll.interval)
    #expect(poll.phase == .complete)
    #expect(!poll.isWaiting)
}

@Test func connectPollRetryResetsCleanly() {
    var poll = ConnectPoll(startedAt: 0)
    poll.handle(.browserOpened, at: 0)
    for attempt in 1...ConnectPoll.maxAttempts {
        poll.handle(.accountMissing, at: Double(attempt) * ConnectPoll.interval)
    }
    #expect(poll.phase == .timedOut)
    poll.handle(.retry, at: 500)
    #expect(poll.phase == .initiating)
    // The global clock restarted with the retry: nowhere near the cap yet.
    poll.handle(.browserOpened, at: 501)
    #expect(poll.phase == .waiting(attempts: 0))
    poll.handle(.accountMissing, at: 502)
    #expect(poll.phase == .waiting(attempts: 1), "attempt count starts over too")
}

@Test func connectPollIgnoresEventsOnceComplete() {
    var poll = ConnectPoll(startedAt: 0)
    poll.handle(.browserOpened, at: 0)
    poll.handle(.accountSeen, at: 3)
    #expect(poll.phase == .complete)
    poll.handle(.accountMissing, at: 6)
    #expect(poll.phase == .complete, "a stray tick after complete changes nothing")
    poll.handle(.failure(message: "late"), at: 6)
    #expect(poll.phase == .complete, "nor does a stray failure")
}
