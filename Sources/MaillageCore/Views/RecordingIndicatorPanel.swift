import AppKit
import Foundation
import SwiftUI

/// A small floating window showing a live bar-spectrogram for each audio track while a meeting
/// records — what used to be two inline level-meter bars in ``MeetingView``'s recording banner,
/// pulled out so it stays visible whichever window is frontmost. A meeting is often recorded
/// with maillage itself in the background, and "is it actually capturing sound" is exactly the
/// question a level meter answers, so that question shouldn't disappear along with the window.
///
/// Non-activating and `.floating`: it must never steal key focus from whatever window someone
/// is actually using, but has to stay above ordinary windows the way a HUD does. Consistent with
/// the app's existing direct-AppKit spots (`ForegroundActivation` in `MaillageApp`,
/// `SystemAudioTap`'s Core Audio calls) rather than a second SwiftUI `Scene`, which can't be
/// made non-activating or told to float above every other window.
@MainActor
public final class RecordingIndicatorPanel {
    private let model = SpectrogramModel()
    private lazy var panel = Self.makePanel(hosting: SpectrogramView(model: model))
    private var microphoneTask: Task<Void, Never>?
    private var systemAudioTask: Task<Void, Never>?

    public init() {}

    /// Shows the panel and starts consuming both tracks' live sample streams. Call once per
    /// recording, right after `AudioCaptureSession.start(microphoneURL:systemAudioURL:)`
    /// succeeds — its streams are fresh per call, so consuming a stale pair left over from a
    /// previous recording would just sit on an already-finished stream.
    public func show(capture: AudioCaptureSession) {
        stopConsuming()
        model.reset()
        panel.orderFrontRegardless()
        microphoneTask = Task { [model] in
            var lastUpdate = Date.distantPast
            for await samples in capture.microphoneSamples {
                guard Self.isDueForUpdate(since: &lastUpdate) else { continue }
                model.updateMicrophone(with: samples)
            }
        }
        systemAudioTask = Task { [model] in
            var lastUpdate = Date.distantPast
            for await samples in capture.systemAudioSamples {
                guard Self.isDueForUpdate(since: &lastUpdate) else { continue }
                model.updateSystemAudio(with: samples)
            }
        }
    }

    /// Caps how often a track's buffers actually reach `SpectrumAnalyzer` — the callbacks
    /// feeding `capture.microphoneSamples`/`systemAudioSamples` run at hundreds of buffers a
    /// second, but a bar-spectrogram only needs to move at roughly the same 10-15 Hz cadence the
    /// old level-meter polling used. `minimumUpdateInterval` sits just inside that: skip a buffer
    /// arriving too soon after the last one actually processed, rather than running a full FFT
    /// (plus an `@Observable` invalidation) on every single callback for the length of a meeting.
    private static let minimumUpdateInterval: TimeInterval = 0.08

    private static func isDueForUpdate(since lastUpdate: inout Date) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) >= minimumUpdateInterval else { return false }
        lastUpdate = now
        return true
    }

    /// Hides the panel and stops consuming. Safe to call even if `show` was never called, the
    /// same as `MeetingRecorder.stop()` being safe to call on an idle recorder.
    public func hide() {
        panel.orderOut(nil)
        stopConsuming()
        model.reset()
    }

    private func stopConsuming() {
        microphoneTask?.cancel()
        systemAudioTask?.cancel()
        microphoneTask = nil
        systemAudioTask = nil
    }

    private static let size = NSSize(width: 220, height: 84)

    /// Borderless rather than titled: this is a HUD-style indicator, not a document window, and
    /// carries no title worth showing. The rounded card look comes from `SpectrogramView` itself
    /// via `Theme` tokens, the same as everywhere else in the app — the panel's own background is
    /// left transparent so that card reads as floating rather than sitting inside a second frame.
    private static func makePanel(hosting content: some View) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: content)

        if let screenFrame = NSScreen.main?.visibleFrame {
            let margin: CGFloat = 16
            panel.setFrameOrigin(
                NSPoint(
                    x: screenFrame.maxX - size.width - margin,
                    y: screenFrame.maxY - size.height - margin))
        }
        return panel
    }
}

// MARK: - Model

/// Holds the most recently computed bins for each track, smoothed across updates so the bars
/// read as alive rather than jumping straight to each new reading. `@Observable` so
/// `SpectrogramView` redraws as new buffers arrive, the same as every other live view in the app.
@MainActor
@Observable
final class SpectrogramModel {
    static let binCount = 8

    private(set) var microphoneBins = SpectrogramModel.emptyBins
    private(set) var systemAudioBins = SpectrogramModel.emptyBins

    private static let emptyBins = [Float](repeating: 0, count: binCount)

    /// How much a fresh reading moves the displayed bar versus how much of the previous one
    /// remains — an exponential moving average, the smallest smoothing that still keeps a burst
    /// of speech from flickering bar-to-bar at whatever rate buffers happen to arrive at.
    private static let smoothing: Float = 0.35

    func updateMicrophone(with samples: [Float]) {
        microphoneBins = Self.smoothed(previous: microphoneBins, samples: samples)
    }

    func updateSystemAudio(with samples: [Float]) {
        systemAudioBins = Self.smoothed(previous: systemAudioBins, samples: samples)
    }

    func reset() {
        microphoneBins = Self.emptyBins
        systemAudioBins = Self.emptyBins
    }

    private static func smoothed(previous: [Float], samples: [Float]) -> [Float] {
        let fresh = SpectrumAnalyzer.bins(from: samples, count: binCount)
        return zip(previous, fresh).map { $0 + ($1 - $0) * smoothing }
    }
}

// MARK: - View

/// The bar-spectrogram itself: one group of bars per track.
struct SpectrogramView: View {
    let model: SpectrogramModel

    var body: some View {
        Card {
            HStack(alignment: .bottom, spacing: Theme.Spacing.large) {
                barGroup(label: "Microphone", bins: model.microphoneBins)
                barGroup(label: "Audio System", bins: model.systemAudioBins)
            }
        }
    }

    private static let barHeight: CGFloat = 32
    private static let barWidth: CGFloat = 4
    private static let barSpacing: CGFloat = 2
    private static let barCornerRadius: CGFloat = 1

    /// Magnitudes out of `SpectrumAnalyzer` sit on the FFT's own small, unnormalized scale, not
    /// 0...1 — this maps them onto a decibel range instead of a raw linear one, since a fixed
    /// linear gain would either miss quiet speech or clip loud speech depending which one it was
    /// eyeballed against.
    ///
    /// ponytail: `floorDB`/`ceilingDB` are eyeballed against the analyzer's own output scale, not
    /// measured against a real microphone — retune them if bars read too flat or too twitchy once
    /// heard against actual recorded speech.
    private static let floorDB: Float = -60
    private static let ceilingDB: Float = -15

    private func barGroup(label: String, bins: [Float]) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(Array(bins.enumerated()), id: \.offset) { _, magnitude in
                    RoundedRectangle(cornerRadius: Self.barCornerRadius)
                        .fill(Theme.accent)
                        .frame(width: Self.barWidth, height: barHeight(for: magnitude))
                }
            }
            .frame(height: Self.barHeight, alignment: .bottom)
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func barHeight(for magnitude: Float) -> CGFloat {
        let decibels = 20 * log10(max(magnitude, 1e-6))
        let clamped = min(max(decibels, Self.floorDB), Self.ceilingDB)
        let normalized = (clamped - Self.floorDB) / (Self.ceilingDB - Self.floorDB)
        return max(2, CGFloat(normalized) * Self.barHeight)
    }
}
