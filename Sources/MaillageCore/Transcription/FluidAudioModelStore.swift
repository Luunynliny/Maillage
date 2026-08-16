import CoreML
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

    /// Sortformer's `fastV2_1` config — the lowest-latency of FluidAudio's streaming tiers
    /// (~1s inherent lag from its right-context window), fetched at build time by
    /// `Scripts/fetch-fluidaudio-diarizer-model.sh` and landing at
    /// `Maillage.app/Contents/Resources/FluidAudioModels/sortformer-fastv2.1-fp16/`.
    ///
    /// Loads the compiled `.mlmodelc` directly via `MLModel.load(contentsOf:)` — Apple's own
    /// compile-if-needed loader — rather than `SortformerModels.load(mainModelPath:)`, which
    /// always recompiles from an uncompiled `.mlpackage` and would choke on the pre-compiled
    /// bundle this app ships.
    public func loadStreamingDiarizer() async throws -> SortformerDiarizer {
        guard
            let modelURL = Bundle.main.resourceURL?
                .appendingPathComponent(
                    "FluidAudioModels/sortformer-fastv2.1-fp16/Sortformer_v2.1.mlmodelc")
        else {
            throw FluidAudioModelStoreError.bundledDiarizerModelMissing
        }
        let config = SortformerConfig.fastV2_1
        let mainModel = try await MLModel.load(
            contentsOf: modelURL, configuration: MLModelConfiguration())
        let models = try SortformerModels(config: config, main: mainModel)
        let diarizer = SortformerDiarizer(config: config)
        diarizer.initialize(models: models)
        return diarizer
    }
}

public enum FluidAudioModelStoreError: Error, LocalizedError {
    case bundledModelMissing
    case bundledDiarizerModelMissing

    public var errorDescription: String? {
        switch self {
        case .bundledModelMissing:
            "The FluidAudio ASR model isn't in this build — run Scripts/fetch-fluidaudio-asr-model.sh and rebuild."
        case .bundledDiarizerModelMissing:
            "The FluidAudio diarizer model isn't in this build — run Scripts/fetch-fluidaudio-diarizer-model.sh and rebuild."
        }
    }
}
