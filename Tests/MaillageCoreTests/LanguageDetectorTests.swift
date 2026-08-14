import Testing

@testable import MaillageCore

@Suite("Language detector silence skip")
struct LanguageDetectorTests {
    @Test("Skips a leading silent second before detecting")
    func skipsLeadingSilence() {
        let silence = [Float](repeating: 0, count: 16_000)
        let voice = [Float](repeating: 0.5, count: 16_000)
        let result = LanguageDetector.skippingLeadingSilence(silence + voice)
        #expect(result.count == voice.count)
    }

    @Test("An entirely silent window falls back to the untouched samples")
    func entirelySilentFallsBack() {
        let silence = [Float](repeating: 0, count: 16_000)
        #expect(LanguageDetector.skippingLeadingSilence(silence).count == silence.count)
    }

    @Test("Empty input stays empty")
    func emptyStaysEmpty() {
        #expect(LanguageDetector.skippingLeadingSilence([]).isEmpty)
    }
}
