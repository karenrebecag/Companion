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

@Test @MainActor func settingsModuleTests() {
    testAppearancePreferenceRoundTrip()
    testAppearanceAutoLeavesWindowToSystem()
    testTypeScaleClampAndNudge()
    testProfileFieldsRoundTrip()
    testWorkdirPreferenceLabel()
    testWorkdirRejectsUnboundedRoots()
}

@MainActor func testAppearancePreferenceRoundTrip() {
    let previous = AppearancePreference.stored
    defer { AppearancePreference.stored = previous }
    for pref in AppearancePreference.allCases {
        AppearancePreference.stored = pref
        expectEq(AppearancePreference.stored, pref,
                 "tema: \(pref.rawValue) round-trip")
    }
    expectEq(AppearancePreference.light.label, "Claro", "tema: claro")
    expectEq(AppearancePreference.dark.label, "Oscuro", "tema: oscuro")
    expectEq(AppearancePreference.auto.label, "Sistema", "tema: sistema")
}

@MainActor func testAppearanceAutoLeavesWindowToSystem() {
    expect(WindowChrome.appearance(for: .auto) == nil,
           "tema: auto no fuerza NSAppearance")
    expect(WindowChrome.appearance(for: .light) != nil,
           "tema: claro pinta aqua")
    expect(WindowChrome.appearance(for: .dark) != nil,
           "tema: oscuro pinta darkAqua")
}

@MainActor func testTypeScaleClampAndNudge() {
    let previous = TypeScale.delta
    defer { TypeScale.delta = previous }
    TypeScale.delta = TypeScale.min
    expectEq(TypeScale.nudge(-1), TypeScale.min, "tipo: no baja de −2")
    TypeScale.delta = TypeScale.max
    expectEq(TypeScale.nudge(1), TypeScale.max, "tipo: no sube de +3")
    TypeScale.delta = 0
    expectEq(TypeScale.nudge(1), 1, "tipo: nudge +1")
    expectEq(TypeScale.displayLabel(0), "0", "tipo: cero se lee 0")
    expectEq(TypeScale.displayLabel(2), "+2", "tipo: positivo con signo")
    expectEq(TypeScale.displayLabel(-1), "−1", "tipo: negativo tipográfico")
}

@MainActor func testProfileFieldsRoundTrip() {
    let previousName = UserProfile.ownerName
    let previousAbout = UserProfile.about
    let previousInstructions = UserProfile.instructions
    defer {
        UserProfile.ownerName = previousName
        UserProfile.about = previousAbout
        UserProfile.instructions = previousInstructions
    }
    UserProfile.ownerName = "Karen"
    UserProfile.about = "diseña producto"
    UserProfile.instructions = "Sé breve"
    expectEq(UserProfile.ownerName, "Karen", "perfil: nombre")
    expectEq(UserProfile.about, "diseña producto", "perfil: about")
    expectEq(UserProfile.instructions, "Sé breve", "perfil: instrucciones")
}

@MainActor func testWorkdirPreferenceLabel() {
    let previous = WorkdirPreference.stored
    defer { WorkdirPreference.stored = previous }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    WorkdirPreference.stored = home + "/Desktop"
    if WorkdirPreference.isAllowed(home + "/Desktop") {
        expectEq(WorkdirPreference.label, "Desktop", "carpeta: último componente")
    }
    WorkdirPreference.stored = nil
    expect(WorkdirPreference.label == nil, "carpeta: nil no inventa etiqueta")
}

@MainActor func testWorkdirRejectsUnboundedRoots() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    expect(!WorkdirPreference.isAllowed("/"), "carpeta: no la raíz del disco")
    expect(!WorkdirPreference.isAllowed("/Users"), "carpeta: no /Users")
    expect(!WorkdirPreference.isAllowed("/tmp"), "carpeta: no fuera del home")
    expect(WorkdirPreference.isAllowed(home), "carpeta: el home sí")
    let previous = WorkdirPreference.stored
    defer { WorkdirPreference.stored = previous }
    WorkdirPreference.stored = "/"
    expect(WorkdirPreference.validated == nil,
           "carpeta: / no sobrevive a validated")
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
