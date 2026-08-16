import AudioCommon
import Foundation
import Qwen3ASR

/// Implements ``Transcriber`` over `speech-swift`'s `StreamingASR` — Qwen3-ASR guided by a Silero
/// VAD pass, replacing WhisperKit.
///
/// **Chunking.** `StreamingASR.transcribeStream` is VAD-first, not fixed-window: it walks the
/// audio through `SileroVADModel`, and only the spans it flags as speech ever reach the ASR model
/// (`StreamingASRConfig.vadConfig`, default `.sileroDefault`, keeps a 0.25s minimum speech
/// duration, so a stray blip too short to be a real utterance never becomes a chunk at all). A
/// continuous speech span longer than `maxSegmentDuration` (10s here, `speech-swift`'s own
/// default) is still force-split mid-speech so a long monologue — or a two-hour meeting with no
/// natural pause — never becomes one unbounded decode. This is the same VAD-boundary reasoning
/// `WhisperTranscriber`'s `chunkingStrategy: .vad` fix used, on a library that does it natively
/// rather than needing a hand-rolled chunker rebuilt a third time.
///
/// **Hallucination filtering.** Unlike WhisperKit's `noSpeechProb`, nothing in `speech-swift`'s
/// `Qwen3ASRModel.transcribe(audio:...) -> String` returns a confidence or no-speech signal to
/// filter on — confirmed by reading the real source, not assumed from docs:
/// `SpeechRecognitionModel.transcribeWithLanguage`'s default protocol extension returns
/// `TranscriptionResult(text:)` with `confidence: 0.0` for any conformer that doesn't override it,
/// and `Qwen3ASRModel`'s own conformance never does. There is therefore no per-segment score left
/// to filter on here, unlike the old `noSpeechThreshold` — the VAD gate above is the only
/// hallucination mitigation this backend has, structurally different from Whisper's (which decoded
/// fixed windows regardless of voice activity and needed `noSpeechProb` to catch what leaked
/// through). Whether that's sufficient against Qwen3-ASR's own hallucination modes needs real-audio
/// verification; this is flagged, not silently assumed fine.
///
/// **Language.** `language: nil` throughout: `Qwen3ASRModel.generateText` (read directly) only
/// appends a `"language <code>"` hint token when a language is passed — when it isn't, the model
/// auto-detects and emits its own `"language XX<asr_text>"` prefix, which the library strips
/// before returning. Passing `nil` here, per VAD-bounded segment (each `StreamingASR` segment gets
/// its own independent `transcribe()` call, and so its own independent auto-detect), is what
/// preserves the real per-utterance language switching this backend was chosen for — the
/// underlying reason Qwen3-ASR replaced Parakeet TDT's whole-clip conditioning. Real-audio testing
/// of a French recording with a dropped-in English term is still required to confirm this in
/// practice, the same way WhisperKit's own detectLanguage needed it.
///
/// `StreamingASR` isn't Sendable ("not thread-safe. Create separate instances for concurrent
/// use.", per its own doc comment) — every call into it here is a single `await`, never
/// concurrent from multiple tasks against the same instance, the same posture `WhisperTranscriber`
/// already took.
public final class LocalASRTranscriber: Transcriber, @unchecked Sendable {
    private let streamingASR: StreamingASR

    public init(streamingASR: StreamingASR) {
        self.streamingASR = streamingASR
    }

    public func transcribe(fileAt url: URL) async throws -> [TranscriptSegment] {
        let samples = try AudioFileLoader.load(url: url, targetSampleRate: 16_000)
        let config = StreamingASRConfig(
            maxSegmentDuration: 10.0, language: nil, emitPartialResults: false)
        let stream = streamingASR.transcribeStream(
            audio: samples, sampleRate: 16_000, config: config)

        var segments: [TranscriptSegment] = []
        for try await segment in stream {
            segments.append(
                TranscriptSegment(
                    offsetSeconds: Int(segment.startTime.rounded()), text: segment.text))
        }
        return segments
    }
}
