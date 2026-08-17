import Foundation

/// Groups per-sentence transcript segments into paragraphs for display — plain-text, no
/// timestamps, and no per-sentence Text views, since the model already returns punctuated
/// sentences and needing a timestamp on every one just to read a transcript was the thing being
/// fixed here.
///
/// `TranscriptSegment` only carries a start offset, not a duration, so a gap is measured
/// start-to-start rather than true silence between sentences — a coarser signal than the real
/// pause length, but the only one available. Pure and unit-tested without a window, the same
/// reasoning as ``TranscriptMerger``.
public enum TranscriptParagraphs {
    /// A new paragraph starts whenever the gap since the previous segment exceeds
    /// `gapThreshold` (default 4s) — long enough that consecutive sentences spoken at an
    /// ordinary pace stay together, short enough that a real pause still reads as a break.
    public static func group(_ segments: [TranscriptSegment], gapThreshold: Int = 4) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        var lastOffset: Int?

        for segment in segments {
            if let lastOffset, segment.offsetSeconds - lastOffset > gapThreshold {
                paragraphs.append(current.joined(separator: " "))
                current = []
            }
            current.append(segment.text)
            lastOffset = segment.offsetSeconds
        }
        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }

        return paragraphs
    }
}
