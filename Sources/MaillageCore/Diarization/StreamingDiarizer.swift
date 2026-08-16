import FluidAudio

/// Wraps one track's `SortformerDiarizer` session: ingest live audio as it arrives, then flush
/// the trailing chunk and read back every segment the whole session produced.
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

    public func ingest(samples: [Float]) throws {
        _ = try diarizer.process(samples: samples)
    }

    /// Flushes the trailing chunk and returns every finalized segment across all four slots,
    /// oldest first.
    public func finish() throws -> [DiarizerSegment] {
        _ = try diarizer.finalizeSession()
        return diarizer.timeline.speakers.values
            .flatMap(\.finalizedSegments)
            .sorted { $0.startFrame < $1.startFrame }
    }
}
