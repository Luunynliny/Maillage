import Foundation
import Testing

@testable import MaillageCore

@Suite("Summarizer transcript line rendering")
struct FoundationModelsSummarizerTests {
    @Test("A segment with no speaker renders with no name at all")
    func noSpeaker() {
        let segment = TranscriptSegment(offsetSeconds: 15, text: "On va commencer.")
        let line = FoundationModelsSummarizer.line(for: segment, displayNames: [:])
        #expect(line == "(00:15) On va commencer.")
    }

    @Test("A resolved speaker renders with their display name")
    func resolvedSpeaker() {
        let segment = TranscriptSegment(
            offsetSeconds: 15, text: "On va commencer.",
            speaker: Speaker(track: .mic, slot: 0, personID: "marie-dupont"))
        let line = FoundationModelsSummarizer.line(
            for: segment, displayNames: ["marie-dupont": "Marie Dupont"])
        #expect(line == "(00:15) Marie Dupont: On va commencer.")
    }

    @Test("An unresolved speaker falls back to Speaker N")
    func unresolvedSpeaker() {
        let segment = TranscriptSegment(
            offsetSeconds: 15, text: "On va commencer.",
            speaker: Speaker(track: .system, slot: 1))
        let line = FoundationModelsSummarizer.line(for: segment, displayNames: [:])
        #expect(line == "(00:15) Speaker 2: On va commencer.")
    }

    @Test("A resolved personID missing from displayNames falls back to Speaker N")
    func resolvedButUnknownPersonFallsBack() {
        let segment = TranscriptSegment(
            offsetSeconds: 15, text: "On va commencer.",
            speaker: Speaker(track: .mic, slot: 2, personID: "deleted-person"))
        let line = FoundationModelsSummarizer.line(for: segment, displayNames: [:])
        #expect(line == "(00:15) Speaker 3: On va commencer.")
    }
}
