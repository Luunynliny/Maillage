import Foundation
import Testing

@testable import MaillageCore

private struct StubError: Error {}

@Suite("Transcript cleaner per-chunk isolation")
struct FoundationModelsTranscriptCleanerTests {
    @Test("Concatenates every chunk's cleaned result, in order")
    func concatenatesInOrder() async throws {
        let chunks = [
            [TranscriptSegment(offsetSeconds: 0, text: "a")],
            [TranscriptSegment(offsetSeconds: 10, text: "b")],
        ]
        let result = try await FoundationModelsTranscriptCleaner.mapChunks(
            chunks,
            shouldRetry: { _ in false },
            cleanChunk: { chunk in
                chunk.map {
                    TranscriptSegment(offsetSeconds: $0.offsetSeconds, text: $0.text.uppercased())
                }
            }
        )
        #expect(result.map(\.text) == ["A", "B"])
    }

    @Test("A chunk that fails for a non-retry reason falls back to its own original segments")
    func failedChunkPassesThroughUnchanged() async throws {
        let chunks = [
            [TranscriptSegment(offsetSeconds: 0, text: "a")],
            [TranscriptSegment(offsetSeconds: 10, text: "b")],
            [TranscriptSegment(offsetSeconds: 20, text: "c")],
        ]
        let result = try await FoundationModelsTranscriptCleaner.mapChunks(
            chunks,
            shouldRetry: { _ in false },
            cleanChunk: { chunk in
                if chunk.first?.text == "b" { throw StubError() }
                return chunk.map {
                    TranscriptSegment(offsetSeconds: $0.offsetSeconds, text: $0.text.uppercased())
                }
            }
        )
        #expect(result.map(\.text) == ["A", "b", "C"])
    }

    @Test(
        "A chunk that fails for a retry-worthy reason rethrows immediately instead of passing through"
    )
    func retryWorthyFailureRethrows() async throws {
        let chunks = [
            [TranscriptSegment(offsetSeconds: 0, text: "a")],
            [TranscriptSegment(offsetSeconds: 10, text: "b")],
        ]
        await #expect(throws: StubError.self) {
            try await FoundationModelsTranscriptCleaner.mapChunks(
                chunks,
                shouldRetry: { _ in true },
                cleanChunk: { chunk in
                    if chunk.first?.text == "b" { throw StubError() }
                    return chunk
                }
            )
        }
    }
}
