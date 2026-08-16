import FluidAudio
import Foundation

/// Feeds live 16 kHz mono audio to a streaming ASR session and produces both a live-updating
/// full-text view (for display while recording) and, once the session ends, real timestamped
/// segments — only available at that point, built from token timings, not incrementally. See
/// the meeting-recording-v2 design doc for why "live" is a growing block of text, not a
/// scrolling list of timestamped rows, until the meeting actually stops: the streaming manager
/// only ever hands back a plain running transcript while it's listening, and per-word timing
/// only once, at the end.
///
/// A protocol, not just `FluidAudioStreamingTranscriber` directly, mirroring the old batch
/// `Transcriber` — so `MeetingRecorder`'s orchestration can be exercised without a loaded model.
public protocol StreamingTranscriber: Sendable {
    /// Registers the callback fired every time the live transcript grows. Call once, before any
    /// audio — the manager's own decode cadence decides when it fires, not the caller.
    func onUpdate(_ callback: @escaping @Sendable (String) -> Void) async
    func ingest(samples: [Float]) async throws
    /// Flushes trailing audio and returns final utterance-level segments, offsets relative to
    /// the start of this transcriber's own stream — the caller applies any track-level offset.
    /// `track`/`diarizerSegments` assign each segment a speaker slot when diarization ran
    /// alongside this transcriber — see ``TokenTimingGrouper``.
    func finish(track: AudioTrack?, diarizerSegments: [DiarizerSegment]) async throws
        -> [TranscriptSegment]
    /// The first language tag the decoder emitted this session, or `nil` if none yet — only
    /// meaningful after `finish()` has returned.
    func detectedLanguage() async -> String?
}

/// The FluidAudio-backed implementation, wrapping one `StreamingNemotronMultilingualAsrManager`
/// session. One instance per track, per recording — the manager holds streaming state for
/// exactly one continuous session, never shared between mic and system audio, since those are
/// unrelated speaker populations and must never decode as if they were one stream.
public struct FluidAudioStreamingTranscriber: StreamingTranscriber {
    private let manager: StreamingNemotronMultilingualAsrManager

    public init(manager: StreamingNemotronMultilingualAsrManager) {
        self.manager = manager
    }

    public func onUpdate(_ callback: @escaping @Sendable (String) -> Void) async {
        await manager.setPartialCallback(callback)
    }

    public func ingest(samples: [Float]) async throws {
        _ = try await manager.process(samples: samples)
    }

    public func finish(track: AudioTrack? = nil, diarizerSegments: [DiarizerSegment] = [])
        async throws -> [TranscriptSegment]
    {
        let (_, timings) = try await manager.finishWithTokenTimings()
        return TokenTimingGrouper.segments(
            from: timings, track: track, diarizerSegments: diarizerSegments)
    }

    public func detectedLanguage() async -> String? {
        await manager.detectedLanguage()
    }
}
