import Foundation

/// Turns one meeting's merged transcript into a structured summary.
///
/// Map-reduce — chunking, per-chunk summarizing, and merging multiple chunk summaries into one —
/// is entirely this call's business, hidden behind a single `summarize(_:language:)`, so
/// `MeetingRecorder` calls this once with the whole transcript and never orchestrates chunking
/// itself.
public protocol MeetingSummarizer: Sendable {
    /// `language` is the meeting's already-detected ISO code (e.g. `"fr"`), the same value the
    /// streaming transcriber already found — no new detection here. `displayNames` resolves a
    /// diarized segment's `personID` to the name shown in the transcript excerpt the model reads
    /// — a plain `[EntityID: String]` rather than a `VaultStore` closure, since `VaultStore` is
    /// `@MainActor` and this call's own map-reduce chunking is not.
    func summarize(
        _ segments: [TranscriptSegment], language: String, displayNames: [EntityID: String]
    ) async throws -> MeetingSummary
}
