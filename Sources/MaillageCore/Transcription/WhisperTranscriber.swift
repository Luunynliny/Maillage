import Foundation
import WhisperKit

/// Implements ``Transcriber`` over WhisperKit, letting it auto-detect the spoken language itself
/// rather than forcing one for the whole meeting — the fix this backend swap exists for.
/// `detectLanguage: true` makes `TranscribeTask.decodeWithFallback` genuinely re-run language
/// detection every ~30-second seek window (confirmed against the current WhisperKit source, not
/// a workaround), so a French recording with an English term dropped in mid-sentence decodes as
/// itself instead of drifting a whole chunk into the wrong language, the failure mode that sank
/// the earlier Parakeet-based attempt. No prompt tokens either: those existed only to bias
/// decoding toward one already-detected language's vocabulary, which no longer applies once
/// nothing is forced up front.
///
/// WhisperKit's segments already arrive punctuated and grouped into sentences, so no separate
/// grouping step is needed here, unlike the raw-token output the FluidAudio-backed attempts had
/// to post-process.
///
/// WhisperKit itself isn't Sendable, but every call into it here is a single `await`, never
/// concurrent from multiple tasks against the same instance — the same posture `MeetingRecorder`
/// already takes as a `@MainActor` type.
public final class WhisperTranscriber: Transcriber, @unchecked Sendable {
    private let whisperKit: WhisperKit

    public init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    /// Whisper's well-known "Thank you." / "Thanks for watching" hallucination — stock phrases
    /// from its YouTube-heavy training data, produced on near-silent audio the model still tries
    /// to decode something for. `noSpeechProb` is the model's own estimate of whether a segment's
    /// audio contained speech at all, independent of how confident it was in whatever text it
    /// produced, so filtering on it (WhisperKit's own documented default threshold for treating a
    /// segment as silent) drops exactly this failure mode without touching genuine speech — a
    /// real spoken "thank you" scores low here, since there's real speech underneath it.
    private static let noSpeechThreshold: Float = 0.6

    public func transcribe(fileAt url: URL) async throws -> [TranscriptSegment] {
        // Without VAD chunking, a fixed 30s window can span both leading silence and real speech
        // together — `noSpeechProb` above is computed once per window, not per fragment inside
        // it, so a hallucination at a window's silent start shares the same (low, "there IS
        // speech in here somewhere") score as the genuine speech later in it and survives the
        // filter. VAD chunking (WhisperKit's own built-in energy detector, no extra model needed)
        // splits on actual voice-activity boundaries first, so each window is homogeneous.
        let options = DecodingOptions(
            language: nil, detectLanguage: true, skipSpecialTokens: true, wordTimestamps: false,
            chunkingStrategy: .vad)
        let results = try await whisperKit.transcribe(audioPath: url.path, decodeOptions: options)
        return results.flatMap { result in
            result.segments
                .filter { $0.noSpeechProb < Self.noSpeechThreshold }
                .map {
                    TranscriptSegment(
                        offsetSeconds: Int($0.start.rounded()),
                        text: $0.text.trimmingCharacters(in: .whitespaces))
                }
        }
    }
}
