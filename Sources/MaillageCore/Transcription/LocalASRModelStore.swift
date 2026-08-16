import AudioCommon
import Foundation
import Qwen3ASR
import SpeechVAD

/// Resolves the Qwen3-ASR and Silero VAD models bundled inside the running app and loads both,
/// wiring them into a ``StreamingASR`` — `speech-swift`'s VAD-guided ASR pipeline.
///
/// Fetched at *build* time by `Scripts/fetch-asr-model.sh` (see the "Fetch ASR Model" build phase
/// in `maillage.xcodeproj`) and lands at `Maillage.app/Contents/Resources/ASRModel/`, in two
/// sibling folders — `qwen3-asr-0.6b-mlx-4bit` and `silero-vad-mlx`. Never downloaded at runtime:
/// both loads below pass `offlineMode: true`, which — read directly from
/// `HuggingFaceDownloader.downloadWeights` in `speech-swift`'s `AudioCommon` target — short-circuits
/// to a local completeness check (does `cacheDir` already contain a `.safetensors` file, and does
/// every shard a `model.safetensors.index.json` names exist) and throws rather than ever reaching
/// the network.
///
/// Two folders, not one, despite `StreamingASR.fromPretrained(cacheDir:)` accepting a single
/// directory: that convenience initializer forwards the *same* `cacheDir` to both
/// `Qwen3ASRModel.fromPretrained` and `SileroVADModel.fromPretrained`, which would download both
/// models' `.safetensors` files into one flat folder and — since each model's own weight loader
/// only recognises its own key prefixes but still treats *every* `.safetensors` file in the
/// directory as a shard to scan — makes the "is the cache complete" check ambiguous between the
/// two models the moment they share a directory. Loading each model separately with its own
/// bundled folder, then handing both to ``StreamingASR``'s memberwise initializer, sidesteps that
/// entirely and mirrors how ``WhisperModelStore`` and `LocalLLMModelStore` each get their own
/// resource subdirectory.
public final class LocalASRModelStore {
    public init() {}

    public func loadStreamingASR() async throws -> StreamingASR {
        guard
            let asrDirectory = Bundle.main.resourceURL?
                .appendingPathComponent("ASRModel/qwen3-asr-0.6b-mlx-4bit"),
            let vadDirectory = Bundle.main.resourceURL?
                .appendingPathComponent("ASRModel/silero-vad-mlx")
        else {
            throw LocalASRModelStoreError.bundledModelMissing
        }

        let asrModel = try await Qwen3ASRModel.fromPretrained(
            modelId: Qwen3ASRModel.defaultModelId, cacheDir: asrDirectory, offlineMode: true)
        let vadModel = try await SileroVADModel.fromPretrained(
            modelId: SileroVADModel.defaultModelId, cacheDir: vadDirectory, offlineMode: true)
        return StreamingASR(asrModel: asrModel, vadModel: vadModel)
    }
}

public enum LocalASRModelStoreError: Error, LocalizedError {
    case bundledModelMissing

    public var errorDescription: String? {
        "The local ASR model isn't in this build — run Scripts/fetch-asr-model.sh and rebuild."
    }
}
