import Foundation
import Testing

@testable import MaillageCore

@Suite("Frontmatter codec")
struct FrontmatterCodecTests {
    @Test("Splits frontmatter from body")
    func splitsBody() throws {
        let file = """
            ---
            id: marie-dupont
            type: person
            ---

            Met at the Paris conference.
            """
        let (yaml, body) = try FrontmatterCodec.split(file)
        #expect(yaml.contains("id: marie-dupont"))
        #expect(body == "Met at the Paris conference.")
    }

    @Test("Preserves multi-paragraph body including '---' inside text")
    func preservesBody() throws {
        let body = """
            First paragraph.

            Second paragraph with a --- dash run inside it.

            - a list item
            """
        let person = Person(id: "marie-dupont", firstname: "Marie", lastname: "Dupont", body: body)
        let file = try FrontmatterCodec.encode(person, body: person.body)
        let (decoded, decodedBody) = try FrontmatterCodec.decode(Person.self, from: file)

        #expect(decoded.id == "marie-dupont")
        #expect(decodedBody == body)
    }

    @Test("Round-trips a fully populated person")
    func roundTripsPerson() throws {
        let person = Person(
            id: "marie-dupont",
            firstname: "Marie",
            lastname: "Dupont",
            email: "marie@example.com",
            organizations: [Wikilink("acme-corp")],
            projects: [Wikilink("maillage")],
            relations: [
                Relation(to: "jean-martin", label: "manager of"),
                Relation(to: "alice-bernard", label: "friend of"),
            ],
            body: "Notes."
        )

        let file = try FrontmatterCodec.encode(person, body: person.body)
        let (decoded, body) = try FrontmatterCodec.decode(Person.self, from: file)

        #expect(decoded.firstname == "Marie")
        #expect(decoded.email == "marie@example.com")
        #expect(decoded.organizations == [Wikilink("acme-corp")])
        #expect(decoded.relations.count == 2)
        #expect(decoded.relations.first?.label == "manager of")
        #expect(decoded.relations.first?.to.id == "jean-martin")
        #expect(body == "Notes.")
    }

    @Test("Writes wikilinks in Obsidian [[id]] form")
    func writesWikilinkForm() throws {
        let person = Person(
            id: "marie-dupont",
            organizations: [Wikilink("acme-corp")],
            relations: [Relation(to: "jean-martin", label: "manager of")]
        )
        let file = try FrontmatterCodec.encode(person, body: "")
        #expect(file.contains("[[acme-corp]]"))
        #expect(file.contains("[[jean-martin]]"))
        #expect(file.contains("manager of"))
    }

    @Test("Round-trips a placeholder person with no name")
    func roundTripsPlaceholder() throws {
        let person = Person(
            id: "_head-of-aa",
            placeholder: true,
            descriptor: "Head of AA",
            organizations: [Wikilink("aa")],
            body: "Introduced by Marie."
        )
        let file = try FrontmatterCodec.encode(person, body: person.body)
        let (decoded, _) = try FrontmatterCodec.decode(Person.self, from: file)

        #expect(decoded.placeholder)
        #expect(decoded.descriptor == "Head of AA")
        #expect(decoded.firstname == nil)
        #expect(decoded.displayName == "Head of AA")
    }

    @Test("Round-trips organization and project")
    func roundTripsOrgAndProject() throws {
        let org = Organization(id: "acme-corp", name: "Acme Corp", domain: "acme.com")
        let (decodedOrg, _) = try FrontmatterCodec.decode(
            Organization.self, from: try FrontmatterCodec.encode(org, body: ""))
        #expect(decodedOrg.name == "Acme Corp")
        #expect(decodedOrg.domain == "acme.com")

        let project = Project(
            id: "maillage", name: "Maillage", status: .active,
            organizations: [Wikilink("acme-corp")])
        let (decodedProject, _) = try FrontmatterCodec.decode(
            Project.self, from: try FrontmatterCodec.encode(project, body: ""))
        #expect(decodedProject.name == "Maillage")
        #expect(decodedProject.status == .active)
        #expect(decodedProject.organizations == [Wikilink("acme-corp")])
    }

    /// Regression: encoding a `Date` made Yams emit a UTC timestamp, so a Paris-local
    /// `2026-08-06` was written as `2026-08-05T22:00:00Z` — a day earlier than meant.
    @Test("Round-trips a created date as yyyy-MM-dd without shifting the day")
    func roundTripsDate() throws {
        let day = try #require(CalendarDay("2026-08-06"))
        let person = Person(id: "marie-dupont", firstname: "Marie", created: day)
        let file = try FrontmatterCodec.encode(person, body: "")
        // Quoted by Yams to keep it a string rather than a YAML timestamp — which is
        // precisely what stops the timezone drift.
        #expect(file.contains("created: '2026-08-06'") || file.contains("created: 2026-08-06"))
        #expect(!file.contains("T22:00"))

        let (decoded, _) = try FrontmatterCodec.decode(Person.self, from: file)
        #expect(decoded.created == day)
    }

    /// A hand-written unquoted `yyyy-MM-dd` is a YAML timestamp, not a string.
    @Test("Reads an unquoted hand-written date")
    func readsUnquotedDate() throws {
        let file = """
            ---
            id: marie-dupont
            type: person
            created: 2026-08-06
            ---
            """
        let (decoded, _) = try FrontmatterCodec.decode(Person.self, from: file)
        #expect(decoded.created == CalendarDay("2026-08-06"))
    }

    @Test("Rejects a file with no frontmatter")
    func rejectsMissingFrontmatter() throws {
        #expect(throws: FrontmatterError.self) {
            try FrontmatterCodec.split("Just a note with no frontmatter.")
        }
    }

    @Test("Tolerates unknown frontmatter keys added by hand")
    func tolerantOfUnknownKeys() throws {
        let file = """
            ---
            id: marie-dupont
            type: person
            firstname: Marie
            some_future_key: whatever
            ---
            """
        let (decoded, _) = try FrontmatterCodec.decode(Person.self, from: file)
        #expect(decoded.firstname == "Marie")
    }
}
