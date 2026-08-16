import Foundation
import MLXLMCommon

/// Summarizes a meeting's transcript using a local MLX model, map-reduce over fixed-size chunks
/// so a long meeting never lands in one call — map-step chunks produce partial summary markdown
/// directly from the model, and a reduce pass combines those partials into one final markdown
/// summary, also via the model.
///
/// Unlike ``FoundationModelsSummarizer`` (removed with this type's introduction), there is no
/// windowSize-halving retry on overflow: that existed only because `FoundationModels` sessions
/// had a confirmed, fixed ~4,096-token budget. Qwen2.5-1.5B-Instruct's context window is far
/// larger (32K tokens), `mlx-swift-lm` surfaces no comparable "exceeded context" error to retry
/// on, and `defaultWindowSize` below stays comfortably inside that budget even for a talkative
/// chunk — so the retry loop would have nothing real to guard against.
public final class LocalLLMSummarizer: MeetingSummarizer, Sendable {
    private let container: ModelContainer
    /// The vault's `.maillage/prompts/summary.md` (or its built-in default) — see
    /// ``PromptTemplateStore``. Loaded once by the caller and passed in, so this type stays a
    /// plain, vault-agnostic consumer of already-resolved instructions.
    private let instructions: String

    /// Heuristic, like ``FoundationModelsSummarizer``'s own constant was: a short utterance-level
    /// segment runs roughly 25-120 characters, so 50 segments lands well inside Qwen2.5-1.5B's
    /// 32K-token context even with instructions and generated output included.
    private static let defaultWindowSize = 50

    public init(container: ModelContainer, instructions: String) {
        self.container = container
        self.instructions = instructions
    }

    public func summarize(
        _ segments: [TranscriptSegment], language: String
    ) async throws -> String {
        let chunks = TranscriptChunker.chunk(segments, windowSize: Self.defaultWindowSize)
        guard let first = chunks.first else { return "" }

        var chunkSummaries = [try await summarizeChunk(first, language: language)]
        for chunk in chunks.dropFirst() {
            chunkSummaries.append(try await summarizeChunk(chunk, language: language))
        }
        return chunkSummaries.count == 1
            ? chunkSummaries[0]
            : try await reduce(chunkSummaries, language: language)
    }

    private func summarizeChunk(
        _ segments: [TranscriptSegment], language: String
    ) async throws -> String {
        // Fresh ChatSession per call, mirroring the reasoning behind FoundationModelsSummarizer's
        // fresh-session-per-chunk: no context should accumulate between independent chunks. Cheap
        // here too — the session only holds a KV cache and message history, not the weights,
        // which stay loaded once in the shared `container` across every chunk and the reduce call
        // below.
        let session = ChatSession(
            container, instructions: "\(instructions) Respond in \(language).")
        let transcriptText = segments.map { Self.line(for: $0) }.joined(separator: "\n")
        return try await session.respond(
            to: "Summarize this meeting transcript excerpt:\n\n\(transcriptText)")
    }

    /// `(00:15) text` — plain, since this vault records no speaker identification. Also used by
    /// ``LocalLLMTranscriptCleaner`` to render its own input text, so both tasks agree on one line
    /// format for what a transcript excerpt looks like.
    static func line(for segment: TranscriptSegment) -> String {
        let timestamp = TranscriptCodec.formatTimestamp(seconds: segment.offsetSeconds)
        return "(\(timestamp)) \(segment.text)"
    }

    private func reduce(
        _ chunkSummaries: [String], language: String
    ) async throws -> String {
        let session = ChatSession(
            container,
            instructions:
                "You merge several partial summaries of one continuous meeting into a single "
                + "overall markdown summary, deduplicating repeated points. Respond in \(language)."
        )
        let combined = chunkSummaries.enumerated()
            .map { "Part \($0.offset + 1):\n\($0.element)" }
            .joined(separator: "\n\n")
        return try await session.respond(
            to: "Combine these partial meeting summaries into one:\n\n\(combined)")
    }
}
