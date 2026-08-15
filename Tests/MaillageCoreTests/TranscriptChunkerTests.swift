import Testing

@testable import MaillageCore

@Suite("Transcript chunker")
struct TranscriptChunkerTests {
    private func segments(_ count: Int) -> [TranscriptSegment] {
        (0..<count).map { TranscriptSegment(offsetSeconds: $0, text: "Segment \($0)") }
    }

    @Test("Empty input yields no chunks")
    func emptyInput() {
        #expect(TranscriptChunker.chunk([], windowSize: 10).isEmpty)
    }

    @Test("Fewer segments than the window fit in one chunk")
    func fewerThanWindow() {
        let chunks = TranscriptChunker.chunk(segments(3), windowSize: 10)
        #expect(chunks.count == 1)
        #expect(chunks[0].count == 3)
    }

    @Test("A window larger than the segment count still yields one chunk")
    func windowLargerThanSegmentCount() {
        let chunks = TranscriptChunker.chunk(segments(2), windowSize: 50)
        #expect(chunks.count == 1)
        #expect(chunks[0].count == 2)
    }

    @Test("An exact multiple of the window yields equal chunks")
    func exactMultiple() {
        let chunks = TranscriptChunker.chunk(segments(6), windowSize: 3)
        #expect(chunks.count == 2)
        #expect(chunks.allSatisfy { $0.count == 3 })
    }

    @Test("A remainder leaves the last chunk smaller")
    func remainder() {
        let chunks = TranscriptChunker.chunk(segments(7), windowSize: 3)
        #expect(chunks.map(\.count) == [3, 3, 1])
    }

    @Test("A window of one chunks every segment on its own")
    func windowOfOne() {
        let chunks = TranscriptChunker.chunk(segments(3), windowSize: 1)
        #expect(chunks.map(\.count) == [1, 1, 1])
    }

    @Test("A single segment yields one one-segment chunk")
    func singleSegment() {
        let chunks = TranscriptChunker.chunk(segments(1), windowSize: 50)
        #expect(chunks.count == 1)
        #expect(chunks[0].count == 1)
    }

    @Test("A non-positive window clamps to one rather than looping or crashing")
    func nonPositiveWindowClamps() {
        let chunks = TranscriptChunker.chunk(segments(3), windowSize: 0)
        #expect(chunks.map(\.count) == [1, 1, 1])
    }
}
