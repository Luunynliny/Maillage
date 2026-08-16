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

    // MARK: Plausibility guard against a chunk that summarized/truncated instead of cleaning

    @Test("Keeping every segment is plausible")
    func keepingEveryoneIsPlausible() {
        let original = (0..<10).map { TranscriptSegment(offsetSeconds: $0 * 5, text: "line \($0)") }
        #expect(LocalLLMTranscriptCleaner.isPlausible(original, original: original))
    }

    @Test("Dropping under half the segments is plausible")
    func droppingAFewIsPlausible() {
        let original = (0..<10).map { TranscriptSegment(offsetSeconds: $0 * 5, text: "line \($0)") }
        let cleaned = Array(original.prefix(6))
        #expect(LocalLLMTranscriptCleaner.isPlausible(cleaned, original: original))
    }

    @Test("Dropping more than half the segments is implausible — that's condensing, not cleaning")
    func droppingMostIsImplausible() {
        let original = (0..<10).map { TranscriptSegment(offsetSeconds: $0 * 5, text: "line \($0)") }
        let cleaned = Array(original.prefix(4))
        #expect(!LocalLLMTranscriptCleaner.isPlausible(cleaned, original: original))
    }

    @Test("An empty cleaned result is implausible when the original had more than one segment")
    func emptyIsImplausible() {
        let original = (0..<10).map { TranscriptSegment(offsetSeconds: $0 * 5, text: "line \($0)") }
        #expect(!LocalLLMTranscriptCleaner.isPlausible([], original: original))
    }

    @Test("A single-segment chunk that cleans to nothing is plausible — dropping one hallucination")
    func singleSegmentDroppedEntirelyIsPlausible() {
        let original = [TranscriptSegment(offsetSeconds: 0, text: "thank you")]
        #expect(LocalLLMTranscriptCleaner.isPlausible([], original: original))
    }

    @Test("A timestamp past the original chunk's end is implausible — the model kept going")
    func timestampPastTheEndIsImplausible() {
        let original = [
            TranscriptSegment(offsetSeconds: 0, text: "a"),
            TranscriptSegment(offsetSeconds: 10, text: "b"),
        ]
        let cleaned = [
            TranscriptSegment(offsetSeconds: 0, text: "a"),
            TranscriptSegment(offsetSeconds: 999, text: "made up"),
        ]
        #expect(!LocalLLMTranscriptCleaner.isPlausible(cleaned, original: original))
    }

    @Test("An empty original chunk trivially passes — nothing to compare against")
    func emptyOriginalIsTriviallyPlausible() {
        #expect(LocalLLMTranscriptCleaner.isPlausible([], original: []))
    }

    // MARK: maxTokens scales with input size

    @Test("A short input still gets a usable floor, not a token-starved cap")
    func maxTokensHasAFloor() {
        #expect(LocalLLMTranscriptCleaner.maxTokens(forInputCharacterCount: 10) == 256)
    }

    @Test("A long input scales past the floor")
    func maxTokensScalesUp() {
        #expect(LocalLLMTranscriptCleaner.maxTokens(forInputCharacterCount: 4_000) == 4_000)
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
