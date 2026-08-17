import Foundation
import Testing

@testable import MaillageCore

@Suite("Prompt template loading, fallback and seeding")
struct PromptTemplateStoreTests {
    private func withTempVault(_ body: (VaultLocation) throws -> Void) rethrows {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("maillage-prompt-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(VaultLocation(root: root))
    }

    @Test("No file on disk yet: returns the built-in default")
    func fallsBackToDefault() throws {
        try withTempVault { location in
            let text = PromptTemplateStore.load(.cleanup, location: location)
            #expect(text == PromptTemplate.cleanup.defaultText)
        }
    }

    @Test("No file on disk yet: seeds the vault with the default so it's there to edit next time")
    func seedsDefaultFile() throws {
        try withTempVault { location in
            _ = PromptTemplateStore.load(.summary, location: location)
            let url = location.promptURL(named: "summary")
            let onDisk = try String(contentsOf: url, encoding: .utf8)
            #expect(onDisk == PromptTemplate.summary.defaultText)
        }
    }

    @Test("An existing file's content wins over the default")
    func existingContentWins() throws {
        try withTempVault { location in
            let url = location.promptURL(named: "cleanup")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "Custom cleanup instructions.".write(to: url, atomically: true, encoding: .utf8)

            let text = PromptTemplateStore.load(.cleanup, location: location)
            #expect(text == "Custom cleanup instructions.")
        }
    }

    @Test("Loading twice doesn't overwrite an edit made after the first seed")
    func doesNotReseedOverAnEdit() throws {
        try withTempVault { location in
            _ = PromptTemplateStore.load(.cleanup, location: location)
            let url = location.promptURL(named: "cleanup")
            try "Edited after first use.".write(to: url, atomically: true, encoding: .utf8)

            let text = PromptTemplateStore.load(.cleanup, location: location)
            #expect(text == "Edited after first use.")
        }
    }
}
