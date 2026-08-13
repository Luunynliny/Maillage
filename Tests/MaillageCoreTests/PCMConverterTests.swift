import AVFoundation
import Testing

@testable import MaillageCore

/// The one piece of the audio pipeline that's pure enough to test without a microphone or a
/// system-audio tap: converting some hardware format down to the 16 kHz mono Int16 target.
/// Everything else in `Audio/` touches real Core Audio devices, which `swift test` cannot do
/// headlessly — see the design doc's verification section — so it's checked by running the
/// app instead.
@Suite("PCM converter")
struct PCMConverterTests {
    /// A buffer of silence in `format`, long enough that a real conversion ratio shows up.
    private func silence(format: AVAudioFormat, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        return buffer
    }

    @Test("Downsamples 48 kHz stereo to 16 kHz mono")
    func downsamplesToTarget() throws {
        let sourceFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false
            ))
        let converter = try #require(PCMConverter(from: sourceFormat))

        let input = silence(format: sourceFormat, frameCount: 4_800)  // 0.1s at 48kHz
        let output = try #require(converter.convert(input))

        #expect(output.format.sampleRate == 16_000)
        #expect(output.format.channelCount == 1)
        #expect(output.format.commonFormat == AVAudioCommonFormat.pcmFormatInt16)
        // Not pinned to the ~1600 frames 0.1s at 16kHz implies: a resampling filter has its
        // own warm-up latency, so one call's output legitimately falls short of that and
        // catches up over several. What has to hold is just that real downsampling happened.
        #expect(output.frameLength > 0)
        #expect(output.frameLength < input.frameLength)
    }

    @Test("Passes mono 16 kHz through near enough unchanged")
    func passesThroughAtTargetRate() throws {
        let sourceFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
            ))
        let converter = try #require(PCMConverter(from: sourceFormat))

        let input = silence(format: sourceFormat, frameCount: 1_600)
        let output = try #require(converter.convert(input))

        #expect(output.format.sampleRate == 16_000)
        #expect(Int(output.frameLength) == 1_600)
    }

    @Test("A second buffer converts independently of the first")
    func convertsMultipleBuffersIndependently() throws {
        let sourceFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false
            ))
        let converter = try #require(PCMConverter(from: sourceFormat))

        let first = try #require(
            converter.convert(silence(format: sourceFormat, frameCount: 4_410)))
        let second = try #require(
            converter.convert(silence(format: sourceFormat, frameCount: 4_410)))

        // Both calls need their own "no more data after this one" flag — this is the one
        // converter instance every buffer from a whole recording passes through, so a flag
        // that leaked across calls would starve every buffer after the first.
        #expect(first.frameLength > 0)
        #expect(second.frameLength > 0)
    }
}
