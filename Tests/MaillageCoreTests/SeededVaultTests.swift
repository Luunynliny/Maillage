import Foundation
import Testing

@testable import MaillageCore

/// Reads the hand-written vault at `~/Documents/Maillage` if it exists, proving the
/// app agrees with the format documented for humans editing files directly.
///
/// Skipped when there is no vault, so the suite stays green on a clean machine.
@MainActor
@Suite("Seeded vault")
struct SeededVaultTests {
    @Test("Loads the hand-written seed vault with derived backlinks")
    func loadsSeedVault() throws {
        let location = VaultLocation.default
        try #require(
            FileManager.default.fileExists(
                atPath: location.fileURL(kind: .person, id: "marie-dupont").path),
            "no seeded vault present")

        let store = VaultStore(location: location)
        store.load()

        #expect(store.snapshot.issues.isEmpty)

        let marie = try #require(store.snapshot.people["marie-dupont"])
        #expect(marie.displayName == "Marie Dupont")
        #expect(marie.email == "marie@example.com")
        #expect(marie.organizations.map(\.id) == ["acme-corp"])
        #expect(marie.relations.count == 2)
        #expect(marie.body == "Met at the Paris conference.")

        // Jean stores nothing, yet sees Marie's relation as a backlink.
        let jean = try #require(store.snapshot.people["jean-martin"])
        #expect(jean.relations.isEmpty)
        #expect(store.backlinks(for: "jean-martin") == [Backlink(from: "marie-dupont", label: "manager of")])

        // The placeholder has no name but still shows a usable label.
        let placeholder = try #require(store.snapshot.people["_head-of-aa"])
        #expect(placeholder.placeholder)
        #expect(placeholder.displayName == "Head of AA")

        #expect(store.members(ofOrganization: "acme-corp").map(\.id) == ["jean-martin", "marie-dupont"])
        #expect(store.projects(inOrganization: "acme-corp").map(\.id) == ["maillage"])
        #expect(store.members(ofProject: "maillage").map(\.id) == ["marie-dupont"])
    }
}
