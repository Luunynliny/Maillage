import Foundation
import Testing

@testable import MaillageCore

@Suite("Transcript codec")
struct TranscriptCodecTests {
    @Test("Round-trips a preamble and its segments")
    func roundTrips() {
        let segments = [
            TranscriptSegment(offsetSeconds: 12, text: "On ship cette semaine ?"),
            TranscriptSegment(offsetSeconds: 15, text: "Oui, mais il faut d'abord."),
        ]
        let body = TranscriptCodec.join(preamble: "## Summary\n\n**Ship it.**", segments: segments)

        let (preamble, decoded) = TranscriptCodec.split(body)
        #expect(preamble == "## Summary\n\n**Ship it.**")
        #expect(decoded == segments)
    }

    @Test("A body with no transcript heading is all preamble")
    func noHeadingIsAllPreamble() {
        let (preamble, segments) = TranscriptCodec.split("Just some notes, no meeting yet.")
        #expect(preamble == "Just some notes, no meeting yet.")
        #expect(segments.isEmpty)
    }

    @Test("Joining with no segments omits the heading entirely")
    func joiningWithNoSegmentsOmitsHeading() {
        let body = TranscriptCodec.join(preamble: "Some notes.", segments: [])
        #expect(body == "Some notes.")
        #expect(!body.contains(TranscriptCodec.heading))
    }

    @Test("An empty preamble and no segments round-trips to an empty body")
    func emptyEverythingRoundTrips() {
        let body = TranscriptCodec.join(preamble: "", segments: [])
        #expect(body.isEmpty)
        let (preamble, segments) = TranscriptCodec.split(body)
        #expect(preamble.isEmpty)
        #expect(segments.isEmpty)
    }

    @Test("A literal ** inside speech round-trips as plain text")
    func doubleStarInsideSpeech() {
        let segments = [
            TranscriptSegment(offsetSeconds: 0, text: "Wrap it in ** for bold.")
        ]
        let (_, decoded) = TranscriptCodec.split(
            TranscriptCodec.join(preamble: "", segments: segments))
        #expect(decoded == segments)
    }

    @Test("Parentheses inside speech round-trip, not mistaken for the timestamp")
    func parenthesesInsideSpeech() {
        let segments = [
            TranscriptSegment(
                offsetSeconds: 5, text: "It's fine (I already checked with them).")
        ]
        let (_, decoded) = TranscriptCodec.split(
            TranscriptCodec.join(preamble: "", segments: segments))
        #expect(decoded == segments)
    }

    @Test("A literal newline inside speech round-trips without breaking the one-line shape")
    func newlineInsideSpeech() {
        let segments = [
            TranscriptSegment(offsetSeconds: 3, text: "First line.\nSecond line.")
        ]
        let body = TranscriptCodec.join(preamble: "", segments: segments)
        // Escaped, so the transcript stays exactly one physical line per segment.
        #expect(body.split(separator: "\n").count == 2)  // heading + the one segment line
        let (_, decoded) = TranscriptCodec.split(body)
        #expect(decoded == segments)
    }

    @Test("Timestamps past one hour round-trip as H:MM:SS")
    func timestampsPastOneHour() {
        #expect(TranscriptCodec.formatTimestamp(seconds: 3_725) == "1:02:05")
        #expect(TranscriptCodec.formatTimestamp(seconds: 45) == "00:45")
        #expect(TranscriptCodec.formatTimestamp(seconds: 90) == "01:30")

        let segments = [
            TranscriptSegment(offsetSeconds: 3_725, text: "An hour in.")
        ]
        let (_, decoded) = TranscriptCodec.split(
            TranscriptCodec.join(preamble: "", segments: segments))
        #expect(decoded == segments)
    }

    @Test("Multiple segments interleave in the order they were given")
    func multipleSegmentsPreserveOrder() {
        let segments = [
            TranscriptSegment(offsetSeconds: 0, text: "First."),
            TranscriptSegment(offsetSeconds: 4, text: "Second."),
            TranscriptSegment(offsetSeconds: 9, text: "Third."),
        ]
        let (_, decoded) = TranscriptCodec.split(
            TranscriptCodec.join(preamble: "", segments: segments))
        #expect(decoded == segments)
    }

    // MARK: Speaker tags

    @Test("An old-format line with no speaker tag still parses, with speaker nil")
    func oldFormatLineHasNoSpeaker() {
        let body = "## Transcript\n\n(00:15) Oui, mais il faut wire le canary d'abord."
        let (_, segments) = TranscriptCodec.split(body)
        #expect(
            segments == [
                TranscriptSegment(
                    offsetSeconds: 15, text: "Oui, mais il faut wire le canary d'abord.")
            ])
    }

    @Test("An unresolved speaker tag round-trips")
    func unresolvedSpeakerTagRoundTrips() {
        let segments = [
            TranscriptSegment(
                offsetSeconds: 15, text: "On va commencer.",
                speaker: Speaker(track: .mic, slot: 2))
        ]
        let body = TranscriptCodec.join(preamble: "", segments: segments)
        #expect(body.contains("(00:15 #M2) On va commencer."))
        let (_, decoded) = TranscriptCodec.split(body)
        #expect(decoded == segments)
    }

    @Test("A resolved speaker tag round-trips, including the person id")
    func resolvedSpeakerTagRoundTrips() {
        let segments = [
            TranscriptSegment(
                offsetSeconds: 15, text: "On va commencer.",
                speaker: Speaker(track: .system, slot: 0, personID: "marie-dupont"))
        ]
        let body = TranscriptCodec.join(preamble: "", segments: segments)
        #expect(body.contains("(00:15 #S0:marie-dupont) On va commencer."))
        let (_, decoded) = TranscriptCodec.split(body)
        #expect(decoded == segments)
    }

    @Test("Mixed diarized and undiarized segments round-trip in the same transcript")
    func mixedSpeakerAndNoSpeakerRoundTrips() {
        let segments = [
            TranscriptSegment(
                offsetSeconds: 0, text: "Diarized.",
                speaker: Speaker(track: .mic, slot: 1, personID: "amy-wong")),
            TranscriptSegment(offsetSeconds: 5, text: "Not diarized."),
        ]
        let (_, decoded) = TranscriptCodec.split(
            TranscriptCodec.join(preamble: "", segments: segments))
        #expect(decoded == segments)
    }
}
