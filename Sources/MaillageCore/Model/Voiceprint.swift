/// A person's stored voice signature: a short clip of confirmed speech, 16 kHz mono. Not
/// compared in this app's own code — Sortformer has no public API exposing a per-speaker
/// embedding, only `enrollSpeaker(withAudio:)`, which primes a session with known audio and does
/// its own acoustic matching internally. So a voiceprint here is exactly what that call needs:
/// real audio, not an abstract vector. Not enough audio to be a recording of what was said,
/// either — a few seconds, long enough to recognize a voice, nowhere near a transcript's worth.
/// Stored as `assets/people/<id>.voiceprint`, one small JSON file per person, the same "a logo is
/// a file, not a field" shape as a profile picture.
public struct Voiceprint: Codable, Hashable, Sendable {
    public var samples: [Float]
    public var sampleRate: Int

    public init(samples: [Float], sampleRate: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}
