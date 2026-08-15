import Foundation
import FoundationModels
import Observation
import WhisperKit

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
/// starts both audio tracks, and on Stop detects the meeting's language, transcribes both
/// tracks, merges and writes the transcript, then deletes the audio.
///
/// Deliberately not part of `VaultStore` — the store mirrors the vault and every other method
/// on it completes in one call, where this one runs for as long as a meeting does, well past
/// Stop now that transcription happens in the background. It also isn't folded into
/// `RecordingSheet`: unlike `PersonEditor` and the other editors, which own their `@State` and
/// call `VaultStore` directly because saving is a single atomic step, a recording is a *process*
/// whose lifetime must outlive the sheet showing it — `RootView` owns the instance for exactly
/// this reason, handing it to `RecordingSheet` as a binding rather than letting the sheet own it.
@MainActor
@Observable
public final class MeetingRecorder {
    public private(set) var state: MeetingRecorderState = .idle
    public private(set) var meetingID: EntityID?

    public let capture = AudioCaptureSession()

    private let store: VaultStore
    /// Drain `capture`'s live sample streams for the duration of the recording. No-op for now —
    /// a later phase replaces these with the actual streaming transcriber — but wiring them up
    /// here first proves buffers flow end to end, and that consuming them changes nothing about
    /// how a recording behaves, before anything downstream depends on it.
    private var microphoneDrainTask: Task<Void, Never>?
    private var systemAudioDrainTask: Task<Void, Never>?

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
            microphoneDrainTask = Task { [capture] in
                for await _ in capture.microphoneSamples {}
            }
            systemAudioDrainTask = Task { [capture] in
                for await _ in capture.systemAudioSamples {}
            }
        } catch {
            capture.stop()
            try? FileManager.default.removeItem(at: directory)
            store.delete(kind: .meeting, id: meeting.id)
            meetingID = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// Stops both tracks, writes the recording's duration, then hands off to transcription in
    /// the background — this call itself returns immediately, so Stop & Save can dismiss the
    /// sheet without waiting on a model. Idle if nothing was recording — calling this from a
    /// sheet's `onDisappear` as a safety net must not throw or misbehave just because Stop was
    /// already pressed.
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
            await self?.transcribe(meetingID: meetingID, directory: directory)
        }
    }

    /// Detect → prompt → transcribe both tracks → merge → write → delete the audio. Every step
    /// after detection depends on the language it found, and both tracks share one prompt built
    /// from it — see the design doc's Constraint 2 for why the language is held for the whole
    /// meeting rather than redetected per track or per chunk.
    private func transcribe(meetingID: EntityID, directory: URL) async {
        defer {
            self.meetingID = nil
            if case .failed = state {} else { state = .done }
        }
        do {
            let micURL = directory.appendingPathComponent("mic.wav")
            let systemURL = directory.appendingPathComponent("system.wav")

            let whisperKit = try await WhisperModelStore().loadWhisperKit()
            let language = try await LanguageDetector(whisperKit: whisperKit)
                .detect(micTrackAt: micURL, systemTrackAt: systemURL)

            guard var meeting = store.snapshot.meetings[meetingID] else { return }

            let customTerms =
                store.usedProjectRoles + store.usedRelationLabels
                + VaultConfig.vocabularyTerms(at: store.location)
            // `Constants` is WhisperKit's own top-level type, not nested under `WhisperKit` — read
            // from it rather than hardcode, so this tracks the library if the context size changes.
            let tokenLimit = (Constants.maxTokenContext / 2) - 1
            let promptText = VocabularyPrompt.build(
                meeting: meeting, snapshot: store.snapshot, language: language,
                customTerms: customTerms,
                budget: .init(
                    limit: tokenLimit,
                    count: { whisperKit.tokenizer?.encode(text: $0).count ?? 0 }))
            let promptTokens =
                promptText.isEmpty ? nil : whisperKit.tokenizer?.encode(text: promptText)

            let transcriber = WhisperTranscriber(whisperKit: whisperKit)
            var micSegments = try await transcriber.transcribe(
                fileAt: micURL, language: language, promptTokens: promptTokens)
            var systemSegments = try await transcriber.transcribe(
                fileAt: systemURL, language: language, promptTokens: promptTokens)
            if !promptText.isEmpty {
                micSegments = PromptEchoFilter.strip(micSegments, prompt: promptText)
                systemSegments = PromptEchoFilter.strip(systemSegments, prompt: promptText)
            }

            let merged = TranscriptMerger.merge(
                micSegments: micSegments, systemSegments: systemSegments)

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
            // skip. That's a device-capability gap, not a per-meeting problem — a banner on every
            // meeting on an ineligible Mac would just be noise.
        } catch {
            state = .failed(error.localizedDescription)
            // The recording sheet is long gone by the time transcription fails or succeeds, so
            // `state` alone is never observed — route through the same banner `VaultStore` already
            // shows for a failed save or load, rather than adding a second, parallel error surface.
            let name = store.displayName(for: meetingID) ?? meetingID
            store.lastError = "Couldn't transcribe \"\(name)\": \(error.localizedDescription)"
        }
    }
}
