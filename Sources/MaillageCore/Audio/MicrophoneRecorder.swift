import AVFoundation

public enum MicrophoneRecorderError: Error, LocalizedError {
    case converterUnavailable
    case engineFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .converterUnavailable:
            "Couldn't convert the microphone's audio format."
        case .engineFailed(let error):
            "Couldn't start the microphone: \(error.localizedDescription)"
        }
    }
}

/// Records the microphone to a 16 kHz mono WAV file via `AVAudioEngine`.
///
/// The ordinary half of capture — unlike ``SystemAudioTap``, `AVAudioEngine` is the standard,
/// well-trodden API for this, with no Core Audio C calls of its own.
///
/// Not `@MainActor`: `installTap`'s callback runs on a real-time audio thread, and hopping
/// that onto the main actor on every buffer would be both wrong for a real-time callback and
/// pointless, since nothing here needs to run on the main actor. ``level`` is published
/// through a ``LockedValue`` instead; ``AudioCaptureSession`` polls it on a timer.
final class MicrophoneRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: PCMConverter?
    private var onBuffer: (@Sendable ([Float]) -> Void)?

    /// Root-mean-square of the most recent buffer, 0 (silence) to roughly 1. Read by
    /// ``AudioCaptureSession`` for the level meter; not filtered or smoothed here, since how
    /// a level meter *moves* is a UI concern, not a capture one.
    let level = LockedValue<Float>(0)

    /// `onBuffer`, if given, is handed the same converted 16 kHz mono samples as they're
    /// written to `url` — a live tap for a streaming transcriber, not a substitute for the
    /// file. Called on the same real-time thread as the write, so it must be as cheap as
    /// everything else in ``process(_:)`` and must not itself touch actor-isolated state; a
    /// `Sendable` closure over something thread-safe (an `AsyncStream.Continuation`, say) is
    /// the intended shape, not a capture of `self`.
    func start(to url: URL, onBuffer: (@Sendable ([Float]) -> Void)? = nil) throws {
        self.onBuffer = onBuffer
        let input = engine.inputNode
        // The input's own format, whatever the hardware actually is — never assumed, since
        // built-in mics, USB interfaces and Bluetooth headsets all report different ones.
        let format = input.outputFormat(forBus: 0)
        guard let converter = PCMConverter(from: format) else {
            throw MicrophoneRecorderError.converterUnavailable
        }
        self.converter = converter
        self.file = try AVAudioFile(
            forWriting: url, settings: PCMFormat.target.settings,
            commonFormat: PCMFormat.target.commonFormat,
            interleaved: PCMFormat.target.isInterleaved)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MicrophoneRecorderError.engineFailed(error)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        converter = nil
        onBuffer = nil
        level.set(0)
    }

    /// Called on the real-time audio thread `AVAudioEngine` owns. Must not block, allocate
    /// unpredictably, or touch anything actor-isolated.
    private func process(_ buffer: AVAudioPCMBuffer) {
        level.set(Self.rootMeanSquare(of: buffer))
        guard let converted = converter?.convert(buffer) else { return }
        try? file?.write(from: converted)
        if let onBuffer {
            onBuffer(Self.samples(from: converted))
        }
    }

    /// Copies the mono channel out to a plain `[Float]`, normalized to -1.0...1.0 — the shape
    /// an `AsyncStream` (or anything else off the real-time thread) needs, since the buffer
    /// itself is only valid for the duration of this callback. `PCMFormat.target` is 16-bit
    /// integer PCM (what a WAV file is written in), so this reads `int16ChannelData`, never
    /// `floatChannelData` — that's `nil` for an Int16 buffer and would silently hand every
    /// caller an empty array.
    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.int16ChannelData?[0] else { return [] }
        let frameCount = Int(buffer.frameLength)
        return (0..<frameCount).map { Float(channel[$0]) / 32768.0 }
    }

    private static func rootMeanSquare(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for frame in 0..<frameCount {
            let sample = channel[frame]
            sum += sample * sample
        }
        return sqrt(sum / Float(frameCount))
    }
}
