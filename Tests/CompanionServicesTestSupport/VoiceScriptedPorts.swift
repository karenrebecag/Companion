import CompanionCore
import CompanionServices
import Foundation

// Voice ports scripted for tests in more than one target: they were file-local
// to one test file until the voice tests split across Services and Integration.

/// A sensor with a real delay, so a test can prove `senseVoice` reads an
/// already-finished press-time Task instead of paying the delay again at
/// commit — and records whether cancellation ever reached it.
package final class DelayedContextSensor: ContextSensing, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _cancelled = false
    private var _finished = 0
    package var finished: Int { lock.withLock { _finished } }
    package var calls: Int { lock.withLock { _calls } }
    package var wasCancelled: Bool { lock.withLock { _cancelled } }
    private let delay: TimeInterval
    private let laterDelay: TimeInterval
    private let context: TurnContext

    /// `laterDelay` applies from the second `sense` on: a test that must prove
    /// the commit does not sense again makes a second call unmistakably slow.
    package init(delay: TimeInterval, laterDelay: TimeInterval? = nil, context: TurnContext) {
        self.delay = delay
        self.laterDelay = laterDelay ?? delay
        self.context = context
    }

    package func sense(_ channels: ContextChannels, budget: Duration) async -> TurnContext {
        let call = lock.withLock { _calls += 1; return _calls }
        do {
            try await Task.sleep(for: .seconds(call == 1 ? delay : laterDelay))
            lock.withLock { _finished += 1 }
        } catch {
            lock.withLock { _cancelled = true }
        }
        return context
    }
}

package final class ScriptedFieldProbe: FocusedFieldProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var _probes = 0
    package var field: FocusedField?
    package var trusted = true
    /// What the caller wants recorded at probe time (12e: that the mic is
    /// already opening when Accessibility is asked).
    package var onProbe: (@Sendable () -> Void)?
    package var probes: Int { lock.withLock { _probes } }
    package init(_ field: FocusedField? = nil) { self.field = field }
    package func isTrusted() -> Bool { trusted }
    package func focusedField() -> FocusedField? {
        lock.withLock { _probes += 1 }
        onProbe?()
        return field
    }
}

package final class ScriptedInjector: TextInjecting, @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var _texts: [String] = []
    private var _fields: [FocusedField] = []
    package var failure: InjectionFailure?
    package var texts: [String] { lock.withLock { _texts } }
    package var fields: [FocusedField] { lock.withLock { _fields } }

    package func inject(_ text: String, into field: FocusedField) async -> InjectionResult {
        lock.withLock {
            _texts.append(text)
            _fields.append(field)
        }
        if let failure { return .failed(failure) }
        return .injected(text.count, via: .ax)
    }
}

/// One parent tool whose result carries attacker-controlled page text.
package final class EchoingParentTools: ParentToolExecuting, @unchecked Sendable {
    package let output: String
    package init(output: String) { self.output = output }
    package func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    package func handles(_ name: String) -> Bool { true }
    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: output, target: name)
    }
}
