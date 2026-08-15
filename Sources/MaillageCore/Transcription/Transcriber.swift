import Foundation

/// Turns one audio file into transcript segments, forcing a language and a vocabulary prompt
/// rather than leaving either to be decided per call — both are resolved once per meeting by
/// whoever orchestrates a transcription (`MeetingRecorder`), never inside this call.
///
/// Deviates from the design doc's `vocabulary: [String]` in favour of already-tokenized
/// `promptTokens`: both tracks of a meeting share the exact same detected language and rendered
/// prompt, so tokenizing once at the orchestration layer — rather than re-rendering and
/// re-tokenizing per file inside a conforming type — avoids redundant work for no benefit.
public protocol Transcriber: Sendable {
    func transcribe(fileAt url: URL, language: String, promptTokens: [Int]?) async throws
        -> [TranscriptSegment]
}
