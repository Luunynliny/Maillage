import Foundation
import Testing

@testable import MaillageCore

@Suite("Voiceprint")
struct VoiceprintTests {
    @Test("First enrollment is just the normalized embedding, sample count 1")
    func firstEnrollment() {
        let voiceprint = Voiceprint.updated(nil, confirming: [3, 4, 0])
        #expect(voiceprint.sampleCount == 1)
        // 3-4-0 has magnitude 5, so it normalizes to 0.6/0.8/0.
        #expect(abs(voiceprint.embedding[0] - 0.6) < 0.0001)
        #expect(abs(voiceprint.embedding[1] - 0.8) < 0.0001)
        #expect(abs(voiceprint.embedding[2] - 0) < 0.0001)
    }

    @Test("A confirmed re-enrollment blends toward the new embedding, not past it")
    func blendsTowardNewSample() {
        let first = Voiceprint.updated(nil, confirming: [1, 0])
        let second = Voiceprint.updated(first, confirming: [0, 1])

        #expect(second.sampleCount == 2)
        // Blended (1-0.2)*[1,0] + 0.2*[0,1] = [0.8, 0.2], then normalized — still mostly the
        // original direction, nudged toward the new sample rather than replaced by it.
        #expect(second.embedding[0] > second.embedding[1])
        #expect(second.embedding[1] > 0)
    }

    @Test("Repeated confirmations keep drifting toward a consistently different sample")
    func repeatedConfirmationsDriftFurther() {
        var voiceprint = Voiceprint.updated(nil, confirming: [1, 0])
        for _ in 0..<20 {
            voiceprint = Voiceprint.updated(voiceprint, confirming: [0, 1])
        }
        // Absorbs a sustained shift (the illness case) rather than staying anchored forever to
        // the first sample.
        #expect(voiceprint.embedding[1] > voiceprint.embedding[0])
    }

    @Test("Cosine similarity of identical vectors is 1")
    func identicalVectorsAreMaximallySimilar() {
        #expect(abs(Voiceprint.similarity([1, 2, 3], [1, 2, 3]) - 1) < 0.0001)
    }

    @Test("Cosine similarity of orthogonal vectors is 0")
    func orthogonalVectorsAreDissimilar() {
        #expect(abs(Voiceprint.similarity([1, 0], [0, 1])) < 0.0001)
    }

    @Test("Cosine similarity of opposite vectors is -1")
    func oppositeVectorsAreNegative() {
        #expect(abs(Voiceprint.similarity([1, 0], [-1, 0]) - (-1)) < 0.0001)
    }

    @Test("A dimension mismatch reads as 0 similarity rather than crashing")
    func dimensionMismatchIsZero() {
        #expect(Voiceprint.similarity([1, 2, 3], [1, 2]) == 0)
    }

    @Test("bestMatch picks the highest-scoring voiceprint above threshold")
    func bestMatchPicksHighestScore() {
        let voiceprints: [EntityID: Voiceprint] = [
            "amy-wong": Voiceprint(embedding: [1, 0], sampleCount: 3),
            "philip-fry": Voiceprint(embedding: [0.9, 0.1], sampleCount: 1),
        ]
        let match = Voiceprint.bestMatch(candidate: [1, 0], among: voiceprints, threshold: 0.5)
        #expect(match?.personID == "amy-wong")
    }

    @Test("bestMatch returns nil when nothing clears the threshold")
    func bestMatchNilBelowThreshold() {
        let voiceprints: [EntityID: Voiceprint] = [
            "amy-wong": Voiceprint(embedding: [0, 1], sampleCount: 1)
        ]
        let match = Voiceprint.bestMatch(candidate: [1, 0], among: voiceprints, threshold: 0.7)
        #expect(match == nil)
    }

    @Test("bestMatch with no enrolled voiceprints is nil")
    func bestMatchNilWhenEmpty() {
        #expect(Voiceprint.bestMatch(candidate: [1, 0], among: [:]) == nil)
    }
}
