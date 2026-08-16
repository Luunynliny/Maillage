import FluidAudio
import Foundation

/// Resolves the FluidAudio models bundled inside the running app and loads them.
///
/// The batch ASR model — Parakeet TDT 0.6B v3, FluidAudio's CoreML port, int8 encoder — handles
/// French/English code-switching mid-meeting with no per-call fixed-language lock, unlike the
/// alternative Cohere pipeline. Fetched at *build* time by `Scripts/fetch-fluidaudio-asr-model.sh`
/// (see the "Fetch FluidAudio ASR Model" build phase in `maillage.xcodeproj`) and lands at
/// `Maillage.app/Contents/Resources/FluidAudioModels/parakeet-tdt-0.6b-v3/`. Never downloaded at
/// runtime: `ModelHub.offlineMode` is set once, at launch (see `MaillageApp`), so any code path
/// that would otherwise reach for the network throws instead of silently fetching.
public final class FluidAudioModelStore {
    public init() {}

    /// Set once, at launch, before anything touches FluidAudio's loader — kept here rather than
    /// requiring `Maillage` (the app target) to `import FluidAudio` itself just for this one
    /// flag, so that target never needs to depend on a model library directly.
    public static func enableOfflineMode() {
        ModelHub.offlineMode = true
    }

    /// Loads the bundled Parakeet models and wraps them in a fresh `AsrManager`, ready for one
    /// track's batch transcription. `AsrModels.load(from:)` is the same bundled-directory,
    /// offline-only pattern already used for the streaming model this replaces.
    public func loadBatchASR() async throws -> AsrManager {
        guard
            let modelsDirectory = Bundle.main.resourceURL?
                .appendingPathComponent("FluidAudioModels/parakeet-tdt-0.6b-v3")
        else {
            throw FluidAudioModelStoreError.bundledModelMissing
        }
        let models = try await AsrModels.load(from: modelsDirectory)
        return AsrManager(models: models)
    }
}

public enum FluidAudioModelStoreError: Error, LocalizedError {
    case bundledModelMissing

    public var errorDescription: String? {
        switch self {
        case .bundledModelMissing:
            "The FluidAudio ASR model isn't in this build — run Scripts/fetch-fluidaudio-asr-model.sh and rebuild."
        }
    }
}
