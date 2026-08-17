import Foundation

/// Drops hallucinated or nonsensical fragments from an ASR transcript and tidies formatting,
/// without summarizing or inventing content — the cleaned segments become the transcript that
/// gets persisted. See ``MeetingRecorder/finishTranscription(meetingID:directory:)``, which runs
/// this between merging both tracks' segments and writing them.
public protocol TranscriptCleaner: Sendable {
    /// `language` is the meeting's already-detected ISO code (e.g. `"fr"`), the same value
    /// ``MeetingSummarizer/summarize(_:language:)`` uses — no new detection here.
    func clean(
        _ segments: [TranscriptSegment], language: String
    ) async throws -> [TranscriptSegment]
}
