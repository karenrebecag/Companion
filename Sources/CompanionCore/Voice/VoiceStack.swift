import Foundation

/// One product-chosen role. `id` is the model or adapter; `provider` is who
/// serves it. Neither is the chat picker.
package struct VoiceRole: Sendable, Equatable {
    package var id: String
    package var provider: String

    package init(id: String, provider: String) {
        self.id = id
        self.provider = provider
    }
}

package struct VoiceStack: Sendable, Equatable {
    package var ear: VoiceRole?
    package var brain: VoiceRole?
    package var mouth: VoiceRole?
    package var sight: VoiceRole?

    package init(
        ear: VoiceRole? = nil,
        brain: VoiceRole? = nil,
        mouth: VoiceRole? = nil,
        sight: VoiceRole? = nil
    ) {
        self.ear = ear
        self.brain = brain
        self.mouth = mouth
        self.sight = sight
    }

    /// 15c-4/15c-7: a brain that already picks the tool by commit, so the
    /// local router in front of it only adds latency.
    package var hasFastBrain: Bool {
        guard let provider = brain?.provider else { return false }
        return HoldBrainCatalog.fast.contains { $0.id == provider }
    }

    package var logLine: String {
        "ear=\(Self.tag(ear)) brain=\(Self.tag(brain)) mouth=\(Self.tag(mouth)) sight=\(Self.tag(sight))"
    }

    private static func tag(_ role: VoiceRole?) -> String { role?.id ?? "-" }
}

package enum VoiceStackResolver: Sendable {
    /// Keys and probes only. `providerOrder` is deliberately not a parameter:
    /// the hold must not follow the typed-chat ladder (Wave 14a).
    package static func resolve(
        secrets: [SecretKey: Bool],
        appleSpeech: Bool,
        localModel: String?,
        elevenLabsVoiceID: String = ""
    ) -> VoiceStack {
        let openAI = secrets[.openAI] == true
        let cerebras = secrets[.cerebras] == true
        let openRouter = secrets[.openRouter] == true
        let local = (localModel ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLocal = !local.isEmpty

        // 15e: the hold's ear is Apple's on-device analyzer whatever keys
        // exist; naming the cloud ear here made the press log lie.
        let ear: VoiceRole? = appleSpeech
            ? VoiceRole(id: "apple-analyzer", provider: "apple")
            : nil

        let brain: VoiceRole?
        if cerebras {
            brain = VoiceRole(
                id: ProviderDescriptor.cerebras.model, provider: "cerebras")
        } else if openAI {
            // Mini is the hold brain; chat's default gpt-4o is a different lane.
            brain = VoiceRole(id: HoldBrainCatalog.openAIModel, provider: "openai")
        } else if openRouter {
            brain = VoiceRole(
                id: ProviderDescriptor.openRouter.model, provider: "openrouter")
        } else if hasLocal {
            brain = VoiceRole(id: local, provider: "ollama")
        } else {
            brain = nil
        }

        let mouth: VoiceRole?
        if ElevenLabsMouth.isChosen(
            hasKey: secrets[.elevenLabs] == true, voiceID: elevenLabsVoiceID) {
            mouth = VoiceRole(id: "elevenlabs/\(ElevenLabsMouth.model)", provider: "elevenlabs")
        } else if openAI {
            mouth = VoiceRole(id: "gpt-4o-mini-tts", provider: "openai")
        } else if brain != nil {
            mouth = VoiceRole(id: "avspeech", provider: "apple")
        } else {
            mouth = nil
        }

        let sight: VoiceRole? = openAI
            ? VoiceRole(id: "gpt-4o-mini", provider: "openai")
            : nil

        return VoiceStack(ear: ear, brain: brain, mouth: mouth, sight: sight)
    }
}

/// Wave 15f-7a: the one rule for when the hold speaks through ElevenLabs,
/// shared by the press log and the router that actually picks the mouth so
/// the two can never disagree.
package enum ElevenLabsMouth {
    /// Flash v2.5: ElevenLabs' lowest-latency model (~75 ms per its docs,
    /// elevenlabs.io/docs/overview/models), and it takes `language_code`.
    package static let model = "eleven_flash_v2_5"

    package static func isChosen(hasKey: Bool, voiceID: String) -> Bool {
        hasKey && !voiceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 15f-6: the voice bench shortlist (spec §8.3), Karen's blind pick
    /// first; Brian stays as the old default so it is one click away.
    package static let presets: [ElevenLabsVoicePreset] = [
        ElevenLabsVoicePreset(name: "Ana María", id: "m7yTemJqdIqrcNleANfX"),
        ElevenLabsVoicePreset(name: "Regina", id: "9Godp7dNohUvXk6qp0gS"),
        ElevenLabsVoicePreset(name: "Jorge", id: "Rt1JHkPO27QCUX6Nd5bV"),
        ElevenLabsVoicePreset(name: "Antonio", id: "htFfPSZGJwjBv1CL0aMD"),
        ElevenLabsVoicePreset(name: "Cristina Campos", id: "CaJslL1xziwefCeTNzHv"),
        ElevenLabsVoicePreset(name: "Brian", id: "Gubgw9l4dtIoQA9YZHgx"),
    ]

    static let maxVoiceIDLength = 64

    /// Security review 2026-09-25 (LOW-1): the id is spliced into a URL
    /// path, so only what ElevenLabs issues passes — `^[A-Za-z0-9]{1,64}$`
    /// after trimming the ends. Lives here so Settings refuses exactly
    /// what the client would refuse.
    package static func isValidVoiceID(_ raw: String) -> Bool {
        let voice = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... maxVoiceIDLength).contains(voice.unicodeScalars.count) else { return false }
        return voice.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A: return true
            default: return false
            }
        }
    }
}

package struct ElevenLabsVoicePreset: Sendable, Equatable, Hashable {
    package let name: String
    package let id: String

    package init(name: String, id: String) {
        self.name = name
        self.id = id
    }
}

/// 15e-3: which providers the hold's two chat clients may ask. Pure so the
/// composition root's wiring is testable without building the app.
package enum HoldBrainCatalog {
    /// The hold's brain on OpenAI: a tool call by commit costs less than
    /// gpt-4o's, and it is what `VoiceStackResolver` names in the log.
    package static let openAIModel = "gpt-4o-mini"

    /// One attempt each, no backoff: a 429 retried with sleeps was the
    /// 8-24 s turns measured live (15c-7).
    package static let fast: [ProviderDescriptor] = [.cerebras]

    /// The fallback when the fast brain fails before its first delta. The
    /// fast rungs were already asked this turn, so they are skipped.
    package static func ladder(_ effective: [ProviderDescriptor]) -> [ProviderDescriptor] {
        let fastIDs = Set(fast.map(\.id))
        return effective
            .filter { !fastIDs.contains($0.id) }
            .map { $0.id == ProviderDescriptor.openAI.id ? $0.withModel(openAIModel) : $0 }
    }
}
