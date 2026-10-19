import Foundation

/// Which provider reads a screen. Pure, so the hold's capture gate and the
/// sidecar that sends the frame pick the same provider from the same keys.
package enum VisionRoute {
    /// Cerebras first: its vision model is the one that needs no OpenAI key.
    package static func provider(keys: Set<SecretKey>) -> ProviderDescriptor? {
        if keys.contains(.cerebras) { return .cerebrasVision }
        if keys.contains(.openAI) { return .openAIVision }
        return nil
    }

    /// A hold captures the screen only when it may and a provider can read it.
    package static func holdCaptures(seesScreen: Bool, keys: Set<SecretKey>) -> Bool {
        seesScreen && provider(keys: keys) != nil
    }
}
