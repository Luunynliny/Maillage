import Foundation

/// Reads `.maillage/vocabulary.txt` — custom transcription vocabulary. Absent in most vaults,
/// which is the normal state, not an issue, so a missing file degrades to an empty list rather
/// than throwing.
public enum VaultConfig {
    /// One term per line, blank lines and `#`-comments skipped.
    public static func vocabularyTerms(at location: VaultLocation) -> [String] {
        guard let contents = try? String(contentsOf: location.vocabularyFileURL, encoding: .utf8)
        else { return [] }
        return contents.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
