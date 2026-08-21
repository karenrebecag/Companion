import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func settingsTests() {
    testPreferencePersistence()
    testPreferenceRoundTrip()
}

@MainActor func testPreferencePersistence() {
    // Test theme preference
    let originalTheme = AppTypeface.stored
    AppTypeface.stored = .serif
    expectEq(AppTypeface.stored, .serif,
             "theme: stored preference persists")
    AppTypeface.stored = originalTheme

    // Test accent preference
    let originalHighlight = Highlight.stored
    Highlight.stored = .blue
    expectEq(Highlight.stored, .blue,
             "accent: stored preference persists")
    Highlight.stored = originalHighlight
}

@MainActor func testPreferenceRoundTrip() {
    // Test all typeface options round-trip
    for face in AppTypeface.allCases {
        AppTypeface.stored = face
        expectEq(AppTypeface.stored, face,
                 "typeface: \(face.rawValue) round-trips")
    }

    // Test all highlight options round-trip
    for highlight in Highlight.allCases {
        Highlight.stored = highlight
        expectEq(Highlight.stored, highlight,
                 "highlight: \(highlight.rawValue) round-trips")
    }

    // Reset to defaults
    AppTypeface.stored = .inter
    Highlight.stored = .standard
}

// MARK: - Preview de voz y preferencias (cableado de Wave 5a)

@Test @MainActor func voicePreviewTests() async {
    await testPreviewPlaysChosenVoice()
    await testPreviewReportsFailure()
    await testPreviewIgnoresDoubleTap()
    testPreferencesSurviveRoundTrip()
}

@MainActor func testPreviewPlaysChosenVoice() async {
    let sampler = RecordingSampler()
    let preview = VoicePreview(sampler: sampler)
    preview.play(.cedar)
    await pumpUntil("preview: termina") { preview.playing == nil }
    expectEq(sampler.played.first?.voice, .cedar, "preview: usa la voz elegida")
    expectEq(sampler.played.first?.text, VoicePreview.sampleText,
             "preview: frase corta de muestra")
    expect(preview.errorText == nil, "preview: sin error")
}

@MainActor func testPreviewReportsFailure() async {
    let preview = VoicePreview(sampler: FailingSampler())
    preview.play(.marin)
    await pumpUntil("preview: termina con error") { preview.playing == nil }
    expectEq(preview.errorText, VoiceCopy.previewFailed,
             "preview: sin red lo dice en vez de callar")
}

@MainActor func testPreviewIgnoresDoubleTap() async {
    let sampler = RecordingSampler(delay: 0.05)
    let preview = VoicePreview(sampler: sampler)
    preview.play(.alloy)
    preview.play(.alloy)
    await pumpUntil("preview: termina") { preview.playing == nil }
    expectEq(sampler.played.count, 1, "preview: no encima dos muestras")
}

@MainActor func testPreferencesSurviveRoundTrip() {
    let previousName = UserProfile.ownerName
    let previousVoice = VoiceProfile.stored
    defer {
        UserProfile.ownerName = previousName
        VoiceProfile.stored = previousVoice
    }
    UserProfile.ownerName = "Karen"
    VoiceProfile.stored = .sage
    expectEq(UserProfile.ownerName, "Karen", "prefs: el nombre persiste")
    expectEq(VoiceProfile.stored, .sage, "prefs: la voz persiste")
}

private final class RecordingSampler: VoiceSampling, @unchecked Sendable {
    struct Sample: Equatable { let text: String; let voice: VoiceID }
    private let lock = NSLock()
    private let delay: TimeInterval
    private var samples: [Sample] = []
    var played: [Sample] { lock.withLock { samples } }

    init(delay: TimeInterval = 0) { self.delay = delay }

    func play(_ text: String, voice: VoiceID) async throws {
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        lock.withLock { samples.append(Sample(text: text, voice: voice)) }
    }
}

private struct FailingSampler: VoiceSampling {
    func play(_ text: String, voice: VoiceID) async throws {
        throw ChatError.unreachable
    }
}
