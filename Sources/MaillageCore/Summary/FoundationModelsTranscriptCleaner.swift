import Foundation
import FoundationModels

/// Drops hallucinated or nonsensical fragments from an ASR transcript and tidies formatting,
/// without summarizing or inventing content — the cleaned segments become the transcript that
/// gets persisted. See ``MeetingRecorder/finishTranscription(meetingID:directory:)``, which runs
/// this between merging both tracks' segments and writing them.
public protocol TranscriptCleaner: Sendable {
    /// `language` is the meeting's already-detected ISO code (e.g. `"fr"`), the same value
    /// ``MeetingSummarizer/summarize(_:language:)`` uses — no new detection here.
    func clean(
        _ segments: [TranscriptSegment], language: String
    ) async throws -> [TranscriptSegment]
}

/// One cleaned excerpt, mirroring ``MeetingSummary``'s `@Generable` shape so the model returns
/// structured `(offsetSeconds, text)` pairs rather than a prose blob — ``TranscriptCodec`` and
/// the paragraph grouper both expect that shape unchanged.
@Generable(description: "A cleaned excerpt of a meeting transcript.")
struct CleanedTranscriptChunk: Sendable {
    @Guide(
        description:
            "The excerpt's segments, in order, with hallucinated or nonsensical fragments removed entirely — not replaced, dropped"
    )
    var segments: [CleanedSegment]
}

/// One cleaned transcript segment.
@Generable(description: "One cleaned transcript segment.")
struct CleanedSegment: Sendable {
    @Guide(description: "Seconds from the start of the recording, unchanged from the original")
    var offsetSeconds: Int
    @Guide(description: "The utterance's cleaned text")
    var text: String
}

/// Cleans a transcript using Apple's on-device `FoundationModels`, map-only over fixed-size
/// chunks — unlike ``FoundationModelsSummarizer``'s map-reduce, cleaned chunks just concatenate
/// back together in order, since deciding whether one chunk's fragment is a hallucination needs
/// no knowledge of the other chunks.
public final class FoundationModelsTranscriptCleaner: TranscriptCleaner, Sendable {
    // No stored state — a session is created fresh per call, see `cleanChunk` — so this is
    // safely `Sendable` outright.

    /// Smaller than the summarizer's 50: summarization's output is far shorter than its input,
    /// so 50 segments fits the ~4,096-token session budget comfortably, but cleanup's output is
    /// roughly as long as its input, which roughly doubles the effective token cost per call for
    /// the same segment count — a smaller window keeps the same safety margin.
    private static let defaultWindowSize = 25
    /// Mirrors ``FoundationModelsSummarizer``'s own floor — same reasoning, a persistent overflow
    /// is given up on rather than chased forever.
    private static let minWindowSize = 5

    public init() {}

    public func clean(
        _ segments: [TranscriptSegment], language: String
    ) async throws -> [TranscriptSegment] {
        try await map(segments, language: language, windowSize: Self.defaultWindowSize)
    }

    private func map(
        _ segments: [TranscriptSegment], language: String, windowSize: Int
    ) async throws -> [TranscriptSegment] {
        let chunks = TranscriptChunker.chunk(segments, windowSize: windowSize)
        guard !chunks.isEmpty else { return [] }
        do {
            return try await Self.mapChunks(
                chunks,
                shouldRetry: Self.isExceededContextWindow,
                cleanChunk: { chunk in try await self.cleanChunk(chunk, language: language) }
            )
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize(_)
            where windowSize > Self.minWindowSize
        {
            return try await map(segments, language: language, windowSize: windowSize / 2)
        }
    }

    /// Runs `cleanChunk` over every chunk in order and concatenates the results — pure aside from
    /// the `cleanChunk` closure itself, so the per-chunk isolation policy is unit-tested without a
    /// real model call. A chunk whose `cleanChunk` throws an error `shouldRetry` rejects falls
    /// back to its own original segments, so one bad chunk never costs the rest of the transcript.
    /// A chunk whose error `shouldRetry` accepts is rethrown immediately instead — that signals
    /// the whole pass needs a smaller window, not just this one chunk, so partial results here are
    /// discarded in favor of `map`'s full retry.
    static func mapChunks(
        _ chunks: [[TranscriptSegment]],
        shouldRetry: (Error) -> Bool,
        cleanChunk: ([TranscriptSegment]) async throws -> [TranscriptSegment]
    ) async throws -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for chunk in chunks {
            do {
                result += try await cleanChunk(chunk)
            } catch {
                if shouldRetry(error) { throw error }
                result += chunk
            }
        }
        return result
    }

    private static func isExceededContextWindow(_ error: Error) -> Bool {
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error {
            return true
        }
        return false
    }

    private func cleanChunk(
        _ segments: [TranscriptSegment], language: String
    ) async throws -> [TranscriptSegment] {
        // Fresh session per call, per the same reasoning as the summarizer's own per-chunk
        // sessions: reusing one across chunks would accumulate context and burn the same token
        // budget faster, working against the reason chunking exists.
        let session = LanguageModelSession(
            instructions:
                """
                You clean up one excerpt of an automatically transcribed meeting. Remove \
                sentences or words that are hallucinated, nonsensical, or clearly don't belong \
                (stock phrases like "thank you" that don't fit the conversation, garbled \
                fragments) by dropping them entirely — never replace them with placeholder text. \
                Fix obvious formatting and punctuation. Do not summarize, shorten, or add \
                anything — keep the speaker's actual words as close to the original as possible \
                aside from removing garbage. Respond in \(language).
                """
        )
        let transcriptText = segments.map { FoundationModelsSummarizer.line(for: $0) }
            .joined(separator: "\n")
        let response = try await session.respond(
            to: "Clean up this meeting transcript excerpt:\n\n\(transcriptText)",
            generating: CleanedTranscriptChunk.self)
        return response.content.segments.map {
            TranscriptSegment(offsetSeconds: $0.offsetSeconds, text: $0.text)
        }
    }
}
