import FluidAudio

/// Assigns a diarized speaker slot to an ASR word-span by time overlap — pure, no model
/// dependency, the same "plain function over model output" shape as `TranscriptMerger`.
public enum SpeakerAligner {
    /// The diarizer slot with the greatest overlap against `start...end`, or `nil` when nothing
    /// overlaps — the diarizer hasn't caught up to this point in the audio yet, or this span
    /// fell in a silence gap between two of its segments.
    public static func assign(start: Float, end: Float, in diarizerSegments: [DiarizerSegment])
        -> Int?
    {
        diarizerSegments
            .compactMap { segment -> (slot: Int, overlap: Float)? in
                let overlap = min(end, segment.endTime) - max(start, segment.startTime)
                return overlap > 0 ? (segment.speakerIndex, overlap) : nil
            }
            .max { $0.overlap < $1.overlap }?
            .slot
    }
}
