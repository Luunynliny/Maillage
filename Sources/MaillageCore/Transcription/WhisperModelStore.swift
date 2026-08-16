import Foundation
import WhisperKit

/// Resolves the WhisperKit model bundled inside the running app and loads it.
///
/// The model — `large-v3-turbo`, the compressed (~632MB) variant, chosen over the smaller
/// `small_216MB` this app used previously because its accuracy is far closer to what the prior
/// FluidAudio-based attempts delivered, and the size difference barely matters next to the
/// ~600MB-1GB models this app has already shipped through this whole saga — is fetched at
/// *build* time by `Scripts/fetch-whisper-model.sh` (see the "Fetch WhisperKit Model" build phase
/// in `maillage.xcodeproj`) and lands at
/// `Maillage.app/Contents/Resources/WhisperKitModel/large-v3-turbo`. Never downloaded at runtime:
/// there is no network dependency, no progress to report, and no partial-download failure mode to
/// guard against — the model is either present in the signed bundle, in which case loading it
/// cannot meaningfully fail from anything this type controls, or the bundle itself is broken,
/// which is a build problem, not a runtime one.
public final class WhisperModelStore {
    public init() {}

    public func loadWhisperKit() async throws -> WhisperKit {
        guard
            let modelFolder = Bundle.main.resourceURL?
                .appendingPathComponent("WhisperKitModel/large-v3-turbo")
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
