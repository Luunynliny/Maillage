import Accelerate

/// Turns a raw sample buffer into a small number of magnitude bins via vDSP's FFT — the pure
/// piece behind ``RecordingIndicatorPanel``'s live bar-spectrogram. Samples in, bins out; no
/// AppKit, no SwiftUI, nothing that needs a microphone or a loaded model, so it's tested with a
/// synthesized tone rather than a running recording.
public enum SpectrumAnalyzer {
    /// Samples per FFT — fixed rather than sized to whatever a caller hands in, and a power of
    /// two, as `vDSP_fft_zrip` requires. A live audio callback's buffer length varies release to
    /// release and even call to call, so a fixed window keeps one call's frequency resolution,
    /// and therefore what "bin 5" means, identical to the next.
    static let windowSize = 1_024

    /// `count` magnitude bins, log-spaced from this window's own frequency resolution
    /// (`sampleRate / windowSize`) up to Nyquist (`sampleRate / 2`) — log-spaced because voiced
    /// speech concentrates energy in the lower few hundred Hz, which equal-width linear bins
    /// would flatten into a single bar, and because a spectrogram read at a glance cares about
    /// octaves, not linear Hz.
    ///
    /// `samples` is trimmed to its most recent `windowSize` samples, or zero-padded if shorter
    /// — a poll tick with less audio than a full window still returns `count` bins rather than
    /// throwing, since "not enough signal yet" reads the same as silence to whatever is
    /// displaying these.
    public static func bins(from samples: [Float], count: Int, sampleRate: Float = 16_000)
        -> [Float]
    {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return [Float](repeating: 0, count: count) }
        let windowed = fit(samples, to: windowSize)
        let spectrum = powerSpectrum(of: windowed)
        return logBins(from: spectrum, count: count, sampleRate: sampleRate)
    }

    /// Trims to the most recent `size` samples, or zero-pads at the end if there are fewer.
    private static func fit(_ samples: [Float], to size: Int) -> [Float] {
        if samples.count == size { return samples }
        if samples.count > size { return Array(samples.suffix(size)) }
        return samples + [Float](repeating: 0, count: size - samples.count)
    }

    /// Power (magnitude-squared) per FFT bin — `windowSize / 2` of them, bin `k` centred on
    /// `k * sampleRate / windowSize` Hz. `samples.count` must equal `windowSize`.
    private static func powerSpectrum(of samples: [Float]) -> [Float] {
        let n = windowSize
        let halfN = n / 2
        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: halfN)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var realPart = [Float](repeating: 0, count: halfN)
        var imaginaryPart = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        realPart.withUnsafeMutableBufferPointer { realBuffer in
            imaginaryPart.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                samples.withUnsafeBufferPointer { samplesBuffer in
                    samplesBuffer.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self, capacity: halfN
                    ) { packed in
                        vDSP_ctoz(packed, 2, &split, 1, vDSP_Length(halfN))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }
        return magnitudes
    }

    /// Groups the linear FFT bins into `count` log-spaced frequency ranges. Each range's power
    /// is averaged, then square-rooted to get back to a magnitude-like scale, then divided by
    /// the window size so the result sits in a small range rather than the FFT's raw
    /// (unnormalized) one.
    private static func logBins(from powerSpectrum: [Float], count: Int, sampleRate: Float)
        -> [Float]
    {
        let binHz = sampleRate / Float(windowSize)
        let minHz = binHz
        let maxHz = sampleRate / 2
        let ratio = pow(maxHz / minHz, 1 / Float(count))

        return (0..<count).map { index in
            let lowHz = minHz * pow(ratio, Float(index))
            let highHz = minHz * pow(ratio, Float(index + 1))
            let lowBin = max(1, Int((lowHz / binHz).rounded(.down)))
            let highBin = min(
                powerSpectrum.count, max(lowBin + 1, Int((highHz / binHz).rounded(.up))))
            let range = powerSpectrum[lowBin..<highBin]
            let averagePower = range.reduce(0, +) / Float(range.count)
            return averagePower.squareRoot() / Float(windowSize)
        }
    }
}
