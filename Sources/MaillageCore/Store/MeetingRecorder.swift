import FluidAudio
import Foundation
import FoundationModels
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

/// Drives one recording from Start to a finished transcript: creates the meeting it belongs to,
/// starts both audio tracks and their live streaming transcribers (plus, unless the >4-speaker
/// opt-out is set, a diarizer alongside each) together, and on Stop waits for each track's
/// trailing audio to flush, merges the final segments, writes the transcript, then deletes the
/// audio.
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

    /// The live-growing transcript for each track, as the streaming ASR decodes it — one flat,
    /// continuously-updating block of text per track, not discrete timestamped rows. That's not
    /// a placeholder shape: FluidAudio's streaming session only ever hands back a plain running
    /// transcript while it's listening, and real per-utterance timing only once, at the end (see
    /// ``StreamingTranscriber``). `MeetingView` reads these while `state == .recording`; once
    /// Stop runs, the real timestamped segments in `meeting.body` take over.
    public private(set) var microphoneLiveText = ""
    public private(set) var systemAudioLiveText = ""

    private let store: VaultStore
    /// Each track's live pipeline for the duration of the recording: ingest buffers as they
    /// arrive, republish the growing live text, and — once `capture.stop()` finishes the sample
    /// stream — flush trailing audio and resolve to that track's final segments and detected
    /// language. `stop()` awaits both directly rather than polling anything.
    private var microphonePipeline: Task<TrackResult, Error>?
    private var systemAudioPipeline: Task<TrackResult, Error>?

    private struct TrackResult {
        var segments: [TranscriptSegment]
        var language: String?
    }

    public init(store: VaultStore) {
        self.store = store
    }

    /// Creates the meeting, loads a fresh streaming transcriber per track, and starts recording
    /// into its `.maillage/recordings/<id>/` folder. All three happen together because none of
    /// them mean anything without the others: a recording with no meeting to attach it to is
    /// orphaned audio, a meeting created before capture actually starts would exist with a
    /// duration it hasn't earned yet, and audio captured with nothing transcribing it can never
    /// produce the one thing this feature exists for.
    ///
    /// On failure, whatever this created is undone — the meeting entity included — so a denied
    /// microphone permission, or a missing bundled model, never leaves a zero-second meeting
    /// sitting in the vault.
    public func start(
        title: String,
        organization: Wikilink?,
        project: Wikilink?,
        attendees: [Wikilink],
        disableDiarization: Bool = false
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

            // Loaded before capture starts: a missing or broken bundled model is a reason not to
            // record at all, not something discovered only once Stop is pressed.
            let modelStore = FluidAudioModelStore()
            let microphoneTranscriber = FluidAudioStreamingTranscriber(
                manager: try await modelStore.loadStreamingASR())
            let systemAudioTranscriber = FluidAudioStreamingTranscriber(
                manager: try await modelStore.loadStreamingASR())

            // Never created for the >4-speaker opt-out: no diarizer, no speaker slots, every
            // segment's `speaker` stays `nil` — the same shape as a meeting recorded before this
            // feature existed.
            let microphoneDiarizer: FluidAudioStreamingDiarizer? =
                disableDiarization
                ? nil
                : FluidAudioStreamingDiarizer(
                    diarizer: try await modelStore.loadStreamingDiarizer())
            let systemAudioDiarizer: FluidAudioStreamingDiarizer? =
                disableDiarization
                ? nil
                : FluidAudioStreamingDiarizer(
                    diarizer: try await modelStore.loadStreamingDiarizer())

            await microphoneTranscriber.onUpdate { [weak self] text in
                Task { @MainActor in self?.microphoneLiveText = text }
            }
            await systemAudioTranscriber.onUpdate { [weak self] text in
                Task { @MainActor in self?.systemAudioLiveText = text }
            }

            try await capture.start(
                microphoneURL: directory.appendingPathComponent("mic.wav"),
                systemAudioURL: directory.appendingPathComponent("system.wav"))
            state = .recording

            microphonePipeline = Self.runPipeline(
                samples: capture.microphoneSamples, transcriber: microphoneTranscriber,
                diarizer: microphoneDiarizer, track: .mic)
            systemAudioPipeline = Self.runPipeline(
                samples: capture.systemAudioSamples, transcriber: systemAudioTranscriber,
                diarizer: systemAudioDiarizer, track: .system)
        } catch {
            capture.stop()
            try? FileManager.default.removeItem(at: directory)
            store.delete(kind: .meeting, id: meeting.id)
            meetingID = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// Feeds one track's live samples into its transcriber until `capture.stop()` finishes the
    /// stream, then flushes it. `nonisolated` and `static` so this runs entirely off the main
    /// actor — nothing here touches `self`, only the stream and transcriber it's given.
    ///
    /// A single buffer's `ingest` failing is tolerated (`try?`) and just drops that buffer's
    /// audio — a transient decode hiccup shouldn't cost the rest of the session. `finish()`
    /// failing is not tolerated: it means this track never produced a usable transcript at all,
    /// and `finishTranscription` needs to know that rather than silently getting an empty one.
    nonisolated private static func runPipeline(
        samples: AsyncStream<[Float]>, transcriber: FluidAudioStreamingTranscriber,
        diarizer: FluidAudioStreamingDiarizer?, track: AudioTrack
    ) -> Task<TrackResult, Error> {
        Task {
            for await buffer in samples {
                try? await transcriber.ingest(samples: buffer)
                try? diarizer?.ingest(samples: buffer)
            }
            let diarizerSegments = try diarizer?.finish() ?? []
            let segments = try await transcriber.finish(
                track: track, diarizerSegments: diarizerSegments)
            let language = await transcriber.detectedLanguage()
            return TrackResult(segments: segments, language: language)
        }
    }

    /// Stops both tracks, writes the recording's duration, then hands off to finishing
    /// transcription in the background — this call itself returns immediately, so Stop & Save
    /// can dismiss without waiting on either track's trailing audio to flush. Idle if nothing was
    /// recording — calling this from a sheet's `onDisappear` as a safety net must not throw or
    /// misbehave just because Stop was already pressed.
    public func stop() {
        guard state == .recording, let meetingID else { return }
        let duration = capture.stop()

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

    /// Awaits both tracks' final segments and detected language, merges, writes, deletes the
    /// audio, then summarises. `capture.stop()` already finished both sample streams in `stop()`,
    /// so each pipeline task is already on its way to resolving by the time this awaits them —
    /// this is not a fresh transcription pass, just collecting what streamed in live.
    private func finishTranscription(meetingID: EntityID, directory: URL) async {
        defer {
            self.meetingID = nil
            if case .failed = state {} else { state = .done }
        }
        guard let microphonePipeline, let systemAudioPipeline else {
            state = .failed("No live transcription was running for this meeting.")
            return
        }

        do {
            let microphoneResult = try await microphonePipeline.value
            let systemAudioResult = try await systemAudioPipeline.value

            guard var meeting = store.snapshot.meetings[meetingID] else { return }

            let merged = TranscriptMerger.merge(
                micSegments: microphoneResult.segments,
                systemSegments: systemAudioResult.segments)

            // The mic's own detected language wins ties: the person recording is the one this
            // app is for, where a remote caller's language is a fact about them, not about this
            // meeting. Falls back to "en" only when neither track ever emitted a language tag at
            // all — a near-silent recording.
            let language = microphoneResult.language ?? systemAudioResult.language ?? "en"

            meeting.language = language
            meeting.body = TranscriptCodec.join(
                preamble: TranscriptCodec.split(meeting.body).preamble, segments: merged)
            store.update(meeting)

            try? FileManager.default.removeItem(at: directory)

            state = .summarising
            if SystemLanguageModel.default.availability == .available {
                do {
                    let summary = try await FoundationModelsSummarizer().summarize(
                        merged, language: language)
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
        } catch {
            state = .failed(error.localizedDescription)
            // The recording sheet is long gone by the time transcription fails or succeeds, so
            // `state` alone is never observed — route through the same banner `VaultStore`
            // already shows for a failed save or load, rather than adding a second, parallel
            // error surface.
            let name = store.displayName(for: meetingID) ?? meetingID
            store.lastError = "Couldn't transcribe \"\(name)\": \(error.localizedDescription)"
        }
    }
}
