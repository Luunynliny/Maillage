import FluidAudio
import Foundation
import Testing

@testable import MaillageCore

private func timing(_ token: String, start: Double, end: Double) -> TokenTiming {
    TokenTiming(token: token, tokenId: 0, startTime: start, endTime: end, confidence: 1)
}

@Suite("Token timing grouper")
struct TokenTimingGrouperTests {
    @Test("Joins word-piece tokens into one segment, dropping the boundary marker")
    func joinsWordPieces() {
        let timings = [
            timing("▁On", start: 0, end: 0.2),
            timing("▁ship", start: 0.3, end: 0.6),
            timing("s", start: 0.6, end: 0.7),
            timing("▁cette", start: 0.8, end: 1.1),
            timing("▁semaine", start: 1.2, end: 1.6),
        ]
        let segments = TokenTimingGrouper.segments(from: timings)
        #expect(segments.count == 1)
        #expect(segments[0].text == "On ships cette semaine")
        #expect(segments[0].offsetSeconds == 0)
    }

    @Test("A gap past the pause threshold starts a new segment")
    func pauseStartsNewSegment() {
        let timings = [
            timing("▁First", start: 0, end: 0.4),
            timing("▁line", start: 0.5, end: 0.8),
            // 2 second gap, past the default 1.5s threshold.
            timing("▁Second", start: 2.8, end: 3.2),
            timing("▁line", start: 3.3, end: 3.6),
        ]
        let segments = TokenTimingGrouper.segments(from: timings)
        #expect(segments.count == 2)
        #expect(segments[0].text == "First line")
        #expect(segments[0].offsetSeconds == 0)
        #expect(segments[1].text == "Second line")
        #expect(segments[1].offsetSeconds == 3)
    }

    @Test("A gap under the pause threshold stays in the same segment")
    func shortGapStaysTogether() {
        let timings = [
            timing("▁First", start: 0, end: 0.4),
            // 1 second gap, under the default 1.5s threshold.
            timing("▁second", start: 1.4, end: 1.8),
        ]
        let segments = TokenTimingGrouper.segments(from: timings)
        #expect(segments.count == 1)
        #expect(segments[0].text == "First second")
    }

    @Test("A custom pause threshold changes the grouping")
    func customThreshold() {
        let timings = [
            timing("▁First", start: 0, end: 0.4),
            timing("▁second", start: 1.0, end: 1.4),
        ]
        // 0.6s gap: stays together at the default threshold, splits at a tighter one.
        #expect(TokenTimingGrouper.segments(from: timings).count == 1)
        #expect(TokenTimingGrouper.segments(from: timings, pauseThreshold: 0.5).count == 2)
    }

    @Test("Empty timings produce no segments")
    func emptyTimingsProduceNoSegments() {
        #expect(TokenTimingGrouper.segments(from: []).isEmpty)
    }

    @Test("Language-tag tokens are dropped from the text")
    func dropsLanguageTags() {
        let timings = [
            timing("<fr-FR>", start: 0, end: 0.05),
            timing("▁Bonjour", start: 0.1, end: 0.5),
        ]
        let segments = TokenTimingGrouper.segments(from: timings)
        #expect(segments.count == 1)
        #expect(segments[0].text == "Bonjour")
    }

    @Test("A segment made entirely of language tags produces no segment")
    func onlyLanguageTagsProducesNothing() {
        let timings = [timing("<fr-FR>", start: 0, end: 0.05)]
        #expect(TokenTimingGrouper.segments(from: timings).isEmpty)
    }
}
