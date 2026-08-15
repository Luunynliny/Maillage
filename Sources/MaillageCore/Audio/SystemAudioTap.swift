import AVFoundation
import CoreAudio

public enum SystemAudioTapError: Error, LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case converterUnavailable
    case ioProcFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let status):
            "Couldn't create the system-audio tap (status \(status))."
        case .aggregateDeviceCreationFailed(let status):
            "Couldn't create the aggregate device for system audio (status \(status))."
        case .converterUnavailable:
            "Couldn't convert the system audio's format."
        case .ioProcFailed(let status):
            "Couldn't start reading system audio (status \(status))."
        }
    }
}

/// Records everything the system is playing — every process except this one — to a 16 kHz
/// mono WAV file, via a Core Audio process tap.
///
/// Confines the C API to this one file, per the design's own rule for it: a `CATapDescription`
/// excluding our own process becomes an AudioObjectID; that tap, wrapped in a private,
/// tap-only aggregate device, becomes something `AudioDeviceCreateIOProcIDWithBlock` can read
/// like any other input device. There is no lower-level or better-documented way to do this —
/// `AVAudioEngine` has no notion of "the system's output" at all.
///
/// Not `@MainActor`, for the same reason as ``MicrophoneRecorder``: the IOProc block runs on a
/// real-time thread Core Audio owns, and ``level`` is read by ``AudioCaptureSession`` through
/// a ``LockedValue`` rather than by hopping actors on every callback.
final class SystemAudioTap {
    private var tapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var ioProcID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var converter: PCMConverter?
    private var onBuffer: (@Sendable ([Float]) -> Void)?

    let level = LockedValue<Float>(0)

    /// See ``MicrophoneRecorder/start(to:onBuffer:)`` for what `onBuffer` is for and the
    /// real-time-thread constraints on it — identical here, just fed from the IOProc instead
    /// of `AVAudioEngine`'s tap.
    func start(to url: URL, onBuffer: (@Sendable ([Float]) -> Void)? = nil) throws {
        self.onBuffer = onBuffer
        try createTapExcludingSelf()
        try createAggregateDevice()

        let tapFormat = try nativeFormat(ofTap: tapID)
        guard let converter = PCMConverter(from: tapFormat) else {
            teardown()
            throw SystemAudioTapError.converterUnavailable
        }
        self.converter = converter
        self.file = try AVAudioFile(
            forWriting: url, settings: PCMFormat.target.settings,
            commonFormat: PCMFormat.target.commonFormat,
            interleaved: PCMFormat.target.isInterleaved)

        var ioProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID, aggregateDeviceID, nil
        ) { [weak self] _, inputData, _, _, _ in
            self?.process(inputData, format: tapFormat)
        }
        guard procStatus == noErr, let ioProcID else {
            teardown()
            throw SystemAudioTapError.ioProcFailed(procStatus)
        }
        self.ioProcID = ioProcID

        let startStatus = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard startStatus == noErr else {
            teardown()
            throw SystemAudioTapError.ioProcFailed(startStatus)
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        teardown()
    }

    /// Tears down whatever was created, in reverse order, so a partial failure during
    /// `start` never leaks a tap or an aggregate device that outlives this object.
    private func teardown() {
        ioProcID = nil
        file = nil
        converter = nil
        onBuffer = nil
        level.set(0)
        if aggregateDeviceID != .unknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    // MARK: Tap and aggregate device

    private func createTapExcludingSelf() throws {
        let selfProcessObject = try processObject(forPID: ProcessInfo.processInfo.processIdentifier)
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [selfProcessObject])
        // Never surfaced in the system's audio device list or picked up by another app
        // enumerating taps — this exists to feed one file, not to be a reusable device.
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID: AudioObjectID = .unknown
        let status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw SystemAudioTapError.tapCreationFailed(status) }
        tapID = newTapID
    }

    private func createAggregateDevice() throws {
        let tapUID = try uid(ofTap: tapID)
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceNameKey as String: "maillage-system-audio-\(aggregateUID)",
            // Never shown in System Settings' Sound pane — this stands for one recording, not
            // a device anyone should be able to pick.
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUID,
                    kAudioSubTapDriftCompensationKey as String: true,
                ]
            ],
        ]

        var newAggregateID: AudioObjectID = .unknown
        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary, &newAggregateID)
        guard status == noErr else {
            throw SystemAudioTapError.aggregateDeviceCreationFailed(status)
        }
        aggregateDeviceID = newAggregateID
    }

    // MARK: Core Audio property reads

    private func processObject(forPID pid: pid_t) throws -> AudioObjectID {
        var mutablePID = pid
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var processObjectID: AudioObjectID = .unknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &mutablePID) { pidPointer -> OSStatus in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), pidPointer,
                &size, &processObjectID)
        }
        guard status == noErr, processObjectID != .unknown else {
            throw SystemAudioTapError.tapCreationFailed(status)
        }
        return processObjectID
    }

    private func uid(ofTap tap: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else {
            throw SystemAudioTapError.aggregateDeviceCreationFailed(status)
        }
        return uid.takeUnretainedValue() as String
    }

    /// The tap's own format — never assumed, since it mirrors whatever the system's audio
    /// engine is mixing at, which changes with the connected output device.
    private func nativeFormat(ofTap tap: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw SystemAudioTapError.converterUnavailable
        }
        return format
    }

    // MARK: IO

    /// Called on the real-time thread Core Audio drives this IOProc from. Must not block or
    /// touch anything actor-isolated, for the same reason as ``MicrophoneRecorder/process(_:)``.
    private func process(_ inputData: UnsafePointer<AudioBufferList>, format: AVAudioFormat) {
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil)
        else { return }
        level.set(Self.rootMeanSquare(of: buffer))
        guard let converted = converter?.convert(buffer) else { return }
        try? file?.write(from: converted)
        if let onBuffer {
            onBuffer(Self.samples(from: converted))
        }
    }

    /// See ``MicrophoneRecorder``'s copy of this — same reasoning: the buffer is only valid
    /// for the duration of this callback, so anything handed off the real-time thread needs
    /// its own plain array.
    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private static func rootMeanSquare(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for frame in 0..<frameCount {
            let sample = channel[frame]
            sum += sample * sample
        }
        return sqrt(sum / Float(frameCount))
    }
}

extension AudioObjectID {
    /// `kAudioObjectUnknown`, spelled to read as a sentinel at every call site above rather
    /// than as a magic `0`.
    fileprivate static let unknown = AudioObjectID(kAudioObjectUnknown)
}
