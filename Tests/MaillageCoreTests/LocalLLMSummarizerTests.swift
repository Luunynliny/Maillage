import Foundation
import Testing

@testable import MaillageCore

@Suite("Local LLM summarizer transcript line rendering")
struct LocalLLMSummarizerTests {
    @Test("A segment renders as a plain timestamped line")
    func plainLine() {
        let segment = TranscriptSegment(offsetSeconds: 15, text: "On va commencer.")
        let line = LocalLLMSummarizer.line(for: segment)
        #expect(line == "(00:15) On va commencer.")
    }
}
