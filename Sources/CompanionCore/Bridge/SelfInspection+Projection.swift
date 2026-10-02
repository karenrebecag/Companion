import Foundation

// Output side of the self-inspection contract: every field is a case name, a
// count, a length or a flag. An initializer that takes free text keeps its
// length and drops the text.

/// Names that come from outside the app: the client an agent declared and a
/// tool name an MCP server chose. They go out, but capped, so a long one
/// cannot come back as a payload aimed at the next agent that reads it. The
/// same ceiling the bridge puts on the client name it logs.
package enum InspectionName {
    package static let maxScalars = 32

    package static func capped(_ name: String) -> String {
        String(String.UnicodeScalarView(name.unicodeScalars.prefix(maxScalars)))
    }
}

package struct SessionInspection: Sendable, Encodable, Equatable {
    package let kind: String
    package let phase: String?
    package let voice: String
    package let pipeline: String?
    package let holding: Bool
    package let dictating: Bool
    package let jobActive: Bool
    package let jobSteps: Int
    package let jobGoalLength: Int
    package let queuedJobs: Int
    package let approvalToolName: String?
    package let approvalIsMCP: Bool?
    package let approvalQueueSize: Int
    package let notice: String?
    package let cards: [String]
    package let interruption: String?
    package let targetCount: Int
    package let handsLentTo: String?
    package let handsActing: Bool
    package let hasReceipt: Bool

    package init(_ p: SessionProjection) {
        kind = inspectionCaseName(p.kind)
        if case .processing(let phase) = p.kind {
            self.phase = inspectionCaseName(phase)
        } else {
            phase = nil
        }
        voice = inspectionCaseName(p.voice)
        pipeline = p.pipeline.map(inspectionCaseName)
        holding = p.holding
        dictating = p.dictation != nil
        jobActive = p.job != nil
        jobSteps = p.job?.steps.count ?? 0
        jobGoalLength = p.job?.goal?.count ?? 0
        queuedJobs = p.queued.count
        approvalToolName = p.approval.map { InspectionName.capped($0.toolName) }
        approvalIsMCP = p.approval?.isMCP
        approvalQueueSize = p.approvalQueue.count
        notice = p.notice.map(inspectionCaseName)
        cards = p.cards.map(inspectionCaseName)
        interruption = p.interruption.map(inspectionCaseName)
        targetCount = p.targets.count
        handsLentTo = p.handsLentTo.map(InspectionName.capped)
        handsActing = p.handsActing
        hasReceipt = p.receipt != nil
    }
}

package struct IslandInspection: Sendable, Encodable, Equatable {
    package let size: String
    package let meter: String
    package let line: String
    package let textLengths: [Int]
    package let catalogText: String?
    package let light: String
    package let action: String?
    package let showsStop: Bool
    package let approvalToolName: String?
    package let hands: String?
    package let hasReceipt: Bool
    package let partialLength: Int

    package init(_ painted: PaintedIsland) {
        let state = painted.state
        size = inspectionCaseName(state.size)
        meter = inspectionCaseName(state.meter)
        line = inspectionCaseName(state.line)
        textLengths = state.line.textLengths
        // The catalog sentence is copy only for lines with no content in them.
        catalogText = state.line.carriesText ? nil : painted.catalogText
        light = inspectionCaseName(state.light)
        action = state.action.map(inspectionCaseName)
        showsStop = state.showsStop
        approvalToolName = state.approval.map { InspectionName.capped($0.toolName) }
        hands = state.hands.map(InspectionName.capped)
        hasReceipt = state.receipt != nil
        partialLength = state.partial?.count ?? 0
    }
}

/// A closed list: a field not named here cannot leak. Nothing from the
/// Keychain, not even whether a key exists.
package struct SettingsInspection: Sendable, Encodable, Equatable {
    package let languageStored: String?
    package let languageEffective: String
    package let appearance: String
    package let voice: String
    package let volume: Double
    package let voiceMode: String
    package let dictationKey: String
    package let interfaceSounds: Bool
    package let thinkingSound: Bool
    package let decision: Bool
    package let handsLending: Bool
    package let providerOrder: [String]
    package let ownerNameLength: Int
    package let aboutLength: Int
    package let instructionsLength: Int
    package let cityLength: Int
    package let vocabularyWords: Int

    package init(
        languageStored: String?, languageEffective: String, appearance: String, voice: String,
        volume: Double, voiceMode: String, dictationKey: DictationKey, interfaceSounds: Bool,
        thinkingSound: Bool, decision: Bool, handsLending: Bool, providerOrder: [String],
        ownerName: String, about: String, instructions: String, city: String,
        vocabularyWords: Int
    ) {
        self.languageStored = languageStored
        self.languageEffective = languageEffective
        self.appearance = appearance
        self.voice = voice
        self.volume = volume
        self.voiceMode = voiceMode
        self.dictationKey = dictationKey.rawValue
        self.interfaceSounds = interfaceSounds
        self.thinkingSound = thinkingSound
        self.decision = decision
        self.handsLending = handsLending
        self.providerOrder = providerOrder
        ownerNameLength = ownerName.count
        aboutLength = about.count
        instructionsLength = instructions.count
        cityLength = city.count
        self.vocabularyWords = vocabularyWords
    }
}

package struct MessageInspection: Sendable, Encodable, Equatable {
    package let role: String?
    package let origin: String
    package let isStatus: Bool
    package let isFailure: Bool
    package let restored: Bool
    package let attachments: Int
    package let length: Int
    package let language: String?
    package let confidence: Double?

    /// `detected` is computed in-process by the caller from the text; only the
    /// code and the confidence come out (D4).
    package init(_ input: ThreadMessageInput, detected: DetectedLanguage?) {
        role = input.role?.rawValue
        origin = input.origin.rawValue
        isStatus = input.isStatus
        isFailure = input.isFailure
        restored = input.restored
        attachments = input.attachments
        length = input.text.count
        language = detected?.code
        confidence = detected?.confidence
    }
}
