import FluidAudio
import Foundation

/// Groups a streaming ASR session's final token-level timings into utterance-level segments —
/// the shape a batch model's own chunking already gave ``MeetingRecorder`` for free, but a
/// streaming session only ever hands over as one flat list of tokens, at `finish()`, never
/// incrementally. Pure — no FluidAudio model dependency beyond the `TokenTiming` type itself, so
/// it's unit-tested without one loaded, the same reasoning as ``TranscriptMerger``.
public enum TokenTimingGrouper {
    /// A new segment starts whenever the gap since the previous word exceeds `pauseThreshold`
    /// (default 1.5s) — a heuristic, not a measured number: long enough that an ordinary breath
    /// or word gap never splits a sentence in two, short enough that a real pause between
    /// utterances still reads as two lines instead of one run-on paragraph.
    ///
    /// Groups by word, not by raw sub-word token — via FluidAudio's own
    /// ``buildWordTimings(from:)``, so the sub-word joining (SentencePiece's `▁` word-boundary
    /// marker) is the library's tested logic, not a reimplementation of it here. Language-tag
    /// tokens (`<xx-XX>`, the decoder's own bookkeeping for which language it's decoding) are
    /// dropped — metadata about the utterance, never something anyone said.
    /// `track`/`diarizerSegments` assign each grouped segment a ``Speaker`` by overlapping its
    /// full word-span against that track's diarizer segments (see ``SpeakerAligner``) — omitted
    /// (the defaults) when diarization is off, which leaves every segment's `speaker` `nil`.
    public static func segments(
        from timings: [TokenTiming], pauseThreshold: TimeInterval = 1.5,
        track: AudioTrack? = nil, diarizerSegments: [DiarizerSegment] = []
    ) -> [TranscriptSegment] {
        let words = buildWordTimings(from: timings).filter {
            !($0.word.hasPrefix("<") && $0.word.hasSuffix(">"))
        }

        var segments: [TranscriptSegment] = []
        var current: [WordTiming] = []

        func flush() {
            defer { current = [] }
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.word).joined(separator: " ")
            let speaker = track.flatMap { track in
                SpeakerAligner.assign(
                    start: Float(first.startTime), end: Float(last.endTime), in: diarizerSegments
                ).map { Speaker(track: track, slot: $0) }
            }
            segments.append(
                TranscriptSegment(
                    offsetSeconds: Int(first.startTime.rounded()), text: text, speaker: speaker))
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
