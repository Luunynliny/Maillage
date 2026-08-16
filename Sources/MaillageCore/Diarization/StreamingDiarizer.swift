import FluidAudio

/// Wraps one track's `SortformerDiarizer` session: enroll known voices before any real audio
/// arrives, ingest live audio as it comes in, then flush the trailing chunk and read back every
/// segment the whole session produced, plus which slots Sortformer itself recognized.
///
/// One instance per track (mic, system) — never shared, since Sortformer's four speaker slots
/// mean something only within the track they came from. `SortformerDiarizer`'s own methods are
/// synchronous (unlike the streaming ASR manager, which is an actor), so this stays a plain
/// struct rather than needing `async` itself.
public struct FluidAudioStreamingDiarizer {
    private let diarizer: SortformerDiarizer

    public init(diarizer: SortformerDiarizer) {
        self.diarizer = diarizer
    }

    /// Primes this session to recognize `personID`'s voice from a previously confirmed sample —
    /// Sortformer's own acoustic matching does the work; nothing here compares embeddings.
    /// Silently does nothing if the sample is too short to prime with (FluidAudio logs a
    /// warning) — a missing recognition is no worse than never having enrolled at all.
    public func enroll(personID: EntityID, voiceprint: Voiceprint) {
        _ = try? diarizer.enrollSpeaker(
            withAudio: voiceprint.samples, sourceSampleRate: Double(voiceprint.sampleRate),
            named: personID)
    }

    public func ingest(samples: [Float]) throws {
        _ = try diarizer.process(samples: samples)
    }

    public struct Result: Sendable {
        /// Every finalized segment across all four slots, oldest first.
        public var segments: [DiarizerSegment]
        /// Slot -> personID, only for slots Sortformer matched to a prior `enroll(personID:
        /// voiceprint:)` call this session — a suggestion for a human to confirm, never applied
        /// on its own (see the meeting-recording-v2 design doc's privacy reasoning).
        public var recognizedPersonIDs: [Int: EntityID]
    }

    /// Flushes the trailing chunk and returns the whole session's segments and recognitions.
    public func finish() throws -> Result {
        _ = try diarizer.finalizeSession()
        let speakers = diarizer.timeline.speakers
        let segments = speakers.values.flatMap(\.finalizedSegments)
            .sorted { $0.startFrame < $1.startFrame }
        let recognizedPersonIDs = speakers.compactMapValues(\.name)
        return Result(segments: segments, recognizedPersonIDs: recognizedPersonIDs)
    }
}
