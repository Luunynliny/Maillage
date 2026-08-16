import FluidAudio
import Foundation

/// Groups a batch ASR result's token-level timings into utterance-level segments.
///
/// Pure — no FluidAudio model dependency beyond the `TokenTiming` type itself, so it's
/// unit-tested without one loaded, the same reasoning as ``TranscriptMerger``.
public enum TokenTimingGrouper {
    /// A new segment starts whenever the gap since the previous word exceeds `pauseThreshold`
    /// (default 1.5s) — a heuristic, not a measured number: long enough that an ordinary breath
    /// or word gap never splits a sentence in two, short enough that a real pause between
    /// utterances still reads as two lines instead of one run-on paragraph.
    ///
    /// Groups by word, not by raw sub-word token — via FluidAudio's own
    /// ``buildWordTimings(from:)``, so the sub-word joining (SentencePiece's `▁` word-boundary
    /// marker) is the library's tested logic, not a reimplementation of it here. Nemotron decodes
    /// with inline language-tag tokens (`<fr-FR>`, `<en-US>`, ...) as its own bookkeeping for
    /// which language it just detected, never something anyone said — but FluidAudio itself
    /// already excludes those before a `TokenTiming` is ever produced (confirmed against the
    /// pinned version: `StreamingNemotronMultilingualAsrManager` drops any `langTagTokenIds`
    /// token before appending it). The bracket filter below is a defensive backstop against any
    /// other bracket-shaped special token slipping through, not the place tag-stripping actually
    /// happens — a future FluidAudio version could change that internal behavior, so this stays
    /// cheap insurance rather than dead weight to delete.
    public static func segments(
        from timings: [TokenTiming], pauseThreshold: TimeInterval = 1.5
    ) -> [TranscriptSegment] {
        let words = buildWordTimings(from: timings).filter {
            !($0.word.hasPrefix("<") && $0.word.hasSuffix(">"))
        }

        var segments: [TranscriptSegment] = []
        var current: [WordTiming] = []

        func flush() {
            defer { current = [] }
            guard let first = current.first else { return }
            let text = current.map(\.word).joined(separator: " ")
            segments.append(
                TranscriptSegment(offsetSeconds: Int(first.startTime.rounded()), text: text))
        }

        for word in words {
            if let last = current.last, word.startTime - last.endTime > pauseThreshold {
                flush()
            }
            current.append(word)
        }
        flush()

        return segments
    }
}
