import Foundation
import WhisperKit

/// Owns first-run model download and load. The model variant (default `large-v3`) is resolved
/// by the caller from `.maillage/config.yaml` via ``VaultConfig`` — this type stays free of YAML
/// parsing, and only knows the variant string it was asked for.
///
/// "Download interrupted" is handled by never loading what didn't finish, rather than by
/// resuming or cleaning up a partial download ourselves: `WhisperKit(modelFolder:)` is only ever
/// constructed after `WhisperKit.download` returns successfully, so a half-downloaded CoreML
/// model — which would load and produce garbage rather than fail loudly, the worst failure mode
/// available — is never constructed in the first place. A failed download simply throws;
/// retrying calls `download` again, which resumes or redoes its own snapshot.
public final class WhisperModelStore {
    private let variant: String
    private let downloadBase: URL?

    public init(variant: String, downloadBase: URL? = nil) {
        self.variant = variant
        self.downloadBase = downloadBase
    }

    /// - Parameter onProgress: Download fraction complete, `0...1`. Loading the downloaded model
    ///   has no incremental progress of its own to report, so this only fires during download.
    public func loadWhisperKit(
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> WhisperKit {
        let modelFolder = try await WhisperKit.download(
            variant: variant, downloadBase: downloadBase
        ) { progress in
            onProgress(progress.fractionCompleted)
        }
        return try await WhisperKit(modelFolder: modelFolder.path, load: true)
    }
}
