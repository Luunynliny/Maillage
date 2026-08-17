import Foundation

/// Turns one meeting's merged transcript into a markdown summary, written by the model directly
/// rather than filled into a structured schema — see `LocalLLMSummarizer`, this protocol's only
/// implementation, for why: MLX's structured-output story isn't leaned on here, so the model just
/// writes the same markdown ``TranscriptCodec`` persists as the "## Summary" preamble.
///
/// Map-reduce — chunking, per-chunk summarizing, and merging multiple chunk summaries into one —
/// is entirely this call's business, hidden behind a single `summarize(_:language:)`, so
/// `MeetingRecorder` calls this once with the whole transcript and never orchestrates chunking
/// itself.
public protocol MeetingSummarizer: Sendable {
    /// `language` is the meeting's already-detected ISO code (e.g. `"fr"`), the same value
    /// `NLLanguageRecognizer` found over the merged transcript — no new detection here.
    func summarize(
        _ segments: [TranscriptSegment], language: String
    ) async throws -> String
}
