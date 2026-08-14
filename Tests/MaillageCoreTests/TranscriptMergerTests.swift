import Testing

@testable import MaillageCore

@Suite("Transcript merger")
struct TranscriptMergerTests {
    @Test("Interleaves both tracks chronologically")
    func interleaves() {
        let mic = [
            TranscriptSegment(speaker: "", offsetSeconds: 0, text: "Salut"),
            TranscriptSegment(speaker: "", offsetSeconds: 10, text: "Ça va ?"),
        ]
        let system = [
            TranscriptSegment(speaker: "", offsetSeconds: 5, text: "Oui et toi")
        ]
        let merged = TranscriptMerger.merge(
            micSegments: mic, systemSegments: system, soleAttendeeName: "Marie Dupont")
        #expect(merged.map(\.offsetSeconds) == [0, 5, 10])
        #expect(merged.map(\.speaker) == ["You", "Marie Dupont", "You"])
    }

    @Test("Labels the system track Others when there's no sole attendee")
    func labelsOthersWithoutSoleAttendee() {
        let system = [TranscriptSegment(speaker: "", offsetSeconds: 0, text: "Bonjour")]
        let merged = TranscriptMerger.merge(
            micSegments: [], systemSegments: system, soleAttendeeName: nil)
        #expect(merged.first?.speaker == "Others")
    }

    @Test("One empty track still merges cleanly")
    func oneEmptyTrack() {
        let mic = [TranscriptSegment(speaker: "", offsetSeconds: 0, text: "Salut")]
        let merged = TranscriptMerger.merge(
            micSegments: mic, systemSegments: [], soleAttendeeName: nil)
        #expect(merged.count == 1)
        #expect(merged.first?.speaker == "You")
    }
}
