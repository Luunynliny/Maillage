import Testing

@testable import MaillageCore

@Suite("Language detector voice trimming")
struct LanguageDetectorTests {
    @Test("Skips a leading silent second before detecting")
    func skipsLeadingSilence() {
        let silence = [Float](repeating: 0, count: 16_000)
        let voice = [Float](repeating: 0.5, count: 16_000)
        let result = LanguageDetector.trimmedToFirstVoice(silence + voice)
        #expect(result?.count == voice.count)
    }

    @Test("An entirely silent window returns nil, signalling the caller to try another track")
    func entirelySilentReturnsNil() {
        let silence = [Float](repeating: 0, count: 16_000)
        #expect(LanguageDetector.trimmedToFirstVoice(silence) == nil)
    }

    @Test("Empty input returns nil")
    func emptyReturnsNil() {
        #expect(LanguageDetector.trimmedToFirstVoice([]) == nil)
    }
}
