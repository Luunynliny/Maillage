import Foundation
import WhisperKit

/// Implements ``Transcriber`` over WhisperKit: the forced language and prompt tokens are applied
/// to every chunk via `chunkingStrategy: .vad`, not just the first — confirmed empirically
/// against a recording longer than one chunk, per the design doc's own open question.
// WhisperKit itself isn't Sendable, but every call into it here is a single `await`, never
// concurrent from multiple tasks against the same instance — the same posture `MeetingRecorder`
// already takes as a `@MainActor` type.
public final class WhisperTranscriber: Transcriber, @unchecked Sendable {
    private let whisperKit: WhisperKit

    public init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    public func transcribe(fileAt url: URL, language: String, promptTokens: [Int]?) async throws
        -> [TranscriptSegment]
    {
        let options = DecodingOptions(
            language: language,
            detectLanguage: false,
            skipSpecialTokens: true,
            wordTimestamps: true,
            promptTokens: promptTokens,
            chunkingStrategy: .vad
        )
        let results = try await whisperKit.transcribe(audioPath: url.path, decodeOptions: options)
        return results.flatMap { result in
            result.segments.map {
                TranscriptSegment(
                    offsetSeconds: Int($0.start), text: $0.text.trimmingCharacters(in: .whitespaces)
                )
            }
        }
    }
}
