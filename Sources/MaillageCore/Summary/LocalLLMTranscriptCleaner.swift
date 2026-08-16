import Foundation
import MLXLMCommon

/// Cleans a transcript using a local MLX model, map-only over fixed-size chunks — unlike
/// ``LocalLLMSummarizer``'s map-reduce, cleaned chunks just concatenate back together in order,
/// since deciding whether one chunk's fragment is a hallucination needs no knowledge of the other
/// chunks.
///
/// Output format is plain text, not JSON: the model is asked to return the same `(mm:ss) text`
/// lines it was given, then ``parseCleanedLines(_:)`` parses that back leniently — a local model
/// doesn't guarantee the exact shape the way `FoundationModels`' `@Generable` schema validation
/// once did, so a stray line of commentary is dropped rather than failing the whole chunk.
public final class LocalLLMTranscriptCleaner: TranscriptCleaner, Sendable {
    private let container: ModelContainer
    /// The vault's `.maillage/prompts/cleanup.md` (or its built-in default) — see
    /// ``PromptTemplateStore``. Loaded once by the caller and passed in, so this type stays a
    /// plain, vault-agnostic consumer of already-resolved instructions.
    private let instructions: String

    /// Smaller than the summarizer's 50: cleanup's output is roughly as long as its input, unlike
    /// summarization's much shorter output, which roughly doubles the effective token cost per
    /// call for the same segment count — a smaller window keeps the same safety margin.
    private static let defaultWindowSize = 25

    public init(container: ModelContainer, instructions: String) {
        self.container = container
        self.instructions = instructions
    }

    public func clean(
        _ segments: [TranscriptSegment], language: String
    ) async throws -> [TranscriptSegment] {
        let chunks = TranscriptChunker.chunk(segments, windowSize: Self.defaultWindowSize)
        guard !chunks.isEmpty else { return [] }
        return try await Self.mapChunks(
            chunks,
            cleanChunk: { chunk in try await self.cleanChunk(chunk, language: language) }
        )
    }

    /// Runs `cleanChunk` over every chunk in order and concatenates the results — pure aside from
    /// the `cleanChunk` closure itself, so the per-chunk isolation policy is unit-tested without a
    /// real model call. A chunk whose `cleanChunk` throws falls back to its own original segments,
    /// so one bad chunk never costs the rest of the transcript.
    ///
    /// No `shouldRetry`/window-halving here, unlike the `FoundationModels` version this replaces:
    /// that existed only to detect a fixed ~4,096-token session budget being exceeded, which
    /// doesn't apply to this backend (see ``LocalLLMSummarizer``'s doc comment for why) — every
    /// chunk failure is isolated the same way, with nothing left to distinguish "retry with a
    /// smaller window" from "skip this chunk."
    static func mapChunks(
        _ chunks: [[TranscriptSegment]],
        cleanChunk: ([TranscriptSegment]) async throws -> [TranscriptSegment]
    ) async throws -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for chunk in chunks {
            do {
                result += try await cleanChunk(chunk)
            } catch {
                result += chunk
            }
        }
        return result
    }

    private func cleanChunk(
        _ segments: [TranscriptSegment], language: String
    ) async throws -> [TranscriptSegment] {
        // Fresh ChatSession per call — no context should accumulate between independent chunks.
        // Cheap: the shared `container`'s weights are loaded once and reused across every chunk.
        let session = ChatSession(
            container, instructions: "\(instructions) Respond in \(language).")
        let transcriptText = segments.map { LocalLLMSummarizer.line(for: $0) }.joined(
            separator: "\n")
        let response = try await session.respond(
            to: "Clean up this meeting transcript excerpt:\n\n\(transcriptText)")

        let cleaned = Self.parseCleanedLines(response)
        // A response that parsed to nothing at all is worse than useless — treat it as a failure
        // so `mapChunks` falls back to this chunk's original segments instead of silently
        // dropping them, the same "never lose the transcript" posture as everywhere else in this
        // path.
        guard !cleaned.isEmpty else { throw LocalLLMTranscriptCleanerError.unparseableResponse }
        return cleaned
    }

    /// Parses the model's cleaned-up response back into segments, one `(mm:ss) text` (or
    /// `(h:mm:ss) text`) line at a time. A line that doesn't match — blank, commentary, malformed
    /// — is skipped rather than treated as a parse failure for the whole response.
    static func parseCleanedLines(_ text: String) -> [TranscriptSegment] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap {
            parseLine($0.trimmingCharacters(in: .whitespaces))
        }
    }

    private static func parseLine(_ line: String) -> TranscriptSegment? {
        guard line.hasPrefix("(") else { return nil }
        let afterOpenParen = line.index(after: line.startIndex)
        guard let closingParen = line[afterOpenParen...].firstIndex(of: ")") else { return nil }
        guard
            let offset = TranscriptCodec.parseTimestamp(String(line[afterOpenParen..<closingParen]))
        else { return nil }

        let afterTimestamp = line[line.index(after: closingParen)...]
        guard afterTimestamp.hasPrefix(" ") else { return nil }
        let text = afterTimestamp.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        return TranscriptSegment(offsetSeconds: offset, text: text)
    }
}

enum LocalLLMTranscriptCleanerError: Error, LocalizedError {
    case unparseableResponse

    var errorDescription: String? {
        "The local LLM's cleanup response didn't contain any parseable transcript lines."
    }
}
