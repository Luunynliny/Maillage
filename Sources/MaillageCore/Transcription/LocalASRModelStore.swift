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
/// `Qwen3ASRModel.fromPretrained` and `SileroVADModel.fromPretrained`. Both repos publish a file
/// literally named `model.safetensors` (and `config.json`) — sharing a directory is a flat
/// filename collision, not an ambiguity, and the second download would clobber the first. Loading
/// each model separately with its own bundled folder, then handing both to ``StreamingASR``'s
/// memberwise initializer, sidesteps that entirely and mirrors how ``WhisperModelStore`` and
/// `LocalLLMModelStore` each get their own resource subdirectory.
public final class LocalASRModelStore {
    /// The exact repos `Scripts/fetch-asr-model.sh` downloads (`asr_repo`/`vad_repo` there) —
    /// hardcoded here rather than read from `Qwen3ASRModel.defaultModelId`/
    /// `SileroVADModel.defaultModelId`. `fromPretrained` derives the model's *architecture* (size,
    /// quantization bits) from this string alone, not from `config.json`, and applies weights with
    /// no verification that they match — so if a future `speech-swift` release moves its library
    /// default (e.g. to the 1.7B model) while the bundled weights on disk are still whatever this
    /// build's fetch script downloaded, following the library default here would silently build a
    /// differently-shaped model over mismatched weights instead of failing to load. These two
    /// literals and the fetch script's are one fact with two copies — keep them in sync by hand.
    private static let asrModelID = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
    private static let vadModelID = "aufklarer/Silero-VAD-v6.2.1-MLX"

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

        // `offlineMode`'s own completeness check (`HuggingFaceDownloader.weightsExist`) only looks
        // for a `.safetensors` file — it never checks `vocab.json`. Read directly from
        // `Qwen3ASRModel.fromPretrained`: the tokenizer load is conditional with no `else` and no
        // throw, so a missing `vocab.json` doesn't fail the load, it just leaves the model
        // tokenizer-less — and `generateText` then falls through to returning raw token IDs
        // ("15043 1247 8891 …") as if that were a transcript, with no error anywhere in the path.
        // Verified today by the fetch script always downloading `vocab.json` alongside the
        // weights; checked explicitly here too so an upstream layout change (say, `vocab.json`
        // renamed) fails loudly at load time instead of writing token-ID garbage into someone's
        // meeting transcript.
        let fm = FileManager.default
        guard
            fm.fileExists(atPath: asrDirectory.appendingPathComponent("vocab.json").path),
            fm.fileExists(atPath: asrDirectory.appendingPathComponent("model.safetensors").path),
            fm.fileExists(atPath: vadDirectory.appendingPathComponent("model.safetensors").path)
        else {
            throw LocalASRModelStoreError.bundledModelMissing
        }

        let asrModel = try await Qwen3ASRModel.fromPretrained(
            modelId: Self.asrModelID, cacheDir: asrDirectory, offlineMode: true)
        let vadModel = try await SileroVADModel.fromPretrained(
            modelId: Self.vadModelID, cacheDir: vadDirectory, offlineMode: true)
        return StreamingASR(asrModel: asrModel, vadModel: vadModel)
    }
}

public enum LocalASRModelStoreError: Error, LocalizedError {
    case bundledModelMissing

    public var errorDescription: String? {
        "The local ASR model isn't in this build — run Scripts/fetch-asr-model.sh and rebuild."
    }
}
