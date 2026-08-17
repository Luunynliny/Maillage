import Foundation
import Testing

@testable import MaillageCore

@MainActor
@Suite("Vault store")
struct VaultStoreTests {
    @Test("Creates a person and writes a markdown file")
    func createsPerson() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let marie = try #require(
            store.createPerson(firstname: "Marie", lastname: "Dupont", email: "marie@example.com"))

        #expect(marie.id == "marie-dupont")
        #expect(marie.displayName == "Marie Dupont")

        let file = root.appendingPathComponent("people/marie-dupont.md")
        #expect(FileManager.default.fileExists(atPath: file.path))

        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents.contains("firstname: Marie"))
        #expect(contents.contains("marie@example.com"))
    }

    @Test("Folds diacritics when slugifying names")
    func slugifiesDiacritics() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let person = try #require(store.createPerson(firstname: "Zoé", lastname: "Müller"))
        #expect(person.id == "zoe-muller")
    }

    @Test("Disambiguates duplicate names instead of overwriting")
    func disambiguatesDuplicates() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let first = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        let second = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))

        #expect(first.id == "jean-martin")
        #expect(second.id == "jean-martin-2")
        #expect(store.allPeople.count == 2)
    }

    /// The core of the storage model: a relation exists in exactly one file.
    @Test("Stores relations one-way and derives the backlink")
    func storesRelationsOneWay() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))

        #expect(store.addRelation(from: marie.id, to: jean.id, label: "manager of"))

        // Forward: stored on Marie only.
        #expect(store.snapshot.people[marie.id]?.relations.count == 1)
        #expect(store.snapshot.people[marie.id]?.relations.first?.label == "manager of")

        // Inverse: never written to Jean's file.
        #expect(store.snapshot.people[jean.id]?.relations.isEmpty == true)
        let jeanFile = try String(
            contentsOf: root.appendingPathComponent("people/jean-martin.md"), encoding: .utf8)
        #expect(!jeanFile.contains("relations"))

        // But Jean sees it as a derived backlink.
        let backlinks = store.backlinks(for: jean.id)
        #expect(backlinks.count == 1)
        #expect(backlinks.first?.from == marie.id)
        #expect(backlinks.first?.label == "manager of")

        // And Marie has no incoming backlink from this relation.
        #expect(store.backlinks(for: marie.id).isEmpty)
    }

    @Test("Removing a relation clears the derived backlink")
    func removesRelation() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        #expect(store.addRelation(from: marie.id, to: jean.id, label: "manager of"))

        let relation = try #require(store.snapshot.people[marie.id]?.relations.first)
        #expect(store.removeRelation(from: marie.id, relation: relation))
        #expect(store.backlinks(for: jean.id).isEmpty)
    }

    @Test("Relation labels are derived from use, most-used first")
    func derivesRelationLabels() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        // Nothing to offer until the user has named a relationship themselves.
        #expect(store.usedRelationLabels.isEmpty)

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        let alice = try #require(store.createPerson(firstname: "Alice", lastname: "Roy"))

        #expect(store.addRelation(from: marie.id, to: jean.id, label: "climbs with"))
        #expect(store.addRelation(from: marie.id, to: alice.id, label: "manager of"))
        #expect(store.addRelation(from: jean.id, to: alice.id, label: "manager of"))

        #expect(store.usedRelationLabels == ["manager of", "climbs with"])

        // Dropping the last use of a label drops the label with it.
        let relation = try #require(
            store.snapshot.people[marie.id]?.relations.first { $0.label == "climbs with" })
        #expect(store.removeRelation(from: marie.id, relation: relation))
        #expect(store.usedRelationLabels == ["manager of"])
    }

    @Test("A project's body is titled Description, everyone else's is Notes")
    func bodyTitlePerKind() throws {
        #expect(EntityKind.project.bodyTitle == "Description")
        #expect(EntityKind.person.bodyTitle == "Notes")
        #expect(EntityKind.organization.bodyTitle == "Notes")
    }

    @Test("Reloading from disk reproduces the same state")
    func reloadsFromDisk() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        let acme = try #require(store.createOrganization(name: "Acme Corp", domain: "acme.com"))
        #expect(store.addRelation(from: marie.id, to: jean.id, label: "manager of"))

        var updated = try #require(store.snapshot.people[marie.id])
        updated.organization = Wikilink(acme.id)
        #expect(store.update(updated))

        // A second store reading the same folder must see identical data.
        let reloaded = VaultStore(location: VaultLocation(root: root))
        reloaded.load()

        #expect(reloaded.snapshot.issues.isEmpty)
        #expect(reloaded.allPeople.count == 2)
        #expect(reloaded.allOrganizations.count == 1)
        #expect(reloaded.backlinks(for: jean.id).first?.label == "manager of")
        #expect(reloaded.members(ofOrganization: acme.id).map(\.id) == [marie.id])
    }

    @Test("Renaming a person rewrites inbound relations")
    func renameRewritesInboundRelations() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        #expect(store.addRelation(from: marie.id, to: jean.id, label: "manager of"))

        #expect(store.renameEntity(kind: .person, from: jean.id, to: "jean-martin-renamed") != nil)

        // Marie's stored relation now points at the new id, with nothing dangling.
        let relations = try #require(store.snapshot.people[marie.id]?.relations)
        #expect(relations.first?.to.id == "jean-martin-renamed")
        #expect(store.backlinks(for: "jean-martin-renamed").count == 1)
        #expect(store.backlinks(for: jean.id).isEmpty)

        // On disk too, and the old file is gone.
        let marieFile = try String(
            contentsOf: root.appendingPathComponent("people/marie-dupont.md"), encoding: .utf8)
        #expect(marieFile.contains("[[jean-martin-renamed]]"))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("people/jean-martin.md").path))
    }

    @Test("Renaming an organization rewrites membership links")
    func renameRewritesMembership() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.organization = Wikilink(acme.id)
        #expect(store.update(marie))

        #expect(store.renameEntity(kind: .organization, from: acme.id, to: "acme-global") != nil)

        #expect(store.snapshot.people[marie.id]?.organization == Wikilink("acme-global"))
        #expect(store.members(ofOrganization: "acme-global").count == 1)
    }

    /// The other inbound link an organization has: a project's owner.
    @Test("Renaming an organization rewrites its projects' owner link")
    func renameRewritesProjectOwner() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        let project = try #require(
            store.createProject(name: "Maillage", organization: Wikilink(acme.id)))

        #expect(store.renameEntity(kind: .organization, from: acme.id, to: "acme-global") != nil)

        #expect(store.snapshot.projects[project.id]?.organization == Wikilink("acme-global"))
        #expect(store.projects(inOrganization: "acme-global").map(\.id) == [project.id])
    }

    // MARK: Membership and roles

    @Test("Employing someone replaces their previous employer")
    func employmentIsSingular() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        let globex = try #require(store.createOrganization(name: "Globex"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))

        marie.organization = Wikilink(acme.id)
        #expect(store.update(marie))
        marie.organization = Wikilink(globex.id)
        #expect(store.update(marie))

        #expect(store.members(ofOrganization: acme.id).isEmpty)
        #expect(store.members(ofOrganization: globex.id).map(\.id) == [marie.id])
    }

    /// A role belongs to the membership, so it is written to the person's file and the
    /// project file learns nothing about its roster.
    @Test("A project role is written to the person's file, not the project's")
    func storesRoleOnThePerson() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let project = try #require(store.createProject(name: "Maillage"))
        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))

        #expect(
            store.setParticipants(ofProject: project.id, to: [(person: marie.id, role: "Lead")]))

        let participants = store.participants(ofProject: project.id)
        #expect(participants.map(\.person.id) == [marie.id])
        #expect(participants.first?.role == "Lead")

        let marieFile = try String(
            contentsOf: root.appendingPathComponent("people/marie-dupont.md"), encoding: .utf8)
        #expect(marieFile.contains("role: Lead"))
        let projectFile = try String(
            contentsOf: root.appendingPathComponent("projects/maillage.md"), encoding: .utf8)
        #expect(!projectFile.contains("marie-dupont"))
        #expect(!projectFile.contains("Lead"))
    }

    /// The editor hands over whatever is in the field, so blanks are the store's to reject.
    @Test("A blank role clears the stored one but keeps the membership")
    func clearsProjectRole() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let project = try #require(store.createProject(name: "Maillage"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.projects = [ProjectMembership(to: project.id, role: "Lead")]
        #expect(store.update(marie))

        #expect(
            store.setParticipants(ofProject: project.id, to: [(person: marie.id, role: "   ")]))
        #expect(store.participants(ofProject: project.id).first?.role == nil)
        #expect(store.members(ofProject: project.id).map(\.id) == [marie.id])
    }

    /// What the project editor saves: it knows the intended roster, not which entries moved.
    @Test("Setting a roster adds, updates and removes memberships to match")
    func setsParticipants() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let project = try #require(store.createProject(name: "Maillage"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.projects = [ProjectMembership(to: project.id, role: "Reviewer")]
        #expect(store.update(marie))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        var alice = try #require(store.createPerson(firstname: "Alice", lastname: "Roy"))
        alice.projects = [ProjectMembership(to: project.id, role: "Lead")]
        #expect(store.update(alice))

        // Marie's role changes, Jean joins, Alice is dropped.
        #expect(
            store.setParticipants(
                ofProject: project.id,
                to: [(person: marie.id, role: "Lead"), (person: jean.id, role: nil)]))

        let participants = store.participants(ofProject: project.id)
        #expect(participants.map(\.person.id) == [jean.id, marie.id])
        #expect(participants.first { $0.person.id == marie.id }?.role == "Lead")
        #expect(participants.first { $0.person.id == jean.id }?.role == nil)
        #expect(store.snapshot.people[alice.id]?.projects.isEmpty == true)

        // Still nothing about the roster on the project's own file.
        let projectFile = try String(
            contentsOf: root.appendingPathComponent("projects/maillage.md"), encoding: .utf8)
        #expect(!projectFile.contains("marie-dupont"))
    }

    /// Saving a project sets its whole roster, so an unchanged person must not have their
    /// file rewritten just for being on it.
    @Test("Setting an unchanged roster rewrites nobody")
    func setParticipantsSkipsUnchanged() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let project = try #require(store.createProject(name: "Maillage"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.projects = [ProjectMembership(to: project.id, role: "Lead")]
        #expect(store.update(marie))

        let file = root.appendingPathComponent("people/marie-dupont.md")
        let before = try #require(
            try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)

        #expect(
            store.setParticipants(ofProject: project.id, to: [(person: marie.id, role: "Lead")]))

        let after = try #require(
            try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        #expect(before == after)
    }

    /// A project nobody is on: the roster still has to clear, or removing the last person
    /// would silently leave them attached.
    @Test("Setting an empty roster clears every membership")
    func setParticipantsToEmpty() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let project = try #require(store.createProject(name: "Maillage"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.projects = [ProjectMembership(to: project.id, role: "Lead")]
        #expect(store.update(marie))

        #expect(store.setParticipants(ofProject: project.id, to: []))
        #expect(store.participants(ofProject: project.id).isEmpty)
        #expect(store.snapshot.people[marie.id]?.projects.isEmpty == true)
    }

    /// Someone on two projects must keep the other one when a roster is applied.
    @Test("Setting a roster leaves other projects alone")
    func setParticipantsLeavesOtherProjects() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let maillage = try #require(store.createProject(name: "Maillage"))
        let atlas = try #require(store.createProject(name: "Atlas"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.projects = [
            ProjectMembership(to: maillage.id, role: "Lead"),
            ProjectMembership(to: atlas.id, role: "Reviewer"),
        ]
        #expect(store.update(marie))

        #expect(store.setParticipants(ofProject: maillage.id, to: []))

        #expect(
            store.snapshot.people[marie.id]?.projects
                == [ProjectMembership(to: atlas.id, role: "Reviewer")])
    }

    @Test("Project roles are derived from use, most-used first")
    func derivesProjectRoles() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        #expect(store.usedProjectRoles.isEmpty)

        let maillage = try #require(store.createProject(name: "Maillage"))
        let atlas = try #require(store.createProject(name: "Atlas"))

        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.projects = [
            ProjectMembership(to: maillage.id, role: "Lead"),
            ProjectMembership(to: atlas.id, role: "Reviewer"),
        ]
        #expect(store.update(marie))

        var jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        jean.projects = [ProjectMembership(to: maillage.id, role: "Reviewer")]
        #expect(store.update(jean))

        #expect(store.usedProjectRoles == ["Reviewer", "Lead"])
    }

    @Test("Renaming a project keeps the role on the membership")
    func renameKeepsProjectRole() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let project = try #require(store.createProject(name: "Maillage"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.projects = [ProjectMembership(to: project.id, role: "Lead")]
        #expect(store.update(marie))

        #expect(store.renameEntity(kind: .project, from: project.id, to: "maillage-v2") != nil)

        #expect(
            store.snapshot.people[marie.id]?.projects
                == [ProjectMembership(to: "maillage-v2", role: "Lead")])
        #expect(store.participants(ofProject: "maillage-v2").first?.role == "Lead")
    }

    /// The clustered graph derives each cluster's position from its index in this list, so
    /// the order has to be stable and nobody may fall out of it.
    @Test("Groups people by employer with the unaffiliated last")
    func groupsPeopleByOrganization() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        _ = try #require(store.createOrganization(name: "Zenith"))  // no employees
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.organization = Wikilink(acme.id)
        #expect(store.update(marie))
        var jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        // Hand-edited link to an org that doesn't exist: still has to appear somewhere.
        jean.organization = Wikilink("ghost-corp")
        #expect(store.update(jean))
        let alice = try #require(store.createPerson(firstname: "Alice", lastname: "Roy"))

        let groups = store.peopleGroupedByOrganization()

        // Zenith is omitted: an anchor with nobody around it is just a stray node.
        #expect(groups.map { $0.organization?.id } == [acme.id, nil])
        #expect(groups.first?.people.map(\.id) == [marie.id])
        #expect(groups.last?.people.map(\.id) == [alice.id, jean.id])

        // Same input, same order — the layout has to be recognisable between launches.
        #expect(
            store.peopleGroupedByOrganization().map { $0.organization?.id }
                == groups.map { $0.organization?.id })
    }

    @Test("Deleting a project scrubs the membership and its role")
    func deleteScrubsProjectMembership() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let project = try #require(store.createProject(name: "Maillage"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.projects = [ProjectMembership(to: project.id, role: "Lead")]
        #expect(store.update(marie))

        #expect(store.delete(kind: .project, id: project.id))

        #expect(store.snapshot.people[marie.id]?.projects.isEmpty == true)
        let marieFile = try String(
            contentsOf: root.appendingPathComponent("people/marie-dupont.md"), encoding: .utf8)
        #expect(!marieFile.contains("maillage"))
        #expect(!marieFile.contains("Lead"))
    }

    // MARK: Placeholders

    @Test("Creates a placeholder person with no name")
    func createsPlaceholder() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let head = try #require(
            store.createPerson(descriptor: "Head of AA", placeholder: true))

        #expect(head.placeholder)
        #expect(head.displayName == "Head of AA")
        #expect(head.firstname == nil)
        // Underscore prefix keeps placeholders visually grouped in the vault folder.
        #expect(head.id == "_head-of-aa")
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("people/_head-of-aa.md").path))
    }

    /// The editor's "No name yet" toggle can be flipped after a name has been typed, so it
    /// drops those fields — a placeholder carrying a name would show the name everywhere
    /// while still sorting and rendering as unnamed.
    @Test("A placeholder keeps no name, only a descriptor")
    func placeholderHasNoName() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let head = try #require(
            store.createPerson(
                firstname: nil, lastname: nil, email: nil, descriptor: "Head of AA",
                placeholder: true))

        #expect(head.firstname == nil)
        #expect(head.lastname == nil)
        #expect(head.email == nil)
        #expect(head.descriptor == "Head of AA")
        #expect(head.displayName == "Head of AA")

        let file = try String(
            contentsOf: root.appendingPathComponent("people/_head-of-aa.md"), encoding: .utf8)
        #expect(!file.contains("firstname"))
    }

    /// The role is usually *why* you know an unnamed person exists, so it survives the
    /// descriptor being replaced by a real name.
    @Test("A placeholder keeps its role through resolution")
    func placeholderKeepsRole() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let head = try #require(
            store.createPerson(
                role: "Head of AA", descriptor: "Head of AA", placeholder: true))
        #expect(head.role == "Head of AA")

        let resolved = try #require(
            store.resolvePlaceholder(head.id, firstname: "Alice", lastname: "Bernard"))
        #expect(resolved.role == "Head of AA")
    }

    @Test("Resolving a placeholder renames the file and keeps inbound links intact")
    func resolvesPlaceholder() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let head = try #require(store.createPerson(descriptor: "Head of AA", placeholder: true))
        #expect(store.addRelation(from: marie.id, to: head.id, label: "introduced me to"))

        let resolved = try #require(
            store.resolvePlaceholder(head.id, firstname: "Alice", lastname: "Bernard"))

        #expect(!resolved.placeholder)
        #expect(resolved.descriptor == nil)
        #expect(resolved.displayName == "Alice Bernard")
        #expect(resolved.id == "alice-bernard")

        // The relation followed the rename — no orphaned link.
        #expect(store.snapshot.people[marie.id]?.relations.first?.to.id == "alice-bernard")
        #expect(store.backlinks(for: "alice-bernard").count == 1)

        // Old placeholder file replaced by the named one.
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("people/_head-of-aa.md").path))
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("people/alice-bernard.md").path))
    }

    // MARK: Deletion

    @Test("Deleting a person scrubs relations pointing at them")
    func deleteScrubsRelations() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        #expect(store.addRelation(from: marie.id, to: jean.id, label: "manager of"))

        #expect(store.delete(kind: .person, id: jean.id))

        #expect(store.snapshot.people[jean.id] == nil)
        // No dangling relation left behind on Marie.
        #expect(store.snapshot.people[marie.id]?.relations.isEmpty == true)
        #expect(store.backlinks(for: jean.id).isEmpty)

        let marieFile = try String(
            contentsOf: root.appendingPathComponent("people/marie-dupont.md"), encoding: .utf8)
        #expect(!marieFile.contains("jean-martin"))
    }

    @Test("Deleting an organization scrubs membership links")
    func deleteScrubsMembership() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.organization = Wikilink(acme.id)
        #expect(store.update(marie))

        #expect(store.delete(kind: .organization, id: acme.id))
        #expect(store.snapshot.people[marie.id]?.organization == nil)
    }

    /// A project outlives the org that owned it — it just loses the owner link, rather than
    /// keeping one that points at nothing.
    @Test("Deleting an organization clears its projects' owner link")
    func deleteScrubsProjectOwner() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        let project = try #require(
            store.createProject(name: "Maillage", organization: Wikilink(acme.id)))

        #expect(store.delete(kind: .organization, id: acme.id))

        #expect(store.snapshot.projects[project.id] != nil)
        #expect(store.snapshot.projects[project.id]?.organization == nil)
    }

    /// A project belongs to one organization, so assigning a second replaces the first —
    /// otherwise it would show on two boards at once.
    @Test("Assigning a project to an organization replaces its previous owner")
    func projectOwnershipIsSingular() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        let globex = try #require(store.createOrganization(name: "Globex"))
        var project = try #require(
            store.createProject(name: "Maillage", organization: Wikilink(acme.id)))

        project.organization = Wikilink(globex.id)
        #expect(store.update(project))

        #expect(store.projects(inOrganization: acme.id).isEmpty)
        #expect(store.projects(inOrganization: globex.id).map(\.id) == [project.id])
    }

    // MARK: Robustness

    @Test("A malformed file is reported without blocking the rest of the vault")
    func malformedFileIsIsolated() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        _ = store.createPerson(firstname: "Marie", lastname: "Dupont")
        try "this file has no frontmatter at all".write(
            to: root.appendingPathComponent("people/broken.md"), atomically: true, encoding: .utf8)

        let reloaded = VaultStore(location: VaultLocation(root: root))
        reloaded.load()

        #expect(reloaded.allPeople.count == 1)
        #expect(reloaded.snapshot.issues.count == 1)
        #expect(reloaded.snapshot.issues.first?.path == "broken.md")
    }

    @Test("Filename wins when frontmatter id disagrees")
    func filenameIsAuthoritative() throws {
        let (store, root) = try makeStore(prefix: "maillage-tests")
        defer { cleanUp(root) }

        try location(root, "people/actual-name.md")
            .write(
                contents: """
                    ---
                    id: some-other-id
                    type: person
                    firstname: Marie
                    ---
                    """)

        let reloaded = VaultStore(location: VaultLocation(root: root))
        reloaded.load()

        #expect(reloaded.snapshot.people["actual-name"] != nil)
        #expect(reloaded.snapshot.people["some-other-id"] == nil)
        _ = store
    }
}

// MARK: - Helpers

private struct FileHandleAt {
    let url: URL
    func write(contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

private func location(_ root: URL, _ relativePath: String) -> FileHandleAt {
    FileHandleAt(url: root.appendingPathComponent(relativePath))
}
