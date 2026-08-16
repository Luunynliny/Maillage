import Foundation
import Testing

@testable import MaillageCore

@Suite("Summarizer transcript line rendering")
struct FoundationModelsSummarizerTests {
    @Test("A segment renders as a plain timestamped line")
    func plainLine() {
        let segment = TranscriptSegment(offsetSeconds: 15, text: "On va commencer.")
        let line = FoundationModelsSummarizer.line(for: segment)
        #expect(line == "(00:15) On va commencer.")
    }
}
