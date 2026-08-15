import Foundation
import WhisperKit

/// Finds the language a meeting was held in — once, from a short window of real speech — never
/// per audio chunk. The result is held and forced for every chunk of both tracks for the rest of
/// the meeting; see the design doc's Constraint 2 for why redetecting per chunk was considered
/// and rejected.
///
/// Prefers the mic track, since that's where the meeting's own participant usually speaks — but
/// falls back to the system track when the mic has no detectable speech at all. A meeting
/// recorded while mostly listening (a call you mostly listen to, or — the case that surfaced
/// this — testing transcription by just playing a video with the mic silent) would otherwise
/// hand the detector nothing but room tone, and Whisper's language-ID on pure noise is little
/// better than a random guess, forced onto real speech on the other track for the whole meeting.
public struct LanguageDetector {
    private let whisperKit: WhisperKit

    public init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    /// - Parameters:
    ///   - micURL: The mic track's WAV file, tried first.
    ///   - systemURL: The system track's WAV file, tried only if the mic track has no
    ///     detectable speech.
    /// - Returns: A language code, e.g. `"fr"`.
    public func detect(micTrackAt micURL: URL, systemTrackAt systemURL: URL) async throws -> String
    {
        let window: [Float]
        if let voiced = try Self.voicedWindow(fromFileAt: micURL) {
            window = voiced
        } else if let voiced = try Self.voicedWindow(fromFileAt: systemURL) {
            window = voiced
        } else {
            // Neither track has anything resembling speech in its first 30s — best-effort on
            // the raw mic audio rather than fail the whole meeting over an edge case this quiet.
            window = try AudioProcessor.loadAudioAsFloatArray(
                fromPath: micURL.path, startTime: 0, endTime: 30)
        }
        // WhisperKit's own misspelling of "language" — matching it exactly, not a typo of mine.
        let (language, _) = try await whisperKit.detectLangauge(audioArray: window)
        return language
    }

    /// Loads the first 30s of `url` and trims it to the first window with real energy, or
    /// returns `nil` if the whole thing is silence/noise — the signal the caller uses to try
    /// the other track instead of detecting on nothing.
    private static func voicedWindow(fromFileAt url: URL) throws -> [Float]? {
        let samples = try AudioProcessor.loadAudioAsFloatArray(
            fromPath: url.path, startTime: 0, endTime: 30)
        return trimmedToFirstVoice(samples)
    }

    /// Whisper's language-ID is unreliable on pure silence and known to default to English, so
    /// this walks 1-second chunks — via WhisperKit's own energy-based VAD, the same one
    /// `chunkingStrategy: .vad` uses, rather than reimplementing silence detection — until it
    /// finds one with real energy. `nil` if nothing in the window is voiced at all.
    static func trimmedToFirstVoice(_ samples: [Float], sampleRate: Int = 16_000) -> [Float]? {
        guard !samples.isEmpty else { return nil }
        let frameLength = sampleRate
        let chunkCount = max(1, samples.count / frameLength)
        let activity = AudioProcessor.calculateVoiceActivityInChunks(
            of: samples, chunkCount: chunkCount, frameLengthSamples: frameLength)
        guard let firstVoiced = activity.firstIndex(of: true) else { return nil }
        return Array(samples[(firstVoiced * frameLength)...])
    }
}
