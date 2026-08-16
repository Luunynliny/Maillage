import FluidAudio
import Foundation

/// Batch-transcribes one track's already-recorded WAV file, once, after Stop — FluidAudio's
/// Parakeet TDT v3 batch path, replacing the live streaming ASR this app used to run concurrently
/// with recording. A meeting's transcript is read after the fact, never live, so multilingual
/// accuracy on mixed French/English speech wins over the streaming model's lower latency.
///
/// A protocol, not just `FluidAudioTranscriber` directly, so `MeetingRecorder`'s orchestration can
/// be exercised without a loaded model.
public protocol Transcriber: Sendable {
    /// Transcribes `fileURL` end to end and returns FluidAudio's own result, including token-
    /// level timings — grouped into utterance-level segments by ``TokenTimingGrouper``, not here.
    func transcribe(fileURL: URL) async throws -> ASRResult
}

/// The FluidAudio-backed implementation, wrapping one `AsrManager` loaded from the bundled
/// Parakeet TDT v3 models. One instance per track (mic, system), same as the streaming pipeline
/// this replaces — mic and system audio are unrelated speaker populations and must never share a
/// decoder session.
public struct FluidAudioTranscriber: Transcriber {
    private let manager: AsrManager

    public init(manager: AsrManager) {
        self.manager = manager
    }

    public func transcribe(fileURL: URL) async throws -> ASRResult {
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        // `transcribeDiskBacked` streams the file off disk at constant memory, unlike
        // `transcribe(_:decoderState:language:)`, which loads the whole file into memory first —
        // the difference that matters for a meeting recording that can run long.
        //
        // `language: nil` — Parakeet's language hint is only a same-script token filter, not a
        // hard lock, so leaving it unset avoids biasing against either language in a mixed
        // French/English recording.
        return try await manager.transcribeDiskBacked(
            fileURL, decoderState: &decoderState, language: nil)
    }
}
