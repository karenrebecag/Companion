@preconcurrency import AVFoundation
import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func realtimePCMTests() {
    testEncoderFloat48k()
    testEncoderInt16AtTarget()
    testEncoderSilenceAndEmpty()
    testEncoderFormatChangeAndRates()
    testEncoderStereoLargeAndTiny()
    testMicAccessInjected()
    testMicConstructsWithoutEngine()
    testPlayerUnstartedPlayNoops()
    testPlayerSharedStartWithoutEngine()
}

@MainActor func testEncoderFloat48k() {
    var encoder = RealtimeEncoder()
    let buf = makePCMBuffer(
        common: .pcmFormatFloat32, sampleRate: 48_000, channels: 1,
        interleaved: false, frames: 480, asSine: true)
    let data = encoder.encode(buf)
    expect(data != nil, "encoder: float 48k produce")
    expect((data?.count ?? 0) > 0, "encoder: float 48k no vacío")
    expectEq((data?.count ?? 1) % 2, 0, "encoder: float 48k int16 par")
}

@MainActor func testEncoderInt16AtTarget() {
    var encoder = RealtimeEncoder()
    let buf = makePCMBuffer(
        common: .pcmFormatInt16, sampleRate: 24_000, channels: 1,
        interleaved: true, frames: 240, asSine: true)
    let data = encoder.encode(buf)
    expect(data != nil, "encoder: int16 24k produce")
    expect((data?.count ?? 0) > 0, "encoder: int16 24k no vacío")
    expectEq((data?.count ?? 1) % 2, 0, "encoder: int16 24k par")
    // Same format again: converter stays armed.
    let again = encoder.encode(buf)
    expect((again?.count ?? 0) > 0, "encoder: reusa converter")
    expectEq((again?.count ?? 1) % 2, 0, "encoder: reusa par")
}

@MainActor func testEncoderSilenceAndEmpty() {
    var encoder = RealtimeEncoder()
    let silent = makePCMBuffer(
        common: .pcmFormatInt16, sampleRate: 24_000, channels: 1,
        interleaved: true, frames: 120, asSine: false)
    let quiet = encoder.encode(silent)
    expect((quiet?.count ?? 0) > 0, "encoder: silencio no es nil")
    expectEq((quiet?.count ?? 1) % 2, 0, "encoder: silencio par")

    let empty = makePCMBuffer(
        common: .pcmFormatFloat32, sampleRate: 48_000, channels: 1,
        interleaved: false, frames: 0, asSine: false)
    expect(encoder.encode(empty) == nil, "encoder: 0 frames → nil")

    let vacant = makeVacantBuffer(
        common: .pcmFormatFloat32, sampleRate: 16_000, channels: 1,
        interleaved: false, capacity: 64)
    expect(encoder.encode(vacant) == nil, "encoder: capacity sin frames → nil")
}

@MainActor func testEncoderFormatChangeAndRates() {
    var encoder = RealtimeEncoder()
    let float48 = makePCMBuffer(
        common: .pcmFormatFloat32, sampleRate: 48_000, channels: 1,
        interleaved: false, frames: 960, asSine: true)
    let first = encoder.encode(float48)
    expect((first?.count ?? 0) > 0, "encoder: 48k antes del cambio")

    let int16_16k = makePCMBuffer(
        common: .pcmFormatInt16, sampleRate: 16_000, channels: 1,
        interleaved: true, frames: 320, asSine: true)
    let second = encoder.encode(int16_16k)
    expect((second?.count ?? 0) > 0, "encoder: rearma a 16k int16")
    expectEq((second?.count ?? 1) % 2, 0, "encoder: 16k par")

    let float24 = makePCMBuffer(
        common: .pcmFormatFloat32, sampleRate: 24_000, channels: 1,
        interleaved: false, frames: 240, asSine: true)
    let third = encoder.encode(float24)
    expect((third?.count ?? 0) > 0, "encoder: 24k float")
    expectEq((third?.count ?? 1) % 2, 0, "encoder: 24k float par")

    let interleaved = makePCMBuffer(
        common: .pcmFormatFloat32, sampleRate: 44_100, channels: 1,
        interleaved: true, frames: 441, asSine: true)
    let fourth = encoder.encode(interleaved)
    expect((fourth?.count ?? 0) > 0, "encoder: 44.1k interleaved")
    expectEq((fourth?.count ?? 1) % 2, 0, "encoder: 44.1k par")
}

@MainActor func testEncoderStereoLargeAndTiny() {
    var encoder = RealtimeEncoder()
    let stereo = makePCMBuffer(
        common: .pcmFormatFloat32, sampleRate: 48_000, channels: 2,
        interleaved: false, frames: 480, asSine: true)
    let mixed = encoder.encode(stereo)
    expect((mixed?.count ?? 0) > 0, "encoder: stereo → mono")
    expectEq((mixed?.count ?? 1) % 2, 0, "encoder: stereo par")

    let large = makePCMBuffer(
        common: .pcmFormatFloat32, sampleRate: 48_000, channels: 1,
        interleaved: false, frames: 10_000, asSine: true)
    let big = encoder.encode(large)
    expect((big?.count ?? 0) > 100, "encoder: 10k frames produce")
    expectEq((big?.count ?? 1) % 2, 0, "encoder: 10k par")

    let tiny = makePCMBuffer(
        common: .pcmFormatFloat32, sampleRate: 48_000, channels: 1,
        interleaved: false, frames: 1, asSine: true)
    let one = encoder.encode(tiny)
    if let one {
        expectEq(one.count % 2, 0, "encoder: 1 frame par si produce")
    } else {
        expect(true, "encoder: 1 frame puede ser nil (slack/converter)")
    }

    let high = makePCMBuffer(
        common: .pcmFormatInt16, sampleRate: 24_000, channels: 1,
        interleaved: true, frames: 8, asSine: false)
    fillInt16(high, repeating: Int16.max)
    let peak = encoder.encode(high)
    expect((peak?.count ?? 0) > 0, "encoder: Int16.max produce")
    expectEq((peak?.count ?? 1) % 2, 0, "encoder: Int16.max par")

    let minBuf = makePCMBuffer(
        common: .pcmFormatInt16, sampleRate: 24_000, channels: 1,
        interleaved: true, frames: 8, asSine: false)
    fillInt16(minBuf, repeating: Int16.min)
    let trough = encoder.encode(minBuf)
    expect((trough?.count ?? 0) > 0, "encoder: Int16.min produce")
}

@MainActor func testMicAccessInjected() {
    pcmOk("mic deny") {
        let denied = MicCapture(access: { false })
        expect(!(await denied.requestAccess()), "mic: injected false")
        expect(!(await denied.requestAccess()), "mic: deny estable")
    }
    pcmOk("mic grant") {
        let granted = MicCapture(access: { true })
        expect(await granted.requestAccess(), "mic: injected true")
    }
    pcmOk("mic flip") {
        let flag = AccessFlag(false)
        let flipping = MicCapture(access: { await flag.take() })
        expect(!(await flipping.requestAccess()), "mic: primer false")
        expect(await flipping.requestAccess(), "mic: segundo true")
    }
}

@MainActor func testMicConstructsWithoutEngine() {
    pcmOk("mic construct") {
        let mic = MicCapture(access: { true })
        let port: any MicCapturing = mic
        expect(!(await port.receivedBuffer), "mic: sin tap")
        expect(!(await port.hasEchoCancellation), "mic: AEC off hasta start")
        await port.disableVoiceProcessing()
        expect(!(await port.hasEchoCancellation), "mic: veto sin start")
        expect(!(await port.receivedBuffer), "mic: disable no finge tap")
        _ = port.frames
    }
    pcmOk("mic opt-in idle") {
        let opted = MicCapture(echoCancellation: true, access: { true })
        expect(!opted.hasEchoCancellation, "mic: opt-in no enciende solo")
        expect(!opted.receivedBuffer, "mic: opt-in sin tap")
        await opted.stop()
    }
}

@MainActor func testPlayerUnstartedPlayNoops() {
    pcmOk("player unstarted") {
        let player = RealtimePlayer()
        let port: any PCMPlaying = player
        expect(!(await port.hasPending), "player: idle sin pending")
        await port.play(Data())
        await port.play(Data([0x00]))
        await port.play(Data([0x00, 0xFF, 0x7F, 0x80]))
        await port.play(Data("ñoño — café".utf8))
        await port.play(Data(repeating: 0xAB, count: 10_000))
        expect(!(await port.hasPending), "player: play sin start no encola")
        await port.flush()
        expect(!(await port.hasPending), "player: flush sin start")
        await port.stop()
        expect(!(await port.hasPending), "player: stop sin start")
        _ = port.drained
        _ = port.levels
    }
}

@MainActor func testPlayerSharedStartWithoutEngine() {
    let player = RealtimePlayer()
    do {
        try runAsync {
            try await player.start(sharedEngine: true)
        }
        expect(false, "player shared missing: debía tirar unreachable")
    } catch let error as VoiceTransportError {
        expectEq(error, .unreachable, "player shared missing")
    } catch {
        expect(false, "player shared missing: VoiceTransportError, no \(error)")
    }
    pcmOk("player after failed shared") {
        await player.play(Data([0x01, 0x00, 0x02, 0x00]))
        expect(!(await player.hasPending), "player: failed start no pending")
        await player.flush()
        await player.stop()
    }
}

@MainActor func pcmOk(_ label: String, _ body: @escaping @Sendable () async throws -> Void) {
    do { try runAsync(body) }
    catch { expect(false, "\(label): no debía tirar \(error)") }
}

private func makePCMBuffer(
    common: AVAudioCommonFormat,
    sampleRate: Double,
    channels: AVAudioChannelCount,
    interleaved: Bool,
    frames: AVAudioFrameCount,
    asSine: Bool
) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: common, sampleRate: sampleRate,
        channels: channels, interleaved: interleaved)!
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frames, 1))!
    buf.frameLength = frames
    let n = Int(frames)
    guard n > 0 else { return buf }
    if common == .pcmFormatFloat32, let planes = buf.floatChannelData {
        for c in 0..<Int(channels) {
            for i in 0..<n {
                if asSine {
                    let s = sin(2 * Double.pi * 440 * Double(i) / sampleRate)
                    planes[c][i] = Float(s) * 0.5
                } else {
                    planes[c][i] = 0
                }
            }
        }
    } else if common == .pcmFormatInt16, let planes = buf.int16ChannelData {
        for c in 0..<Int(channels) {
            for i in 0..<n {
                if asSine {
                    let s = sin(2 * Double.pi * 440 * Double(i) / sampleRate) * 0.5
                    planes[c][i] = Int16(s * 32767)
                } else {
                    planes[c][i] = 0
                }
            }
        }
    }
    return buf
}

private func makeVacantBuffer(
    common: AVAudioCommonFormat,
    sampleRate: Double,
    channels: AVAudioChannelCount,
    interleaved: Bool,
    capacity: AVAudioFrameCount
) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: common, sampleRate: sampleRate,
        channels: channels, interleaved: interleaved)!
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
    buf.frameLength = 0
    return buf
}

private func fillInt16(_ buffer: AVAudioPCMBuffer, repeating value: Int16) {
    let n = Int(buffer.frameLength)
    guard let planes = buffer.int16ChannelData else { return }
    for c in 0..<Int(buffer.format.channelCount) {
        for i in 0..<n { planes[c][i] = value }
    }
}

private final class AccessFlag: @unchecked Sendable {
    private var values: [Bool]
    init(_ first: Bool) { values = [first, true] }
    func take() async -> Bool {
        if values.isEmpty { return true }
        return values.removeFirst()
    }
}
