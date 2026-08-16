import Foundation

/// Turns one audio file into transcript segments.
///
/// A protocol, not just ``WhisperTranscriber`` directly, so `MeetingRecorder`'s orchestration can
/// be exercised without a loaded model.
public protocol Transcriber: Sendable {
    func transcribe(fileAt url: URL) async throws -> [TranscriptSegment]
}
