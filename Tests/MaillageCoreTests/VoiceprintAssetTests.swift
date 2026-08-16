import Foundation
import Testing

@testable import MaillageCore

@MainActor
private func makeStore() throws -> (store: VaultStore, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("maillage-voiceprint-tests-\(UUID().uuidString)", isDirectory: true)
    let store = VaultStore(location: VaultLocation(root: root))
    store.load()
    return (store, root)
}

private func cleanUp(_ root: URL) {
    try? FileManager.default.removeItem(at: root)
}

/// A voiceprint is a file, not frontmatter — same shape as ``EntityLogoTests``, just for
/// `assets/people/<id>.voiceprint` instead of `.png`, and people-only since only a person is
/// ever diarized against.
@MainActor
@Suite("Voiceprint assets")
struct VoiceprintAssetTests {
    @Test("Setting a voiceprint writes a JSON file named after the person")
    func writesTheFile() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(
            store.setVoiceprint(personID: marie.id, samples: [0.1, 0.2, 0.3], sampleRate: 16_000))

        let file = root.appendingPathComponent("assets/people/marie-dupont.voiceprint")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(store.hasVoiceprint(personID: marie.id))
        #expect(store.voiceprint(personID: marie.id)?.samples == [0.1, 0.2, 0.3])

        // Nothing about it reaches the markdown: the file's presence is the only record.
        let markdown = try String(
            contentsOf: root.appendingPathComponent("people/marie-dupont.md"), encoding: .utf8)
        #expect(!markdown.contains("voiceprint"))
    }

    @Test("A second confirmation replaces the stored sample outright")
    func secondConfirmationReplaces() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(store.setVoiceprint(personID: marie.id, samples: [0.1], sampleRate: 16_000))
        #expect(store.setVoiceprint(personID: marie.id, samples: [0.2, 0.3], sampleRate: 16_000))

        let voiceprint = try #require(store.voiceprint(personID: marie.id))
        #expect(voiceprint.samples == [0.2, 0.3])
    }

    @Test("Removing a voiceprint deletes the file")
    func removesTheFile() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(store.setVoiceprint(personID: marie.id, samples: [0.1], sampleRate: 16_000))
        #expect(store.removeVoiceprint(personID: marie.id))

        let file = root.appendingPathComponent("assets/people/marie-dupont.voiceprint")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!store.hasVoiceprint(personID: marie.id))
        #expect(store.voiceprint(personID: marie.id) == nil)
    }

    /// The filename is the identity, so a rename that left the voiceprint behind would orphan
    /// the file and silently drop a person's enrolled voice.
    @Test("Renaming a person carries their voiceprint across")
    func renameCarriesTheVoiceprint() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let jean = try #require(store.createPerson(firstname: "Jean", lastname: "Martin"))
        #expect(store.setVoiceprint(personID: jean.id, samples: [0.1], sampleRate: 16_000))

        #expect(store.renameEntity(kind: .person, from: jean.id, to: "jean-martin-renamed") != nil)

        let fm = FileManager.default
        #expect(
            !fm.fileExists(
                atPath: root.appendingPathComponent("assets/people/jean-martin.voiceprint").path))
        #expect(
            fm.fileExists(
                atPath: root.appendingPathComponent(
                    "assets/people/jean-martin-renamed.voiceprint"
                ).path))
        #expect(!store.hasVoiceprint(personID: jean.id))
        #expect(store.hasVoiceprint(personID: "jean-martin-renamed"))
    }

    /// An orphaned asset would be inherited as someone else's voice by a later person who reuses
    /// the id — the same reasoning as a logo, just for a biometric-adjacent file, where it
    /// matters more.
    @Test("Deleting a person deletes their voiceprint")
    func deleteRemovesTheVoiceprint() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(store.setVoiceprint(personID: marie.id, samples: [0.1], sampleRate: 16_000))
        #expect(store.delete(kind: .person, id: marie.id))

        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("assets/people/marie-dupont.voiceprint").path)
        )
        #expect(!store.hasVoiceprint(personID: marie.id))

        // The id is free again, and comes back with no inherited voice.
        let again = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(again.id == marie.id)
        #expect(!store.hasVoiceprint(personID: again.id))
    }

    /// Derived, not declared — dropping a `.voiceprint` file into `assets/` by hand works, the
    /// same as a hand-placed logo.
    @Test("A hand-placed voiceprint file is picked up on load")
    func derivesFromDisk() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        #expect(!store.hasVoiceprint(personID: marie.id))

        let voiceprint = Voiceprint(samples: [0.1, 0.2, 0.3], sampleRate: 16_000)
        try JSONEncoder().encode(voiceprint).write(
            to: root.appendingPathComponent("assets/people/marie-dupont.voiceprint"))
        store.load()

        #expect(store.hasVoiceprint(personID: marie.id))
        #expect(store.voiceprint(personID: marie.id) == voiceprint)
    }

    /// *A malformed file is an issue, not a crash*, applied to voiceprints.
    @Test("A voiceprint file that won't decode reads as none rather than crashing")
    func toleratesACorruptFile() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(root) }

        let marie = try #require(store.createPerson(firstname: "Marie", lastname: "Dupont"))
        try Data("not really json".utf8).write(
            to: root.appendingPathComponent("assets/people/marie-dupont.voiceprint"))
        store.load()

        // Present as a file, so the index says yes — but undecodable, so there is no voiceprint.
        #expect(store.hasVoiceprint(personID: marie.id))
        #expect(store.voiceprint(personID: marie.id) == nil)
    }
}
