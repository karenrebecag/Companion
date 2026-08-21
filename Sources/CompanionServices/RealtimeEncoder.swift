@preconcurrency import AVFoundation
import Foundation

/// Device PCM → Realtime wire: int16 LE, 24 kHz, mono.
public struct RealtimeEncoder: @unchecked Sendable {
    private static let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true)!

    private var converter: AVAudioConverter?
    private var srcFormat: AVAudioFormat?

    public init() {}

    /// Re-arms when the mic format changes (Voice Processing on/off).
    public mutating func encode(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.format.sampleRate > 0, buffer.frameLength > 0 else { return nil }
        if converter == nil || srcFormat != buffer.format {
            srcFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: Self.target)
        }
        guard let converter else { return nil }
        let ratio = Self.target.sampleRate / buffer.format.sampleRate
        // Converter can emit extra frames while resampling.
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard cap > 0,
              let out = AVAudioPCMBuffer(pcmFormat: Self.target, frameCapacity: cap)
        else { return nil }
        let feed = ConvertOnce(buffer)
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if feed.fed {
                status.pointee = .noDataNow
                return nil
            }
            feed.fed = true
            status.pointee = .haveData
            return feed.buffer
        }
        guard err == nil, out.frameLength > 0, let ch = out.int16ChannelData else {
            return nil
        }
        return Data(bytes: ch[0], count: Int(out.frameLength) * 2)
    }
}

/// convert() marks the input block @Sendable; the call is synchronous.
private final class ConvertOnce: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var fed = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
