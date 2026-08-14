import Testing

@testable import MaillageCore

@Suite("Prompt echo filter")
struct PromptEchoFilterTests {
    private let prompt =
        "Réunion avec Marie Dupont et Jean Martin chez Acme Corp, projet maillage."

    @Test("A leading echo of the prompt is stripped")
    func stripsLeadingEcho() {
        let segments = [
            TranscriptSegment(
                speaker: "", offsetSeconds: 0,
                text: "Réunion avec Marie Dupont et Jean Martin chez Acme Corp"),
            TranscriptSegment(
                speaker: "", offsetSeconds: 5, text: "On fait le point sur le sprint."),
        ]
        let filtered = PromptEchoFilter.strip(segments, prompt: prompt)
        #expect(filtered.count == 1)
        #expect(filtered.first?.text == "On fait le point sur le sprint.")
    }

    @Test("A genuine opening line that merely resembles the prompt is kept")
    func keepsGenuineResemblance() {
        let segments = [
            TranscriptSegment(speaker: "", offsetSeconds: 0, text: "Marie, tu peux lancer ça ?")
        ]
        let filtered = PromptEchoFilter.strip(segments, prompt: prompt)
        #expect(filtered.count == 1)
    }

    @Test("An empty transcript has nothing to strip")
    func emptyTranscript() {
        #expect(PromptEchoFilter.strip([], prompt: prompt).isEmpty)
    }
}
