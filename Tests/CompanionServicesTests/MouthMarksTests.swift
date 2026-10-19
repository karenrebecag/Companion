import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

/// Row 8: a scripted classic turn — the mouth's marks land on the session's
/// clock and the `voice timeline:` line carries the three new segments with
/// values; `firstToken→audio` stays. Marks with no released hold are a
/// stranger's (a job announcement) and are dropped.
@Test @MainActor func testTheVoiceTimelineCarriesTheMouthSegments() async {
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-timeline-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: logURL) }
    await Log.capturing(to: logURL) {
        let h = makeVoiceHarness()
        h.synth.yield(.mark(.firstCut))
        await settle(0.05)
        expectEq(await h.session.timeline.firstCut, nil, "boca: sin hold no se marca")

        h.transcriber.stoppedText = "abre Safari"
        h.chat.rounds = [[.text("Listo.")]]
        h.clock.now = 10
        await h.session.hold()
        await pumpUntil("boca: listening") { h.watch.latest.state == .listening }
        h.clock.now = 11
        await h.session.release()
        await pumpUntil("boca: habla") { h.synth.queue.contains("Listo.") }
        h.clock.now = 11.4
        h.synth.yield(.mark(.firstCut))
        await pumpUntilAsync("boca: firstCut") { await h.session.timeline.firstCut != nil }
        h.clock.now = 11.42
        h.synth.yield(.mark(.ttsRequest))
        await pumpUntilAsync("boca: ttsRequest") { await h.session.timeline.ttsRequest != nil }
        h.clock.now = 12.0
        h.synth.yield(.mark(.firstByte))
        await pumpUntilAsync("boca: firstByte") { await h.session.timeline.firstByte != nil }
        h.clock.now = 12.03
        h.synth.yield(.chunkStarted(text: "Listo.", duration: 0))
        await pumpUntilAsync("boca: se aplana") { await h.session.lastTimeline != nil }
    }
    let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    let line = text.split(separator: "\n").first { $0.contains("voice timeline:") }
        .map(String.init) ?? ""
    expect(line.contains("firstCut→ttsRequest 20"), "boca: corte a petición (\(line))")
    expect(line.contains("ttsRequest→firstByte 580"), "boca: petición a primer byte (\(line))")
    expect(line.contains("firstByte→audible 30"), "boca: primer byte a audible (\(line))")
    expect(line.contains("firstToken→audio"), "boca: firstToken→audio sigue en la línea")
}

/// Row 8: a fetcher with a style of its own; returns fresh audio every time.
final class StyledFetch: TTSFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var calls: [String] { lock.withLock { stored } }

    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        lock.withLock { stored.append(text) }
        return Data("nueva".utf8)
    }

    func cacheVariant(voice: VoiceID) -> String { "\(voice.rawValue)|1.1|abc" }
}
