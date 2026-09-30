import Foundation

/// Unified-memory tier. The product default is the 16 GB tier on purpose:
/// calibrating on a bigger machine turns a 16 GB Mac's first launch into swap,
/// and the machine this was written on is not the machine it ships to.
package enum RAMTier: String, Sendable, Equatable, CaseIterable {
    case small, medium, large, xlarge

    /// Thresholds sit BETWEEN shipping configurations (8/16/18/24/32/36/48/64),
    /// never on one: a Mac that lands exactly on a boundary would change tier
    /// with the vendor's rounding rather than with its own capability. The
    /// large/xlarge cut is 40 and not 48 for exactly that reason — 48 GB is a
    /// configuration Apple sells, and it belongs above the line, not on it.
    package static func forBytes(_ bytes: UInt64) -> RAMTier {
        let gib = bytes / (1024 * 1024 * 1024)
        switch gib {
        case ..<12: return .small
        case ..<20: return .medium
        case ..<40: return .large
        default: return .xlarge
        }
    }

    /// Ceiling for picking an already-installed model. Roughly half the tier:
    /// the weights must leave room for the OS and the app, or the machine
    /// swaps and the answer never arrives.
    package var maxModelBytes: UInt64 {
        let gib = UInt64(1024 * 1024 * 1024)
        switch self {
        case .small: return 3 * gib
        case .medium: return 9 * gib
        case .large: return 20 * gib
        case .xlarge: return 48 * gib
        }
    }

    /// Suggested pull, dated 2026-08. This is the ONLY place in the product
    /// that names a model tag: when the recommendation ages, it ages here.
    package var suggestedPull: String {
        switch self {
        case .small: return "llama3.2:3b"
        case .medium: return "qwen3:8b"
        case .large: return "qwen3:14b"
        case .xlarge: return "qwen3:32b"
        }
    }

    /// Delegation needs tool calling, and the 3B class fails it often enough
    /// that promising a specialist there would be a lie in the copy.
    package var suitableForJobs: Bool { self != .small }
}

package struct InstalledModel: Sendable, Equatable {
    package var name: String
    package var sizeBytes: UInt64

    package init(name: String, sizeBytes: UInt64) {
        self.name = name
        self.sizeBytes = sizeBytes
    }
}

/// Picking which local model to talk to. Pure: the HTTP scan lives in Services.
package enum LocalModelChoice: Sendable {
    /// Names that are not chat models. Handing one to the router fails the
    /// first message with a friendlier face than a phantom tag, which is the
    /// exact defect this wave exists to fix.
    static let nonChatMarkers = ["embed", "bge", "rerank"]

    package static func usable(_ models: [InstalledModel]) -> [InstalledModel] {
        models.filter { model in
            let name = model.name.lowercased()
            return !nonChatMarkers.contains { name.contains($0) }
        }
    }

    /// Order of the rules is the product decision, not an implementation
    /// detail: what the user already chose beats what the heuristic prefers.
    package static func choose(
        from models: [InstalledModel],
        tier: RAMTier,
        preferred: String?
    ) -> InstalledModel? {
        let candidates = usable(models)
        if candidates.isEmpty { return nil }

        if let preferred,
           let kept = candidates.first(where: { $0.name == preferred }) {
            return kept
        }

        let fits = candidates.filter { $0.sizeBytes <= tier.maxModelBytes }
        if !fits.isEmpty { return largest(fits) }

        // Nothing fits the tier. The user already paid for that download, so
        // "you have no model" would be false: slow is a different problem
        // from absent. Take the least bad one.
        return smallest(candidates)
    }

    /// Ties break lexicographically so the same inventory always resolves to
    /// the same model — a picker that wobbles between launches is a bug the
    /// user reports as "it forgot my model".
    private static func largest(_ models: [InstalledModel]) -> InstalledModel? {
        best(models, preferLarger: true)
    }

    private static func smallest(_ models: [InstalledModel]) -> InstalledModel? {
        best(models, preferLarger: false)
    }

    /// `min` with a "is better than" predicate: the winner is the element no
    /// other element beats.
    private static func best(
        _ models: [InstalledModel], preferLarger: Bool
    ) -> InstalledModel? {
        models.min { a, b in
            if a.sizeBytes != b.sizeBytes {
                return preferLarger
                    ? a.sizeBytes > b.sizeBytes
                    : a.sizeBytes < b.sizeBytes
            }
            return a.name < b.name
        }
    }
}

/// A way to talk without a key. The model tag travels with the path because
/// "Ollama is alive" and "Ollama can answer you" are different facts, and only
/// the second one is worth showing someone.
package enum LocalPath: Sendable, Equatable {
    case ollama(model: String)
    case appleFM

    /// Matches the catalog descriptor's id. The ladder is keyed by id and not
    /// by name: the name is copy and can be reworded, an id cannot.
    package var providerId: String {
        switch self {
        case .ollama: return ProviderDescriptor.ollama.id
        case .appleFM: return "apple"
        }
    }

    /// For display only.
    package var providerName: String {
        switch self {
        case .ollama: return "Ollama"
        case .appleFM: return "Apple"
        }
    }

    package var model: String? {
        switch self {
        case .ollama(let model): return model
        case .appleFM: return nil
        }
    }
}

/// How the app decided to open. Four states, not a Bool: "still looking" is a
/// real answer, and collapsing it into "no key" is what makes a launch flicker
/// from onboarding to chat and back.
package enum StartupState: Sendable, Equatable {
    /// A key is stored: the paid path, unchanged and never slowed by a probe.
    case premium
    /// Looking for a local path. The thread is NOT shown in this state.
    case probing
    /// At least one local path answered.
    case base([LocalPath])
    /// Nothing answered.
    case none
}

/// Read-only detection of the ways this Mac can answer without a key.
/// Implemented in Services; the view model only knows the port.
package protocol StartupProbing: Sendable {
    func probe(preferred: String?) async -> [LocalPath]
}
