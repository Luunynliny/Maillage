import AVFoundation

/// Reads a time range back out of a recorded track — the one place a voiceprint's candidate
/// audio comes from, since it must be captured while `mic.wav`/`system.wav` still exist, which
/// is only true for the brief window between Stop and the recordings directory being deleted.
///
/// Unlike ``MicrophoneRecorder``/``SystemAudioTap``'s own buffer conversion, this reads through
/// `AVAudioFile`'s `processingFormat`, which is Float32 by default regardless of the file's own
/// on-disk format (16-bit integer PCM) — so, unlike those two, this can trust
/// `floatChannelData` directly.
enum WAVSampleReader {
    static func samples(in url: URL, startTime: Float, endTime: Float) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(Double(max(0, startTime)) * sampleRate)
        let endFrame = min(file.length, AVAudioFramePosition(Double(endTime) * sampleRate))
        let frameCount = AVAudioFrameCount(max(0, endFrame - startFrame))
        guard frameCount > 0 else { return nil }
        file.framePosition = startFrame
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: frameCount)
        else { return nil }
        guard (try? file.read(into: buffer, frameCount: frameCount)) != nil else { return nil }
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
