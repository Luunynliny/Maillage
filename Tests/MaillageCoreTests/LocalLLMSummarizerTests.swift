import Foundation
import Testing

@testable import MaillageCore

private struct StubError: Error {}

@Suite("Local LLM summarizer transcript line rendering")
struct LocalLLMSummarizerTests {
    @Test("A segment renders as a plain timestamped line")
    func plainLine() {
        let segment = TranscriptSegment(offsetSeconds: 15, text: "On va commencer.")
        let line = LocalLLMSummarizer.line(for: segment)
        #expect(line == "(00:15) On va commencer.")
    }
}

@Suite("Local LLM summarizer per-chunk tolerance")
struct LocalLLMSummarizerMapChunksTests {
    @Test("Collects every chunk's summary, in order")
    func collectsInOrder() async {
        let chunks = [
            [TranscriptSegment(offsetSeconds: 0, text: "a")],
            [TranscriptSegment(offsetSeconds: 10, text: "b")],
        ]
        let result = await LocalLLMSummarizer.mapChunksTolerantly(chunks) { chunk in
            chunk.first?.text ?? ""
        }
        #expect(result == ["a", "b"])
    }

    @Test("A chunk that throws is dropped, not substituted")
    func droppedChunkIsSkipped() async {
        let chunks = [
            [TranscriptSegment(offsetSeconds: 0, text: "a")],
            [TranscriptSegment(offsetSeconds: 10, text: "b")],
            [TranscriptSegment(offsetSeconds: 20, text: "c")],
        ]
        let result = await LocalLLMSummarizer.mapChunksTolerantly(chunks) { chunk in
            if chunk.first?.text == "b" { throw StubError() }
            return chunk.first?.text ?? ""
        }
        #expect(result == ["a", "c"])
    }

    @Test("Every chunk failing yields an empty result, not a thrown error")
    func everyChunkFailingYieldsEmpty() async {
        let chunks = [[TranscriptSegment(offsetSeconds: 0, text: "a")]]
        let result = await LocalLLMSummarizer.mapChunksTolerantly(chunks) { _ in
            throw StubError()
        }
        #expect(result.isEmpty)
    }
}
