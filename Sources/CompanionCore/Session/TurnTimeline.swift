import Foundation

/// One hold, in milliseconds (Wave 12c). The line answers the questions
/// the corpus optimizes with: is the session hot at the press, how long
/// until the ear hears, how much dead air after the release. The two tool
/// gaps measure how long the model takes to decide a tool call and how long
/// the code takes to run it (Wave DM0). Pure; the session marks, the log reads.
package struct TurnTimeline: Sendable, Equatable {
    package enum Point: Sendable, Equatable, CaseIterable {
        case pressed, micReady, earReady, sessionReady, firstPartial, released, committed, contextReady, toolCallSeen, toolDone, firstAudio, decision, firstToken, earFinal, firstCut, ttsRequest, firstByte, acknowledged
    }

    package var pressed: TimeInterval?
    package var micReady: TimeInterval?
    package var earReady: TimeInterval?
    package var sessionReady: TimeInterval?
    package var firstPartial: TimeInterval?
    package var released: TimeInterval?
    package var committed: TimeInterval?
    /// Wave 15g-5: the context fan-out is in hand and the chat request is
    /// about to leave — splits the vision wait from the model's own share.
    package var contextReady: TimeInterval?
    package var toolCallSeen: TimeInterval?
    package var toolDone: TimeInterval?
    package var firstAudio: TimeInterval?
    /// DM1c: when `DecisionGate.plan` returned. Done says `< 1.5s` here.
    package var decision: TimeInterval?
    /// Wave 15c-0: the brain's first content for this turn — a chat delta or
    /// the router's own reply — measured from `committed` so a slow model is
    /// visible apart from a slow mouth (wave-15c-tubo-rapido.md §1).
    package var firstToken: TimeInterval?
    /// Wave 15d-0: the ear's final transcript in hand — splits
    /// the ear's share of the wait from the brain's and the mouth's.
    package var earFinal: TimeInterval?
    /// Wave 15f-5: the mouth's own share, for the first sentence only.
    package var firstCut: TimeInterval?
    package var ttsRequest: TimeInterval?
    package var firstByte: TimeInterval?
    /// Wave 16h-2: the turn's own acknowledgement was queued, before the
    /// slow work it announces — criterion 1 reads `commit→ack` < 2 s.
    package var acknowledged: TimeInterval?

    package init() {}

    /// The first mark of a point wins: a retry never rewrites history.
    package mutating func mark(_ point: Point, at time: TimeInterval) {
        switch point {
        case .pressed: if pressed == nil { pressed = time }
        case .micReady: if micReady == nil { micReady = time }
        case .earReady: if earReady == nil { earReady = time }
        case .sessionReady: if sessionReady == nil { sessionReady = time }
        case .firstPartial: if firstPartial == nil { firstPartial = time }
        case .released: if released == nil { released = time }
        case .committed: if committed == nil { committed = time }
        case .contextReady: if contextReady == nil { contextReady = time }
        case .toolCallSeen: if toolCallSeen == nil { toolCallSeen = time }
        case .toolDone: if toolDone == nil { toolDone = time }
        case .firstAudio: if firstAudio == nil { firstAudio = time }
        case .decision: if decision == nil { decision = time }
        case .firstToken: if firstToken == nil { firstToken = time }
        case .earFinal: if earFinal == nil { earFinal = time }
        case .firstCut: if firstCut == nil { firstCut = time }
        case .ttsRequest: if ttsRequest == nil { ttsRequest = time }
        case .firstByte: if firstByte == nil { firstByte = time }
        case .acknowledged: if acknowledged == nil { acknowledged = time }
        }
    }

    /// Nil before a press: there is nothing to say about a hold that did
    /// not happen.
    package func line() -> String? {
        guard let pressed else { return nil }
        let parts = [
            "press→mic \(Self.gap(pressed, micReady))",
            "press→ear \(Self.gap(pressed, earReady))",
            "press→ready \(Self.gap(pressed, sessionReady))",
            "press→partial \(Self.gap(pressed, firstPartial))",
            "release→commit \(Self.gap(released, committed))",
            // 15d-0: ear, brain and mouth each get their own share of the wait.
            "release→earFinal \(Self.gap(released, earFinal))",
            // 15b-0: the number Done §6.3 measures — soltar→primer audio —
            // straight from the release, not routed through `committed`.
            "release→audio \(Self.gap(released, firstAudio))",
            "firstToken→audio \(Self.gap(firstToken, firstAudio))",
            // 15f-5: the mouth's share split into queue, network and player.
            "firstCut→ttsRequest \(Self.gap(firstCut, ttsRequest))",
            "ttsRequest→firstByte \(Self.gap(ttsRequest, firstByte))",
            "firstByte→audible \(Self.gap(firstByte, firstAudio))",
            "commit→ack \(Self.gap(committed, acknowledged))",
            "commit→audio \(Self.gap(committed, firstAudio))",
            // 15g-5: the context fan-out's share, before the model starts.
            "commit→context \(Self.gap(committed, contextReady))",
            "commit→firstToken \(Self.gap(committed, firstToken))",
            "commit→decision \(Self.gap(committed, decision))",
            "commit→tool \(Self.gap(committed, toolCallSeen))",
            "tool→done \(Self.gap(toolCallSeen, toolDone))",
        ]
        return "voice timeline: " + parts.joined(separator: " · ")
    }

    private static func gap(_ from: TimeInterval?, _ to: TimeInterval?) -> String {
        guard let from, let to else { return "—" }
        return String(Int(((to - from) * 1000).rounded()))
    }
}

extension TurnTimeline.Point {
    /// The mouth reports its instants without knowing about the timeline.
    package init(_ mark: SpeechMark) {
        switch mark {
        case .firstCut: self = .firstCut
        case .ttsRequest: self = .ttsRequest
        case .firstByte: self = .firstByte
        }
    }
}
