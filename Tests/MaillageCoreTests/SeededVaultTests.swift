import Foundation
import Testing

@testable import MaillageCore

/// Reads the hand-written example vault at `~/Documents/Maillage` if it exists, proving the
/// app agrees with the format documented for humans editing files directly.
///
/// The vault maps the Futurama cast — three employers, five projects, one placeholder — chosen
/// so every centre pane has something to draw: an org with people on no project, a project
/// with a member who has no role, and a relation crossing employers.
///
/// Skipped when there is no vault, so the suite stays green on a clean machine — CI included,
/// which never has one.
///
/// The skip is a `.enabled(if:)` trait rather than a `#require` in the body on purpose: a failed
/// `#require` *fails* the test, it does not skip it, so guarding this way is what actually keeps
/// a machine without a vault green.
@MainActor
@Suite("Seeded vault")
struct SeededVaultTests {
    /// Whether the hand-written vault is present. Evaluated once, before the test runs, because
    /// a trait's condition has to be answerable without the test body.
    static let hasSeededVault = FileManager.default.fileExists(
        atPath: VaultLocation.default.fileURL(kind: .person, id: "philip-fry").path)

    @Test(
        "Loads the hand-written example vault with derived backlinks",
        .enabled(if: hasSeededVault, "no seeded vault at ~/Documents/Maillage"))
    func loadsSeedVault() throws {
        let location = VaultLocation.default
        let store = VaultStore(location: location)
        store.load()

        #expect(store.snapshot.issues.isEmpty)

        let fry = try #require(store.snapshot.people["philip-fry"])
        #expect(fry.displayName == "Philip Fry")
        #expect(fry.email == "fry@planetexpress.com")
        #expect(fry.organization?.id == "planet-express")
        #expect(fry.relations.count == 4)

        // Leela stores one relation to Fry's four, yet sees his as a backlink — the inversion
        // is derived, and nothing was written to her file.
        let leela = try #require(store.snapshot.people["turanga-leela"])
        #expect(leela.relations.count == 2)
        #expect(
            store.backlinks(for: "turanga-leela") == [
                Backlink(from: "lord-nibbler", label: "adopted by"),
                Backlink(from: "philip-fry", label: "fiancé of"),
                Backlink(from: "zapp-brannigan", label: "ex-lover of"),
            ])

        // The placeholder has no name but still shows a usable label, and is the target of a
        // relation — the case placeholders exist for.
        let placeholder = try #require(store.snapshot.people["_head-of-legal-at-momcorp"])
        #expect(placeholder.placeholder)
        #expect(placeholder.displayName == "Head of Legal at MomCorp")

        #expect(
            store.members(ofOrganization: "planet-express").map(\.id) == [
                "amy-wong", "bender-rodriguez", "hermes-conrad", "hubert-farnsworth",
                "john-zoidberg", "lord-nibbler", "philip-fry", "turanga-leela",
            ])
        #expect(
            store.projects(inOrganization: "planet-express").map(\.id) == [
                "dark-matter-supply", "ship-refit", "slurm-factory-delivery",
            ])

        // Fry's `ship-refit` entry is a bare `"[[id]]"` rather than a `to:`/`role:` mapping, so
        // the roster has to render a member with no role beside the three that have one.
        let refit = store.participants(ofProject: "ship-refit")
        #expect(refit.map(\.person.id) == ["amy-wong", "bender-rodriguez", "philip-fry", "turanga-leela"])
        #expect(refit.map(\.role) == ["Engineer", "Bending", nil, "Pilot"])

        // Zoidberg is on staff and on nothing else, which is what the board's "On no project"
        // card is for.
        #expect(store.snapshot.people["john-zoidberg"]?.projects.isEmpty == true)

        // Logos are files, so every entity that has one is discovered by scanning `assets/`.
        #expect(store.logoIDs[.person]?.contains("philip-fry") == true)
        #expect(store.logoIDs[.organization]?.contains("planet-express") == true)
        #expect(store.logo(kind: .person, id: "philip-fry") != nil)
    }
}
