import Foundation
import WhisperKit

/// Finds the language a meeting was held in — once, from a short window of real speech on the
/// mic track — never per audio chunk.
///
/// The mic track, never the system track: the system track may open silent before anyone else
/// has spoken, which is exactly the case that misdetects. The result is held and forced for
/// every chunk of both tracks for the rest of the meeting; see the design doc's Constraint 2 for
/// why redetecting per chunk was considered and rejected.
public struct LanguageDetector {
    private let whisperKit: WhisperKit

    public init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    /// - Parameter url: The mic track's WAV file.
    /// - Returns: A language code, e.g. `"fr"`.
    public func detect(micTrackAt url: URL) async throws -> String {
        let samples = try AudioProcessor.loadAudioAsFloatArray(
            fromPath: url.path, startTime: 0, endTime: 30)
        let window = Self.skippingLeadingSilence(samples)
        // WhisperKit's own misspelling of "language" — matching it exactly, not a typo of mine.
        let (language, _) = try await whisperKit.detectLangauge(audioArray: window)
        return language
    }

    /// Whisper's language-ID is unreliable on pure silence and known to default to English, so
    /// this walks 1-second chunks — via WhisperKit's own energy-based VAD, the same one
    /// `chunkingStrategy: .vad` uses, rather than reimplementing silence detection — until it
    /// finds one with real energy. Falls back to the untouched samples if the whole window is
    /// silent: a slow-starting meeting shouldn't fail detection outright, just risk a worse
    /// guess, and that guess is still better than refusing to detect at all.
    static func skippingLeadingSilence(_ samples: [Float], sampleRate: Int = 16_000) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let frameLength = sampleRate
        let chunkCount = max(1, samples.count / frameLength)
        let activity = AudioProcessor.calculateVoiceActivityInChunks(
            of: samples, chunkCount: chunkCount, frameLengthSamples: frameLength)
        guard let firstVoiced = activity.firstIndex(of: true) else { return samples }
        return Array(samples[(firstVoiced * frameLength)...])
    }
}
