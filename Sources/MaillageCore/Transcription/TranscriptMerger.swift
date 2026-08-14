import Foundation

/// Interleaves both tracks' segments into one chronological transcript, labelling mic segments
/// `You` and system segments with the sole attendee's name (the common 1:1 case) or `Others`.
///
/// Pure — no WhisperKit dependency, no I/O — so it's unit-tested without a model, the same
/// reasoning as `TranscriptCodec` and the two graph layouts.
public enum TranscriptMerger {
    public static func merge(
        micSegments: [TranscriptSegment],
        systemSegments: [TranscriptSegment],
        soleAttendeeName: String?
    ) -> [TranscriptSegment] {
        let systemLabel = soleAttendeeName ?? "Others"
        let labeledMic = micSegments.map {
            TranscriptSegment(speaker: "You", offsetSeconds: $0.offsetSeconds, text: $0.text)
        }
        let labeledSystem = systemSegments.map {
            TranscriptSegment(speaker: systemLabel, offsetSeconds: $0.offsetSeconds, text: $0.text)
        }
        // `sorted` is stable, so segments landing in the same second keep mic-before-system
        // order from the concatenation — a deterministic tie-break, not an arbitrary one.
        return (labeledMic + labeledSystem).sorted { $0.offsetSeconds < $1.offsetSeconds }
    }
}
