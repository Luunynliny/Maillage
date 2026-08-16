import AVFoundation

/// Converts arbitrary-format PCM into the one format every recording file is written in.
///
/// 16 kHz mono is what the streaming ASR consumes directly, so nothing resamples between capture
/// and transcription. It is also roughly a tenth the size of 48 kHz stereo Float32, for audio
/// this app promises to delete once transcribed.
enum PCMFormat {
    /// Force-unwrapped: these parameters (16-bit signed PCM, 16 kHz, mono, interleaved — moot
    /// at one channel, but explicit) are always valid for `AVAudioFormat`, so a `nil` here
    /// would mean the initializer itself changed shape, not that this call site did anything
    /// wrong to recover from.
    static let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
}

/// Wraps an `AVAudioConverter` for the one conversion this app ever does: some hardware
/// format down to ``PCMFormat/target``. Both ``MicrophoneRecorder`` and ``SystemAudioTap``
/// receive audio in whatever format their source hands them and share this to get to the
/// format their `AVAudioFile` is opened in.
final class PCMConverter {
    private let converter: AVAudioConverter

    /// `nil` when `AVAudioConverter` itself refuses the pair of formats — seen in practice
    /// when a source reports a channel count or sample rate it doesn't actually produce.
    init?(from sourceFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: sourceFormat, to: PCMFormat.target) else {
            return nil
        }
        self.converter = converter
    }

    /// Converts one buffer. `nil` on the rare conversion failure, which the caller treats as
    /// "drop this buffer" rather than "stop recording" — a single lost buffer is a few
    /// milliseconds of audio, not a reason to abandon the whole capture.
    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = PCMFormat.target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: PCMFormat.target, frameCapacity: capacity)
        else { return nil }

        // The input block hands `buffer` over exactly once, then reports no more data — this
        // converter sees one buffer per call, never a stream, so there's nothing to loop over.
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            guard !consumed else {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return nil }
        return output
    }
}
