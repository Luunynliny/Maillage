import Foundation
import Yams

/// Reads `.maillage/config.yaml` and `.maillage/vocabulary.txt` — the two small, optional files
/// backing transcription config. Both are absent in most vaults, which is the normal state, not
/// an issue, so every read here degrades to a sensible default rather than throwing.
public enum VaultConfig {
    /// The WhisperKit model variant to use, from `config.yaml`'s `whisperModel:` key.
    public static func whisperModel(
        at location: VaultLocation, default fallback: String = "large-v3"
    ) -> String {
        guard let data = try? String(contentsOf: location.configFileURL, encoding: .utf8),
            let yaml = try? Yams.load(yaml: data) as? [String: Any],
            let model = yaml["whisperModel"] as? String, !model.isEmpty
        else { return fallback }
        return model
    }

    /// One term per line, blank lines and `#`-comments skipped.
    public static func vocabularyTerms(at location: VaultLocation) -> [String] {
        guard let contents = try? String(contentsOf: location.vocabularyFileURL, encoding: .utf8)
        else { return [] }
        return contents.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
