import Foundation
import Testing

@testable import MaillageCore

/// Each test gets a throwaway vault directory under the system temp folder.
@MainActor
private func makeStore() throws -> (store: VaultStore, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("maillage-tests-\(UUID().uuidString)", isDirectory: true)
    let store = VaultStore(location: VaultLocation(root: root))
    store.load()
    return (store, root)
}

private func cleanUp(_ root: URL) {
    try? FileManager.default.removeItem(at: root)
}

@MainActor
@Suite("Vault store")
struct VaultStoreTests {
    @Test("Creates a person and writes a markdown file")
    func createsPerson() throws {
        let (store, root) = try makeStore()
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
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let person = try #require(store.createPerson(firstname: "Zoé", lastname: "Müller"))
        #expect(person.id == "zoe-muller")
    }

    @Test("Disambiguates duplicate names instead of overwriting")
    func disambiguatesDuplicates() throws {
        let (store, root) = try makeStore()
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
        let (store, root) = try makeStore()
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
        let (store, root) = try makeStore()
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
        let (store, root) = try makeStore()
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

    @Test("Reloading from disk reproduces the same state")
    func reloadsFromDisk() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        let acme = try #require(store.createOrganization(name: "Acme Corp", domain: "acme.com"))
        #expect(store.addRelation(from: marie.id, to: jean.id, label: "manager of"))

        var updated = try #require(store.snapshot.people[marie.id])
        updated.organizations = [Wikilink(acme.id)]
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
        let (store, root) = try makeStore()
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
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("people/jean-martin.md").path))
    }

    @Test("Renaming an organization rewrites membership links")
    func renameRewritesMembership() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.organizations = [Wikilink(acme.id)]
        #expect(store.update(marie))

        #expect(store.renameEntity(kind: .organization, from: acme.id, to: "acme-global") != nil)

        #expect(store.snapshot.people[marie.id]?.organizations == [Wikilink("acme-global")])
        #expect(store.members(ofOrganization: "acme-global").count == 1)
    }

    // MARK: Placeholders

    @Test("Creates a placeholder person with no name")
    func createsPlaceholder() throws {
        let (store, root) = try makeStore()
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

    @Test("Resolving a placeholder renames the file and keeps inbound links intact")
    func resolvesPlaceholder() throws {
        let (store, root) = try makeStore()
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
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("people/_head-of-aa.md").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("people/alice-bernard.md").path))
    }

    // MARK: Deletion

    @Test("Deleting a person scrubs relations pointing at them")
    func deleteScrubsRelations() throws {
        let (store, root) = try makeStore()
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
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        var marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        marie.organizations = [Wikilink(acme.id)]
        #expect(store.update(marie))

        #expect(store.delete(kind: .organization, id: acme.id))
        #expect(store.snapshot.people[marie.id]?.organizations.isEmpty == true)
    }

    // MARK: Robustness

    @Test("A malformed file is reported without blocking the rest of the vault")
    func malformedFileIsIsolated() throws {
        let (store, root) = try makeStore()
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
        let (store, root) = try makeStore()
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
