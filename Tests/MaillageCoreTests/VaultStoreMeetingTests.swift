import Foundation
import Testing

@testable import MaillageCore

/// Each test gets a throwaway vault directory under the system temp folder, matching
/// ``VaultStoreTests``'s own helper — kept private to this file rather than shared, the same
/// way ``EntityLogoTests`` has its own copy.
@MainActor
private func makeStore() throws -> (store: VaultStore, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("maillage-meeting-tests-\(UUID().uuidString)", isDirectory: true)
    let store = VaultStore(location: VaultLocation(root: root))
    store.load()
    return (store, root)
}

private func cleanUp(_ root: URL) {
    try? FileManager.default.removeItem(at: root)
}

@MainActor
@Suite("Vault store — meetings")
struct VaultStoreMeetingTests {
    @Test("Creates a meeting, id-prefixed with its date so files sort chronologically")
    func createsMeeting() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let day = try #require(CalendarDay("2026-08-13"))
        let meeting = try #require(store.createMeeting(title: "Acme standup", date: day))

        #expect(meeting.id == "2026-08-13-acme-standup")
        let file = root.appendingPathComponent("meetings/2026-08-13-acme-standup.md")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("A person's meeting history is derived from every meeting that lists them")
    func meetingHistoryIsDerived() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        let earlierDay = try #require(CalendarDay("2026-08-01"))
        let laterDay = try #require(CalendarDay("2026-08-10"))

        let first = try #require(
            store.createMeeting(
                title: "First sync", date: earlierDay, attendees: [Wikilink(marie.id)]))
        let second = try #require(
            store.createMeeting(
                title: "Second sync", date: laterDay,
                attendees: [Wikilink(marie.id), Wikilink(jean.id)]))

        // Most recent first.
        #expect(store.meetings(withPerson: marie.id).map(\.id) == [second.id, first.id])
        #expect(store.meetings(withPerson: jean.id) == [second])
    }

    @Test("Meetings are found by organization and by project")
    func meetingsByOrganizationAndProject() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        let maillage = try #require(store.createProject(name: "Maillage"))
        let meeting = try #require(
            store.createMeeting(
                title: "Kickoff", organization: Wikilink(acme.id), project: Wikilink(maillage.id)))

        #expect(store.meetings(inOrganization: acme.id) == [meeting])
        #expect(store.meetings(onProject: maillage.id) == [meeting])
    }

    @Test("Deleting a person removes them from every meeting's attendees, without deleting it")
    func deletingPersonScrubsAttendees() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        let meeting = try #require(
            store.createMeeting(
                title: "Sync", attendees: [Wikilink(marie.id), Wikilink(jean.id)]))

        #expect(store.delete(kind: .person, id: marie.id))

        let updated = try #require(store.snapshot.meetings[meeting.id])
        #expect(updated.attendees == [Wikilink(jean.id)])
    }

    @Test("Deleting an organization clears a meeting's organization link, not the meeting")
    func deletingOrganizationClearsLink() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        let meeting = try #require(
            store.createMeeting(title: "Sync", organization: Wikilink(acme.id)))

        #expect(store.delete(kind: .organization, id: acme.id))

        let updated = try #require(store.snapshot.meetings[meeting.id])
        #expect(updated.organization == nil)
    }

    @Test("Deleting a project clears a meeting's project link, not the meeting")
    func deletingProjectClearsLink() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let maillage = try #require(store.createProject(name: "Maillage"))
        let meeting = try #require(
            store.createMeeting(title: "Sync", project: Wikilink(maillage.id)))

        #expect(store.delete(kind: .project, id: maillage.id))

        let updated = try #require(store.snapshot.meetings[meeting.id])
        #expect(updated.project == nil)
    }

    @Test("Renaming a person rewrites them in every meeting's attendees")
    func renamingPersonRewritesAttendees() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let meeting = try #require(
            store.createMeeting(title: "Sync", attendees: [Wikilink(marie.id)]))

        let newID = try #require(store.renameEntity(kind: .person, from: marie.id, to: "m-dupont"))

        let updated = try #require(store.snapshot.meetings[meeting.id])
        #expect(updated.attendees == [Wikilink(newID)])
    }

    @Test("Renaming an organization or project rewrites a meeting's links")
    func renamingOrganizationAndProjectRewritesLinks() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        let maillage = try #require(store.createProject(name: "Maillage"))
        let meeting = try #require(
            store.createMeeting(
                title: "Sync", organization: Wikilink(acme.id), project: Wikilink(maillage.id)))

        let newOrgID = try #require(
            store.renameEntity(kind: .organization, from: acme.id, to: "acme-inc"))
        let newProjectID = try #require(
            store.renameEntity(kind: .project, from: maillage.id, to: "maillage-app"))

        let updated = try #require(store.snapshot.meetings[meeting.id])
        #expect(updated.organization == Wikilink(newOrgID))
        #expect(updated.project == Wikilink(newProjectID))
    }

    @Test("Renaming a meeting moves its file and keeps its content")
    func renamingMeetingMovesFile() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let meeting = try #require(store.createMeeting(title: "Sync"))
        let newID = try #require(
            store.renameEntity(kind: .meeting, from: meeting.id, to: "renamed"))

        #expect(newID == "renamed")
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "meetings/\(meeting.id).md"
                ).path))
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "meetings/renamed.md"
                ).path))
        #expect(store.snapshot.meetings["renamed"]?.title == "Sync")
    }

    @Test("Meetings appear in allEntities and are found by id")
    func meetingsAreGenericEntities() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let meeting = try #require(store.createMeeting(title: "Sync"))

        #expect(store.entity(id: meeting.id) == .meeting(meeting))
        #expect(store.allEntities.contains(.meeting(meeting)))
    }
}
