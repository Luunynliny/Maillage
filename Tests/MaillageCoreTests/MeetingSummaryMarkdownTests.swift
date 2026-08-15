import Testing

@testable import MaillageCore

@Suite("Meeting summary markdown")
struct MeetingSummaryMarkdownTests {
    @Test("All sections present render in order, with no dangling '## Summary' heading")
    func allSectionsPresent() {
        let summary = MeetingSummary(
            headline: "Ship the importer behind a canary flag.",
            keyPoints: ["The importer needs a feature flag"],
            decisions: ["Ship behind a canary flag."],
            actionItems: [ActionItem(owner: "Marie", what: "wire the flag", due: "Friday")])
        let markdown = summary.markdown

        #expect(!markdown.contains("## Summary"))
        #expect(markdown.contains("**Ship the importer behind a canary flag.**"))
        #expect(markdown.contains("### Key points"))
        #expect(markdown.contains("### Decisions"))
        #expect(markdown.contains("### Actions"))

        let headlineRange = markdown.range(of: "**Ship")!
        let keyPointsRange = markdown.range(of: "### Key points")!
        let decisionsRange = markdown.range(of: "### Decisions")!
        let actionsRange = markdown.range(of: "### Actions")!
        #expect(headlineRange.lowerBound < keyPointsRange.lowerBound)
        #expect(keyPointsRange.lowerBound < decisionsRange.lowerBound)
        #expect(decisionsRange.lowerBound < actionsRange.lowerBound)
    }

    @Test("An action item renders as 'Owner: what'")
    func actionItemFormat() {
        let summary = MeetingSummary(
            headline: "", keyPoints: [], decisions: [],
            actionItems: [ActionItem(owner: "Marie", what: "wire the flag", due: nil)])
        #expect(summary.markdown.contains("- Marie: wire the flag"))
    }

    @Test("An action item with a due date appends it")
    func actionItemWithDue() {
        let summary = MeetingSummary(
            headline: "", keyPoints: [], decisions: [],
            actionItems: [ActionItem(owner: "Marie", what: "wire the flag", due: "Friday")])
        #expect(summary.markdown.contains("- Marie: wire the flag (due Friday)"))
    }

    @Test("An action item with no due date omits the fragment")
    func actionItemWithoutDue() {
        let summary = MeetingSummary(
            headline: "", keyPoints: [], decisions: [],
            actionItems: [ActionItem(owner: "Marie", what: "wire the flag", due: nil)])
        #expect(!summary.markdown.contains("(due"))
    }

    @Test("Empty sections are omitted entirely, not emitted with nothing under them")
    func emptySectionsOmitted() {
        let summary = MeetingSummary(
            headline: "Just a headline.", keyPoints: [], decisions: [], actionItems: [])
        let markdown = summary.markdown
        #expect(markdown == "**Just a headline.**")
        #expect(!markdown.contains("### Key points"))
        #expect(!markdown.contains("### Decisions"))
        #expect(!markdown.contains("### Actions"))
    }
}
