import Testing

@testable import MaillageCore

@Suite("Transcript paragraphs")
struct TranscriptParagraphsTests {
    private func segment(_ offsetSeconds: Int, _ text: String) -> TranscriptSegment {
        TranscriptSegment(offsetSeconds: offsetSeconds, text: text)
    }

    @Test("Empty segments produce no paragraphs")
    func emptySegmentsProduceNoParagraphs() {
        #expect(TranscriptParagraphs.group([]).isEmpty)
    }

    @Test("Segments close together merge into one paragraph")
    func closeSegmentsMergeIntoOneParagraph() {
        let segments = [
            segment(0, "Hello."), segment(2, "How are you?"), segment(4, "Fine, thanks."),
        ]
        let paragraphs = TranscriptParagraphs.group(segments)
        #expect(paragraphs == ["Hello. How are you? Fine, thanks."])
    }

    @Test("A gap past the threshold starts a new paragraph")
    func gapPastThresholdStartsNewParagraph() {
        let segments = [segment(0, "First paragraph."), segment(20, "Second paragraph.")]
        let paragraphs = TranscriptParagraphs.group(segments, gapThreshold: 4)
        #expect(paragraphs == ["First paragraph.", "Second paragraph."])
    }

    @Test("A gap under the threshold stays in the same paragraph")
    func gapUnderThresholdStaysInSameParagraph() {
        let segments = [segment(0, "Still going."), segment(3, "Same thought.")]
        let paragraphs = TranscriptParagraphs.group(segments, gapThreshold: 4)
        #expect(paragraphs == ["Still going. Same thought."])
    }

    @Test("A single segment is its own paragraph")
    func singleSegmentIsItsOwnParagraph() {
        #expect(TranscriptParagraphs.group([segment(0, "Just this.")]) == ["Just this."])
    }
}
