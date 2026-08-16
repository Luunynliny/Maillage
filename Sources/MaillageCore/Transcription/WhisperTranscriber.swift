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

    public func transcribe(fileAt url: URL) async throws -> [TranscriptSegment] {
        let options = DecodingOptions(language: nil, detectLanguage: true, wordTimestamps: false)
        let results = try await whisperKit.transcribe(audioPath: url.path, decodeOptions: options)
        return results.flatMap { result in
            result.segments.map {
                TranscriptSegment(
                    offsetSeconds: Int($0.start.rounded()),
                    text: $0.text.trimmingCharacters(in: .whitespaces))
            }
        }
    }
}
