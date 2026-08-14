import Foundation
import Observation

/// Where one recording currently stands.
///
/// Two states short of the full pipeline in the design doc (`transcribing`, `summarising`
/// come with the phases that implement them) — this phase only records, so `.recording` is
/// followed straight by `.idle` once the files and the meeting are both finalised.
public enum MeetingRecorderState: Equatable, Sendable {
    case idle
    case recording
    case failed(String)
}

/// Drives one recording from Start to Stop: creates the meeting it belongs to, starts both
/// audio tracks, and finalises the meeting's duration when they stop.
///
/// Deliberately not part of `VaultStore` — the store mirrors the vault and every other method
/// on it completes in one call, where this one runs for as long as a meeting does. It also
/// isn't folded into `RecordingSheet`: unlike `PersonEditor` and the other editors, which own
/// their `@State` and call `VaultStore` directly because saving is a single atomic step, a
/// recording is a *process* with its own lifetime, independent of whether the sheet showing it
/// stays open — reason enough for its own type even before phase 4 gives it more to coordinate.
@MainActor
@Observable
public final class MeetingRecorder {
    public private(set) var state: MeetingRecorderState = .idle
    public private(set) var meetingID: EntityID?

    public let capture = AudioCaptureSession()

    private let store: VaultStore

    public init(store: VaultStore) {
        self.store = store
    }

    /// Creates the meeting and starts recording into its `.maillage/recordings/<id>/` folder.
    /// The two happen together because neither means anything without the other: a recording
    /// with no meeting to attach it to is orphaned audio, and a meeting created before capture
    /// actually starts would exist with a duration it hasn't earned yet.
    ///
    /// On failure, whatever this created is undone — the meeting entity included — so a denied
    /// microphone permission never leaves a zero-second meeting sitting in the vault.
    public func start(
        title: String,
        language: String?,
        organization: Wikilink?,
        project: Wikilink?,
        attendees: [Wikilink]
    ) async {
        guard
            let meeting = store.createMeeting(
                title: title, language: language, organization: organization, project: project,
                attendees: attendees)
        else {
            state = .failed(store.lastError ?? "Couldn't create the meeting.")
            return
        }
        meetingID = meeting.id

        let directory = store.location.recordingsDirectory(forMeeting: meeting.id)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try await capture.start(
                microphoneURL: directory.appendingPathComponent("mic.wav"),
                systemAudioURL: directory.appendingPathComponent("system.wav"))
            state = .recording
        } catch {
            capture.stop()
            try? FileManager.default.removeItem(at: directory)
            store.delete(kind: .meeting, id: meeting.id)
            meetingID = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// Stops both tracks and writes the recording's duration to the meeting. Idle if nothing
    /// was recording — calling this from a sheet's `onDisappear` as a safety net must not
    /// throw or misbehave just because Stop was already pressed.
    public func stop() {
        guard state == .recording, let meetingID else { return }
        let duration = capture.stop()

        if var meeting = store.snapshot.meetings[meetingID] {
            meeting.duration = duration
            store.update(meeting)
        }

        self.meetingID = nil
        state = .idle
    }
}
