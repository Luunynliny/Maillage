import Testing

@testable import MaillageCore

@Suite("Vocabulary prompt")
struct VocabularyPromptTests {
    private func wordCount(_ text: String) -> Int {
        text.split(separator: " ").count
    }

    private func meeting(
        attendees: [Wikilink] = [], organization: Wikilink? = nil, project: Wikilink? = nil
    ) -> Meeting {
        Meeting(
            id: "test-meeting", title: "Test", organization: organization, project: project,
            attendees: attendees)
    }

    private var snapshot: VaultSnapshot {
        var snapshot = VaultSnapshot()
        snapshot.people["marie-dupont"] = Person(
            id: "marie-dupont", firstname: "Marie", lastname: "Dupont")
        snapshot.people["jean-martin"] = Person(
            id: "jean-martin", firstname: "Jean", lastname: "Martin")
        snapshot.organizations["acme-corp"] = Organization(id: "acme-corp", name: "Acme Corp")
        snapshot.projects["maillage"] = Project(id: "maillage", name: "maillage")
        return snapshot
    }

    @Test("Attendee names survive a token limit low enough to drop jargon")
    func attendeeNamesSurviveLowLimit() {
        let prompt = VocabularyPrompt.build(
            meeting: meeting(attendees: [Wikilink("marie-dupont")]), snapshot: snapshot,
            language: "fr", customTerms: ["feature flag", "canary deploy", "pull request"],
            budget: .init(limit: 6, count: wordCount))
        #expect(prompt.contains("Marie Dupont"))
        #expect(!prompt.contains("canary deploy"))
    }

    @Test("Output is prose in the base language, not a word list")
    func renderedAsProse() {
        let prompt = VocabularyPrompt.build(
            meeting: meeting(
                attendees: [Wikilink("marie-dupont"), Wikilink("jean-martin")],
                organization: Wikilink("acme-corp"), project: Wikilink("maillage")),
            snapshot: snapshot, language: "fr", customTerms: ["feature flag"],
            budget: .init(limit: 100, count: wordCount))
        #expect(prompt.hasPrefix("Réunion avec"))
        #expect(prompt.contains("et Jean Martin"))
        #expect(prompt.contains("chez Acme Corp"))
        #expect(prompt.contains("projet maillage"))
    }

    @Test("An unrecognized language falls back to the English carrier")
    func fallsBackToEnglish() {
        let prompt = VocabularyPrompt.build(
            meeting: meeting(attendees: [Wikilink("marie-dupont")]), snapshot: snapshot,
            language: "de", customTerms: [], budget: .init(limit: 100, count: wordCount))
        #expect(prompt.hasPrefix("Meeting with"))
    }

    @Test("A zero-limit case yields no prompt rather than a truncated fragment")
    func zeroLimitYieldsNoPrompt() {
        let prompt = VocabularyPrompt.build(
            meeting: meeting(attendees: [Wikilink("marie-dupont")]), snapshot: snapshot,
            language: "fr", customTerms: ["feature flag"],
            budget: .init(limit: 0, count: wordCount))
        #expect(prompt.isEmpty)
    }

    @Test("A meeting with nothing to prime yields no prompt")
    func emptyMeetingYieldsNoPrompt() {
        let prompt = VocabularyPrompt.build(
            meeting: meeting(), snapshot: snapshot, language: "fr", customTerms: [],
            budget: .init(limit: 100, count: wordCount))
        #expect(prompt.isEmpty)
    }
}
