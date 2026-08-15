import Testing

@testable import MaillageCore

@Suite("Transcript merger")
struct TranscriptMergerTests {
    @Test("Interleaves both tracks chronologically")
    func interleaves() {
        let mic = [
            TranscriptSegment(offsetSeconds: 0, text: "Salut"),
            TranscriptSegment(offsetSeconds: 10, text: "Ça va ?"),
        ]
        let system = [
            TranscriptSegment(offsetSeconds: 5, text: "Oui et toi")
        ]
        let merged = TranscriptMerger.merge(micSegments: mic, systemSegments: system)
        #expect(merged.map(\.offsetSeconds) == [0, 5, 10])
        #expect(merged.map(\.text) == ["Salut", "Oui et toi", "Ça va ?"])
    }

    @Test("Ties on the same second keep mic before system")
    func tieBreaksMicFirst() {
        let mic = [TranscriptSegment(offsetSeconds: 5, text: "Mic side")]
        let system = [TranscriptSegment(offsetSeconds: 5, text: "System side")]
        let merged = TranscriptMerger.merge(micSegments: mic, systemSegments: system)
        #expect(merged.map(\.text) == ["Mic side", "System side"])
    }

    @Test("One empty track still merges cleanly")
    func oneEmptyTrack() {
        let mic = [TranscriptSegment(offsetSeconds: 0, text: "Salut")]
        let merged = TranscriptMerger.merge(micSegments: mic, systemSegments: [])
        #expect(merged.count == 1)
        #expect(merged.first?.text == "Salut")
    }

    @Test("Both tracks empty merges to an empty transcript")
    func bothEmpty() {
        #expect(TranscriptMerger.merge(micSegments: [], systemSegments: []).isEmpty)
    }
}
