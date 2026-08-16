import Foundation
import Testing

@testable import MaillageCore

private struct StubError: Error {}

@Suite("Local LLM transcript cleaner")
struct LocalLLMTranscriptCleanerTests {
    // MARK: Lenient line parsing

    @Test("Parses a plain '(mm:ss) text' line")
    func parsesPlainLine() {
        let segments = LocalLLMTranscriptCleaner.parseCleanedLines("(00:15) On va commencer.")
        #expect(segments == [TranscriptSegment(offsetSeconds: 15, text: "On va commencer.")])
    }

    @Test("Parses an hour-scale '(h:mm:ss) text' line")
    func parsesHourScaleLine() {
        let segments = LocalLLMTranscriptCleaner.parseCleanedLines("(1:02:05) Toujours là.")
        #expect(segments == [TranscriptSegment(offsetSeconds: 3725, text: "Toujours là.")])
    }

    @Test("Parses multiple lines in order")
    func parsesMultipleLines() {
        let segments = LocalLLMTranscriptCleaner.parseCleanedLines(
            "(00:00) Bonjour.\n(00:05) Ça va ?")
        #expect(
            segments == [
                TranscriptSegment(offsetSeconds: 0, text: "Bonjour."),
                TranscriptSegment(offsetSeconds: 5, text: "Ça va ?"),
            ])
    }

    @Test("Skips a line with no leading timestamp instead of failing the whole response")
    func skipsLineWithoutTimestamp() {
        let segments = LocalLLMTranscriptCleaner.parseCleanedLines(
            "Here is the cleaned transcript:\n(00:15) On va commencer.")
        #expect(segments == [TranscriptSegment(offsetSeconds: 15, text: "On va commencer.")])
    }

    @Test("Skips a blank line")
    func skipsBlankLine() {
        let segments = LocalLLMTranscriptCleaner.parseCleanedLines(
            "(00:00) Bonjour.\n\n(00:05) Ça va ?")
        #expect(segments.count == 2)
    }

    @Test("Skips a line whose parens hold no text after them")
    func skipsLineWithNoText() {
        let segments = LocalLLMTranscriptCleaner.parseCleanedLines("(00:15)")
        #expect(segments.isEmpty)
    }

    @Test("Empty response parses to no segments")
    func emptyResponseParsesEmpty() {
        #expect(LocalLLMTranscriptCleaner.parseCleanedLines("").isEmpty)
    }

    // MARK: Per-chunk isolation (mapChunks, reused unchanged from the FoundationModels version)

    @Test("Concatenates every chunk's cleaned result, in order")
    func concatenatesInOrder() async throws {
        let chunks = [
            [TranscriptSegment(offsetSeconds: 0, text: "a")],
            [TranscriptSegment(offsetSeconds: 10, text: "b")],
        ]
        let result = try await LocalLLMTranscriptCleaner.mapChunks(
            chunks,
            cleanChunk: { chunk in
                chunk.map {
                    TranscriptSegment(offsetSeconds: $0.offsetSeconds, text: $0.text.uppercased())
                }
            }
        )
        #expect(result.map(\.text) == ["A", "B"])
    }

    @Test("A chunk that throws falls back to its own original segments")
    func failedChunkPassesThroughUnchanged() async throws {
        let chunks = [
            [TranscriptSegment(offsetSeconds: 0, text: "a")],
            [TranscriptSegment(offsetSeconds: 10, text: "b")],
            [TranscriptSegment(offsetSeconds: 20, text: "c")],
        ]
        let result = try await LocalLLMTranscriptCleaner.mapChunks(
            chunks,
            cleanChunk: { chunk in
                if chunk.first?.text == "b" { throw StubError() }
                return chunk.map {
                    TranscriptSegment(offsetSeconds: $0.offsetSeconds, text: $0.text.uppercased())
                }
            }
        )
        #expect(result.map(\.text) == ["A", "b", "C"])
    }
}
