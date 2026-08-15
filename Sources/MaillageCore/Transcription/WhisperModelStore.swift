import Foundation
import WhisperKit

/// Resolves the WhisperKit model bundled inside the running app and loads it.
///
/// The model — `openai_whisper-small`, the smallest WhisperKit variant with usable multilingual
/// and code-switching accuracy — is fetched at *build* time by `Scripts/fetch-whisper-model.sh`
/// (see the "Fetch WhisperKit Model" build phase in `maillage.xcodeproj`) and lands at
/// `Maillage.app/Contents/Resources/WhisperKitModel/openai_whisper-small_216MB`. Never downloaded
/// at runtime: there is no network dependency, no progress to report, and no partial-download
/// failure mode to guard against — the model is either present in the signed bundle, in which
/// case loading it cannot meaningfully fail from anything this type controls, or the bundle
/// itself is broken, which is a build problem, not a runtime one.
public final class WhisperModelStore {
    public init() {}

    public func loadWhisperKit() async throws -> WhisperKit {
        guard
            let modelFolder = Bundle.main.resourceURL?
                .appendingPathComponent("WhisperKitModel/openai_whisper-small_216MB")
        else {
            throw WhisperModelStoreError.bundledModelMissing
        }
        return try await WhisperKit(modelFolder: modelFolder.path, load: true, download: false)
    }
}

public enum WhisperModelStoreError: Error, LocalizedError {
    case bundledModelMissing

    public var errorDescription: String? {
        "The WhisperKit model isn't in this build — run Scripts/fetch-whisper-model.sh and rebuild."
    }
}
