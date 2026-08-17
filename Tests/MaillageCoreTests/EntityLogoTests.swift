import AppKit
import Foundation
import Testing

@testable import MaillageCore

/// A one-pixel square of `color`, already in the stored format — enough to be a logo without
/// exercising ``ImageSquarer``, which has its own suite.
private func pngData(_ color: NSColor) throws -> Data {
    let image = NSImage(size: CGSize(width: 1, height: 1))
    image.lockFocus()
    color.setFill()
    NSRect(x: 0, y: 0, width: 1, height: 1).fill()
    image.unlockFocus()
    return try #require(ImageSquarer.squarePNG(from: image))
}

/// Logos are files, not frontmatter — so what these tests check is mostly what happens to a file
/// when the entity it is named after moves, is deleted, or shares its id with something of
/// another kind.
@MainActor
@Suite("Entity logos")
struct EntityLogoTests {
    @Test("Setting a logo writes a PNG named after the entity")
    func writesTheFile() throws {
        let (store, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(store.setLogo(kind: .person, id: marie.id, pngData: try pngData(.red)))

        let file = root.appendingPathComponent("assets/people/marie-dupont.png")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(store.hasLogo(kind: .person, id: marie.id))
        #expect(store.logo(kind: .person, id: marie.id) != nil)

        // Nothing about it reaches the markdown: the file's presence is the only record.
        let markdown = try String(
            contentsOf: root.appendingPathComponent("people/marie-dupont.md"), encoding: .utf8)
        #expect(!markdown.contains("logo"))
    }

    /// The invariant the whole storage layout rests on. `availableID` only checks one kind's
    /// folder, so a person and a project can both be `acme` — a flat asset folder would give
    /// them one file between them.
    @Test("Ids that collide across kinds get separate logos")
    func partitionsByKind() throws {
        let (store, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        let person = try #require(store.createPerson(firstname: "Acme", lastname: nil))
        let project = try #require(store.createProject(name: "Acme"))
        // The premise: the same id in two kinds.
        #expect(person.id == project.id)

        #expect(store.setLogo(kind: .person, id: person.id, pngData: try pngData(.red)))
        #expect(store.setLogo(kind: .project, id: project.id, pngData: try pngData(.blue)))

        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("assets/people/acme.png").path))
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("assets/projects/acme.png").path))

        // And removing one leaves the other alone, which a shared file could not manage.
        #expect(store.removeLogo(kind: .person, id: person.id))
        #expect(!store.hasLogo(kind: .person, id: person.id))
        #expect(store.hasLogo(kind: .project, id: project.id))
    }

    @Test("Removing a logo deletes the file")
    func removesTheFile() throws {
        let (store, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        #expect(store.setLogo(kind: .organization, id: acme.id, pngData: try pngData(.blue)))
        #expect(store.removeLogo(kind: .organization, id: acme.id))

        let file = root.appendingPathComponent("assets/organizations/acme-corp.png")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!store.hasLogo(kind: .organization, id: acme.id))
        #expect(store.logo(kind: .organization, id: acme.id) == nil)
    }

    /// The filename is the identity, so a rename that left the logo behind would orphan the file
    /// *and* silently blank the avatar.
    @Test("Renaming an entity carries its logo across")
    func renameCarriesTheLogo() throws {
        let (store, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        #expect(store.setLogo(kind: .person, id: jean.id, pngData: try pngData(.green)))

        #expect(store.renameEntity(kind: .person, from: jean.id, to: "jean-martin-renamed") != nil)

        let fm = FileManager.default
        #expect(
            !fm.fileExists(
                atPath: root.appendingPathComponent("assets/people/jean-martin.png").path))
        #expect(
            fm.fileExists(
                atPath: root.appendingPathComponent("assets/people/jean-martin-renamed.png").path))
        #expect(!store.hasLogo(kind: .person, id: jean.id))
        #expect(store.hasLogo(kind: .person, id: "jean-martin-renamed"))
        #expect(store.logo(kind: .person, id: "jean-martin-renamed") != nil)
    }

    /// The sharpest version of the rename case: `_head-of-aa` becomes a real slug, and the face
    /// you had before you had the name has to survive it.
    @Test("Resolving a placeholder carries its logo to the real id")
    func resolvingCarriesTheLogo() throws {
        let (store, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        let head = try #require(
            store.createPerson(descriptor: "Head of AA", placeholder: true))
        #expect(store.setLogo(kind: .person, id: head.id, pngData: try pngData(.orange)))

        let resolved = try #require(
            store.resolvePlaceholder(head.id, firstname: "Alice", lastname: "Bernard"))

        #expect(resolved.id == "alice-bernard")
        #expect(store.hasLogo(kind: .person, id: resolved.id))
        #expect(!store.hasLogo(kind: .person, id: head.id))
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("assets/people/alice-bernard.png").path))
    }

    /// An orphaned asset would be inherited as their own avatar by a later entity that reused
    /// the id — `marie-dupont` deleted and re-added would come back wearing the old logo.
    @Test("Deleting an entity deletes its logo")
    func deleteRemovesTheLogo() throws {
        let (store, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(store.setLogo(kind: .person, id: marie.id, pngData: try pngData(.red)))
        #expect(store.delete(kind: .person, id: marie.id))

        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("assets/people/marie-dupont.png").path))
        #expect(!store.hasLogo(kind: .person, id: marie.id))

        // The id is free again, and comes back without a logo.
        let again = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(again.id == marie.id)
        #expect(!store.hasLogo(kind: .person, id: again.id))
    }

    /// Derived, not declared: dropping a PNG into `assets/` in Finder is how the vault stays a
    /// plain folder you can edit by hand, exactly as backlinks are derived from other files.
    @Test("A hand-placed PNG is picked up on load")
    func derivesFromDisk() throws {
        let (store, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(!store.hasLogo(kind: .person, id: marie.id))

        try pngData(.purple).write(
            to: root.appendingPathComponent("assets/people/marie-dupont.png"))
        store.load()

        #expect(store.hasLogo(kind: .person, id: marie.id))
        #expect(store.logo(kind: .person, id: marie.id) != nil)
    }

    /// *A malformed file is an issue, not a crash*, applied to assets: the avatar falls back to
    /// its glyph rather than the view trapping on a decode that failed.
    @Test("A PNG that won't decode reads as no logo rather than crashing")
    func toleratesACorruptFile() throws {
        let (store, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        try Data("not really a PNG".utf8).write(
            to: root.appendingPathComponent("assets/people/marie-dupont.png"))
        store.load()

        // Present as a file, so the index says yes — but undecodable, so there is no image.
        #expect(store.hasLogo(kind: .person, id: marie.id))
        #expect(store.logo(kind: .person, id: marie.id) == nil)
    }

    @Test("Replacing a logo shows the new image, not the cached one")
    func replacingInvalidatesTheCache() throws {
        let (store, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        let acme = try #require(store.createOrganization(name: "Acme Corp"))
        #expect(store.setLogo(kind: .organization, id: acme.id, pngData: try pngData(.red)))
        let first = try #require(store.logo(kind: .organization, id: acme.id))

        #expect(store.setLogo(kind: .organization, id: acme.id, pngData: try pngData(.blue)))
        let second = try #require(store.logo(kind: .organization, id: acme.id))

        // Different bytes behind the same id: the memo has to have been dropped.
        #expect(first.tiffRepresentation != second.tiffRepresentation)
    }

    @Test("A vault skeleton includes an asset folder per logo-supporting kind")
    func createsAssetDirectories() throws {
        let (_, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        for kind in EntityKind.allCases where kind.supportsLogo {
            let directory = root.appendingPathComponent("assets/\(kind.directoryName)")
            var isDirectory: ObjCBool = false
            #expect(
                FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
    }

    @Test("A kind with no logos of its own gets no asset folder")
    func skipsAssetDirectoryForMeetings() throws {
        let (_, root) = try makeStore(prefix: "maillage-logo-tests")
        defer { cleanUp(root) }

        #expect(!EntityKind.meeting.supportsLogo)
        let directory = root.appendingPathComponent("assets/meetings")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
