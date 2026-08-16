import Foundation

/// Splits a transcript into fixed-size windows for map-reduce summarizing.
///
/// Pure — no model dependency, no I/O — so it's unit-tested without one, the same reasoning as
/// ``TranscriptMerger`` and ``TranscriptCodec``.
public enum TranscriptChunker {
    /// Groups consecutive segments into windows of `windowSize`; the last window holds whatever
    /// remains, never padded. `windowSize` has no default here — this type is a generic pure
    /// utility, and the model's context budget that should decide the default belongs to
    /// whoever actually knows it (``LocalLLMSummarizer``, ``LocalLLMTranscriptCleaner``), not
    /// this pure utility.
    ///
    /// A single segment whose own text is enormous still comes out as its own one-segment
    /// chunk — this groups by count and cannot split inside a segment's text. Segments are short
    /// utterances by construction (``TokenTimingGrouper`` splits on pauses), so that isn't
    /// expected to bite in practice.
    public static func chunk(_ segments: [TranscriptSegment], windowSize: Int)
        -> [[TranscriptSegment]]
    {
        guard !segments.isEmpty else { return [] }
        let size = max(1, windowSize)
        return stride(from: 0, to: segments.count, by: size).map {
            Array(segments[$0..<min($0 + size, segments.count)])
        }
    }
}
