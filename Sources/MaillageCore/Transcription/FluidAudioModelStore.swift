import FluidAudio
import Foundation

/// Resolves the FluidAudio models bundled inside the running app and loads them.
///
/// The streaming ASR model — Nemotron Speech Streaming Multilingual, "latin" ship (shared
/// vocabulary across en/es/fr/it/pt/de, so French sentences with English technical terms decode
/// as one language), 2240ms chunk tier (FluidAudio's documented recommended default) — is fetched
/// at *build* time by `Scripts/fetch-fluidaudio-asr-model.sh` (see the "Fetch FluidAudio ASR
/// Model" build phase in `maillage.xcodeproj`) and lands at
/// `Maillage.app/Contents/Resources/FluidAudioModels/nemotron-multilingual-latin-2240ms/`. Never
/// downloaded at runtime: `ModelHub.offlineMode` is set once, at launch (see `MaillageApp`), so
/// any code path that would otherwise reach for the network throws instead of silently fetching.
public final class FluidAudioModelStore {
    public init() {}

    /// Set once, at launch, before anything touches FluidAudio's loader — kept here rather than
    /// requiring `Maillage` (the app target) to `import FluidAudio` itself just for this one
    /// flag, so that target never needs to depend on a model library directly.
    public static func enableOfflineMode() {
        ModelHub.offlineMode = true
    }

    public func loadStreamingASR() async throws -> StreamingNemotronMultilingualAsrManager {
        guard
            let modelsDirectory = Bundle.main.resourceURL?
                .appendingPathComponent("FluidAudioModels/nemotron-multilingual-latin-2240ms")
        else {
            throw FluidAudioModelStoreError.bundledModelMissing
        }
        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadModels(from: modelsDirectory)
        return manager
    }
}

public enum FluidAudioModelStoreError: Error, LocalizedError {
    case bundledModelMissing

    public var errorDescription: String? {
        "The FluidAudio ASR model isn't in this build — run Scripts/fetch-fluidaudio-asr-model.sh and rebuild."
    }
}
