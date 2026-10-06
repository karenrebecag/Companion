import CompanionCore

/// What the HAL says about one device, reduced to what choosing needs. Pure
/// so the fallback order is tested without a sound card.
package struct MicInputCandidate: Equatable, Sendable {
    package enum Kind: Equatable, Sendable { case builtIn, aggregate, other }

    package var id: UInt32
    package var uid: String
    package var inputChannels: Int
    package var kind: Kind

    package init(id: UInt32, uid: String, inputChannels: Int, kind: Kind) {
        self.id = id
        self.uid = uid
        self.inputChannels = inputChannels
        self.kind = kind
    }
}

package enum MicInputChooser {
    package static func choose(
        target: MicTarget, candidates: [MicInputCandidate], defaultID: UInt32?
    ) -> UInt32? {
        let usable = candidates.filter { $0.inputChannels > 0 }
        let builtIn = usable.first { $0.kind == .builtIn }?.id
        // An aggregate default is the HAL's mix of other devices: pinning it
        // is what leaves voice processing unable to initialize.
        let system = defaultID
            .flatMap { id in usable.first { $0.id == id && $0.kind != .aggregate } }?.id
            ?? builtIn
        switch target {
        case .device(let uid):
            return usable.first { $0.uid == uid }?.id ?? system
        case .builtIn:
            return builtIn ?? system
        case .systemDefault:
            return system
        }
    }
}
