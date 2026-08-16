import FluidAudio
import Testing

@testable import MaillageCore

private func segment(_ speaker: Int, start: Float, end: Float) -> DiarizerSegment {
    DiarizerSegment(
        speakerIndex: speaker, startTime: start, endTime: end, frameDurationSeconds: 0.01)
}

@Suite("Speaker aligner")
struct SpeakerAlignerTests {
    @Test("Picks the slot with the greatest overlap")
    func picksGreatestOverlap() {
        let segments = [
            segment(0, start: 0, end: 1),
            segment(1, start: 0.9, end: 2),
        ]
        // Overlaps slot 0 by 0.6s, slot 1 by 0.5s.
        #expect(SpeakerAligner.assign(start: 0.4, end: 1.4, in: segments) == 0)
    }

    @Test("Returns nil when nothing overlaps")
    func nilWhenNoOverlap() {
        let segments = [segment(0, start: 0, end: 1)]
        #expect(SpeakerAligner.assign(start: 2, end: 3, in: segments) == nil)
    }

    @Test("Returns nil against an empty timeline")
    func nilWithNoSegments() {
        #expect(SpeakerAligner.assign(start: 0, end: 1, in: []) == nil)
    }

    @Test("A touching but non-overlapping boundary counts as no overlap")
    func touchingBoundaryIsNotOverlap() {
        let segments = [segment(0, start: 0, end: 1)]
        #expect(SpeakerAligner.assign(start: 1, end: 2, in: segments) == nil)
    }
}
