import Foundation

/// Strips a leading transcript segment that's substantially an echo of the vocabulary prompt.
///
/// Whisper echoes prompts into the transcript, especially on the first window and over silence —
/// a real, observed behaviour (design doc Constraint 3), not a hypothetical, so this needs an
/// actual filter rather than optimism. Word-overlap against the segment's own length, not the
/// prompt's: a genuine opening line that merely mentions one name from the prompt shares few of
/// its own words with it and survives; a real echo is mostly the prompt's words, in order.
public enum PromptEchoFilter {
    public static func strip(
        _ segments: [TranscriptSegment], prompt: String, threshold: Double = 0.7
    ) -> [TranscriptSegment] {
        guard let first = segments.first, isEcho(first.text, of: prompt, threshold: threshold)
        else { return segments }
        return Array(segments.dropFirst())
    }

    static func isEcho(_ text: String, of prompt: String, threshold: Double = 0.7) -> Bool {
        let textWords = words(in: text)
        guard !textWords.isEmpty, !prompt.isEmpty else { return false }
        let promptWords = Set(words(in: prompt))
        let overlap = textWords.filter { promptWords.contains($0) }.count
        return Double(overlap) / Double(textWords.count) >= threshold
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
