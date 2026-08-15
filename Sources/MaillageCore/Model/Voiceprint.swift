import Foundation

/// A person's stored voice signature: one embedding vector plus how many confirmed samples
/// have folded into it. Not a recording, and not enough to reconstruct one — it's a comparison
/// key, see the meeting-recording-v2 design doc's privacy reasoning for why that distinction is
/// the whole point. Stored as `assets/people/<id>.voiceprint`, one small JSON file per person,
/// the same "a logo is a file, not a field" shape as a profile picture.
public struct Voiceprint: Codable, Hashable, Sendable {
    public var embedding: [Float]
    public var sampleCount: Int

    public init(embedding: [Float], sampleCount: Int) {
        self.embedding = embedding
        self.sampleCount = sampleCount
    }

    /// Fixed-decay exponential moving average: a newly confirmed embedding always nudges the
    /// stored one by the same fraction, so a gradual voice change (an illness was the example
    /// that prompted this) gets absorbed over time instead of one bad sample permanently
    /// poisoning the match. `nil` (nothing enrolled yet) simply becomes the first sample.
    ///
    /// `ponytail:` fixed decay, no confidence weighting or outlier rejection — a wrong confirm
    /// folds in at the same weight as a right one. Fine for a personal CRM tracking one user's
    /// own recurring contacts; revisit (e.g. weight by the match's own similarity score) only if
    /// that actually causes drift in practice.
    public static let decayRate: Float = 0.2

    public static func updated(_ existing: Voiceprint?, confirming embedding: [Float]) -> Voiceprint
    {
        guard let existing, existing.sampleCount > 0 else {
            return Voiceprint(embedding: normalized(embedding), sampleCount: 1)
        }
        let blended = zip(existing.embedding, embedding).map {
            (1 - decayRate) * $0 + decayRate * $1
        }
        return Voiceprint(embedding: normalized(blended), sampleCount: existing.sampleCount + 1)
    }

    /// The best-matching enrolled person for a live candidate embedding, or `nil` when nothing
    /// clears `threshold` — this is always a suggestion to confirm or reject, never a silent
    /// assignment; see the design doc's "the app guessed X" reasoning.
    public static func bestMatch(
        candidate: [Float], among voiceprints: [EntityID: Voiceprint], threshold: Float = 0.7
    ) -> (personID: EntityID, similarity: Float)? {
        voiceprints
            .compactMap { id, voiceprint -> (EntityID, Float)? in
                let score = similarity(candidate, voiceprint.embedding)
                return score >= threshold ? (id, score) : nil
            }
            .max { $0.1 < $1.1 }
            .map { (personID: $0.0, similarity: $0.1) }
    }

    /// Cosine similarity between two embeddings — `0` (never a crash) for a dimension mismatch
    /// or a zero vector, both of which mean "not the same voice" as far as this is concerned.
    public static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let magnitudeA = sqrt(a.reduce(Float(0)) { $0 + $1 * $1 })
        let magnitudeB = sqrt(b.reduce(Float(0)) { $0 + $1 * $1 })
        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }
        return dot / (magnitudeA * magnitudeB)
    }

    private static func normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}
