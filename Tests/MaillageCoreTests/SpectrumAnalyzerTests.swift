import Foundation
import Testing

@testable import MaillageCore

/// The one piece of the live recording indicator that's pure enough to test without a
/// microphone or a running app: turning a sample buffer into magnitude bins. Feed a pure tone
/// at a known frequency, its energy should land in the bin that frequency falls into.
@Suite("Spectrum analyzer")
struct SpectrumAnalyzerTests {
    private let sampleRate: Float = 16_000
    /// Matches `SpectrumAnalyzer`'s fixed FFT window — a real analyzer call is never handed
    /// exactly this many samples (a live audio buffer's size varies), but the analyzer pads or
    /// trims to it internally, so a test buffer of exactly this length exercises that path
    /// without relying on it.
    private let windowSize = 1_024

    private func tone(frequency: Float) -> [Float] {
        (0..<windowSize).map { sample in
            sin(2 * Float.pi * frequency * Float(sample) / sampleRate)
        }
    }

    @Test("A 1 kHz tone's energy lands in the expected log-spaced bin")
    func puresToneLandsInExpectedBin() {
        // 1 kHz is an exact multiple of this window's FFT bin resolution (16kHz / 1024 =
        // 15.625 Hz), so it falls cleanly on a single FFT bin with no spectral leakage to
        // smear it across neighbours — the 8 log-spaced output bins this groups into place
        // it in index 5 (the range ~771 Hz–1683 Hz).
        let samples = tone(frequency: 1_000)

        let bins = SpectrumAnalyzer.bins(from: samples, count: 8, sampleRate: sampleRate)

        #expect(bins.count == 8)
        let peakIndex = bins.indices.max { bins[$0] < bins[$1] }
        #expect(peakIndex == 5)
    }

    @Test("A low tone lands in a lower bin than a high tone")
    func lowerToneLandsBeforeHigherTone() {
        let lowBins = SpectrumAnalyzer.bins(
            from: tone(frequency: 100), count: 8, sampleRate: sampleRate)
        let highBins = SpectrumAnalyzer.bins(
            from: tone(frequency: 4_000), count: 8, sampleRate: sampleRate)

        let lowPeak = lowBins.indices.max { lowBins[$0] < lowBins[$1] } ?? -1
        let highPeak = highBins.indices.max { highBins[$0] < highBins[$1] } ?? -1

        #expect(lowPeak < highPeak)
    }

    @Test("Silence produces bins near zero")
    func silenceProducesNearZeroBins() {
        let bins = SpectrumAnalyzer.bins(
            from: [Float](repeating: 0, count: windowSize), count: 8, sampleRate: sampleRate)

        #expect(bins.allSatisfy { $0 < 0.001 })
    }

    @Test("A buffer shorter than the FFT window is padded, not a crash")
    func shortBufferDoesNotCrash() {
        let bins = SpectrumAnalyzer.bins(from: [0.1, 0.2, 0.3], count: 8, sampleRate: sampleRate)

        #expect(bins.count == 8)
    }

    @Test("An empty buffer returns zeroed bins")
    func emptyBufferReturnsZeroedBins() {
        let bins = SpectrumAnalyzer.bins(from: [], count: 8, sampleRate: sampleRate)

        #expect(bins.count == 8)
        #expect(bins.allSatisfy { $0 == 0 })
    }
}
