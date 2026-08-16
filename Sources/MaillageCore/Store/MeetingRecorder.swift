import FluidAudio
import Foundation
import FoundationModels
import NaturalLanguage
import Observation

/// Where one recording currently stands.
public enum MeetingRecorderState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case summarising
    case failed(String)
    case done
}

/// Drives one recording from Start to a finished transcript: creates the meeting it belongs to
/// and starts both audio tracks recording together, then on Stop transcribes each track's
/// just-closed WAV file in one batch pass, merges the segments, writes the transcript, then
/// deletes the audio.
///
/// Deliberately not part of `VaultStore` — the store mirrors the vault and every other method
/// on it completes in one call, where this one runs for as long as a meeting does, well past
/// Stop now that transcription happens in the background. It also isn't folded into
/// `RecordingSheet`: unlike `PersonEditor` and the other editors, which own their `@State` and
/// call `VaultStore` directly because saving is a single atomic step, a recording is a *process*
/// whose lifetime must outlive both the sheet that starts it and the view that watches it —
/// `RootView` owns the instance for exactly this reason, handing it to `RecordingSheet` to start
/// one and to `MeetingView` to show, edit and stop the active one, rather than letting either own
/// it.
@MainActor
@Observable
public final class MeetingRecorder {
    public private(set) var state: MeetingRecorderState = .idle
    public private(set) var meetingID: EntityID?

    public let capture = AudioCaptureSession()

    private let store: VaultStore
    /// Shown for exactly as long as `capture` is running — see `start()` and `stop()`. Owned
    /// here rather than by `RootView`, since this is exactly where the go/stop transitions this
    /// panel needs to track already happen; `RootView` would otherwise have to re-derive the same
    /// transitions from `capture.isRecording`.
    private let indicatorPanel = RecordingIndicatorPanel()

    public init(store: VaultStore) {
        self.store = store
    }

    /// Creates the meeting and starts recording into its `.maillage/recordings/<id>/` folder.
    /// Both happen together because neither means anything without the other: a recording with
    /// no meeting to attach it to is orphaned audio, and a meeting created before capture starts
    /// would exist with a duration it hasn't earned yet.
    ///
    /// On failure, whatever this created is undone — the meeting entity included — so a denied
    /// microphone permission never leaves a zero-second meeting sitting in the vault.
    public func start(
        title: String,
        organization: Wikilink?,
        project: Wikilink?,
        attendees: [Wikilink]
    ) async {
        guard
            let meeting = store.createMeeting(
                title: title, organization: organization, project: project,
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
            indicatorPanel.show(capture: capture)
        } catch {
            capture.stop()
            try? FileManager.default.removeItem(at: directory)
            store.delete(kind: .meeting, id: meeting.id)
            meetingID = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// Stops both tracks, writes the recording's duration, then hands off to finishing
    /// transcription in the background — this call itself returns immediately, so Stop & Save
    /// can dismiss without waiting on either track's batch transcription. Idle if nothing was
    /// recording — calling this from a sheet's `onDisappear` as a safety net must not throw or
    /// misbehave just because Stop was already pressed.
    public func stop() {
        guard state == .recording, let meetingID else { return }
        let duration = capture.stop()
        indicatorPanel.hide()

        guard var meeting = store.snapshot.meetings[meetingID] else {
            self.meetingID = nil
            state = .idle
            return
        }
        meeting.duration = duration
        store.update(meeting)

        state = .transcribing
        let directory = store.location.recordingsDirectory(forMeeting: meetingID)
        Task { [weak self] in
            await self?.finishTranscription(meetingID: meetingID, directory: directory)
        }
    }

    /// Runs both tracks' batch transcriptions (concurrently, via `async let`), merges, writes,
    /// deletes the audio, then summarises. Each track loads its own model and transcribes its
    /// own WAV file top to bottom — there is no live pipeline left over from `start()` to await,
    /// unlike the streaming design this replaced, so a missing bundled model now surfaces here
    /// rather than at Start, the same failed-transcription banner a decode failure would.
    ///
    /// Each track's failure is caught independently rather than let either throw through a joint
    /// `try await` — a silent system-audio tap (no tap permission, a zero-frame WAV) is a known
    /// failure mode of this capture path, and it must not also discard a perfectly good
    /// microphone transcript. Only both tracks failing counts as the meeting failing; one track
    /// failing degrades to a transcript from the surviving track plus the same soft error banner
    /// a failed summary already uses.
    private func finishTranscription(meetingID: EntityID, directory: URL) async {
        defer {
            self.meetingID = nil
            if case .failed = state {} else { state = .done }
        }

        async let microphoneResult = Self.transcribeResult(
            url: directory.appendingPathComponent("mic.wav"))
        async let systemAudioResult = Self.transcribeResult(
            url: directory.appendingPathComponent("system.wav"))
        let (micResult, systemResult) = await (microphoneResult, systemAudioResult)

        if case .failure(let micError) = micResult, case .failure(let systemError) = systemResult {
            state = .failed(micError.localizedDescription)
            let name = store.displayName(for: meetingID) ?? meetingID
            store.lastError =
                "Couldn't transcribe \"\(name)\": \(micError.localizedDescription); "
                + systemError.localizedDescription
            return
        }

        let micSegments = (try? micResult.get()) ?? []
        let systemSegments = (try? systemResult.get()) ?? []
        let merged = TranscriptMerger.merge(
            micSegments: micSegments, systemSegments: systemSegments)

        // Surface whichever single track failed, non-fatally — the meeting still has a real
        // transcript from the other track, so this is the same soft banner a failed summary
        // uses, not a `.failed` state.
        if case .failure(let error) = micResult {
            let name = store.displayName(for: meetingID) ?? meetingID
            store.lastError =
                "Couldn't transcribe your microphone for \"\(name)\": \(error.localizedDescription)"
        } else if case .failure(let error) = systemResult {
            let name = store.displayName(for: meetingID) ?? meetingID
            store.lastError =
                "Couldn't transcribe the other side's audio for \"\(name)\": \(error.localizedDescription)"
        }

        guard var meeting = store.snapshot.meetings[meetingID] else { return }

        let language = Self.detectedLanguage(of: merged)
        meeting.language = language
        meeting.body = TranscriptCodec.join(
            preamble: TranscriptCodec.split(meeting.body).preamble, segments: merged)
        store.update(meeting)

        // The audio's only reason to still exist was to be transcribed — safe to delete now
        // that whatever segments either track could produce are in hand.
        try? FileManager.default.removeItem(at: directory)

        state = .summarising
        if SystemLanguageModel.default.availability == .available {
            do {
                let summary = try await FoundationModelsSummarizer().summarize(
                    merged, language: language ?? "en")
                if var summarized = store.snapshot.meetings[meetingID] {
                    summarized.body = TranscriptCodec.join(
                        preamble: summary.markdown, segments: merged)
                    store.update(summarized)
                }
            } catch {
                // Never state = .failed here — a summary failure degrades to "transcript, no
                // summary," per the design doc; only surface it the same soft way
                // transcription failure already does, via the shared banner.
                let name = store.displayName(for: meetingID) ?? meetingID
                store.lastError =
                    "Couldn't summarize \"\(name)\": \(error.localizedDescription)"
            }
        }
        // Unavailable (device ineligible, Apple Intelligence off, model not ready): silently
        // skip. That's a device-capability gap, not a per-meeting problem — a banner on
        // every meeting on an ineligible Mac would just be noise.
    }

    /// Loads a fresh batch ASR model and transcribes one track's WAV file top to bottom, grouped
    /// into timestamped segments. `nonisolated` and `static`: touches no recorder state, only the
    /// file it's given — `finishTranscription` runs both tracks' calls concurrently.
    nonisolated private static func transcribe(url: URL) async throws -> [TranscriptSegment] {
        let manager = try await FluidAudioModelStore().loadBatchASR()
        let timings = try await FluidAudioTranscriber(manager: manager).transcribe(fileURL: url)
        return TokenTimingGrouper.segments(from: timings)
    }

    /// `transcribe(url:)`, with its failure caught rather than thrown — so `finishTranscription`
    /// can run both tracks concurrently and inspect each one's outcome independently instead of
    /// either `async let`'s throw wiping out both.
    nonisolated private static func transcribeResult(url: URL) async -> Result<
        [TranscriptSegment], Error
    > {
        do {
            return .success(try await transcribe(url: url))
        } catch {
            return .failure(error)
        }
    }

    /// The meeting's dominant language, detected from its merged transcript text via Apple's
    /// on-device `NLLanguageRecognizer` — the batch ASR result carries no language field of its
    /// own, unlike the streaming manager this replaces. `nil` for an empty transcript, e.g. a
    /// near-silent recording.
    nonisolated private static func detectedLanguage(of segments: [TranscriptSegment]) -> String? {
        let text = segments.map(\.text).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
