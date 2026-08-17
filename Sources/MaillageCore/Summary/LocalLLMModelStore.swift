import Foundation
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Resolves the local LLM bundled inside the running app and loads it — `Qwen2.5-1.5B-Instruct`,
/// already converted to MLX format, used for both transcript cleanup and meeting summarization.
///
/// Fetched at *build* time by `Scripts/fetch-llm-model.sh` (see the "Fetch LLM Model" build phase
/// in `maillage.xcodeproj`) and lands at
/// `Maillage.app/Contents/Resources/LLMModel/qwen2.5-1.5b-instruct-4bit`. Never downloaded at
/// runtime, mirroring ``WhisperModelStore``: `LLMModelFactory`'s local-directory overload of
/// `loadContainer` takes no `Downloader` at all, so there is no network path here to disable —
/// it simply doesn't exist for this call.
///
/// The tokenizer loader — `#huggingFaceTokenizerLoader()`, from `MLXHuggingFace` — reads
/// `tokenizer.json`/`tokenizer_config.json` straight out of the same local directory via
/// `swift-transformers`'s `AutoTokenizer.from(modelFolder:)`; nothing here is Hub-specific despite
/// the macro's name.
public final class LocalLLMModelStore {
    public init() {}

    public func loadContainer() async throws -> ModelContainer {
        guard
            let modelFolder = Bundle.main.resourceURL?
                .appendingPathComponent("LLMModel/qwen2.5-1.5b-instruct-4bit")
        else {
            throw LocalLLMModelStoreError.bundledModelMissing
        }
        return try await LLMModelFactory.shared.loadContainer(
            from: modelFolder, using: #huggingFaceTokenizerLoader())
    }
}

public enum LocalLLMModelStoreError: Error, LocalizedError {
    case bundledModelMissing

    public var errorDescription: String? {
        "The local LLM model isn't in this build — run Scripts/fetch-llm-model.sh and rebuild."
    }
}
