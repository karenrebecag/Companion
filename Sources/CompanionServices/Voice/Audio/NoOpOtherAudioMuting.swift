import CompanionCore

/// Placeholder until the Core Audio adapter lands: the decision, the
/// preference and the wiring already run, nothing is silenced.
package struct NoOpOtherAudioMuting: OtherAudioMuting {
    package init() {}
    package func mute() async {}
    package func unmute() async {}
}
