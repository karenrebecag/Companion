import Foundation

/// Why a mic frame did NOT reach OpenAI. The realtime path gates frames before
/// forwarding; when the model misses part of an instruction, the first question
/// is whether the audio ever left this machine. These are the gates.
public enum GateReason: String, Sendable, Equatable, Hashable, CaseIterable {
    case empty       // the frame carried no PCM
    case muted       // mic muted or disabled
    case echoGuard   // listening, but guarded against the agent's own echo
    case noAEC       // agent is speaking and there is no echo cancellation
    case backchannel // speaking + AEC, but the gate judged it a short "ajá"
}

/// The raw tally of one user turn: how many frames reached OpenAI and how many
/// were gated, by reason. This is "lo que OpenAI recibe", counted.
public struct FrameTally: Sendable, Equatable {
    public var forwarded = 0
    public var gated: [GateReason: Int] = [:]

    public init() {}

    public mutating func add(forwarded: Bool, reason: GateReason?) {
        if forwarded { self.forwarded += 1 }
        else if let reason { gated[reason, default: 0] += 1 }
    }

    public var gatedTotal: Int { gated.values.reduce(0, +) }
    public var total: Int { forwarded + gatedTotal }
}

/// Read-only classifier that names the gate a frame hit, WITHOUT the stateful
/// backchannel RMS check `shouldForward` owns — the audit must never mutate the
/// path it watches. Only called for frames the path already gated, so the
/// forwarded branches here are unreachable and collapse to `.empty`.
public enum RealtimeGate {
    public static func reason(
        muted: Bool, emptyPCM: Bool, micEnabled: Bool,
        state: TurnState, echoGuarded: Bool, aec: Bool
    ) -> GateReason {
        if emptyPCM { return .empty }
        if !micEnabled || muted { return .muted }
        if state != .speaking { return echoGuarded ? .echoGuard : .empty }
        if !aec { return .noAEC }
        return .backchannel
    }
}

/// Turns one turn's evidence into log lines. Pure: no audio, no I/O — just the
/// native ground truth, what OpenAI transcribed and the frame counts.
public enum VoiceAuditReport {
    public static func turnLine(
        native: String, openAI: String, tally: FrameTally, goal: String?
    ) -> String {
        let gates = GateReason.allCases
            .compactMap { r in tally.gated[r].map { "\(r.rawValue) \($0)" } }
            .joined(separator: ", ")
        // Counts, never the words: this line reaches the shared main log.
        let goalPart = goal.map { " goal=\($0.count) chars" } ?? ""
        return "audit turn: native=\(native.count) chars openai=\(openAI.count) chars "
            + "frames fwd=\(tally.forwarded) gated=\(tally.gatedTotal)"
            + (gates.isEmpty ? "" : " (\(gates))") + goalPart
    }
}
