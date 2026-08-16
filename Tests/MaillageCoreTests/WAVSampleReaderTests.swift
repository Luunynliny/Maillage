import AVFoundation
import Foundation
import Testing

@testable import MaillageCore

/// Writes a short 16 kHz mono WAV — the same format `MicrophoneRecorder`/`SystemAudioTap` write
/// — with one second of silence, then one second of a ramp from -1 to 1, so a read range can be
/// checked against known content instead of just "some samples came back."
private func writeTestWAV(to url: URL) throws {
    let file = try AVAudioFile(
        forWriting: url, settings: PCMFormat.target.settings,
        commonFormat: PCMFormat.target.commonFormat, interleaved: PCMFormat.target.isInterleaved)
    let sampleRate = Int(PCMFormat.target.sampleRate)

    func write(_ samples: [Float]) throws {
        guard
            let floatBuffer = AVAudioPCMBuffer(
                pcmFormat: AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: PCMFormat.target.sampleRate,
                    channels: 1, interleaved: false)!,
                frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        floatBuffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            floatBuffer.floatChannelData![0][index] = sample
        }
        guard let converter = PCMConverter(from: floatBuffer.format) else { return }
        if let converted = converter.convert(floatBuffer) {
            try file.write(from: converted)
        }
    }

    try write([Float](repeating: 0, count: sampleRate))
    try write((0..<sampleRate).map { -1 + 2 * Float($0) / Float(sampleRate) })
}

@Suite("WAV sample reader")
struct WAVSampleReaderTests {
    @Test("Reads a range from partway through the file")
    func readsARange() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wav-sample-reader-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTestWAV(to: url)

        // The silent second: near-zero throughout.
        let silence = try #require(WAVSampleReader.samples(in: url, startTime: 0, endTime: 0.5))
        #expect(silence.allSatisfy { abs($0) < 0.01 })

        // The ramp's very start, just after the silent second: near -1.
        let rampStart = try #require(WAVSampleReader.samples(in: url, startTime: 1, endTime: 1.1))
        #expect(rampStart.first.map { abs($0 - (-1)) < 0.05 } == true)
    }

    @Test("An out-of-range window returns nil")
    func outOfRangeReturnsNil() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wav-sample-reader-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTestWAV(to: url)

        #expect(WAVSampleReader.samples(in: url, startTime: 10, endTime: 11) == nil)
    }

    @Test("A missing file returns nil rather than crashing")
    func missingFileReturnsNil() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).wav")
        #expect(WAVSampleReader.samples(in: url, startTime: 0, endTime: 1) == nil)
    }
}
