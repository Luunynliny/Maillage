import Foundation
import Testing

@testable import MaillageCore

@Suite("Meeting frontmatter")
struct MeetingFrontmatterTests {
    @Test("Round-trips a fully populated meeting")
    func roundTripsMeeting() throws {
        let day = try #require(CalendarDay("2026-08-13"))
        let meeting = Meeting(
            id: "2026-08-13-acme-standup",
            title: "Acme standup",
            date: day,
            duration: 1_847,
            language: "fr",
            organization: Wikilink("acme-corp"),
            project: Wikilink("maillage"),
            attendees: [Wikilink("marie-dupont"), Wikilink("jean-martin")],
            created: day,
            body: "## Transcript\n\n**You** (00:12) Salut."
        )

        let file = try FrontmatterCodec.encode(meeting, body: meeting.body)
        let (decoded, body) = try FrontmatterCodec.decode(Meeting.self, from: file)

        #expect(decoded.title == "Acme standup")
        #expect(decoded.date == day)
        #expect(decoded.duration == 1_847)
        #expect(decoded.language == "fr")
        #expect(decoded.organization == Wikilink("acme-corp"))
        #expect(decoded.project == Wikilink("maillage"))
        #expect(decoded.attendees == [Wikilink("marie-dupont"), Wikilink("jean-martin")])
        #expect(body == "## Transcript\n\n**You** (00:12) Salut.")
    }

    @Test("Writes attendees, organization and project in Obsidian [[id]] form")
    func writesWikilinkForm() throws {
        let meeting = Meeting(
            id: "2026-08-13-acme-standup",
            title: "Acme standup",
            organization: Wikilink("acme-corp"),
            project: Wikilink("maillage"),
            attendees: [Wikilink("marie-dupont")]
        )
        let file = try FrontmatterCodec.encode(meeting, body: "")
        #expect(file.contains("[[acme-corp]]"))
        #expect(file.contains("[[maillage]]"))
        #expect(file.contains("[[marie-dupont]]"))
    }

    @Test("A meeting with no attendees omits the key rather than writing an empty list")
    func noAttendeesOmitsKey() throws {
        let meeting = Meeting(id: "2026-08-13-solo-notes", title: "Solo notes")
        let file = try FrontmatterCodec.encode(meeting, body: "")
        #expect(!file.contains("attendees:"))

        let (decoded, _) = try FrontmatterCodec.decode(Meeting.self, from: file)
        #expect(decoded.attendees.isEmpty)
    }

    @Test("A hand-written file with no date or duration still decodes")
    func handWrittenMinimalFile() throws {
        let file = """
            ---
            id: 2026-08-13-quick-chat
            type: meeting
            title: Quick chat
            attendees:
              - '[[marie-dupont]]'
            ---

            Talked in the hallway, no recording.
            """
        let (decoded, body) = try FrontmatterCodec.decode(Meeting.self, from: file)
        #expect(decoded.title == "Quick chat")
        #expect(decoded.date == nil)
        #expect(decoded.duration == nil)
        #expect(decoded.attendees == [Wikilink("marie-dupont")])
        #expect(body == "Talked in the hallway, no recording.")
    }

    @Test("displayName falls back to the id when the title is blank")
    func displayNameFallsBackToID() {
        let meeting = Meeting(id: "2026-08-13-untitled", title: "")
        #expect(meeting.displayName == "2026-08-13-untitled")
    }
}
