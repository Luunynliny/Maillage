import Foundation

/// Interleaves both tracks' segments into one chronological transcript.
///
/// No speaker labels — see ``TranscriptSegment`` for why neither track can be honestly
/// attributed to one person, in any recording topology.
///
/// Pure — no WhisperKit dependency, no I/O — so it's unit-tested without a model, the same
/// reasoning as `TranscriptCodec` and the two graph layouts.
public enum TranscriptMerger {
    public static func merge(
        micSegments: [TranscriptSegment],
        systemSegments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        // `sorted` is stable, so segments landing in the same second keep mic-before-system
        // order from the concatenation — a deterministic tie-break, not an arbitrary one.
        (micSegments + systemSegments).sorted { $0.offsetSeconds < $1.offsetSeconds }
    }
}
