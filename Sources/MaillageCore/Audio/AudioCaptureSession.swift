import Foundation
import Observation

public enum AudioCaptureError: Error, LocalizedError {
    case microphonePermissionDenied
    case microphone(Error)
    case systemAudio(Error)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "maillage needs microphone access to record a meeting. Allow it in System Settings ▸ Privacy & Security ▸ Microphone."
        case .microphone(let error):
            error.localizedDescription
        case .systemAudio(let error):
            error.localizedDescription
        }
    }
}

/// Starts and stops both halves of a recording together, and publishes what a `RecordingSheet`
/// needs to show while it runs: elapsed time and a level meter per track.
///
/// `@MainActor @Observable`, unlike ``MicrophoneRecorder`` and ``SystemAudioTap`` underneath
/// it: those two run their own real-time callbacks and must never be pulled onto the main
/// actor, but this type only ever *polls* them, on a timer, at a rate a person's eye can
/// actually follow — there is no real-time constraint here to protect.
@MainActor
@Observable
public final class AudioCaptureSession {
    public private(set) var isRecording = false
    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var microphoneLevel: Float = 0
    public private(set) var systemAudioLevel: Float = 0

    /// Live 16 kHz mono samples from each track, for a streaming transcriber to consume — the
    /// same converted buffers each recorder writes to its WAV file, just also handed off here.
    /// A fresh stream per ``start(microphoneURL:systemAudioURL:)`` call, already finished
    /// (empty) before the first one — consuming either only makes sense after `start` returns.
    public private(set) var microphoneSamples = AsyncStream<[Float]> { $0.finish() }
    public private(set) var systemAudioSamples = AsyncStream<[Float]> { $0.finish() }

    private let microphone = MicrophoneRecorder()
    private let systemAudio = SystemAudioTap()
    private var microphoneContinuation: AsyncStream<[Float]>.Continuation?
    private var systemAudioContinuation: AsyncStream<[Float]>.Continuation?
    private var startedAt: Date?
    private var pollTask: Task<Void, Never>?

    public init() {}

    /// Starts both tracks, or neither: a recording that captured only the microphone would
    /// silently break the "You"/"Them" split every transcript downstream of this depends on,
    /// so either both start or ``stop()`` unwinds whichever one succeeded before throwing.
    ///
    /// System audio starts first, on purpose: it needs a process tap plus a private aggregate
    /// device, several Core Audio round trips slower than `AVAudioEngine.start()` — measured
    /// on this machine at low single-digit seconds. Starting it first, then the microphone,
    /// keeps the two tracks' true start times close; starting the fast one first would let
    /// that gap grow to the system tap's whole setup time. Some skew is unavoidable either
    /// way, which is a fact about the *files*, not about ``elapsedSeconds`` below — a future
    /// phase merging the two tracks by their own offsets has to know they don't start at
    /// exactly the same wall-clock instant.
    public func start(microphoneURL: URL, systemAudioURL: URL) async throws {
        guard await CapturePermissions.requestMicrophoneAccess() else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        // Built before either track starts, so the very first buffer each callback produces
        // already has somewhere to go — `.makeStream()`'s continuation is `Sendable` and safe
        // to call from the real-time thread the callback below actually runs on, unlike `self`.
        let micStream = AsyncStream<[Float]>.makeStream()
        let systemStream = AsyncStream<[Float]>.makeStream()

        do {
            try systemAudio.start(to: systemAudioURL) { samples in
                systemStream.continuation.yield(samples)
            }
        } catch {
            throw AudioCaptureError.systemAudio(error)
        }

        do {
            try microphone.start(to: microphoneURL) { samples in
                micStream.continuation.yield(samples)
            }
        } catch {
            systemAudio.stop()
            throw AudioCaptureError.microphone(error)
        }

        microphoneSamples = micStream.stream
        systemAudioSamples = systemStream.stream
        microphoneContinuation = micStream.continuation
        systemAudioContinuation = systemStream.continuation

        isRecording = true
        startedAt = Date()
        elapsedSeconds = 0
        startPolling()
    }

    /// Stops both tracks and returns how long the recording ran, rounded to the nearest
    /// second — what `RecordingSheet` writes to `Meeting.duration`.
    @discardableResult
    public func stop() -> Int {
        pollTask?.cancel()
        pollTask = nil
        microphone.stop()
        systemAudio.stop()
        // Finishing lets a `for await` over either stream end on its own, rather than a
        // consumer having to notice `isRecording` went false from the outside.
        microphoneContinuation?.finish()
        systemAudioContinuation?.finish()
        microphoneContinuation = nil
        systemAudioContinuation = nil
        isRecording = false
        microphoneLevel = 0
        systemAudioLevel = 0
        defer { startedAt = nil }
        guard let startedAt else { return 0 }
        return Int(Date().timeIntervalSince(startedAt).rounded())
    }

    /// 10 Hz: fast enough that a level meter reads as live, slow enough to cost nothing next
    /// to audio callbacks running at hundreds of buffers a second.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func tick() {
        guard let startedAt else { return }
        elapsedSeconds = Date().timeIntervalSince(startedAt)
        microphoneLevel = microphone.level.get()
        systemAudioLevel = systemAudio.level.get()
    }
}
