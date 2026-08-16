import FluidAudio
import Foundation

/// Batch-transcribes one track's already-recorded WAV file, once, after Stop — FluidAudio's
/// Nemotron Speech Streaming Multilingual model, driven all at once instead of incrementally.
/// A meeting's transcript is read after the fact, never live, so multilingual accuracy (this
/// model genuinely detects the spoken language per utterance, unlike Parakeet TDT v3's stateless
/// per-chunk decoding, which sometimes drifted whole chunks of clean French audio into English)
/// wins over any latency this model's streaming shape was originally built for.
///
/// A protocol, not just `FluidAudioTranscriber` directly, so `MeetingRecorder`'s orchestration can
/// be exercised without a loaded model.
public protocol Transcriber: Sendable {
    /// Transcribes `fileURL` end to end and returns its token-level timings — grouped into
    /// utterance-level segments by ``TokenTimingGrouper``, not here.
    func transcribe(fileURL: URL) async throws -> [TokenTiming]
}

/// The FluidAudio-backed implementation, wrapping one `StreamingNemotronMultilingualAsrManager`
/// loaded from the bundled Nemotron models. One instance per track (mic, system), same as before
/// — mic and system audio are unrelated speaker populations and must never share a decoder
/// session.
public struct FluidAudioTranscriber: Transcriber {
    private let manager: StreamingNemotronMultilingualAsrManager

    public init(manager: StreamingNemotronMultilingualAsrManager) {
        self.manager = manager
    }

    public func transcribe(fileURL: URL) async throws -> [TokenTiming] {
        // `WAVChunkReader` reads the file in bounded chunks rather than loading it whole —
        // constant memory for a long meeting, the same reasoning `transcribeDiskBacked` served
        // for Parakeet. `process(samples:)` is sample-count-driven with no wall-clock
        // dependency, so feeding it chunk after chunk with no real-time pacing is safe; no
        // `onUpdate`/partial-text callback is wired since this app never shows a live partial —
        // only the final `finishWithTokenTimings()` result matters here.
        try await WAVChunkReader.forEachChunk(in: fileURL) { chunk in
            _ = try await manager.process(samples: chunk)
        }
        let (_, timings) = try await manager.finishWithTokenTimings()
        return timings
    }
}
