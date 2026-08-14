import AVFoundation

/// Requests and reports the microphone permission a recording needs.
///
/// The system-audio side has no equivalent request call: creating a process tap implicitly
/// triggers macOS's "Audio Capture" prompt the first time, gated by `NSAudioCaptureUsageDescription`
/// in `App/Info.plist` rather than by any API here. There is nothing to pre-flight for it —
/// ``SystemAudioTap/start(to:)`` either succeeds or throws, and that thrown error *is* the
/// permission check for that half of capture.
enum CapturePermissions {
    /// Requests microphone access if not yet decided, and reports whether recording may
    /// proceed. Never prompts twice: once denied or restricted, this returns `false` without
    /// showing the system dialog again — only System Settings can change that.
    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
