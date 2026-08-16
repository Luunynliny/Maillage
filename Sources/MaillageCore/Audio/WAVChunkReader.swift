import AVFoundation

/// Reads a whole recorded track's WAV file in bounded chunks — the constant-memory piece that
/// makes feeding a long meeting into `StreamingNemotronMultilingualAsrManager.process(samples:)`
/// safe: nothing here ever holds more than one chunk of the file in memory at once, the same
/// reasoning that favored `AsrManager.transcribeDiskBacked` for Parakeet.
///
/// Simpler than the old (pre-PR#21) `WAVSampleReader`, which supported reading an arbitrary time
/// range for a voiceprint candidate — that case is gone with diarization, so this only needs
/// "read the whole file, one chunk at a time."
enum WAVChunkReader {
    /// 5 seconds at 16kHz: small enough that a long meeting never approaches loading the whole
    /// file into memory, large enough that a single call isn't dominated by per-call overhead.
    static let defaultChunkFrames: AVAudioFrameCount = 16_000 * 5

    /// Calls `body` with each chunk of samples (mono, the file's own processing format — Float32
    /// regardless of on-disk format, same as the old `WAVSampleReader`) at up to `chunkFrames`
    /// frames at a time, in order, until the file is exhausted. The final chunk may be shorter
    /// than `chunkFrames`; it is never padded or dropped.
    static func forEachChunk(
        in url: URL, chunkFrames: AVAudioFrameCount = defaultChunkFrames,
        _ body: ([Float]) async throws -> Void
    ) async throws {
        let file = try AVAudioFile(forReading: url)
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: chunkFrames)
        else {
            throw WAVChunkReaderError.invalidFormat
        }
        // Bounded by `file.length`, not "read until frameLength comes back 0": `AVAudioFile.read`
        // throws once `framePosition` already sits at `length` rather than returning an empty
        // read, so asking for one chunk too many would throw instead of ending the loop cleanly.
        while file.framePosition < file.length {
            let remainingFrames = file.length - file.framePosition
            let framesToRead = AVAudioFrameCount(
                min(AVAudioFramePosition(chunkFrames), remainingFrames))
            try file.read(into: buffer, frameCount: framesToRead)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            try await body(
                Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
        }
    }
}

enum WAVChunkReaderError: Error, LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        "Could not allocate a read buffer for this WAV file's format."
    }
}
